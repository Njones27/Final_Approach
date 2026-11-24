import { GetObjectCommand, type S3Client } from '@aws-sdk/client-s3';
import {
  BatchGetCommand,
  QueryCommand,
  TransactWriteCommand,
  UpdateCommand,
  type DynamoDBDocumentClient,
} from '@aws-sdk/lib-dynamodb';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import {
  deletedAccountSortKey,
  imageKey,
  partitionKey,
  postSortKey,
  userOfPartitionKey,
  voteSortKey,
  voteSortKeyPrefix,
  votingIndex,
} from '../shared/keys.ts';
import type { CloserStore } from './closer.ts';
import type { OpenPost, VoteOutcome, VoteStore } from './store.ts';

export interface AwsVoteStoreSettings {
  readonly dynamo: Pick<DynamoDBDocumentClient, 'send'>;
  readonly tableName: string;
  /** The votes a post needs before it can close. */
  readonly minVotes: number;
}

export interface AwsVoteLinkSettings {
  readonly s3: S3Client;
  readonly bucketName: string;
  readonly imageLinkSeconds: number;
}

/** The order of the parts of a vote, which names the one that failed. */
const accountCheckIndex = 0;
const voteIndex = 1;

/** The most keys DynamoDB reads in one batch. */
const keysPerBatch = 100;

function isNamed(error: unknown, name: string): boolean {
  return error instanceof Error && error.name === name;
}

function isCancelledTransaction(error: unknown): error is { CancellationReasons?: { Code?: string }[] } {
  return isNamed(error, 'TransactionCanceledException');
}

const count = (value: unknown): number => (typeof value === 'number' ? value : 0);

function openPostOf(item: Record<string, unknown>): OpenPost | undefined {
  const ownerID = userOfPartitionKey(String(item['pk']));
  if (ownerID === undefined) return undefined;
  return {
    ownerID,
    photoID: String(item['photoID']),
    postID: String(item['postID']),
    closesAt: String(item['closesAt']),
    voteCount: count(item['voteCount']),
    weightSum: count(item['weightSum']),
    weightedValueSum: count(item['weightedValueSum']),
  };
}

const postKey = (post: OpenPost) => ({ pk: partitionKey(post.ownerID), sk: postSortKey(post.photoID) });

/** Reads the index of posts that carry the open mark. */
function makeIndexReader(dynamo: Pick<DynamoDBDocumentClient, 'send'>, tableName: string) {
  return async function read(
    condition: string,
    values: Record<string, unknown>,
    options: { readonly limit?: number; readonly startKey?: Record<string, unknown> } = {},
  ): Promise<{ posts: OpenPost[]; lastKey?: Record<string, unknown> }> {
    const result = await dynamo.send(
      new QueryCommand({
        TableName: tableName,
        IndexName: votingIndex.name,
        KeyConditionExpression: `${votingIndex.partitionKey} = :open${condition}`,
        ExpressionAttributeValues: { ':open': votingIndex.open, ...values },
        ...(options.limit ? { Limit: options.limit } : {}),
        ...(options.startKey ? { ExclusiveStartKey: options.startKey } : {}),
      }),
    );
    const posts = (result.Items ?? []).flatMap((item) => openPostOf(item) ?? []);
    return { posts, ...(result.LastEvaluatedKey ? { lastKey: result.LastEvaluatedKey } : {}) };
  };
}

