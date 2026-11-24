import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { makePostsHandler } from '../src/posts/handler.ts';
import type { PostOutcome, PostStore, StoredPost } from '../src/posts/store.ts';
import { emptyTally } from '../src/votes/standing.ts';
import { exif, gpsTag, jfif, jpeg, orientationTag } from './jpeg.ts';
import { apiEvent } from './support.ts';

const cleanImage = jpeg(jfif, exif([orientationTag]));

/** A post store that keeps everything in memory. */
function memoryStore() {
  const images = new Map<string, Uint8Array>();
  const saved = new Set<string>();
  const deleted = new Set<string>();
  const posts = new Map<string, StoredPost>();
  let accountDeleted = false;
  const key = (userID: string, photoID: string) => `${userID}/${photoID}`;
  const store: PostStore = {
    async post(userID, post): Promise<PostOutcome> {
      const id = key(userID, post.photoID);
      if (accountDeleted) return { outcome: 'accountDeleted' };
      if (deleted.has(id)) return { outcome: 'photoDeleted' };
      if (!saved.has(id)) return { outcome: 'photoNotSaved' };
      const existing = posts.get(id);
      if (existing) return { outcome: 'alreadyPosted', post: existing };
      const stored = { ...post, ...emptyTally };
      posts.set(id, stored);
      return { outcome: 'posted', post: stored };
    },
    async list(userID, after) {
      const mine = [...posts.entries()]
        .filter(([entry]) => entry.startsWith(`${userID}/`))
        .map(([, post]) => post)
        .filter((post) => after === undefined || post.photoID > after);
      return { posts: mine };
    },
    async imageBytes(userID, photoID) {
      return images.get(key(userID, photoID));
    },
    async showAtSpot(userID, photoID, showing) {
      const existing = posts.get(key(userID, photoID));
      if (!existing) return 'notPosted';
      posts.set(key(userID, photoID), { ...existing, shownAt: showing });
      return 'shown';
    },
    async hideFromSpots(userID, photoID) {
      const existing = posts.get(key(userID, photoID));
      if (!existing) return;
      const { shownAt: _, ...rest } = existing;
      posts.set(key(userID, photoID), rest);
    },
  };
  return {
    store,
    posts,
    /** A photo that was saved with its image, the way the app syncs one. */
    savePhoto(userID: string, photoID: string, image: Uint8Array | null = cleanImage) {
      saved.add(key(userID, photoID));
      if (image) images.set(key(userID, photoID), image);
    },
    deletePhoto: (userID: string, photoID: string) => deleted.add(key(userID, photoID)),
    deleteAccount: () => (accountDeleted = true),
  };
}

function setUp() {
  const memory = memoryStore();
  let clock = new Date('2026-11-24T12:00:00.000Z');
  let made = 0;
  const handler = makePostsHandler({
    store: memory.store,
    votingWindowHours: 72,
    rules: { scaleMax: 5, minVotes: 5 },
    now: () => clock,
    newPostID: () => `post-${(made += 1)}`,
    isListedSpot: (spotID) => spotID === 'xyz-east-fence',
    shownTextMaxLength: 20,
  });
  return { ...memory, handler, setClock: (time: string) => (clock = new Date(time)) };
}

const post = (photoID: string, claims?: Record<string, string> | null) =>
  apiEvent({ routeKey: 'PUT /posts/{photoID}', photoID, ...(claims === undefined ? {} : { claims }) });
const bodyOf = (result: { body?: string | undefined }) => JSON.parse(result.body ?? '{}');

