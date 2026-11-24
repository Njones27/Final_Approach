import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { makePhotosHandler } from '../src/photos/handler.ts';
import type { PhotoPage, PhotoStore, StoredPhoto, WriteOutcome } from '../src/photos/store.ts';
import { apiEvent } from './support.ts';

/** A photo store that keeps everything in memory. */
function memoryStore() {
  const photos = new Map<string, StoredPhoto>();
  const deleted = new Map<string, string>();
  let accountDeleted = false;
  const key = (userID: string, photoID: string) => `${userID}/${photoID}`;
  const store: PhotoStore = {
    async save(userID, photo): Promise<WriteOutcome> {
      if (accountDeleted) return 'accountDeleted';
      if (deleted.has(key(userID, photo.photoID))) return 'photoDeleted';
      photos.set(key(userID, photo.photoID), photo);
      return 'saved';
    },
    async list(userID, after): Promise<PhotoPage> {
      const mine = [...photos.entries()]
        .filter(([entry]) => entry.startsWith(`${userID}/`))
        .map(([, photo]) => photo)
        .filter((photo) => after === undefined || photo.photoID > after);
      const gone = [...deleted.entries()]
        .filter(([entry]) => entry.startsWith(`${userID}/`))
        .map(([entry, deletedAt]) => ({ photoID: entry.split('/')[1] ?? '', deletedAt }));
      return { photos: mine, deleted: gone };
    },
    async remove(userID, photoID, deletedAt): Promise<WriteOutcome> {
      if (accountDeleted) return 'accountDeleted';
      photos.delete(key(userID, photoID));
      deleted.set(key(userID, photoID), deletedAt);
      return 'saved';
    },
    async uploadLink(userID, photoID, imageBytes) {
      return `https://upload.example/${userID}/${photoID}?bytes=${imageBytes}`;
    },
    async imageLink(userID, photoID) {
      return `https://image.example/${userID}/${photoID}`;
    },
  };
  return { store, photos, deleteAccount: () => (accountDeleted = true) };
}

function setUp() {
  const memory = memoryStore();
  const handler = makePhotosHandler({
    store: memory.store,
    limits: { maxDocumentBytes: 1000, maxImageBytes: 5000 },
    uploadLinkSeconds: 300,
    imageLinkSeconds: 900,
    now: () => new Date('2026-11-24T12:00:00Z'),
  });
  return { ...memory, handler };
}

const savePhoto = (photoID: string, extra: Record<string, unknown> = {}, claims?: Record<string, string>) =>
  apiEvent({
    routeKey: 'PUT /photos/{photoID}',
    photoID,
    body: JSON.stringify({ document: { id: photoID, aircraftType: 'B-2' }, ...extra }),
    ...(claims ? { claims } : {}),
  });

const parse = (result: { body?: string | undefined }) => JSON.parse(result.body ?? 'null');

describe('saving a photo', () => {
  test('a record alone is saved with the time of the save', async () => {
    const { handler, photos } = setUp();
    const result = await handler(savePhoto('p1'));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(parse(result), { photoID: 'p1', updatedAt: '2026-11-24T12:00:00.000Z' });
    assert.equal(photos.get('user-1/p1')?.documentJSON, '{"id":"p1","aircraftType":"B-2"}');
  });

  test('a record with an image size gets a link for exactly that image', async () => {
    const { handler } = setUp();
    const result = parse(await handler(savePhoto('p1', { imageBytes: 4096 })));
    assert.deepEqual(result.upload, {
      url: 'https://upload.example/user-1/p1?bytes=4096',
      method: 'PUT',
      headers: { 'Content-Type': 'image/jpeg', 'Content-Length': '4096' },
      expiresInSeconds: 300,
    });
  });

  test('a bad record is refused and nothing is saved', async () => {
    const { handler, photos } = setUp();
    const result = await handler(savePhoto('p1', { imageBytes: 5001 }));
    assert.equal(result.statusCode, 400);
    assert.equal(photos.size, 0);
  });

  test('a body that API Gateway encoded is read', async () => {
    const { handler, photos } = setUp();
    const body = Buffer.from(JSON.stringify({ document: { id: 'p1' } })).toString('base64');
    const result = await handler(
      apiEvent({ routeKey: 'PUT /photos/{photoID}', photoID: 'p1', body, isBase64Encoded: true }),
    );
    assert.equal(result.statusCode, 200);
    assert.equal(photos.get('user-1/p1')?.documentJSON, '{"id":"p1"}');
  });

  test('a deleted photo stays deleted', async () => {
    const { handler, photos } = setUp();
    await handler(savePhoto('p1'));
    await handler(apiEvent({ routeKey: 'DELETE /photos/{photoID}', photoID: 'p1' }));
    const result = await handler(savePhoto('p1', { imageBytes: 10 }));
    assert.equal(result.statusCode, 410);
    assert.equal(parse(result).upload, undefined);
    assert.equal(photos.size, 0);
  });

  test('a deleted account takes no photo and gives no upload link', async () => {
    const { handler, photos, deleteAccount } = setUp();
    deleteAccount();
    const result = await handler(savePhoto('p1', { imageBytes: 10 }));
    assert.equal(result.statusCode, 410);
    assert.equal(parse(result).upload, undefined);
    assert.equal(photos.size, 0);
  });
});

