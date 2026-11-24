import {
  AdminDeleteUserCommand,
  type CognitoIdentityProviderClient,
} from '@aws-sdk/client-cognito-identity-provider';
import { DeleteObjectsCommand, ListObjectsV2Command, type S3Client } from '@aws-sdk/client-s3';
import {
  BatchWriteCommand,
  PutCommand,
  QueryCommand,
  type DynamoDBDocumentClient,
} from '@aws-sdk/lib-dynamodb';
import { deletedAccountSortKey, partitionKey, userFolder } from '../shared/keys.ts';
import type { AccountStore } from './store.ts';

export interface AwsAccountStoreSettings {
  readonly dynamo: Pick<DynamoDBDocumentClient, 'send'>;
  readonly s3: Pick<S3Client, 'send'>;
  readonly cognito: Pick<CognitoIdentityProviderClient, 'send'>;
  readonly tableName: string;
  readonly bucketName: string;
  readonly userPoolID: string;
  /** How long the marker of the deleted account is kept. */
  readonly markerSeconds: number;
  /** How many times a batch of deletes is retried before the call fails. */
  readonly maxBatchAttempts: number;
}

/** The most records DynamoDB deletes in one batch. */
const recordsPerBatch = 25;

/** The name of the table attribute DynamoDB expires items by. */
export const expiryAttribute = 'expiresAt';

export function makeAwsAccountStore(settings: AwsAccountStoreSettings): AccountStore {
  const { dynamo, s3, cognito, tableName, bucketName } = settings;

  /**
   * Leaves a marker that turns away every later write for this user. It
   * goes first, so nothing new can arrive while the rest is removed. The
   * marker holds no personal data and expires by itself.
   */
  async function markDeleted(pk: string, now: Date): Promise<void> {
    await dynamo.send(
      new PutCommand({
        TableName: tableName,
        Item: {
          pk,
          sk: deletedAccountSortKey,
          deletedAt: now.toISOString(),
          [expiryAttribute]: Math.floor(now.getTime() / 1000) + settings.markerSeconds,
        },
      }),
    );
  }

  async function deleteImages(userID: string): Promise<void> {
    let token: string | undefined;
    do {
      const page = await s3.send(
        new ListObjectsV2Command({
          Bucket: bucketName,
          Prefix: userFolder(userID),
          ContinuationToken: token,
        }),
      );
      const keys = (page.Contents ?? []).flatMap((object) => (object.Key ? [{ Key: object.Key }] : []));
      if (keys.length > 0) {
        const result = await s3.send(
          new DeleteObjectsCommand({ Bucket: bucketName, Delete: { Objects: keys, Quiet: true } }),
        );
        if ((result.Errors ?? []).length > 0) {
          throw new Error(`${result.Errors?.length} images could not be deleted.`);
        }
      }
      token = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (token);
  }

  async function deleteBatch(keys: Record<string, unknown>[]): Promise<void> {
    let pending = keys.map((Key) => ({ DeleteRequest: { Key } }));
    for (let attempt = 0; pending.length > 0; attempt += 1) {
      if (attempt >= settings.maxBatchAttempts) {
        throw new Error('Some records could not be deleted.');
      }
      const result = await dynamo.send(
        new BatchWriteCommand({ RequestItems: { [tableName]: pending } }),
      );
      pending = (result.UnprocessedItems?.[tableName] ?? []) as typeof pending;
    }
  }

  async function deleteRecords(pk: string): Promise<void> {
    let startKey: Record<string, unknown> | undefined;
    do {
      const page = await dynamo.send(
        new QueryCommand({
          TableName: tableName,
          KeyConditionExpression: 'pk = :pk',
          ExpressionAttributeValues: { ':pk': pk },
          ProjectionExpression: 'pk, sk',
          ConsistentRead: true,
          ExclusiveStartKey: startKey,
        }),
      );
      // The marker stays, so a token that is still valid cannot write again.
      const keys = (page.Items ?? [])
        .filter((item) => item['sk'] !== deletedAccountSortKey)
        .map((item) => ({ pk: item['pk'], sk: item['sk'] }));
      for (let start = 0; start < keys.length; start += recordsPerBatch) {
        await deleteBatch(keys.slice(start, start + recordsPerBatch));
      }
      startKey = page.LastEvaluatedKey;
    } while (startKey);
  }

  async function deleteSignIn(username: string): Promise<void> {
    try {
      await cognito.send(
        new AdminDeleteUserCommand({ UserPoolId: settings.userPoolID, Username: username }),
      );
    } catch (error) {
      // A second try after a failure finds the user already gone.
      if (error instanceof Error && error.name === 'UserNotFoundException') return;
      throw error;
    }
  }

  return {
    async deleteEverything(caller, now) {
      const pk = partitionKey(caller.userID);
      await markDeleted(pk, now);
      await deleteImages(caller.userID);
      await deleteRecords(pk);
      await deleteSignIn(caller.username);
    },
  };
}