/** Votes kept in the DynamoDB table, each under its voter. */
export function makeAwsVoteStore(settings: AwsVoteStoreSettings & AwsVoteLinkSettings): VoteStore {
  const { dynamo, tableName } = settings;
  const read = makeIndexReader(dynamo, tableName);

  return {
    async openPosts(startAfter, limit) {
      // The ids are random, so reading on from a random id gives every
      // post the same chance of being near the front.
      const after = await read(` AND ${votingIndex.sortKey} > :start`, { ':start': startAfter }, { limit });
      if (after.posts.length >= limit) return after.posts;
      // The end of the index was reached, so the rest comes from its start.
      const before = await read(
        ` AND ${votingIndex.sortKey} <= :start`,
        { ':start': startAfter },
        { limit: limit - after.posts.length },
      );
      return [...after.posts, ...before.posts];
    },

    async openPost(postID) {
      const found = await read(` AND ${votingIndex.sortKey} = :id`, { ':id': postID }, { limit: 1 });
      return found.posts[0];
    },

    async votedOn(voterID, postIDs) {
      const voted = new Set<string>();
      const pk = partitionKey(voterID);
      for (let start = 0; start < postIDs.length; start += keysPerBatch) {
        const batch = postIDs.slice(start, start + keysPerBatch);
        const result = await dynamo.send(
          new BatchGetCommand({
            RequestItems: {
              [tableName]: {
                Keys: batch.map((postID) => ({ pk, sk: voteSortKey(postID) })),
                ProjectionExpression: 'sk',
                ConsistentRead: true,
              },
            },
          }),
        );
        const sortKeys = [
          ...(result.Responses?.[tableName] ?? []),
          // A key that was not read might be a vote. The post is left out
          // of this queue and can come back in the next one.
          ...(result.UnprocessedKeys?.[tableName]?.Keys ?? []),
        ].map((item) => String(item['sk']));
        for (const sortKey of sortKeys) voted.add(sortKey.slice(voteSortKeyPrefix.length));
      }
      return voted;
    },

    async cast(voterID, post, vote, now): Promise<VoteOutcome> {
      const voterKey = partitionKey(voterID);
      try {
        await dynamo.send(
          new TransactWriteCommand({
            TransactItems: [
              {
                ConditionCheck: {
                  TableName: tableName,
                  Key: { pk: voterKey, sk: deletedAccountSortKey },
                  ConditionExpression: 'attribute_not_exists(pk)',
                },
              },
              {
                Put: {
                  TableName: tableName,
                  // The vote names the post by its random id only, so a
                  // voter's records never say whose photo they voted on.
                  Item: { pk: voterKey, sk: voteSortKey(vote.postID), ...vote },
                  ConditionExpression: 'attribute_not_exists(pk)',
                },
              },
              {
                Update: {
                  TableName: tableName,
                  Key: postKey(post),
                  UpdateExpression: 'ADD voteCount :one, weightSum :weight, weightedValueSum :weighted',
                  // The post must still be there, be the same post, and be
                  // open. It is open until its window has ended and it has
                  // the votes it needs. This is checked here as well as in
                  // the handler, so two votes at once cannot both slip in.
                  ConditionExpression:
                    'attribute_exists(pk) AND postID = :postID AND ' +
                    '(closesAt > :now OR attribute_not_exists(voteCount) OR voteCount < :minVotes)',
                  ExpressionAttributeValues: {
                    ':one': 1,
                    ':weight': vote.weight,
                    ':weighted': vote.value * vote.weight,
                    ':postID': vote.postID,
                    ':now': now.toISOString(),
                    ':minVotes': settings.minVotes,
                  },
                },
              },
            ],
          }),
        );
        return 'counted';
      } catch (error) {
        if (!isCancelledTransaction(error)) throw error;
        const reasons = error.CancellationReasons ?? [];
        if (reasons[accountCheckIndex]?.Code === 'ConditionalCheckFailed') return 'accountDeleted';
        if (reasons[voteIndex]?.Code === 'ConditionalCheckFailed') return 'alreadyVoted';
        return 'votingClosed';
      }
    },

    imageLink(post) {
      return getSignedUrl(
        settings.s3,
        new GetObjectCommand({ Bucket: settings.bucketName, Key: imageKey(post.ownerID, post.photoID) }),
        { expiresIn: settings.imageLinkSeconds },
      );
    },
  };
}

/** What the closer needs of the table. */
export function makeAwsCloserStore(settings: AwsVoteStoreSettings): CloserStore {
  const { dynamo, tableName } = settings;
  const read = makeIndexReader(dynamo, tableName);

  return {
    async page(startKey) {
      const result = await read('', {}, startKey ? { startKey } : {});
      return { posts: result.posts, ...(result.lastKey ? { next: result.lastKey } : {}) };
    },

    async close(post, score, finalizedAt) {
      try {
        await dynamo.send(
          new UpdateCommand({
            TableName: tableName,
            Key: postKey(post),
            // Taking the open mark off drops the post from the index.
            UpdateExpression: `SET finalScore = :score, finalizedAt = :at REMOVE ${votingIndex.partitionKey}`,
            // The score is kept only if no vote was counted since the
            // totals were read. If one was, the next run closes the post.
            ConditionExpression: 'attribute_exists(pk) AND postID = :postID AND voteCount = :count',
            ExpressionAttributeValues: {
              ':score': score,
              ':at': finalizedAt,
              ':postID': post.postID,
              ':count': post.voteCount,
            },
          }),
        );
        return true;
      } catch (error) {
        if (isNamed(error, 'ConditionalCheckFailedException')) return false;
        throw error;
      }
    },
  };
}
