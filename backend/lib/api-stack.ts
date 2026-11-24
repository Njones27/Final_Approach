import { CfnOutput, Duration, Stack, type StackProps } from 'aws-cdk-lib';
import { HttpApi, HttpMethod, HttpStage } from 'aws-cdk-lib/aws-apigatewayv2';
import { Rule, Schedule } from 'aws-cdk-lib/aws-events';
import { LambdaFunction } from 'aws-cdk-lib/aws-events-targets';
import { HttpUserPoolAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import type { IUserPool, IUserPoolClient } from 'aws-cdk-lib/aws-cognito';
import type { ITable } from 'aws-cdk-lib/aws-dynamodb';
import type { IBucket } from 'aws-cdk-lib/aws-s3';
import type { ITopic } from 'aws-cdk-lib/aws-sns';
import type { Construct } from 'constructs';
import { alarmPeriod, countAlarm } from './alarms.ts';
import { spotIndex, votingIndex } from '../src/shared/keys.ts';
import { allow, backendFunction, userImages } from './functions.ts';
import { deletedAccountMarkerSeconds, type StageSettings } from './stages.ts';

export interface ApiStackProps extends StackProps {
  readonly stage: StageSettings;
  readonly table: ITable;
  readonly images: IBucket;
  readonly users: IUserPool;
  readonly appClient: IUserPoolClient;
  readonly alerts: ITopic;
}

/** The longest API Gateway waits for a function, less a second to answer. */
const longestRequest = Duration.seconds(29);

/** The HTTP API the app talks to. Every route needs a signed in user. */
export class ApiStack extends Stack {
  readonly api: HttpApi;

  constructor(scope: Construct, id: string, props: ApiStackProps) {
    super(scope, id, props);
    const { stage, table, images, users, alerts } = props;
    const storage = { TABLE_NAME: table.tableName, BUCKET_NAME: images.bucketName };
    const votingRules = {
      VOTE_SCALE_MAX: String(stage.voteScaleMax),
      MIN_VOTES: String(stage.minVotesToFinalize),
    };
    const openPosts = `${table.tableArn}/index/${votingIndex.name}`;

    const photos = backendFunction(this, 'Photos', {
      source: 'photos/index.ts',
      stage,
      alerts,
      environment: {
        ...storage,
        PHOTOS_PER_PAGE: String(stage.photosPerPage),
        UPLOAD_LINK_SECONDS: String(stage.uploadLinkSeconds),
        IMAGE_LINK_SECONDS: String(stage.imageLinkSeconds),
        MAX_DOCUMENT_BYTES: String(stage.maxDocumentBytes),
        MAX_IMAGE_BYTES: String(stage.maxImageBytes),
      },
    });
    // A save is one transaction of a check and a put. A delete also removes
    // the photo's post in the same transaction.
    allow(
      photos,
      ['dynamodb:Query', 'dynamodb:PutItem', 'dynamodb:ConditionCheckItem', 'dynamodb:DeleteItem'],
      table.tableArn,
    );
    allow(photos, ['s3:PutObject', 's3:GetObject', 's3:DeleteObject'], images.arnForObjects(userImages));

    const posts = backendFunction(this, 'Posts', {
      source: 'posts/index.ts',
      stage,
      alerts,
      environment: {
        ...storage,
        POSTS_PER_PAGE: String(stage.photosPerPage),
        MAX_IMAGE_BYTES: String(stage.maxImageBytes),
        VOTING_WINDOW_HOURS: String(stage.votingWindowHours),
        SHOWN_TEXT_MAX_LENGTH: String(stage.shownTextMaxLength),
        ...votingRules,
      },
    });
    // A post is one transaction of two checks and a put, and a second post
    // of the same photo reads the first.
    allow(
      posts,
      // Showing a post at a spot, or taking it off, is an update of the post.
      ['dynamodb:Query', 'dynamodb:GetItem', 'dynamodb:PutItem', 'dynamodb:ConditionCheckItem', 'dynamodb:UpdateItem'],
      table.tableArn,
    );
    // A post reads the photo's image to see that no place is written in it.
    allow(posts, ['s3:GetObject'], images.arnForObjects(userImages));
    // S3 says an image is missing only to a caller that may list the bucket.
    // Any other caller is told it has no access, which reads like a fault.
    // The function lists nothing.
    allow(posts, ['s3:ListBucket'], images.bucketArn);

    const votes = backendFunction(this, 'Votes', {
      source: 'votes/index.ts',
      stage,
      alerts,
      environment: {
        ...storage,
        ...votingRules,
        VOTING_QUEUE_SIZE: String(stage.votingQueueSize),
        VOTING_QUEUE_READ_LIMIT: String(stage.votingQueueReadLimit),
        IMAGE_LINK_SECONDS: String(stage.imageLinkSeconds),
      },
    });
    // The queue reads the index of open posts and the voter's own votes.
    allow(votes, ['dynamodb:Query'], openPosts);
    // A vote is one transaction of a check, a put, and an update of the post's totals.
    allow(
      votes,
      ['dynamodb:BatchGetItem', 'dynamodb:PutItem', 'dynamodb:UpdateItem', 'dynamodb:ConditionCheckItem'],
      table.tableArn,
    );
    // A voter reads a photo through a link this function signs.
    allow(votes, ['s3:GetObject'], images.arnForObjects(userImages));

    // The list of spots is part of the function's own code. For a spot's
    // page it reads the index of photos shown at spots and nothing else in
    // the table, and it writes nothing.
    const spots = backendFunction(this, 'Spots', {
      source: 'spots/index.ts',
      stage,
      alerts,
      environment: {
        ...storage,
        PHOTOS_PER_SPOT: String(stage.photosPerSpot),
        IMAGE_LINK_SECONDS: String(stage.imageLinkSeconds),
      },
    });
    allow(spots, ['dynamodb:Query'], `${table.tableArn}/index/${spotIndex.name}`);
    // A visitor reads a photo through a link this function signs.
    allow(spots, ['s3:GetObject'], images.arnForObjects(userImages));

    const closer = backendFunction(this, 'Closer', {
      source: 'votes/closerIndex.ts',
      stage,
      alerts,
      timeout: Duration.minutes(1),
      environment: { TABLE_NAME: table.tableName, ...votingRules },
    });
    allow(closer, ['dynamodb:Query'], openPosts);
    allow(closer, ['dynamodb:UpdateItem'], table.tableArn);
    new Rule(this, 'CloseFinishedPosts', {
      description: `Closes the posts of the ${stage.name} backend whose voting has ended.`,
      schedule: Schedule.rate(Duration.minutes(stage.closerMinutes)),
      targets: [new LambdaFunction(closer)],
    });

    const account = backendFunction(this, 'Account', {
      source: 'account/index.ts',
      stage,
      alerts,
      timeout: longestRequest,
      environment: {
        ...storage,
        USER_POOL_ID: users.userPoolId,
        DELETED_ACCOUNT_MARKER_SECONDS: String(deletedAccountMarkerSeconds(stage)),
        MAX_BATCH_ATTEMPTS: '5',
      },
    });
    allow(
      account,
      ['dynamodb:Query', 'dynamodb:PutItem', 'dynamodb:BatchWriteItem', 'dynamodb:DeleteItem'],
      table.tableArn,
    );
    allow(account, ['s3:DeleteObject'], images.arnForObjects(userImages));
    allow(account, ['s3:ListBucket'], images.bucketArn, { StringLike: { 's3:prefix': [userImages] } });
    allow(account, ['cognito-idp:AdminDeleteUser'], users.userPoolArn);

    this.api = new HttpApi(this, 'Api', {
      apiName: `final-approach-${stage.name}`,
      createDefaultStage: false,
      defaultAuthorizer: new HttpUserPoolAuthorizer('SignedIn', users, {
        userPoolClients: [props.appClient],
      }),
    });
    const live = new HttpStage(this, 'Live', {
      httpApi: this.api,
      stageName: '$default',
      autoDeploy: true,
      throttle: { rateLimit: stage.requestsPerSecond, burstLimit: stage.requestBurst },
    });

    const photoRoutes = new HttpLambdaIntegration('PhotoRoutes', photos);
    this.api.addRoutes({ path: '/photos', methods: [HttpMethod.GET], integration: photoRoutes });
    this.api.addRoutes({
      path: '/photos/{photoID}',
      methods: [HttpMethod.PUT, HttpMethod.DELETE],
      integration: photoRoutes,
    });
    const postRoutes = new HttpLambdaIntegration('PostRoutes', posts);
    this.api.addRoutes({ path: '/posts', methods: [HttpMethod.GET], integration: postRoutes });
    this.api.addRoutes({
      path: '/posts/{photoID}',
      methods: [HttpMethod.PUT],
      integration: postRoutes,
    });
    this.api.addRoutes({
      path: '/posts/{photoID}/spot',
      methods: [HttpMethod.PUT, HttpMethod.DELETE],
      integration: postRoutes,
    });
    const voteRoutes = new HttpLambdaIntegration('VoteRoutes', votes);
    this.api.addRoutes({ path: '/votes/queue', methods: [HttpMethod.GET], integration: voteRoutes });
    this.api.addRoutes({
      path: '/votes/{postID}',
      methods: [HttpMethod.PUT],
      integration: voteRoutes,
    });
    const spotRoutes = new HttpLambdaIntegration('SpotRoutes', spots);
    this.api.addRoutes({ path: '/spots', methods: [HttpMethod.GET], integration: spotRoutes });
    this.api.addRoutes({
      path: '/spots/{spotID}/photos',
      methods: [HttpMethod.GET],
      integration: spotRoutes,
    });
    this.api.addRoutes({
      path: '/account',
      methods: [HttpMethod.DELETE],
      integration: new HttpLambdaIntegration('AccountRoutes', account),
    });

    // A function that fails answers with a server error, and so does an API
    // that cannot reach its function. This alarm catches both.
    countAlarm(this, 'ServerErrors', {
      stage,
      alerts,
      watches: 'Api-server-errors',
      metric: this.api.metricServerError({ period: alarmPeriod(stage), statistic: 'Sum' }),
      threshold: stage.serverErrorsToAlarm,
      description: `The API of the ${stage.name} backend answered with a server error. The logs of the Photos, Posts, Votes, Spots, and Account functions say why.`,
    });

    new CfnOutput(this, 'ApiURL', { value: live.url });
    new CfnOutput(this, 'UserPoolID', { value: users.userPoolId });
    new CfnOutput(this, 'AppClientID', { value: props.appClient.userPoolClientId });
  }
}
