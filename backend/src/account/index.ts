import { CognitoIdentityProviderClient } from '@aws-sdk/client-cognito-identity-provider';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { S3Client } from '@aws-sdk/client-s3';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { numberSetting, setting } from '../shared/settings.ts';
import { makeAwsAccountStore } from './awsStore.ts';
import { makeAccountHandler } from './handler.ts';

/** The function behind the route that deletes an account. */
export const handler = makeAccountHandler({
  store: makeAwsAccountStore({
    dynamo: DynamoDBDocumentClient.from(new DynamoDBClient({})),
    s3: new S3Client({}),
    cognito: new CognitoIdentityProviderClient({}),
    tableName: setting('TABLE_NAME'),
    bucketName: setting('BUCKET_NAME'),
    userPoolID: setting('USER_POOL_ID'),
    markerSeconds: numberSetting('DELETED_ACCOUNT_MARKER_SECONDS'),
    maxBatchAttempts: numberSetting('MAX_BATCH_ATTEMPTS'),
  }),
  now: () => new Date(),
});
