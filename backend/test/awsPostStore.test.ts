import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { makeAwsPostStore } from '../src/posts/awsStore.ts';
import { awsError, fakeClient } from './support.ts';

function setUp(replies: Record<string, unknown[]> = {}, s3Replies: Record<string, unknown[]> = {}) {
  const dynamo = fakeClient(replies);
  const s3 = fakeClient(s3Replies);
  const store = makeAwsPostStore({
    dynamo,
    s3,
    tableName: 'records',
    bucketName: 'images',
    postsPerPage: 2,
    maxImageBytes: 1000,
  });
  return { dynamo, s3, store };
}

const post = {
  photoID: 'p1',
  postID: 'post-1',
  postedAt: '2026-11-24T12:00:00.000Z',
  closesAt: '2026-11-27T12:00:00.000Z',
};
const cancelled = (...reasons: { Code: string; Item?: unknown }[]) =>
  awsError('TransactionCanceledException', { CancellationReasons: reasons });
const noVotes = { voteCount: 0, weightSum: 0, weightedValueSum: 0 };
const passed = { Code: 'None' };
const failed = { Code: 'ConditionalCheckFailed' };

describe('posting to the table', () => {
  test('a post checks the account and the photo, and is written once, in one transaction', async () => {
    const { dynamo, store } = setUp();
    assert.deepEqual(await store.post('u1', post), { outcome: 'posted', post: { ...post, ...noVotes } });
    const [account, photo, put] = dynamo.sent[0]?.input.TransactItems;
    assert.deepEqual(account.ConditionCheck, {
      TableName: 'records',
      Key: { pk: 'USER#u1', sk: 'ACCOUNT#DELETED' },
      ConditionExpression: 'attribute_not_exists(pk)',
    });
    assert.deepEqual(photo.ConditionCheck, {
      TableName: 'records',
      Key: { pk: 'USER#u1', sk: 'PHOTO#p1' },
      ConditionExpression: 'attribute_exists(pk) AND attribute_not_exists(deletedAt)',
      ReturnValuesOnConditionCheckFailure: 'ALL_OLD',
    });
    assert.deepEqual(put.Put, {
      TableName: 'records',
      Item: { pk: 'USER#u1', sk: 'POST#p1', ...post, votingKey: 'OPEN' },
      ConditionExpression: 'attribute_not_exists(pk)',
    });
  });

  test('a post lives in its owner’s partition, so deleting the account removes it', async () => {
    const { dynamo, store } = setUp();
    await store.post('u1', post);
    assert.equal(dynamo.sent[0]?.input.TransactItems[2].Put.Item.pk, 'USER#u1');
  });

  test('a post holds nothing about where the photo was taken', async () => {
    const { dynamo, store } = setUp();
    await store.post('u1', post);
    assert.deepEqual(Object.keys(dynamo.sent[0]?.input.TransactItems[2].Put.Item).sort(), [
      'closesAt',
      'photoID',
      'pk',
      'postID',
      'postedAt',
      'sk',
      'votingKey',
    ]);
  });

  test('a post for a deleted account is turned away', async () => {
    const { store } = setUp({ TransactWriteCommand: [cancelled(failed, passed, passed)] });
    assert.deepEqual(await store.post('u1', post), { outcome: 'accountDeleted' });
  });

  test('a post of a photo that was never saved is turned away', async () => {
    for (const reason of [failed, { ...failed, Item: {} }]) {
      const { store } = setUp({ TransactWriteCommand: [cancelled(passed, reason, passed)] });
      assert.deepEqual(await store.post('u1', post), { outcome: 'photoNotSaved' });
    }
  });

  test('a post of a deleted photo is turned away', async () => {
    const marker = { pk: { S: 'USER#u1' }, sk: { S: 'PHOTO#p1' }, deletedAt: { S: '2026-11-24T11:00:00.000Z' } };
    const { store } = setUp({
      TransactWriteCommand: [cancelled(passed, { ...failed, Item: marker }, passed)],
    });
    assert.deepEqual(await store.post('u1', post), { outcome: 'photoDeleted' });
  });

  test('a second post answers with the first, read with no stale copy', async () => {
    const first = { ...post, postID: 'post-0', postedAt: '2026-11-23T12:00:00.000Z', closesAt: '2026-11-26T12:00:00.000Z' };
    const { dynamo, store } = setUp({
      TransactWriteCommand: [cancelled(passed, passed, failed)],
      GetCommand: [{ Item: { pk: 'USER#u1', sk: 'POST#p1', ...first, votingKey: 'OPEN' } }],
    });
    assert.deepEqual(await store.post('u1', post), { outcome: 'alreadyPosted', post: { ...first, ...noVotes } });
    assert.deepEqual(dynamo.named('GetCommand')[0]?.input, {
      TableName: 'records',
      Key: { pk: 'USER#u1', sk: 'POST#p1' },
      ConsistentRead: true,
    });
  });

  test('a post that vanished between the two steps means its photo was deleted', async () => {
    const { store } = setUp({ TransactWriteCommand: [cancelled(passed, passed, failed)], GetCommand: [{}] });
    assert.deepEqual(await store.post('u1', post), { outcome: 'photoDeleted' });
  });

  test('any other failure is passed on', async () => {
    const { store } = setUp({ TransactWriteCommand: [awsError('InternalServerError')] });
    await assert.rejects(store.post('u1', post), /InternalServerError/);
  });
});

