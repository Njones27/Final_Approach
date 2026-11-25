import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { App } from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { buildBackend } from '../lib/backend.ts';
import {
  deletedAccountMarkerSeconds,
  deploySubject,
  isStageName,
  stages,
  type StageName,
} from '../lib/stages.ts';

/** The templates for one stage. The function code is not bundled, which keeps this quick. */
function templates(stageName: StageName) {
  const app = new App({ context: { 'aws:cdk:bundling-stacks': [] } });
  const backend = buildBackend(app, stages[stageName]);
  return {
    alerts: Template.fromStack(backend.alerts),
    storage: Template.fromStack(backend.storage),
    identity: Template.fromStack(backend.identity),
    api: Template.fromStack(backend.api),
    stacks: backend,
  };
}

const beta = templates('beta');
const prod = templates('prod');

/** Every statement of every policy in a template, as text, for checks on what is not there. */
function statements(template: Template): { Action: string | string[]; Resource: unknown }[] {
  return Object.values(template.findResources('AWS::IAM::Policy')).flatMap(
    (policy) => policy['Properties'].PolicyDocument.Statement,
  );
}
const actionsOf = (template: Template) => statements(template).flatMap((statement) => statement.Action);

describe('the image bucket', () => {
  test('is closed to the public and takes only encrypted connections', () => {
    beta.storage.hasResourceProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
      BucketEncryption: Match.anyValue(),
      OwnershipControls: { Rules: [{ ObjectOwnership: 'BucketOwnerEnforced' }] },
    });
    beta.storage.hasResourceProperties('AWS::S3::BucketPolicy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({ Effect: 'Deny', Condition: { Bool: { 'aws:SecureTransport': 'false' } } }),
        ]),
      },
    });
  });

  test('keeps no old versions, so a deleted image is gone', () => {
    for (const template of [beta.storage, prod.storage]) {
      const [bucket] = Object.values(template.findResources('AWS::S3::Bucket'));
      assert.equal(bucket?.['Properties'].VersioningConfiguration, undefined);
      assert.equal(bucket?.['Properties'].ReplicationConfiguration, undefined);
    }
  });

  test('calls the sweeper for every image that arrives', () => {
    beta.storage.hasResourceProperties('Custom::S3BucketNotifications', {
      NotificationConfiguration: {
        LambdaFunctionConfigurations: [
          Match.objectLike({
            Events: ['s3:ObjectCreated:*'],
            Filter: { Key: { FilterRules: [{ Name: 'prefix', Value: 'users/' }] } },
          }),
        ],
      },
    });
  });
});

describe('the table', () => {
  test('is billed by use, can be restored, and expires markers', () => {
    beta.storage.hasResourceProperties('AWS::DynamoDB::Table', {
      BillingMode: 'PAY_PER_REQUEST',
      KeySchema: [
        { AttributeName: 'pk', KeyType: 'HASH' },
        { AttributeName: 'sk', KeyType: 'RANGE' },
      ],
      PointInTimeRecoverySpecification: { PointInTimeRecoveryEnabled: true },
      TimeToLiveSpecification: { AttributeName: 'expiresAt', Enabled: true },
    });
  });

  test('has two indexes, of the posts open for votes and of the photos shown at spots', () => {
    for (const stage of [beta, prod]) {
      stage.storage.hasResourceProperties('AWS::DynamoDB::Table', {
        GlobalSecondaryIndexes: [
          {
            IndexName: 'Voting',
            KeySchema: [
              { AttributeName: 'votingKey', KeyType: 'HASH' },
              { AttributeName: 'postID', KeyType: 'RANGE' },
            ],
            Projection: { ProjectionType: 'ALL' },
          },
          {
            IndexName: 'Spot',
            KeySchema: [
              { AttributeName: 'spotKey', KeyType: 'HASH' },
              { AttributeName: 'finalScore', KeyType: 'RANGE' },
            ],
            Projection: { ProjectionType: 'ALL' },
          },
        ],
      });
    }
  });
});

