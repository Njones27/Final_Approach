import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  imageKey,
  isUsablePhotoID,
  parseImageKey,
  partitionKey,
  photoSortKey,
  userFolder,
} from '../src/shared/keys.ts';

describe('photo ids', () => {
  test('the ids the app makes are usable', () => {
    assert.ok(isUsablePhotoID('imported-9F1C2B7E-3A55-4E0B-9C61-2D0B8E7A1F44'));
    assert.ok(isUsablePhotoID('sample_b2'));
  });

  test('an id that could leave the user folder is refused', () => {
    for (const id of ['', '..', '../other', 'a/b', 'a.jpg', 'a b', 'é', 'x'.repeat(81), 7, null, undefined]) {
      assert.equal(isUsablePhotoID(id), false, String(id));
    }
  });
});

describe('where data lives', () => {
  test('every image sits inside its owner folder', () => {
    assert.equal(userFolder('u1'), 'users/u1/');
    assert.equal(imageKey('u1', 'p1'), 'users/u1/photos/p1.jpg');
    assert.ok(imageKey('u1', 'p1').startsWith(userFolder('u1')));
  });

  test('records are keyed by user and photo', () => {
    assert.equal(partitionKey('u1'), 'USER#u1');
    assert.equal(photoSortKey('p1'), 'PHOTO#p1');
  });

  test('an image key reads back to its user and photo', () => {
    assert.deepEqual(parseImageKey(imageKey('u1', 'p-1_a')), { userID: 'u1', photoID: 'p-1_a' });
  });

  test('a key of another shape reads back to nothing', () => {
    for (const key of ['users/u1/p1.jpg', 'users/u1/photos/p1.png', 'other/u1/photos/p1.jpg', 'users/u1/photos/a/b.jpg']) {
      assert.equal(parseImageKey(key), undefined, key);
    }
  });
});
