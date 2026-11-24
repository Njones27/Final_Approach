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
  test('the app can only use the custom flow, with no web sign in and no secret', () => {
    beta.identity.hasResourceProperties('AWS::Cognito::UserPoolClient', {
      ExplicitAuthFlows: ['ALLOW_CUSTOM_AUTH', 'ALLOW_REFRESH_TOKEN_AUTH'],
      AllowedOAuthFlowsUserPoolClient: false,
      GenerateSecret: false,
      PreventUserExistenceErrors: 'ENABLED',
      EnableTokenRevocation: true,
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
  test('has exactly the four routes, and each needs a signed in user', () => {
    const routes = Object.values(beta.api.findResources('AWS::ApiGatewayV2::Route')).map(
      (route) => route['Properties'],
    );
    assert.deepEqual(routes.map((route) => route.RouteKey).sort(), [
      'DELETE /account',
      'DELETE /photos/{photoID}',
      'GET /photos',
      'PUT /photos/{photoID}',
    ]);
    for (const route of routes) assert.equal(route.AuthorizationType, 'JWT', route.RouteKey);
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
      'dynamodb:BatchWriteItem',
      'dynamodb:ConditionCheckItem',
      'dynamodb:DeleteItem',
      'dynamodb:PutItem',
      'dynamodb:PutItem',
      'dynamodb:Query',
      'dynamodb:Query',
      's3:DeleteObject',
      's3:DeleteObject',
      's3:GetObject',
      's3:ListBucket',
      's3:PutObject',
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
    assert.equal(imageStatements.length, 2);
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

  test('only beta can be deployed by GitHub, so prod is deployed by hand', () => {
    assert.equal(stack.stackName, 'FinalApproach-beta-Deploy');
    assert.equal(prod.stacks.deploy, undefined);
    assert.equal(stages.prod.deployFrom, undefined);
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
    assert.equal(
      deploySubject({ owner: 'Owner', ownerID: 12, repository: 'Repo', repositoryID: 34, branch: 'release' }),
      'repo:Owner@12/Repo@34:ref:refs/heads/release',
    );
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
  });
});
