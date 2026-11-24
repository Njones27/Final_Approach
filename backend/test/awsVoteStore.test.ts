import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { S3Client } from '@aws-sdk/client-s3';
import { makeAwsCloserStore, makeAwsVoteStore } from '../src/votes/awsStore.ts';
import type { OpenPost } from '../src/votes/store.ts';
import { awsError, fakeClient } from './support.ts';

/** A real S3 client with made up keys. Signing a link needs no network. */
const signer = new S3Client({
  region: 'us-east-1',
  credentials: { accessKeyId: 'AKIAEXAMPLE', secretAccessKey: 'example' },
});

function setUp(replies: Record<string, unknown[]> = {}) {
  const dynamo = fakeClient(replies);
  const settings = { dynamo, tableName: 'records', minVotes: 5 };
  const store = makeAwsVoteStore({ ...settings, s3: signer, bucketName: 'images', imageLinkSeconds: 900 });
  return { dynamo, store, closer: makeAwsCloserStore(settings) };
}

const item = (owner: string, postID: string, more: Record<string, unknown> = {}) => ({
  pk: `USER#${owner}`,
  sk: `POST#photo-${postID}`,
  photoID: `photo-${postID}`,
  postID,
  postedAt: '2026-11-24T12:00:00.000Z',
  closesAt: '2026-11-27T12:00:00.000Z',
  votingKey: 'OPEN',
  ...more,
});
const post = (owner: string, postID: string, more: Partial<OpenPost> = {}): OpenPost => ({
  ownerID: owner,
  photoID: `photo-${postID}`,
  postID,
  closesAt: '2026-11-27T12:00:00.000Z',
  voteCount: 0,
  weightSum: 0,
  weightedValueSum: 0,
  ...more,
});
const cancelled = (...codes: string[]) =>
  awsError('TransactionCanceledException', { CancellationReasons: codes.map((Code) => ({ Code })) });
const now = new Date('2026-11-25T08:00:00.000Z');
const vote = { postID: 'b', value: 4, weight: 1, votedAt: now.toISOString() };

describe('reading the open posts', () => {
  test('the queue reads the index on from a random id', async () => {
    const { dynamo, store } = setUp({
      QueryCommand: [{ Items: [item('u2', 'c'), item('u3', 'd', { voteCount: 2, weightSum: 2, weightedValueSum: 9 })] }],
    });
    assert.deepEqual(await store.openPosts('b', 2), [
      post('u2', 'c'),
      post('u3', 'd', { voteCount: 2, weightSum: 2, weightedValueSum: 9 }),
    ]);
    assert.deepEqual(dynamo.sent, [
      {
        name: 'QueryCommand',
        input: {
          TableName: 'records',
          IndexName: 'Voting',
          KeyConditionExpression: 'votingKey = :open AND postID > :start',
          ExpressionAttributeValues: { ':open': 'OPEN', ':start': 'b' },
          Limit: 2,
        },
      },
    ]);
  });

  test('at the end of the index the rest comes from its start', async () => {
    const { dynamo, store } = setUp({
      QueryCommand: [{ Items: [item('u2', 'c')] }, { Items: [item('u3', 'a')] }],
    });
    assert.deepEqual((await store.openPosts('b', 3)).map((found) => found.postID), ['c', 'a']);
    assert.deepEqual(dynamo.sent[1]?.input, {
      TableName: 'records',
      IndexName: 'Voting',
      KeyConditionExpression: 'votingKey = :open AND postID <= :start',
      ExpressionAttributeValues: { ':open': 'OPEN', ':start': 'b' },
      Limit: 2,
    });
  });

  test('one post is found by the id voters know it by', async () => {
    const { dynamo, store } = setUp({ QueryCommand: [{ Items: [item('u2', 'b')] }, {}] });
    assert.deepEqual(await store.openPost('b'), post('u2', 'b'));
    assert.equal(dynamo.sent[0]?.input.KeyConditionExpression, 'votingKey = :open AND postID = :id');
    assert.equal(dynamo.sent[0]?.input.IndexName, 'Voting');
    assert.equal(await store.openPost('z'), undefined);
  });

  test('a record that is not under a user is passed over', async () => {
    const { store } = setUp({ QueryCommand: [{ Items: [{ ...item('u2', 'c'), pk: 'OTHER#x' }, item('u2', 'd')] }] });
    assert.deepEqual((await store.openPosts('b', 2)).map((found) => found.postID), ['d']);
  });
});