describe('posting a photo', () => {
  test('a saved photo is posted, and its voting window is the stage’s', async () => {
    const { handler, savePhoto, posts } = setUp();
    savePhoto('user-1', 'p1');
    const result = await handler(post('p1'));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(bodyOf(result), {
      photoID: 'p1',
      postedAt: '2026-11-24T12:00:00.000Z',
      closesAt: '2026-11-27T12:00:00.000Z',
      voteCount: 0,
      status: 'voting',
    });
    assert.equal(posts.get('user-1/p1')?.postID, 'post-1');
  });

  test('the answer never carries the id that voters know the post by', async () => {
    const { handler, savePhoto } = setUp();
    savePhoto('user-1', 'p1');
    assert.ok(!JSON.stringify(bodyOf(await handler(post('p1')))).includes('post-1'));
  });

  test('posting again changes nothing and answers with the first post', async () => {
    const { handler, savePhoto, posts, setClock } = setUp();
    savePhoto('user-1', 'p1');
    const first = bodyOf(await handler(post('p1')));
    setClock('2026-11-25T09:00:00.000Z');
    const second = await handler(post('p1'));
    assert.equal(second.statusCode, 200);
    assert.deepEqual(bodyOf(second), first);
    assert.equal(posts.get('user-1/p1')?.postID, 'post-1');
  });

  test('nothing about the technical check is asked or sent', async () => {
    const { handler, savePhoto } = setUp();
    savePhoto('user-1', 'p1');
    const result = await handler({ ...post('p1'), body: JSON.stringify({ technicalScore: 12, passed: false }) });
    assert.equal(result.statusCode, 200);
  });

  test('a photo that was never saved is turned away with a code', async () => {
    const { handler } = setUp();
    const result = await handler(post('p1'));
    assert.equal(result.statusCode, 409);
    assert.equal(bodyOf(result).code, 'photoNotSaved');
  });

  test('a photo whose image has not arrived is turned away with the same code', async () => {
    const { handler, savePhoto, posts } = setUp();
    savePhoto('user-1', 'p1', null);
    const result = await handler(post('p1'));
    assert.equal(result.statusCode, 409);
    assert.equal(bodyOf(result).code, 'photoNotSaved');
    assert.equal(posts.size, 0);
  });

  test('an image with a location written inside it is never posted', async () => {
    const { handler, savePhoto, posts } = setUp();
    savePhoto('user-1', 'p1', jpeg(jfif, exif([gpsTag])));
    const result = await handler(post('p1'));
    assert.equal(result.statusCode, 422);
    assert.equal(bodyOf(result).code, 'imageHasLocation');
    assert.equal(posts.size, 0);
  });

  test('an image that is not a JPEG is never posted', async () => {
    const { handler, savePhoto, posts } = setUp();
    savePhoto('user-1', 'p1', Buffer.from('not an image'));
    const result = await handler(post('p1'));
    assert.equal(result.statusCode, 422);
    assert.equal(bodyOf(result).code, undefined);
    assert.equal(posts.size, 0);
  });

  test('a deleted photo and a deleted account are each turned away', async () => {
    const first = setUp();
    first.savePhoto('user-1', 'p1');
    first.deletePhoto('user-1', 'p1');
    const gone = await first.handler(post('p1'));
    assert.equal(gone.statusCode, 410);
    assert.equal(bodyOf(gone).code, 'photoDeleted');

    const second = setUp();
    second.savePhoto('user-1', 'p1');
    second.deleteAccount();
    const closed = await second.handler(post('p1'));
    assert.equal(closed.statusCode, 410);
    assert.equal(bodyOf(closed).code, 'accountDeleted');
  });

  test('one user cannot post another user’s photo', async () => {
    const { handler, savePhoto, posts } = setUp();
    savePhoto('user-2', 'p1');
    const result = await handler(post('p1'));
    assert.equal(result.statusCode, 409);
    assert.equal(posts.size, 0);
  });

  test('a caller who is not signed in, and an id that is not usable, are refused', async () => {
    const { handler } = setUp();
    assert.equal((await handler(post('p1', null))).statusCode, 401);
    assert.equal((await handler(post('../p1'))).statusCode, 400);
  });
});

