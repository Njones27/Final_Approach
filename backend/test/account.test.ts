import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { makeAwsAccountStore } from '../src/account/awsStore.ts';
import { makeAccountHandler } from '../src/account/handler.ts';
import type { Caller } from '../src/shared/http.ts';
import { apiEvent, awsError, fakeClient } from './support.ts';

const caller: Caller = { userID: 'u1', username: 'apple-u1' };
const now = new Date('2026-11-24T12:00:00Z');

function setUp(replies: { dynamo?: Record<string, unknown[]>; s3?: Record<string, unknown[]>; cognito?: Record<string, unknown[]> } = {}) {
  const order: string[] = [];
  const tracked = (label: string, client: ReturnType<typeof fakeClient>) => {
    const send = client.send;
    client.send = async (command: any) => (order.push(`${label}:${command.constructor.name}`), send(command));
    return client;
  };
  const dynamo = tracked('dynamo', fakeClient(replies.dynamo));
  const s3 = tracked('s3', fakeClient(replies.s3));
  const cognito = tracked('cognito', fakeClient(replies.cognito));
  const store = makeAwsAccountStore({
    dynamo,
    s3,
    cognito,
    tableName: 'records',
    bucketName: 'images',
    userPoolID: 'pool-1',
    markerSeconds: 7500,
    maxBatchAttempts: 3,
  });
  return { order, dynamo, s3, cognito, store };
}

const keysOf = (count: number, from = 0) =>
  Array.from({ length: count }, (_, index) => ({ pk: 'USER#u1', sk: `PHOTO#p${from + index}` }));

