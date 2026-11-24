import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { S3Client } from '@aws-sdk/client-s3';
import { makeAwsPhotoStore } from '../src/photos/awsStore.ts';
import { awsError, fakeClient } from './support.ts';

/** A real S3 client with made up keys. Signing a link needs no network. */
const signer = new S3Client({
  region: 'us-east-1',
  credentials: { accessKeyId: 'AKIAEXAMPLE', secretAccessKey: 'example' },
});

function setUp(replies: Record<string, unknown[]> = {}, s3: any = signer) {
  const dynamo = fakeClient(replies);
  const store = makeAwsPhotoStore({
    dynamo,
    s3,
    tableName: 'records',
    bucketName: 'images',
    photosPerPage: 2,
    uploadLinkSeconds: 300,
    imageLinkSeconds: 900,
  });
  return { dynamo, store };
}

const photo = { photoID: 'p1', documentJSON: '{"id":"p1"}', updatedAt: '2026-11-24T12:00:00.000Z' };
const cancelled = (...codes: string[]) =>
  awsError('TransactionCanceledException', { CancellationReasons: codes.map((Code) => ({ Code })) });

describe('saving to the table', () => {
  test('a save checks the account marker and the photo marker in one transaction', async () => {
    const { dynamo, store } = setUp();
    assert.equal(await store.save('u1', photo), 'saved');
    const [check, put] = dynamo.sent[0]?.input.TransactItems;
    assert.deepEqual(check.ConditionCheck, {
      TableName: 'records',
      Key: { pk: 'USER#u1', sk: 'ACCOUNT#DELETED' },
      ConditionExpression: 'attribute_not_exists(pk)',
    });
    assert.deepEqual(put.Put, {
      TableName: 'records',
      Item: { pk: 'USER#u1', sk: 'PHOTO#p1', ...photo },
      ConditionExpression: 'attribute_not_exists(deletedAt)',
    });
  });

  test('a save for a deleted account is turned away', async () => {
    const { store } = setUp({ TransactWriteCommand: [cancelled('ConditionalCheckFailed', 'None')] });
    assert.equal(await store.save('u1', photo), 'accountDeleted');
  });

  test('a save of a deleted photo is turned away', async () => {
    const { store } = setUp({ TransactWriteCommand: [cancelled('None', 'ConditionalCheckFailed')] });
    assert.equal(await store.save('u1', photo), 'photoDeleted');
  });

  test('any other failure is passed on', async () => {
    const { store } = setUp({ TransactWriteCommand: [awsError('ProvisionedThroughputExceededException')] });
    await assert.rejects(store.save('u1', photo), /ProvisionedThroughputExceededException/);
  });
});

describe('listing from the table', () => {
  test('a page holds photos and deleted markers, and names where the next starts', async () => {
    const { dynamo, store } = setUp({
      QueryCommand: [
        {
          Items: [
            { pk: 'USER#u1', sk: 'PHOTO#p1', ...photo },
            { pk: 'USER#u1', sk: 'PHOTO#p2', photoID: 'p2', deletedAt: '2026-11-24T13:00:00.000Z' },
          ],
          LastEvaluatedKey: { pk: 'USER#u1', sk: 'PHOTO#p2' },
        },
      ],
    });
    assert.deepEqual(await store.list('u1'), {
      photos: [photo],
      deleted: [{ photoID: 'p2', deletedAt: '2026-11-24T13:00:00.000Z' }],
      nextAfter: 'p2',
    });
    const query = dynamo.sent[0]?.input;
    assert.equal(query.Limit, 2);
    assert.deepEqual(query.ExpressionAttributeValues, { ':pk': 'USER#u1', ':photos': 'PHOTO#' });
    assert.equal(query.ExclusiveStartKey, undefined);
  });

  test('the next page starts inside the caller’s own partition', async () => {
    const { dynamo, store } = setUp();
    assert.deepEqual(await store.list('u1', 'p2'), { photos: [], deleted: [] });
    assert.deepEqual(dynamo.sent[0]?.input.ExclusiveStartKey, { pk: 'USER#u1', sk: 'PHOTO#p2' });
  });
});

describe('deleting from the table and the bucket', () => {
  test('the marker is written first and the image is removed second', async () => {
    const order: string[] = [];
    const s3 = fakeClient();
    const { dynamo, store } = setUp({}, s3);
    const dynamoSend = dynamo.send;
    dynamo.send = async (command: any) => (order.push('marker'), dynamoSend(command));
    const s3Send = s3.send;
    s3.send = async (command: any) => (order.push('image'), s3Send(command));

    assert.equal(await store.remove('u1', 'p1', '2026-11-24T13:00:00.000Z'), 'saved');
    assert.deepEqual(order, ['marker', 'image']);
    assert.deepEqual(dynamo.sent[0]?.input.TransactItems[1].Put, {
      TableName: 'records',
      Item: { pk: 'USER#u1', sk: 'PHOTO#p1', photoID: 'p1', deletedAt: '2026-11-24T13:00:00.000Z' },
    });
    assert.deepEqual(s3.sent, [
      { name: 'DeleteObjectCommand', input: { Bucket: 'images', Key: 'users/u1/photos/p1.jpg' } },
    ]);
  });

  test('a delete takes the photo’s post with it, in the same transaction', async () => {
    const { dynamo, store } = setUp({}, fakeClient());
    await store.remove('u1', 'p1', '2026-11-24T13:00:00.000Z');
    const items = dynamo.sent[0]?.input.TransactItems;
    assert.equal(items.length, 3);
    assert.deepEqual(items[2].Delete, { TableName: 'records', Key: { pk: 'USER#u1', sk: 'POST#p1' } });
  });

  test('a save removes no post', async () => {
    const { dynamo, store } = setUp();
    await store.save('u1', photo);
    assert.equal(dynamo.sent[0]?.input.TransactItems.length, 2);
  });

  test('a delete for a deleted account touches no image', async () => {
    const s3 = fakeClient();
    const { store } = setUp({ TransactWriteCommand: [cancelled('ConditionalCheckFailed', 'None')] }, s3);
    assert.equal(await store.remove('u1', 'p1', '2026-11-24T13:00:00.000Z'), 'accountDeleted');
    assert.deepEqual(s3.sent, []);
  });

  test('a delete fails when the image cannot be removed, so the app tries again', async () => {
    const s3 = fakeClient({ DeleteObjectCommand: [awsError('SlowDown')] });
    const { store } = setUp({}, s3);
    await assert.rejects(store.remove('u1', 'p1', '2026-11-24T13:00:00.000Z'), /SlowDown/);
  });
});

describe('links', () => {
  test('an upload link is bound to the key, the type, the size, and a short life', async () => {
    const { store } = setUp();
    const url = new URL(await store.uploadLink('u1', 'p1', 4096));
    assert.equal(url.pathname, '/users/u1/photos/p1.jpg');
    assert.ok(url.hostname.startsWith('images.'));
    assert.equal(url.searchParams.get('X-Amz-Expires'), '300');
    const signed = (url.searchParams.get('X-Amz-SignedHeaders') ?? '').split(';');
    assert.ok(signed.includes('content-length'), signed.join(';'));
    assert.ok(signed.includes('content-type'), signed.join(';'));
  });

  test('an image link reads one key for a short time', async () => {
    const { store } = setUp();
    const url = new URL(await store.imageLink('u1', 'p1'));
    assert.equal(url.pathname, '/users/u1/photos/p1.jpg');
    assert.equal(url.searchParams.get('X-Amz-Expires'), '900');
  });
});