describe('listing posts', () => {
  test('a user sees their own posts and nobody else’s', async () => {
    const { handler, savePhoto } = setUp();
    savePhoto('user-1', 'p1');
    savePhoto('user-2', 'p2');
    await handler(post('p1'));
    await handler(post('p2', { sub: 'user-2', username: 'apple-user-2' }));
    const result = await handler(apiEvent({ routeKey: 'GET /posts' }));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(bodyOf(result).posts, [
      {
        photoID: 'p1',
        postedAt: '2026-11-24T12:00:00.000Z',
        closesAt: '2026-11-27T12:00:00.000Z',
        voteCount: 0,
        status: 'voting',
      },
    ]);
    assert.equal(bodyOf(result).minVotes, 5);
  });

  const withVotes = (voteCount: number, total: number, finalScore?: number) => ({
    voteCount,
    weightSum: voteCount,
    weightedValueSum: total,
    ...(finalScore === undefined ? {} : { finalScore }),
  });
  const listed = async (setup: ReturnType<typeof setUp>) =>
    bodyOf(await setup.handler(apiEvent({ routeKey: 'GET /posts' }))).posts[0];

  test('while voting is open the owner sees the count and never the score', async () => {
    const setup = setUp();
    setup.savePhoto('user-1', 'p1');
    await setup.handler(post('p1'));
    setup.posts.set('user-1/p1', { ...setup.posts.get('user-1/p1')!, ...withVotes(9, 40) });
    setup.setClock('2026-11-27T11:59:59.000Z');
    const seen = await listed(setup);
    assert.equal(seen.status, 'voting');
    assert.equal(seen.voteCount, 9);
    assert.equal(seen.score, undefined);
  });

  test('a post past its window with too few votes is still voting', async () => {
    const setup = setUp();
    setup.savePhoto('user-1', 'p1');
    await setup.handler(post('p1'));
    setup.posts.set('user-1/p1', { ...setup.posts.get('user-1/p1')!, ...withVotes(4, 20) });
    setup.setClock('2026-12-24T12:00:00.000Z');
    const seen = await listed(setup);
    assert.equal(seen.status, 'voting');
    assert.equal(seen.score, undefined);
  });

  test('once the window has ended with enough votes the grade is final, from the votes alone', async () => {
    const setup = setUp();
    setup.savePhoto('user-1', 'p1');
    await setup.handler(post('p1'));
    // Five votes that add up to twenty stars average four stars, which is 75.
    setup.posts.set('user-1/p1', { ...setup.posts.get('user-1/p1')!, ...withVotes(5, 20) });
    setup.setClock('2026-11-27T12:00:00.000Z');
    const seen = await listed(setup);
    assert.equal(seen.status, 'final');
    assert.equal(seen.score, 75);
    assert.equal(seen.voteCount, 5);
  });

  test('a score that was written down stands', async () => {
    const setup = setUp();
    setup.savePhoto('user-1', 'p1');
    await setup.handler(post('p1'));
    setup.posts.set('user-1/p1', { ...setup.posts.get('user-1/p1')!, ...withVotes(3, 15, 100) });
    const seen = await listed(setup);
    assert.equal(seen.status, 'final');
    assert.equal(seen.score, 100);
  });

  test('a page marker that is not a photo id is refused', async () => {
    const { handler } = setUp();
    const result = await handler(apiEvent({ routeKey: 'GET /posts', query: { after: 'a/b' } }));
    assert.equal(result.statusCode, 400);
  });

  test('any other route is not found', async () => {
    const { handler } = setUp();
    assert.equal((await handler(apiEvent({ routeKey: 'DELETE /posts/{photoID}', photoID: 'p1' }))).statusCode, 404);
  });
});