describe('listing posts from the table', () => {
  test('a page holds the caller’s posts and names where the next starts', async () => {
    const { dynamo, store } = setUp({
      QueryCommand: [
        {
          Items: [{ pk: 'USER#u1', sk: 'POST#p1', ...post, votingKey: 'OPEN' }],
          LastEvaluatedKey: { pk: 'USER#u1', sk: 'POST#p1' },
        },
      ],
    });
    assert.deepEqual(await store.list('u1'), { posts: [{ ...post, ...noVotes }], nextAfter: 'p1' });
    assert.deepEqual(dynamo.sent[0]?.input, {
      TableName: 'records',
      KeyConditionExpression: 'pk = :pk AND begins_with(sk, :posts)',
      ExpressionAttributeValues: { ':pk': 'USER#u1', ':posts': 'POST#' },
      Limit: 2,
    });
  });

  test('a post is read with its votes, and with its final score once it has one', async () => {
    const counted = { voteCount: 6, weightSum: 6, weightedValueSum: 27 };
    const { store } = setUp({
      QueryCommand: [
        {
          Items: [
            { pk: 'USER#u1', sk: 'POST#p1', ...post, ...counted, votingKey: 'OPEN' },
            { pk: 'USER#u1', sk: 'POST#p2', ...post, photoID: 'p2', ...counted, finalScore: 88, finalizedAt: 'x' },
          ],
        },
      ],
    });
    assert.deepEqual((await store.list('u1')).posts, [
      { ...post, ...counted },
      { ...post, photoID: 'p2', ...counted, finalScore: 88 },
    ]);
  });

  test('the next page starts inside the caller’s own partition', async () => {
    const { dynamo, store } = setUp();
    assert.deepEqual(await store.list('u1', 'p1'), { posts: [] });
    assert.deepEqual(dynamo.sent[0]?.input.ExclusiveStartKey, { pk: 'USER#u1', sk: 'POST#p1' });
  });
});

describe('reading an image to check it', () => {
  const body = (bytes: number[]) => ({ transformToByteArray: async () => Uint8Array.from(bytes) });

  test('the image is read from the owner’s folder', async () => {
    const { s3, store } = setUp({}, { GetObjectCommand: [{ ContentLength: 3, Body: body([1, 2, 3]) }] });
    assert.deepEqual(await store.imageBytes('u1', 'p1'), Uint8Array.from([1, 2, 3]));
    assert.deepEqual(s3.sent, [
      { name: 'GetObjectCommand', input: { Bucket: 'images', Key: 'users/u1/photos/p1.jpg' } },
    ]);
  });

  test('an image that has not arrived is nothing, and not a failure', async () => {
    const { store } = setUp({}, { GetObjectCommand: [awsError('NoSuchKey')] });
    assert.equal(await store.imageBytes('u1', 'p1'), undefined);
  });

  test('an object above the size limit is not read', async () => {
    let read = false;
    const large = { ContentLength: 1001, Body: { transformToByteArray: async () => ((read = true), new Uint8Array()) } };
    const { store } = setUp({}, { GetObjectCommand: [large] });
    assert.equal(await store.imageBytes('u1', 'p1'), undefined);
    assert.equal(read, false);
  });

  test('any other failure is passed on, so a fault is not read as a missing image', async () => {
    const { store } = setUp({}, { GetObjectCommand: [awsError('AccessDenied')] });
    await assert.rejects(store.imageBytes('u1', 'p1'), /AccessDenied/);
  });
});
