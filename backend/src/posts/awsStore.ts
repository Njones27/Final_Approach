import { GetObjectCommand, type S3Client } from '@aws-sdk/client-s3';
import {
  GetCommand,
  QueryCommand,
  TransactWriteCommand,
  type DynamoDBDocumentClient,
} from '@aws-sdk/lib-dynamodb';
import {
  deletedAccountSortKey,
  imageKey,
  partitionKey,
  photoSortKey,
  postSortKey,
  postSortKeyPrefix,
  votingIndex,
} from '../shared/keys.ts';
import { emptyTally } from '../votes/standing.ts';
import type { PostOutcome, PostPage, PostStore, StoredPost } from './store.ts';

export interface AwsPostStoreSettings {
  readonly dynamo: Pick<DynamoDBDocumentClient, 'send'>;
  readonly s3: Pick<S3Client, 'send'>;
  readonly tableName: string;
  readonly bucketName: string;
  readonly postsPerPage: number;
  /** The largest image the backend accepts, so nothing larger is read. */
  readonly maxImageBytes: number;
}

/** The order of the parts of a post, which names the one that failed. */
const accountCheckIndex = 0;
const photoCheckIndex = 1;

interface CancellationReason {
  readonly Code?: string;
  readonly Item?: Record<string, unknown>;
}

function isCancelledTransaction(error: unknown): error is { CancellationReasons?: CancellationReason[] } {
  return error instanceof Error && error.name === 'TransactionCanceledException';
}

function isNamed(error: unknown, ...names: string[]): boolean {
  return error instanceof Error && names.includes(error.name);
}

const count = (value: unknown): number => (typeof value === 'number' ? value : 0);

function postOf(item: Record<string, unknown>): StoredPost {
  const finalScore = item['finalScore'];
  return {
    photoID: String(item['photoID']),
    postID: String(item['postID']),
    postedAt: String(item['postedAt']),
    closesAt: String(item['closesAt']),
    // A post has no totals until its first vote is counted.
    voteCount: count(item['voteCount']),
    weightSum: count(item['weightSum']),
    weightedValueSum: count(item['weightedValueSum']),
    ...(typeof finalScore === 'number' ? { finalScore } : {}),
  };
}

/** Posts kept in the DynamoDB table, beside the photos they show. */
export function makeAwsPostStore(settings: AwsPostStoreSettings): PostStore {
  const { dynamo, s3, tableName, bucketName } = settings;

  async function find(userID: string, photoID: string): Promise<StoredPost | undefined> {
    const result = await dynamo.send(
      new GetCommand({
        TableName: tableName,
        Key: { pk: partitionKey(userID), sk: postSortKey(photoID) },
        ConsistentRead: true,
      }),
    );
    return result.Item ? postOf(result.Item) : undefined;
  }

  return {
    async post(userID, post): Promise<PostOutcome> {
      const pk = partitionKey(userID);
      try {
        // All three parts hold or none does. A delete of the photo or of
        // the account that lands at the same moment cannot leave a post
        // with nothing behind it.
        await dynamo.send(
          new TransactWriteCommand({
            TransactItems: [
              {
                ConditionCheck: {
                  TableName: tableName,
                  Key: { pk, sk: deletedAccountSortKey },
                  ConditionExpression: 'attribute_not_exists(pk)',
                },
              },
              {
                ConditionCheck: {
                  TableName: tableName,
                  Key: { pk, sk: photoSortKey(post.photoID) },
                  ConditionExpression: 'attribute_exists(pk) AND attribute_not_exists(deletedAt)',
                  // What the failed check hands back says whether the photo
                  // was deleted or was never saved.
                  ReturnValuesOnConditionCheckFailure: 'ALL_OLD',
                },
              },
              {
                Put: {
                  TableName: tableName,
                  Item: {
                    pk,
                    sk: postSortKey(post.photoID),
                    ...post,
                    [votingIndex.partitionKey]: votingIndex.open,
                  },
                  // A photo is posted once. A second post would start its
                  // votes again.
                  ConditionExpression: 'attribute_not_exists(pk)',
                },
              },
            ],
          }),
        );
        return { outcome: 'posted', post: { ...post, ...emptyTally } };
      } catch (error) {
        if (!isCancelledTransaction(error)) throw error;
        const reasons = error.CancellationReasons ?? [];
        if (reasons[accountCheckIndex]?.Code === 'ConditionalCheckFailed') {
          return { outcome: 'accountDeleted' };
        }
        const photoCheck = reasons[photoCheckIndex];
        if (photoCheck?.Code === 'ConditionalCheckFailed') {
          // A record that fails the check and is there has been deleted.
          // With no record there, nothing comes back.
          const wasDeleted = photoCheck.Item !== undefined && 'deletedAt' in photoCheck.Item;
          return { outcome: wasDeleted ? 'photoDeleted' : 'photoNotSaved' };
        }
        const existing = await find(userID, post.photoID);
        // The post was there a moment ago and is gone, so its photo was deleted.
        return existing ? { outcome: 'alreadyPosted', post: existing } : { outcome: 'photoDeleted' };
      }
    },

    async list(userID, after): Promise<PostPage> {
      const pk = partitionKey(userID);
      const result = await dynamo.send(
        new QueryCommand({
          TableName: tableName,
          KeyConditionExpression: 'pk = :pk AND begins_with(sk, :posts)',
          ExpressionAttributeValues: { ':pk': pk, ':posts': postSortKeyPrefix },
          Limit: settings.postsPerPage,
          // The page marker holds only a photo id. The partition is always
          // the caller's own, so a marker cannot reach into another account.
          ...(after ? { ExclusiveStartKey: { pk, sk: postSortKey(after) } } : {}),
        }),
      );
      const lastKey = result.LastEvaluatedKey?.['sk'];
      const nextAfter =
        typeof lastKey === 'string' ? lastKey.slice(postSortKeyPrefix.length) : undefined;
      return { posts: (result.Items ?? []).map(postOf), ...(nextAfter ? { nextAfter } : {}) };
    },

    async imageBytes(userID, photoID) {
      try {
        const result = await s3.send(
          new GetObjectCommand({ Bucket: bucketName, Key: imageKey(userID, photoID) }),
        );
        // An upload link takes nothing above the limit, so a larger object
        // was not put there by the app. It is treated as no image.
        if ((result.ContentLength ?? 0) > settings.maxImageBytes) return undefined;
        return await result.Body?.transformToByteArray();
      } catch (error) {
        if (isNamed(error, 'NoSuchKey', 'NotFound')) return undefined;
        throw error;
      }
    },
  };
}
