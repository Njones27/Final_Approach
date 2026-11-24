import { CfnOutput, Duration, Stack, type StackProps } from 'aws-cdk-lib';
import { HttpApi, HttpMethod, HttpStage } from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpUserPoolAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import type { IUserPool, IUserPoolClient } from 'aws-cdk-lib/aws-cognito';
import type { ITable } from 'aws-cdk-lib/aws-dynamodb';
import type { IBucket } from 'aws-cdk-lib/aws-s3';
import type { ITopic } from 'aws-cdk-lib/aws-sns';
import type { Construct } from 'constructs';
import { alarmPeriod, countAlarm } from './alarms.ts';
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
      },
    });
    // A post is one transaction of two checks and a put, and a second post
    // of the same photo reads the first.
    allow(
      posts,
      ['dynamodb:Query', 'dynamodb:GetItem', 'dynamodb:PutItem', 'dynamodb:ConditionCheckItem'],
      table.tableArn,
    );
    // A post reads the photo's image to see that no place is written in it.
    allow(posts, ['s3:GetObject'], images.arnForObjects(userImages));
    // S3 says an image is missing only to a caller that may list the bucket.
    // Any other caller is told it has no access, which reads like a fault.
    // The function lists nothing.
    allow(posts, ['s3:ListBucket'], images.bucketArn);

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
      description: `The API of the ${stage.name} backend answered with a server error. The logs of the Photos, Posts, and Account functions say why.`,
    });

    new CfnOutput(this, 'ApiURL', { value: live.url });
    new CfnOutput(this, 'UserPoolID', { value: users.userPoolId });
    new CfnOutput(this, 'AppClientID', { value: props.appClient.userPoolClientId });
  }
}
