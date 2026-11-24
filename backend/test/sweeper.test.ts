import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import type { S3Event } from 'aws-lambda';
import { standingOf } from '../src/photos/standing.ts';
import { makeSweeper, type ImageStanding } from '../src/photos/sweeper.ts';
import { fakeClient } from './support.ts';

const uploaded = (...keys: string[]) =>
  ({ Records: keys.map((key) => ({ s3: { object: { key } } })) }) as unknown as S3Event;

function setUp(standing: ImageStanding) {
  const asked: string[] = [];
  const removed: string[] = [];
  const handler = makeSweeper({
    standing: async (userID, photoID) => (asked.push(`${userID}/${photoID}`), standing),
    removeImage: async (key) => void removed.push(key),
  });
  return { asked, removed, handler };
}

describe('an image that just arrived', () => {
  test('stays when its photo still exists', async () => {
    const { asked, removed, handler } = setUp('wanted');
    await handler(uploaded('users/u1/photos/p1.jpg'));
    assert.deepEqual(asked, ['u1/p1']);
    assert.deepEqual(removed, []);
  });

  test('is removed when its photo or account is gone', async () => {
    const { removed, handler } = setUp('unwanted');
    await handler(uploaded('users/u1/photos/p1.jpg', 'users/u2/photos/p2.jpg'));
    assert.deepEqual(removed, ['users/u1/photos/p1.jpg', 'users/u2/photos/p2.jpg']);
  });

  test('is left alone when its key is not one the backend writes', async () => {
    const { asked, removed, handler } = setUp('unwanted');
    await handler(uploaded('users/u1/notes.txt'));
    assert.deepEqual(asked, []);
    assert.deepEqual(removed, []);
  });

  test('has its key read the way S3 writes it', async () => {
    const { asked, handler } = setUp('wanted');
    await handler(uploaded('users/us-east-1%3Aabc/photos/p1.jpg'));
    assert.deepEqual(asked, ['us-east-1:abc/p1']);
  });
});

describe('whether a photo still wants its image', () => {
  const found = (...items: Record<string, unknown>[]) => ({
    BatchGetCommand: [{ Responses: { records: items } }],
  });
  const photoItem = { pk: 'USER#u1', sk: 'PHOTO#p1', photoID: 'p1' };

  test('a live photo wants it', async () => {
    const dynamo = fakeClient(found(photoItem));
    assert.equal(await standingOf(dynamo, 'records', 'u1', 'p1'), 'wanted');
    const request = dynamo.sent[0]?.input.RequestItems.records;
    assert.equal(request.ConsistentRead, true);
    assert.deepEqual(request.Keys, [
      { pk: 'USER#u1', sk: 'ACCOUNT#DELETED' },
      { pk: 'USER#u1', sk: 'PHOTO#p1' },
    ]);
  });

  test('a photo with no record does not', async () => {
    assert.equal(await standingOf(fakeClient(found()), 'records', 'u1', 'p1'), 'unwanted');
  });

  test('a deleted photo does not', async () => {
    const dynamo = fakeClient(found({ ...photoItem, deletedAt: '2026-11-24T13:00:00.000Z' }));
    assert.equal(await standingOf(dynamo, 'records', 'u1', 'p1'), 'unwanted');
  });

  test('a photo of a deleted account does not', async () => {
    const dynamo = fakeClient(found(photoItem, { pk: 'USER#u1', sk: 'ACCOUNT#DELETED' }));
    assert.equal(await standingOf(dynamo, 'records', 'u1', 'p1'), 'unwanted');
  });

  test('a lookup that did not finish fails, so the event is delivered again', async () => {
    const dynamo = fakeClient({
      BatchGetCommand: [{ Responses: { records: [] }, UnprocessedKeys: { records: { Keys: [{}] } } }],
    });
    await assert.rejects(standingOf(dynamo, 'records', 'u1', 'p1'), /did not finish/);
  });
});