describe('showing a posted photo at a spot', () => {
  const show = (photoID: string, body: unknown, claims?: Record<string, string> | null) =>
    apiEvent({
      routeKey: 'PUT /posts/{photoID}/spot',
      photoID,
      body: typeof body === 'string' ? body : JSON.stringify(body),
      ...(claims === undefined ? {} : { claims }),
    });
  const hide = (photoID: string) => apiEvent({ routeKey: 'DELETE /posts/{photoID}/spot', photoID });
  const showing = { spotID: 'xyz-east-fence', aircraftType: 'Boeing 737-800', airline: 'Southwest' };

  async function posted() {
    const rig = setUp();
    rig.savePhoto('user-1', 'p1');
    await rig.handler(post('p1'));
    return rig;
  }

  test('a posted photo is shown with its spot, type, and airline', async () => {
    const { handler, posts } = await posted();
    const result = await handler(show('p1', showing));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(bodyOf(result), { photoID: 'p1', shownAt: showing });
    assert.deepEqual(posts.get('user-1/p1')?.shownAt, showing);
  });

  test('nothing but the three named things is kept', async () => {
    const { handler, posts } = await posted();
    const extra = { ...showing, registration: 'N8642E', latitude: 33.6, photographer: 'Nathan' };
    await handler(show('p1', extra));
    assert.deepEqual(posts.get('user-1/p1')?.shownAt, showing);
  });

  test('the type and the airline may be left out, and blank text counts as left out', async () => {
    const { handler, posts } = await posted();
    await handler(show('p1', { spotID: 'xyz-east-fence', aircraftType: '  ', airline: null }));
    assert.deepEqual(posts.get('user-1/p1')?.shownAt, { spotID: 'xyz-east-fence' });
  });

  test('text is trimmed before it is kept', async () => {
    const { handler, posts } = await posted();
    await handler(show('p1', { spotID: 'xyz-east-fence', airline: '  Delta ' }));
    assert.deepEqual(posts.get('user-1/p1')?.shownAt, { spotID: 'xyz-east-fence', airline: 'Delta' });
  });

  test('showing again replaces what was shown before', async () => {
    const { handler, posts } = await posted();
    await handler(show('p1', showing));
    await handler(show('p1', { spotID: 'xyz-east-fence', aircraftType: 'Airbus A220' }));
    assert.deepEqual(posts.get('user-1/p1')?.shownAt, { spotID: 'xyz-east-fence', aircraftType: 'Airbus A220' });
  });

  test('a spot that is not listed is refused with its own code', async () => {
    const { handler, posts } = await posted();
    const result = await handler(show('p1', { spotID: 'made-up-spot' }));
    assert.equal(result.statusCode, 404);
    assert.equal(bodyOf(result).code, 'unknownSpot');
    assert.equal(posts.get('user-1/p1')?.shownAt, undefined);
  });

  test('a body with no spot is refused', async () => {
    const { handler } = await posted();
    for (const body of ['', 'not json', '[]', '{}', { spotID: 7 }, { aircraftType: 'Boeing 737' }]) {
      assert.equal((await handler(show('p1', body))).statusCode, 400, JSON.stringify(body));
    }
  });

  test('text that is too long, not text, or holds a control character is refused', async () => {
    const { handler, posts } = await posted();
    for (const aircraftType of ['x'.repeat(21), 7, ['Boeing'], 'Boeing\n737', 'Boeing\u0000']) {
      const result = await handler(show('p1', { spotID: 'xyz-east-fence', aircraftType }));
      assert.equal(result.statusCode, 400, JSON.stringify(aircraftType));
    }
    assert.equal((await handler(show('p1', { spotID: 'xyz-east-fence', airline: 'x'.repeat(21) }))).statusCode, 400);
    assert.equal(posts.get('user-1/p1')?.shownAt, undefined);
  });

  test('a photo that is not posted cannot be shown', async () => {
    const { handler, savePhoto } = setUp();
    savePhoto('user-1', 'p1');
    const result = await handler(show('p1', showing));
    assert.equal(result.statusCode, 409);
    assert.equal(bodyOf(result).code, 'notPosted');
  });

  test('a user cannot show another user’s photo', async () => {
    const { handler, posts } = await posted();
    const result = await handler(show('p1', showing, { sub: 'user-2', username: 'apple-user-2' }));
    assert.equal(bodyOf(result).code, 'notPosted');
    assert.equal(posts.get('user-1/p1')?.shownAt, undefined);
  });

  test('the owner’s list of posts says where each photo is shown', async () => {
    const { handler, savePhoto } = await posted();
    savePhoto('user-1', 'p2');
    await handler(post('p2'));
    await handler(show('p1', showing));
    const listed = bodyOf(await handler(apiEvent({ routeKey: 'GET /posts' }))).posts;
    assert.deepEqual(listed.map((entry: { shownAt?: unknown }) => entry.shownAt), [showing, undefined]);
  });

  test('taking a photo off its spot removes everything that was shown', async () => {
    const { handler, posts } = await posted();
    await handler(show('p1', showing));
    const result = await handler(hide('p1'));
    assert.equal(result.statusCode, 204);
    assert.equal(posts.get('user-1/p1')?.shownAt, undefined);
    // The post itself stays, with its votes.
    assert.equal(posts.get('user-1/p1')?.postID, 'post-1');
  });

  test('taking off a photo that is shown nowhere, or not posted, is not a fault', async () => {
    const { handler } = await posted();
    assert.equal((await handler(hide('p1'))).statusCode, 204);
    assert.equal((await handler(hide('never-posted'))).statusCode, 204);
  });

  test('a caller who is not signed in is turned away', async () => {
    const { handler } = await posted();
    assert.equal((await handler(show('p1', showing, null))).statusCode, 401);
  });

  test('a photo id that is not usable is refused', async () => {
    const { handler } = await posted();
    assert.equal((await handler(show('a/b', showing))).statusCode, 400);
    assert.equal((await handler(hide('a/b'))).statusCode, 400);
  });
});