describe('what a deleted stack leaves behind', () => {
  test('prod keeps its data and beta does not', () => {
    for (const type of ['AWS::DynamoDB::Table', 'AWS::S3::Bucket']) {
      prod.storage.hasResource(type, { DeletionPolicy: 'Retain', UpdateReplacePolicy: 'Retain' });
      beta.storage.hasResource(type, { DeletionPolicy: 'Delete' });
    }
    prod.identity.hasResource('AWS::Cognito::UserPool', { DeletionPolicy: 'Retain' });
    prod.identity.hasResourceProperties('AWS::Cognito::UserPool', { DeletionProtection: 'ACTIVE' });
    prod.storage.hasResourceProperties('AWS::DynamoDB::Table', { DeletionProtectionEnabled: true });
    assert.equal(prod.stacks.storage.terminationProtection, true);
    assert.equal(beta.stacks.storage.terminationProtection, false);
  });
});

describe('sign in', () => {
  test('the app can use the custom flow and a test account’s password, with no web sign in and no secret', () => {
    beta.identity.hasResourceProperties('AWS::Cognito::UserPoolClient', {
      ExplicitAuthFlows: ['ALLOW_USER_PASSWORD_AUTH', 'ALLOW_CUSTOM_AUTH', 'ALLOW_REFRESH_TOKEN_AUTH'],
      AllowedOAuthFlowsUserPoolClient: false,
      GenerateSecret: false,
      PreventUserExistenceErrors: 'ENABLED',
      EnableTokenRevocation: true,
    });
  });

  test('a stage with test accounts turned off leaves Apple as the only way in', () => {
    const app = new App({ context: { 'aws:cdk:bundling-stacks': [] } });
    const backend = buildBackend(app, { ...stages.beta, testAccountSignIn: false });
    Template.fromStack(backend.identity).hasResourceProperties('AWS::Cognito::UserPoolClient', {
      ExplicitAuthFlows: ['ALLOW_CUSTOM_AUTH', 'ALLOW_REFRESH_TOKEN_AUTH'],
    });
  });

  test('all four Apple checks are attached to the pool', () => {
    beta.identity.hasResourceProperties('AWS::Cognito::UserPool', {
      LambdaConfig: {
        PreSignUp: Match.anyValue(),
        DefineAuthChallenge: Match.anyValue(),
        CreateAuthChallenge: Match.anyValue(),
        VerifyAuthChallengeResponse: Match.anyValue(),
      },
      UsernameConfiguration: { CaseSensitive: true },
    });
  });

  test('the functions that read Apple’s token know the app and the age limit', () => {
    beta.identity.resourcePropertiesCountIs(
      'AWS::Lambda::Function',
      {
        Environment: {
          Variables: { APPLE_AUDIENCE: 'com.finalapproach.app', MAX_APPLE_TOKEN_AGE_SECONDS: '600' },
        },
      },
      2,
    );
  });
});