describe('which posts a voter has voted on', () => {
  test('the voter’s own votes are read, with no stale copies', async () => {
    const { dynamo, store } = setUp({
      BatchGetCommand: [{ Responses: { records: [{ sk: 'VOTE#b' }] } }],
    });
    assert.deepEqual([...(await store.votedOn('u1', ['a', 'b']))], ['b']);
    assert.deepEqual(dynamo.sent[0]?.input.RequestItems.records, {
      Keys: [
        { pk: 'USER#u1', sk: 'VOTE#a' },
        { pk: 'USER#u1', sk: 'VOTE#b' },
      ],
      ProjectionExpression: 'sk',
      ConsistentRead: true,
    });
  });

  test('a key that was not read counts as voted, so the post waits for the next queue', async () => {
    const { store } = setUp({
      BatchGetCommand: [{ Responses: { records: [] }, UnprocessedKeys: { records: { Keys: [{ pk: 'USER#u1', sk: 'VOTE#a' }] } } }],
    });
    assert.deepEqual([...(await store.votedOn('u1', ['a', 'b']))], ['a']);
  });

  test('nothing is read for no posts, and many posts go in batches of 100', async () => {
    const none = setUp();
    assert.equal((await none.store.votedOn('u1', [])).size, 0);
    assert.deepEqual(none.dynamo.sent, []);

    const many = setUp();
    await many.store.votedOn('u1', Array.from({ length: 130 }, (_, index) => `p${index}`));
    assert.deepEqual(many.dynamo.sent.map((command) => command.input.RequestItems.records.Keys.length), [100, 30]);
  });
});

describe('counting a vote', () => {
  test('the vote and the post’s totals change in one transaction', async () => {
    const { dynamo, store } = setUp();
    assert.equal(await store.cast('u1', post('u2', 'b'), vote, now), 'counted');
    const [account, put, update] = dynamo.sent[0]?.input.TransactItems;
    assert.deepEqual(account.ConditionCheck, {
      TableName: 'records',
      Key: { pk: 'USER#u1', sk: 'ACCOUNT#DELETED' },
      ConditionExpression: 'attribute_not_exists(pk)',
    });
    assert.deepEqual(put.Put, {
      TableName: 'records',
      Item: { pk: 'USER#u1', sk: 'VOTE#b', ...vote },
      ConditionExpression: 'attribute_not_exists(pk)',
    });
    assert.deepEqual(update.Update, {
      TableName: 'records',
      Key: { pk: 'USER#u2', sk: 'POST#photo-b' },
      UpdateExpression: 'ADD voteCount :one, weightSum :weight, weightedValueSum :weighted',
      ConditionExpression:
        'attribute_exists(pk) AND postID = :postID AND ' +
        '(closesAt > :now OR attribute_not_exists(voteCount) OR voteCount < :minVotes)',
      ExpressionAttributeValues: {
        ':one': 1,
        ':weight': 1,
        ':weighted': 4,
        ':postID': 'b',
        ':now': '2026-11-25T08:00:00.000Z',
        ':minVotes': 5,
      },
    });
  });

  test('a vote sits under its voter and never names the photo’s owner', async () => {
    const { dynamo, store } = setUp();
    await store.cast('u1', post('u2', 'b'), vote, now);
    const kept = JSON.stringify(dynamo.sent[0]?.input.TransactItems[1].Put.Item);
    assert.ok(kept.includes('USER#u1'));
    assert.ok(!kept.includes('u2'));
    assert.ok(!kept.includes('photo-b'));
  });

  test('a heavier vote adds its weight to both totals', async () => {
    const { dynamo, store } = setUp();
    await store.cast('u1', post('u2', 'b'), { ...vote, value: 5, weight: 3 }, now);
    const values = dynamo.sent[0]?.input.TransactItems[2].Update.ExpressionAttributeValues;
    assert.deepEqual([values[':one'], values[':weight'], values[':weighted']], [1, 3, 15]);
  });

  test('each part that fails names why the vote was turned away', async () => {
    const failed = 'ConditionalCheckFailed';
    const outcomes = [
      [cancelled(failed, 'None', 'None'), 'accountDeleted'],
      [cancelled('None', failed, 'None'), 'alreadyVoted'],
      [cancelled('None', 'None', failed), 'votingClosed'],
    ] as const;
    for (const [error, outcome] of outcomes) {
      const { store } = setUp({ TransactWriteCommand: [error] });
      assert.equal(await store.cast('u1', post('u2', 'b'), vote, now), outcome);
    }
  });

  test('any other failure is passed on', async () => {
    const { store } = setUp({ TransactWriteCommand: [awsError('InternalServerError')] });
    await assert.rejects(store.cast('u1', post('u2', 'b'), vote, now), /InternalServerError/);
  });
});