describe('listing photos', () => {
  test('a user sees their own photos, each with a link to its image', async () => {
    const { handler } = setUp();
    await handler(savePhoto('p1'));
    await handler(savePhoto('p2', {}, { sub: 'user-2', username: 'apple-user-2' }));
    const result = await handler(apiEvent({ routeKey: 'GET /photos' }));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(parse(result), {
      photos: [
        {
          photoID: 'p1',
          document: { id: 'p1', aircraftType: 'B-2' },
          updatedAt: '2026-11-24T12:00:00.000Z',
          imageURL: 'https://image.example/user-1/p1',
        },
      ],
      deleted: [],
      imageLinkExpiresInSeconds: 900,
    });
  });

  test('a deleted photo is listed as deleted, so other devices drop it', async () => {
    const { handler } = setUp();
    await handler(savePhoto('p1'));
    await handler(apiEvent({ routeKey: 'DELETE /photos/{photoID}', photoID: 'p1' }));
    const result = parse(await handler(apiEvent({ routeKey: 'GET /photos' })));
    assert.deepEqual(result.photos, []);
    assert.deepEqual(result.deleted, [{ photoID: 'p1', deletedAt: '2026-11-24T12:00:00.000Z' }]);
  });

  test('a page marker that is not a photo id is refused', async () => {
    const { handler } = setUp();
    const result = await handler(apiEvent({ routeKey: 'GET /photos', query: { after: '../x' } }));
    assert.equal(result.statusCode, 400);
  });

  test('the answer is never cached', async () => {
    const { handler } = setUp();
    const result = await handler(apiEvent({ routeKey: 'GET /photos' }));
    assert.equal(result.headers?.['cache-control'], 'no-store');
  });
});

describe('deleting a photo', () => {
  test('a delete answers with no content, and so does a second one', async () => {
    const { handler, photos } = setUp();
    await handler(savePhoto('p1'));
    const remove = apiEvent({ routeKey: 'DELETE /photos/{photoID}', photoID: 'p1' });
    assert.equal((await handler(remove)).statusCode, 204);
    assert.equal((await handler(remove)).statusCode, 204);
    assert.equal(photos.size, 0);
  });

  test('one user cannot delete another user’s photo', async () => {
    const { handler, photos } = setUp();
    await handler(savePhoto('p1'));
    await handler(
      apiEvent({
        routeKey: 'DELETE /photos/{photoID}',
        photoID: 'p1',
        claims: { sub: 'user-2', username: 'apple-user-2' },
      }),
    );
    assert.ok(photos.has('user-1/p1'));
  });
});

describe('who may call', () => {
  test('a request with no verified user is turned away', async () => {
    const { handler } = setUp();
    const unverified: (Record<string, string> | null)[] = [null, {}, { sub: 'user-1' }, { username: 'apple-user-1' }];
    for (const claims of unverified) {
      const result = await handler(apiEvent({ routeKey: 'GET /photos', claims }));
      assert.equal(result.statusCode, 401);
    }
  });

  test('an id token names the user as well as an access token does', async () => {
    const { handler } = setUp();
    const claims = { sub: 'user-1', 'cognito:username': 'apple-user-1' };
    assert.equal((await handler(apiEvent({ routeKey: 'GET /photos', claims }))).statusCode, 200);
  });

  test('an unusable photo id in the address is refused', async () => {
    const { handler } = setUp();
    const result = await handler(apiEvent({ routeKey: 'DELETE /photos/{photoID}', photoID: 'a.b' }));
    assert.equal(result.statusCode, 400);
  });

  test('a route the function does not serve is not found', async () => {
    const { handler } = setUp();
    const result = await handler(apiEvent({ routeKey: 'POST /photos/{photoID}', photoID: 'p1' }));
    assert.equal(result.statusCode, 404);
  });
});