describe('the API', () => {
  test('has exactly the twelve routes, and each needs a signed in user', () => {
    const routes = Object.values(beta.api.findResources('AWS::ApiGatewayV2::Route')).map(
      (route) => route['Properties'],
    );
    assert.deepEqual(routes.map((route) => route.RouteKey).sort(), [
      'DELETE /account',
      'DELETE /photos/{photoID}',
      'DELETE /posts/{photoID}/spot',
      'GET /photos',
      'GET /posts',
      'GET /spots',
      'GET /spots/{spotID}/photos',
      'GET /votes/queue',
      'PUT /photos/{photoID}',
      'PUT /posts/{photoID}',
      'PUT /posts/{photoID}/spot',
      'PUT /votes/{postID}',
    ]);
    for (const route of routes) assert.equal(route.AuthorizationType, 'JWT', route.RouteKey);
  });

  test('the posts function knows how long a vote stays open', () => {
    for (const [stage, name] of [[beta, 'beta'], [prod, 'prod']] as const) {
      stage.api.hasResourceProperties('AWS::Lambda::Function', {
        Environment: {
          Variables: Match.objectLike({
            VOTING_WINDOW_HOURS: String(stages[name].votingWindowHours),
            MAX_IMAGE_BYTES: String(stages[name].maxImageBytes),
          }),
        },
      });
      assert.ok(stages[name].votingWindowHours >= 1);
    }
  });

  test('every function that reads the vote knows the same rules', () => {
    for (const [stage, name] of [[beta, 'beta'], [prod, 'prod']] as const) {
      const rules = {
        VOTE_SCALE_MAX: String(stages[name].voteScaleMax),
        MIN_VOTES: String(stages[name].minVotesToFinalize),
      };
      const functions = Object.values(stage.api.findResources('AWS::Lambda::Function'))
        .map((fn) => fn['Properties'].Environment?.Variables ?? {})
        .filter((variables) => 'VOTE_SCALE_MAX' in variables);
      // Posts, Votes, and the closer.
      assert.equal(functions.length, 3);
      for (const variables of functions) {
        assert.equal(variables.VOTE_SCALE_MAX, rules.VOTE_SCALE_MAX);
        assert.equal(variables.MIN_VOTES, rules.MIN_VOTES);
      }
    }
  });

  test('the voting settings are amounts that make sense', () => {
    for (const stage of Object.values(stages)) {
      assert.ok(stage.voteScaleMax >= 2);
      assert.ok(stage.minVotesToFinalize >= 1);
      assert.ok(stage.votingQueueSize >= 1);
      // The queue reads more posts than it hands out, because some are the
      // voter's own or already voted on. One batch read holds 100 keys.
      assert.ok(stage.votingQueueReadLimit >= stage.votingQueueSize);
      assert.ok(stage.votingQueueReadLimit <= 100);
    }
  });

  test('finished posts are closed on a schedule', () => {
    for (const [stage, name] of [[beta, 'beta'], [prod, 'prod']] as const) {
      stage.api.resourceCountIs('AWS::Events::Rule', 1);
      stage.api.hasResourceProperties('AWS::Events::Rule', {
        ScheduleExpression: `rate(${stages[name].closerMinutes} minutes)`,
        State: 'ENABLED',
      });
    }
  });

  test('is throttled', () => {
    beta.api.hasResourceProperties('AWS::ApiGatewayV2::Stage', {
      StageName: '$default',
      DefaultRouteSettings: { ThrottlingRateLimit: 50, ThrottlingBurstLimit: 100 },
    });
  });

  test('the account function can run as long as API Gateway waits', () => {
    beta.api.hasResourceProperties('AWS::Lambda::Function', {
      Timeout: 29,
      Environment: { Variables: Match.objectLike({ DELETED_ACCOUNT_MARKER_SECONDS: '7500' }) },
    });
  });
});