describe('the link a voter reads an image through', () => {
  test('reads the one image for a short time', async () => {
    const { store } = setUp();
    const url = new URL(await store.imageLink(post('u2', 'b')));
    assert.equal(url.pathname, '/users/u2/photos/photo-b.jpg');
    assert.equal(url.searchParams.get('X-Amz-Expires'), '900');
  });
});

describe('closing a post', () => {
  test('a page of open posts is read from the index, and the next starts where it ended', async () => {
    const lastKey = { votingKey: 'OPEN', postID: 'c', pk: 'USER#u2', sk: 'POST#photo-c' };
    const { dynamo, closer } = setUp({ QueryCommand: [{ Items: [item('u2', 'c')], LastEvaluatedKey: lastKey }, {}] });
    assert.deepEqual(await closer.page(), { posts: [post('u2', 'c')], next: lastKey });
    assert.deepEqual(await closer.page(lastKey), { posts: [] });
    assert.equal(dynamo.sent[0]?.input.KeyConditionExpression, 'votingKey = :open');
    assert.deepEqual(dynamo.sent[1]?.input.ExclusiveStartKey, lastKey);
  });

  test('closing keeps the score and takes the post out of the index', async () => {
    const { dynamo, closer } = setUp();
    const closing = post('u2', 'b', { voteCount: 5, weightSum: 5, weightedValueSum: 20 });
    assert.equal(await closer.close(closing, 75, '2026-11-27T12:00:00.000Z'), true);
    assert.deepEqual(dynamo.sent[0]?.input, {
      TableName: 'records',
      Key: { pk: 'USER#u2', sk: 'POST#photo-b' },
      UpdateExpression: 'SET finalScore = :score, finalizedAt = :at REMOVE votingKey',
      ConditionExpression: 'attribute_exists(pk) AND postID = :postID AND voteCount = :count',
      ExpressionAttributeValues: { ':score': 75, ':at': '2026-11-27T12:00:00.000Z', ':postID': 'b', ':count': 5 },
    });
  });

  test('a post that changed or is gone is left alone, and any other failure is passed on', async () => {
    const changed = setUp({ UpdateCommand: [awsError('ConditionalCheckFailedException')] });
    assert.equal(await changed.closer.close(post('u2', 'b'), 75, 'x'), false);
    const broken = setUp({ UpdateCommand: [awsError('InternalServerError')] });
    await assert.rejects(broken.closer.close(post('u2', 'b'), 75, 'x'), /InternalServerError/);
  });
});