describe('deleting an account', () => {
  test('the marker goes first, then the images, the records, and the sign in', async () => {
    const { order, store } = setUp({
      s3: { ListObjectsV2Command: [{ Contents: [{ Key: 'users/u1/photos/p0.jpg' }] }] },
      dynamo: { QueryCommand: [{ Items: keysOf(1) }] },
    });
    await store.deleteEverything(caller, now);
    assert.deepEqual(order, [
      'dynamo:PutCommand',
      's3:ListObjectsV2Command',
      's3:DeleteObjectsCommand',
      'dynamo:QueryCommand',
      'dynamo:BatchWriteCommand',
      'cognito:AdminDeleteUserCommand',
    ]);
  });

  test('the marker holds no personal data and expires by itself', async () => {
    const { dynamo, store } = setUp();
    await store.deleteEverything(caller, now);
    assert.deepEqual(dynamo.named('PutCommand')[0]?.input, {
      TableName: 'records',
      Item: {
        pk: 'USER#u1',
        sk: 'ACCOUNT#DELETED',
        deletedAt: '2026-11-24T12:00:00.000Z',
        expiresAt: Math.floor(now.getTime() / 1000) + 7500,
      },
    });
  });

  test('every page of images in the user folder is removed', async () => {
    const { s3, store } = setUp({
      s3: {
        ListObjectsV2Command: [
          { Contents: [{ Key: 'users/u1/photos/a.jpg' }], IsTruncated: true, NextContinuationToken: 'next' },
          { Contents: [{ Key: 'users/u1/photos/b.jpg' }] },
        ],
      },
    });
    await store.deleteEverything(caller, now);
    const lists = s3.named('ListObjectsV2Command').map((command) => command.input);
    assert.deepEqual(lists, [
      { Bucket: 'images', Prefix: 'users/u1/', ContinuationToken: undefined },
      { Bucket: 'images', Prefix: 'users/u1/', ContinuationToken: 'next' },
    ]);
    const removed = s3.named('DeleteObjectsCommand').flatMap((command) => command.input.Delete.Objects);
    assert.deepEqual(removed, [{ Key: 'users/u1/photos/a.jpg' }, { Key: 'users/u1/photos/b.jpg' }]);
  });

  test('an image that cannot be removed stops the delete before the sign in goes', async () => {
    const { cognito, store } = setUp({
      s3: {
        ListObjectsV2Command: [{ Contents: [{ Key: 'users/u1/photos/a.jpg' }] }],
        DeleteObjectsCommand: [{ Errors: [{ Key: 'users/u1/photos/a.jpg', Code: 'InternalError' }] }],
      },
    });
    await assert.rejects(store.deleteEverything(caller, now), /could not be deleted/);
    assert.deepEqual(cognito.sent, []);
  });

  test('records go in batches of 25, across pages, and the marker stays', async () => {
    const { dynamo, store } = setUp({
      dynamo: {
        QueryCommand: [
          { Items: keysOf(30), LastEvaluatedKey: { pk: 'USER#u1', sk: 'PHOTO#p29' } },
          { Items: [...keysOf(2, 30), { pk: 'USER#u1', sk: 'ACCOUNT#DELETED' }] },
        ],
      },
    });
    await store.deleteEverything(caller, now);
    const batches = dynamo.named('BatchWriteCommand').map((command) => command.input.RequestItems.records);
    assert.deepEqual(batches.map((batch) => batch.length), [25, 5, 2]);
    const removed = batches.flat().map((request) => request.DeleteRequest.Key.sk);
    assert.equal(removed.length, 32);
    assert.ok(!removed.includes('ACCOUNT#DELETED'));
    assert.equal(dynamo.named('QueryCommand')[0]?.input.ConsistentRead, true);
    assert.deepEqual(dynamo.named('QueryCommand')[1]?.input.ExclusiveStartKey, { pk: 'USER#u1', sk: 'PHOTO#p29' });
  });

  test('a post is removed with the rest, because it sits in the user’s partition', async () => {
    const { dynamo, store } = setUp({
      dynamo: {
        QueryCommand: [{ Items: [...keysOf(1), { pk: 'USER#u1', sk: 'POST#p0' }] }],
      },
    });
    await store.deleteEverything(caller, now);
    const removed = dynamo
      .named('BatchWriteCommand')
      .flatMap((command) => command.input.RequestItems.records)
      .map((request) => request.DeleteRequest.Key.sk);
    assert.deepEqual(removed, ['PHOTO#p0', 'POST#p0']);
    // The sweep asks for the whole partition, and not for photos alone.
    assert.equal(dynamo.named('QueryCommand')[0]?.input.KeyConditionExpression, 'pk = :pk');
  });

  test('records DynamoDB left out of a batch are sent again', async () => {
    const [first, second] = keysOf(2);
    const { dynamo, store } = setUp({
      dynamo: {
        QueryCommand: [{ Items: [first, second] }],
        BatchWriteCommand: [{ UnprocessedItems: { records: [{ DeleteRequest: { Key: second } }] } }, {}],
      },
    });
    await store.deleteEverything(caller, now);
    const batches = dynamo.named('BatchWriteCommand').map((command) => command.input.RequestItems.records);
    assert.deepEqual(batches[1], [{ DeleteRequest: { Key: second } }]);
  });

  test('a batch that never finishes fails after the allowed tries', async () => {
    const stuck = { UnprocessedItems: { records: [{ DeleteRequest: { Key: keysOf(1)[0] } }] } };
    const { dynamo, cognito, store } = setUp({
      dynamo: { QueryCommand: [{ Items: keysOf(1) }], BatchWriteCommand: [stuck, stuck, stuck, stuck] },
    });
    await assert.rejects(store.deleteEverything(caller, now), /could not be deleted/);
    assert.equal(dynamo.named('BatchWriteCommand').length, 3);
    assert.deepEqual(cognito.sent, []);
  });

  test('the sign in is deleted by the name the pool knows', async () => {
    const { cognito, store } = setUp();
    await store.deleteEverything(caller, now);
    assert.deepEqual(cognito.sent, [
      { name: 'AdminDeleteUserCommand', input: { UserPoolId: 'pool-1', Username: 'apple-u1' } },
    ]);
  });

  test('a second try after the sign in is gone still succeeds', async () => {
    const { store } = setUp({ cognito: { AdminDeleteUserCommand: [awsError('UserNotFoundException')] } });
    await store.deleteEverything(caller, now);
  });

  test('any other failure deleting the sign in is passed on', async () => {
    const { store } = setUp({ cognito: { AdminDeleteUserCommand: [awsError('TooManyRequestsException')] } });
    await assert.rejects(store.deleteEverything(caller, now), /TooManyRequestsException/);
  });
});

describe('the delete account route', () => {
  function route() {
    const deleted: Caller[] = [];
    const handler = makeAccountHandler({
      store: { deleteEverything: async (who) => void deleted.push(who) },
      now: () => now,
    });
    return { deleted, handler };
  }

  test('deletes the signed in user and answers with no content', async () => {
    const { deleted, handler } = route();
    const result = await handler(apiEvent({ routeKey: 'DELETE /account' }));
    assert.equal(result.statusCode, 204);
    assert.deepEqual(deleted, [{ userID: 'user-1', username: 'apple-user-1' }]);
  });

  test('deletes nothing for a request with no verified user', async () => {
    const { deleted, handler } = route();
    const result = await handler(apiEvent({ routeKey: 'DELETE /account', claims: null }));
    assert.equal(result.statusCode, 401);
    assert.deepEqual(deleted, []);
  });

  test('deletes nothing on any other route', async () => {
    const { deleted, handler } = route();
    const result = await handler(apiEvent({ routeKey: 'GET /account' }));
    assert.equal(result.statusCode, 404);
    assert.deepEqual(deleted, []);
  });
});