describe('what the functions may do', () => {
  test('no function is given a whole service or every resource', () => {
    for (const template of [beta.storage, beta.identity, beta.api]) {
      for (const statement of statements(template)) {
        for (const action of [statement.Action].flat()) {
          // The helper CDK adds to wire bucket events is the one exception.
          if (action === 's3:PutBucketNotification') continue;
          assert.ok(!action.endsWith('*'), action);
        }
        assert.notEqual(statement.Resource, '*');
      }
    }
  });

  test('the API functions take only the actions their code calls', () => {
    assert.deepEqual(actionsOf(beta.api).sort(), [
      'cognito-idp:AdminDeleteUser',
      'dynamodb:BatchGetItem',
      'dynamodb:BatchWriteItem',
      'dynamodb:ConditionCheckItem',
      'dynamodb:ConditionCheckItem',
      'dynamodb:ConditionCheckItem',
      'dynamodb:DeleteItem',
      'dynamodb:DeleteItem',
      'dynamodb:GetItem',
      'dynamodb:PutItem',
      'dynamodb:PutItem',
      'dynamodb:PutItem',
      'dynamodb:PutItem',
      'dynamodb:Query',
      'dynamodb:Query',
      'dynamodb:Query',
      'dynamodb:Query',
      'dynamodb:Query',
      'dynamodb:Query',
      'dynamodb:UpdateItem',
      'dynamodb:UpdateItem',
      'dynamodb:UpdateItem',
      's3:DeleteObject',
      's3:DeleteObject',
      's3:GetObject',
      's3:GetObject',
      's3:GetObject',
      's3:GetObject',
      's3:ListBucket',
      's3:ListBucket',
      's3:PutObject',
    ]);
  });

  const policyOf = (name: string) => {
    const found = Object.entries(beta.api.findResources('AWS::IAM::Policy')).find(([id]) =>
      id.startsWith(`${name}ServiceRole`),
    );
    assert.ok(found, name);
    return found[1]['Properties'].PolicyDocument.Statement as { Action: string | string[]; Resource: unknown }[];
  };

  test('the votes function reads the index of open posts, and its other reads and writes stay on the table', () => {
    const statements = policyOf('Votes');
    assert.deepEqual(statements.flatMap((statement) => statement.Action).sort(), [
      'dynamodb:BatchGetItem',
      'dynamodb:ConditionCheckItem',
      'dynamodb:PutItem',
      'dynamodb:Query',
      'dynamodb:UpdateItem',
      's3:GetObject',
    ]);
    const query = statements.find((statement) => [statement.Action].flat().includes('dynamodb:Query'));
    assert.match(JSON.stringify(query?.Resource), /\/index\/Voting/);
  });

  test('the closer reads the index of open posts and updates a post, and nothing else', () => {
    const statements = policyOf('Closer');
    assert.deepEqual(statements.flatMap((statement) => statement.Action).sort(), [
      'dynamodb:Query',
      'dynamodb:UpdateItem',
    ]);
    const query = statements.find((statement) => [statement.Action].flat().includes('dynamodb:Query'));
    assert.match(JSON.stringify(query?.Resource), /\/index\/Voting/);
  });

  test('the spots function reads the index of photos shown at spots and signs links, and writes nothing', () => {
    const statements = policyOf('Spots');
    assert.deepEqual(statements.flatMap((statement) => statement.Action).sort(), ['dynamodb:Query', 's3:GetObject']);
    const query = statements.find((statement) => [statement.Action].flat().includes('dynamodb:Query'));
    // It may read the one index, and not the table of every user's records.
    assert.match(JSON.stringify(query?.Resource), /\/index\/Spot"\]\]\}$/);
  });

  test('the posts function reads and writes records and reads images, and changes no image', () => {
    const role = Object.entries(beta.api.findResources('AWS::IAM::Policy')).find(([name]) =>
      name.startsWith('PostsServiceRole'),
    );
    assert.ok(role);
    const actions = role[1]['Properties'].PolicyDocument.Statement.flatMap(
      (statement: { Action: string | string[] }) => statement.Action,
    );
    assert.deepEqual(actions.sort(), [
      'dynamodb:ConditionCheckItem',
      'dynamodb:GetItem',
      'dynamodb:PutItem',
      'dynamodb:Query',
      'dynamodb:UpdateItem',
      's3:GetObject',
      's3:ListBucket',
    ]);
  });

  test('the sweeper can read records and remove images, and nothing else', () => {
    const sweeper = actionsOf(beta.storage).filter((action) => action !== 's3:PutBucketNotification');
    assert.deepEqual(sweeper.sort(), ['dynamodb:BatchGetItem', 'dynamodb:GetItem', 's3:DeleteObject']);
  });

  test('image permissions stop at the user folders', () => {
    const imageStatements = statements(beta.api).filter((statement) =>
      [statement.Action].flat().some((action) => action.startsWith('s3:') && action !== 's3:ListBucket'),
    );
    assert.equal(imageStatements.length, 5);
    for (const statement of imageStatements) {
      assert.match(JSON.stringify(statement.Resource), /\/users\/\*/);
    }
  });
});

describe('deploying from GitHub', () => {
  const stack = beta.stacks.deploy;
  assert.ok(stack, 'beta has a deploy stack');
  const deploy = Template.fromStack(stack);
  const [role] = Object.values(deploy.findResources('AWS::IAM::Role'));
  const trust = role?.['Properties'].AssumeRolePolicyDocument.Statement;

  test('each stage has its own deploy stack', () => {
    assert.equal(stack.stackName, 'FinalApproach-beta-Deploy');
    assert.equal(prod.stacks.deploy?.stackName, 'FinalApproach-prod-Deploy');
  });

  test('the account takes tokens from GitHub that were made for AWS', () => {
    deploy.resourceCountIs('AWS::IAM::OIDCProvider', 1);
    deploy.hasResourceProperties('AWS::IAM::OIDCProvider', {
      Url: 'https://token.actions.githubusercontent.com',
      ClientIdList: ['sts.amazonaws.com'],
    });
  });

  test('the role takes a token only from the main branch of this repository', () => {
    deploy.resourceCountIs('AWS::IAM::Role', 1);
    assert.equal(role?.['Properties'].RoleName, 'FinalApproach-beta-GitHubDeploy');
    assert.equal(trust.length, 1);
    const [statement] = trust;
    assert.equal(statement.Effect, 'Allow');
    assert.equal(statement.Action, 'sts:AssumeRoleWithWebIdentity');
    assert.deepEqual(Object.keys(statement.Principal), ['Federated']);
    // An exact match on both, with no wildcard, so no pull request, fork,
    // tag, or other branch can use the role.
    assert.deepEqual(statement.Condition, {
      StringEquals: {
        'token.actions.githubusercontent.com:aud': 'sts.amazonaws.com',
        // Exactly what GitHub sent on the first run, as the beta account's
        // own log recorded it. The numbers are the ids of the owner and of
        // the repository.
        'token.actions.githubusercontent.com:sub':
          'repo:Njones27@153565100/Final_Approach@1468200614:ref:refs/heads/main',
      },
    });
  });

  test('the subject names the owner and the repository by name and by id', () => {
    const repository = { owner: 'Owner', ownerID: 12, repository: 'Repo', repositoryID: 34 };
    assert.equal(deploySubject({ ...repository, branch: 'release' }), 'repo:Owner@12/Repo@34:ref:refs/heads/release');
    assert.equal(deploySubject({ ...repository, environment: 'live' }), 'repo:Owner@12/Repo@34:environment:live');
  });

  test('the prod role takes a token only from the prod environment of this repository', () => {
    assert.ok(prod.stacks.deploy, 'prod has a deploy stack');
    const prodDeploy = Template.fromStack(prod.stacks.deploy);
    prodDeploy.resourceCountIs('AWS::IAM::Role', 1);
    const [prodRole] = Object.values(prodDeploy.findResources('AWS::IAM::Role'));
    assert.equal(prodRole?.['Properties'].RoleName, 'FinalApproach-prod-GitHubDeploy');
    const prodTrust = prodRole?.['Properties'].AssumeRolePolicyDocument.Statement;
    assert.equal(prodTrust.length, 1);
    assert.equal(prodTrust[0].Action, 'sts:AssumeRoleWithWebIdentity');
    // A job gets this subject only by naming the prod environment, and
    // GitHub starts such a job only after the approval that environment
    // asks for. A push to main alone gets the beta subject, which is not
    // this one.
    assert.deepEqual(prodTrust[0].Condition, {
      StringEquals: {
        'token.actions.githubusercontent.com:aud': 'sts.amazonaws.com',
        'token.actions.githubusercontent.com:sub':
          'repo:Njones27@153565100/Final_Approach@1468200614:environment:prod',
      },
    });
  });

  test('no stage takes the token of another stage', () => {
    const subjects = Object.values(stages).map((stage) => stage.deployFrom && deploySubject(stage.deployFrom));
    assert.equal(new Set(subjects).size, subjects.length);
    for (const subject of subjects) assert.doesNotMatch(subject ?? '*', /\*/);
  });

  test('the prod role is as narrow as the beta role', () => {
    assert.ok(prod.stacks.deploy);
    const prodDeploy = Template.fromStack(prod.stacks.deploy);
    const allowed = statements(prodDeploy);
    assert.equal(allowed.length, 1);
    assert.equal(allowed[0]?.Action, 'sts:AssumeRole');
    const resources = [allowed[0]?.Resource].flat().map((resource) => JSON.stringify(resource));
    assert.equal(resources.length, 3);
    for (const resource of resources) assert.doesNotMatch(resource, /\*/);
    assert.deepEqual(Object.keys(prodDeploy.findOutputs('*')), ['DeployRoleArn']);
  });

  test('the role can only take on the roles the CDK bootstrap made for a deploy', () => {
    const allowed = statements(deploy);
    assert.equal(allowed.length, 1);
    assert.equal(allowed[0]?.Action, 'sts:AssumeRole');
    const resources = [allowed[0]?.Resource].flat().map((resource) => JSON.stringify(resource));
    assert.equal(resources.length, 3);
    for (const name of ['deploy-role', 'file-publishing-role', 'lookup-role']) {
      assert.ok(resources.some((resource) => resource.includes(`:role/cdk-hnb659fds-${name}-`)), name);
    }
    for (const resource of resources) assert.doesNotMatch(resource, /\*/);
    assert.equal(role?.['Properties'].ManagedPolicyArns, undefined);
    assert.equal(role?.['Properties'].MaxSessionDuration, 3600);
  });

  test('the role is the only thing the stack hands out', () => {
    deploy.resourceCountIs('AWS::IAM::Policy', 1);
    assert.deepEqual(Object.keys(deploy.findOutputs('*')), ['DeployRoleArn']);
  });
});

describe('alarms and the budget', () => {
  /** Every alarm in the three stacks that hold something to watch. */
  const alarmsOf = (stage: typeof beta) =>
    [stage.storage, stage.identity, stage.api].flatMap((template) =>
      Object.values(template.findResources('AWS::CloudWatch::Alarm')).map((alarm) => alarm['Properties']),
    );

  test('each stage has one topic, and it takes only encrypted connections', () => {
    for (const stage of [beta, prod]) {
      stage.alerts.resourceCountIs('AWS::SNS::Topic', 1);
      stage.alerts.hasResourceProperties('AWS::SNS::TopicPolicy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({ Effect: 'Deny', Condition: { Bool: { 'aws:SecureTransport': 'false' } } }),
          ]),
        },
      });
    }
  });

  test('only the alarms and the budgets of the same account can write to the topic', () => {
    const [policy] = Object.values(prod.alerts.findResources('AWS::SNS::TopicPolicy'));
    const allowed = (policy?.['Properties'].PolicyDocument.Statement as Record<string, any>[]).filter(
      (statement) => statement['Effect'] === 'Allow',
    );
    assert.deepEqual(allowed.map((statement) => statement['Principal']).sort((a, b) => a.Service.localeCompare(b.Service)), [
      { Service: 'budgets.amazonaws.com' },
      { Service: 'cloudwatch.amazonaws.com' },
    ]);
    for (const statement of allowed) {
      assert.equal(statement['Action'], 'sns:Publish');
      assert.deepEqual(statement['Condition'].StringEquals, { 'aws:SourceAccount': { Ref: 'AWS::AccountId' } });
      assert.ok(statement['Condition'].ArnLike['aws:SourceArn']);
    }
  });

  test('the topic has no subscriber, so no address is written in the repository', () => {
    for (const stage of [beta, prod]) stage.alerts.resourceCountIs('AWS::SNS::Subscription', 0);
  });

  test('every function has an alarm on its failed runs', () => {
    for (const stage of [beta, prod]) {
      const watched = alarmsOf(stage)
        .filter((alarm) => alarm.Namespace === 'AWS/Lambda' && alarm.MetricName === 'Errors')
        .map((alarm) => alarm.AlarmName.replace(/^final-approach-(beta|prod)-/, ''))
        .sort();
      assert.deepEqual(watched, [
        'Account-errors',
        'Closer-errors',
        'CreateAuthChallenge-errors',
        'DefineAuthChallenge-errors',
        'Photos-errors',
        'Posts-errors',
        'PreSignUp-errors',
        'Spots-errors',
        'Sweeper-errors',
        'VerifyAuthChallenge-errors',
        'Votes-errors',
      ]);
    }
  });

  test('one failed run sets an alarm off, but a refused sign up is not news', () => {
    const thresholds = Object.fromEntries(alarmsOf(prod).map((alarm) => [alarm.AlarmName, alarm.Threshold]));
    assert.equal(thresholds['final-approach-prod-Photos-errors'], stages.prod.functionErrorsToAlarm);
    assert.equal(thresholds['final-approach-prod-Sweeper-errors'], 1);
    assert.equal(thresholds['final-approach-prod-PreSignUp-errors'], stages.prod.signUpRefusalsToAlarm);
    assert.ok(stages.prod.signUpRefusalsToAlarm > stages.prod.functionErrorsToAlarm);
  });

  test('the API has an alarm on its server errors', () => {
    for (const stage of [beta, prod]) {
      stage.api.hasResourceProperties('AWS::CloudWatch::Alarm', {
        Namespace: 'AWS/ApiGateway',
        MetricName: '5xx',
        Threshold: 1,
        Dimensions: [{ Name: 'ApiId', Value: Match.anyValue() }],
      });
    }
  });

  test('every alarm counts over one period, tells the topic, and stays quiet with no data', () => {
    for (const stage of [beta, prod]) {
      const alarms = alarmsOf(stage);
      assert.equal(alarms.length, 12);
      for (const alarm of alarms) {
        assert.equal(alarm.Statistic, 'Sum');
        assert.equal(alarm.Period, 300);
        assert.equal(alarm.EvaluationPeriods, 1);
        assert.equal(alarm.ComparisonOperator, 'GreaterThanOrEqualToThreshold');
        assert.equal(alarm.TreatMissingData, 'notBreaching');
        assert.equal(alarm.AlarmActions.length, 1);
        assert.match(JSON.stringify(alarm.AlarmActions[0]), /FinalApproach-(beta|prod)-Alerts/);
      }
    }
  });

  test('the budget is the stage’s own, and it tells the topic', () => {
    for (const [stage, settings] of [
      [beta, stages.beta],
      [prod, stages.prod],
    ] as const) {
      const [budget] = Object.values(stage.alerts.findResources('AWS::Budgets::Budget'));
      const properties = budget?.['Properties'];
      assert.deepEqual(properties.Budget.BudgetLimit, { Amount: settings.monthlyBudgetUSD, Unit: 'USD' });
      assert.equal(properties.Budget.BudgetType, 'COST');
      assert.equal(properties.Budget.TimeUnit, 'MONTHLY');
      assert.equal(properties.Budget.BudgetName, `final-approach-${settings.name}-monthly-cost`);

      const notices = properties.NotificationsWithSubscribers as Record<string, any>[];
      assert.deepEqual(
        notices.map((notice) => `${notice['Notification'].NotificationType} ${notice['Notification'].Threshold}`),
        [...settings.budgetAlertPercents.map((percent) => `ACTUAL ${percent}`), 'FORECASTED 100'],
      );
      for (const notice of notices) {
        assert.equal(notice['Notification'].ThresholdType, 'PERCENTAGE');
        assert.equal(notice['Subscribers'].length, 1);
        assert.equal(notice['Subscribers'][0].SubscriptionType, 'SNS');
      }
      // The budget is refused until the topic lets it write.
      assert.equal(budget?.['DependsOn'].length, 1);
    }
  });

  test('the stage settings are amounts that make sense', () => {
    for (const stage of Object.values(stages)) {
      assert.ok(stage.monthlyBudgetUSD > 0);
      assert.ok(stage.alarmPeriodMinutes >= 1);
      assert.ok(stage.functionErrorsToAlarm >= 1 && stage.serverErrorsToAlarm >= 1);
      // A budget takes five notices at most, and one is the forecast.
      assert.ok(stage.budgetAlertPercents.length >= 1 && stage.budgetAlertPercents.length <= 4);
      for (const percent of stage.budgetAlertPercents) assert.ok(percent > 0);
    }
  });
});

describe('stages', () => {
  test('only beta and prod exist', () => {
    assert.deepEqual(Object.keys(stages), ['beta', 'prod']);
    assert.ok(isStageName('beta'));
    for (const value of ['dev', 'toString', '', undefined, 3]) assert.equal(isStageName(value), false);
  });

  test('a deleted account marker outlives every access token and upload link', () => {
    for (const stage of Object.values(stages)) {
      assert.ok(deletedAccountMarkerSeconds(stage) > stage.accessTokenMinutes * 60 + stage.uploadLinkSeconds);
    }
  });

  test('the stacks carry the stage in their names', () => {
    assert.equal(beta.stacks.api.stackName, 'FinalApproach-beta-Api');
    assert.equal(prod.stacks.storage.stackName, 'FinalApproach-prod-Storage');
    assert.equal(prod.stacks.alerts.stackName, 'FinalApproach-prod-Alerts');
  });
});
