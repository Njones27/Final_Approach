import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DeleteObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { setting } from '../shared/settings.ts';
import { standingOf } from './standing.ts';
import { makeSweeper } from './sweeper.ts';

const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const s3 = new S3Client({});
const tableName = setting('TABLE_NAME');
const bucketName = setting('BUCKET_NAME');

/** The function S3 calls when an image is uploaded. */
export const handler = makeSweeper({
  standing: (userID, photoID) => standingOf(dynamo, tableName, userID, photoID),
  removeImage: async (key) => {
    await s3.send(new DeleteObjectCommand({ Bucket: bucketName, Key: key }));
  },
});
