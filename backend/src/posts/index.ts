import { randomUUID } from 'node:crypto';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { S3Client } from '@aws-sdk/client-s3';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { numberSetting, setting } from '../shared/settings.ts';
import { makeAwsPostStore } from './awsStore.ts';
import { makePostsHandler } from './handler.ts';

/** The function behind the post routes. */
export const handler = makePostsHandler({
  store: makeAwsPostStore({
    dynamo: DynamoDBDocumentClient.from(new DynamoDBClient({})),
    s3: new S3Client({}),
    tableName: setting('TABLE_NAME'),
    bucketName: setting('BUCKET_NAME'),
    postsPerPage: numberSetting('POSTS_PER_PAGE'),
    maxImageBytes: numberSetting('MAX_IMAGE_BYTES'),
  }),
  votingWindowHours: numberSetting('VOTING_WINDOW_HOURS'),
  now: () => new Date(),
  newPostID: randomUUID,
});
