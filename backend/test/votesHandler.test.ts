import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { makeVotesHandler } from '../src/votes/handler.ts';
import type { OpenPost, Vote, VoteOutcome, VoteStore } from '../src/votes/store.ts';
import { apiEvent } from './support.ts';

const rules = { scaleMax: 5, minVotes: 5 };

function openPost(ownerID: string, postID: string, more: Partial<OpenPost> = {}): OpenPost {
  return {
    ownerID,
    photoID: `photo-of-${postID}`,
    postID,
    closesAt: '2026-11-27T12:00:00.000Z',
    voteCount: 0,
    weightSum: 0,
    weightedValueSum: 0,
    ...more,
  };
}

/** A vote store that keeps everything in memory. */
function memoryStore(posts: OpenPost[]) {
  const open = new Map(posts.map((post) => [post.postID, post]));
  const votes = new Map<string, Vote>();
  let accountDeleted = false;
  const reads: { startAfter: string; limit: number }[] = [];
  const store: VoteStore = {
    async openPosts(startAfter, limit) {
      reads.push({ startAfter, limit });
      const sorted = [...open.values()].sort((a, b) => (a.postID < b.postID ? -1 : 1));
      const after = sorted.filter((post) => post.postID > startAfter);
      const wrapped = sorted.filter((post) => post.postID <= startAfter);
      return [...after, ...wrapped].slice(0, limit);
    },
    async openPost(postID) {
      return open.get(postID);
    },
    async votedOn(voterID, postIDs) {
      return new Set(postIDs.filter((postID) => votes.has(`${voterID}/${postID}`)));
    },
    async cast(voterID, post, vote): Promise<VoteOutcome> {
      if (accountDeleted) return 'accountDeleted';
      if (votes.has(`${voterID}/${vote.postID}`)) return 'alreadyVoted';
      const current = open.get(post.postID);
      if (!current) return 'votingClosed';
      votes.set(`${voterID}/${vote.postID}`, vote);
      open.set(post.postID, {
        ...current,
        voteCount: current.voteCount + 1,
        weightSum: current.weightSum + vote.weight,
        weightedValueSum: current.weightedValueSum + vote.value * vote.weight,
      });
      return 'counted';
    },
    async imageLink(post) {
      return `https://image.example/${post.postID}`;
    },
  };
  return { store, open, votes, reads, deleteAccount: () => (accountDeleted = true) };
}

function setUp(posts: OpenPost[], settings: { queueSize?: number; readLimit?: number } = {}) {
  const memory = memoryStore(posts);
  let clock = new Date('2026-11-24T12:00:00.000Z');
  const handler = makeVotesHandler({
    store: memory.store,
    rules,
    queueSize: settings.queueSize ?? 10,
    queueReadLimit: settings.readLimit ?? 50,
    voteWeight: 1,
    imageLinkSeconds: 900,
    now: () => clock,
    randomID: () => 'post-0',
  });
  return { ...memory, handler, setClock: (time: string) => (clock = new Date(time)) };
}

const queue = (claims?: Record<string, string>) =>
  apiEvent({ routeKey: 'GET /votes/queue', ...(claims ? { claims } : {}) });
const vote = (postID: string, value: unknown, claims?: Record<string, string> | null) =>
  ({
    ...apiEvent({ routeKey: 'PUT /votes/{postID}', body: JSON.stringify({ value }), ...(claims === undefined ? {} : { claims }) }),
    pathParameters: { postID },
  }) as ReturnType<typeof apiEvent>;
const bodyOf = (result: { body?: string | undefined }) => JSON.parse(result.body ?? '{}');
const voter2 = { sub: 'user-2', username: 'apple-user-2' };

describe('the voting queue', () => {
  test('hands out other users’ open posts, each with its image and its random id', async () => {
    const { handler } = setUp([openPost('user-2', 'post-1'), openPost('user-3', 'post-2')]);
    const result = await handler(queue());
    assert.equal(result.statusCode, 200);
    assert.deepEqual(bodyOf(result), {
      posts: [
        { postID: 'post-1', imageURL: 'https://image.example/post-1' },
        { postID: 'post-2', imageURL: 'https://image.example/post-2' },
      ],
      scaleMax: 5,
      imageLinkExpiresInSeconds: 900,
    });
  });

  test('is blind, with no owner, photo id, count, score, or closing time', async () => {
    const { handler } = setUp([openPost('user-2', 'post-1', { voteCount: 3, weightSum: 3, weightedValueSum: 12 })]);
    const sent = (await handler(queue())).body ?? '';
    for (const hidden of ['user-2', 'photo-of', 'voteCount', 'weight', 'closesAt', '2026-11-27']) {
      assert.ok(!sent.includes(hidden), hidden);
    }
  });

  test('never holds the voter’s own photos', async () => {
    const { handler } = setUp([openPost('user-1', 'post-1'), openPost('user-2', 'post-2')]);
    assert.deepEqual(bodyOf(await handler(queue())).posts.map((post: any) => post.postID), ['post-2']);
  });

  test('leaves out a post the voter has voted on', async () => {
    const { handler } = setUp([openPost('user-2', 'post-1'), openPost('user-2', 'post-2')]);
    await handler(vote('post-1', 4));
    assert.deepEqual(bodyOf(await handler(queue())).posts.map((post: any) => post.postID), ['post-2']);
  });

  test('leaves out a post whose voting has ended but that is not closed yet', async () => {
    const done = openPost('user-2', 'post-1', { voteCount: 5, weightSum: 5, weightedValueSum: 20 });
    const { handler, setClock } = setUp([done, openPost('user-2', 'post-2')]);
    setClock('2026-11-27T12:00:00.000Z');
    assert.deepEqual(bodyOf(await handler(queue())).posts.map((post: any) => post.postID), ['post-2']);
  });

  test('keeps a post that is past its window and short of votes', async () => {
    const { handler, setClock } = setUp([openPost('user-2', 'post-1', { voteCount: 4, weightSum: 4, weightedValueSum: 16 })]);
    setClock('2026-12-27T12:00:00.000Z');
    assert.equal(bodyOf(await handler(queue())).posts.length, 1);
  });

  test('holds no more than its size, and reads from a random place', async () => {
    const posts = Array.from({ length: 8 }, (_, index) => openPost('user-2', `post-${index + 1}`));
    const { handler, reads } = setUp(posts, { queueSize: 3, readLimit: 20 });
    assert.equal(bodyOf(await handler(queue())).posts.length, 3);
    assert.deepEqual(reads, [{ startAfter: 'post-0', limit: 20 }]);
  });

  test('is empty when there is nothing to vote on', async () => {
    const { handler } = setUp([]);
    assert.deepEqual(bodyOf(await handler(queue())).posts, []);
  });
});

describe('casting a vote', () => {
  test('a vote is counted on the post, with the voter’s weight', async () => {
    const { handler, open, votes } = setUp([openPost('user-2', 'post-1')]);
    const result = await handler(vote('post-1', 4));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(bodyOf(result), { postID: 'post-1', value: 4 });
    assert.deepEqual(votes.get('user-1/post-1'), {
      postID: 'post-1',
      value: 4,
      weight: 1,
      votedAt: '2026-11-24T12:00:00.000Z',
    });
    const counted = open.get('post-1');
    assert.deepEqual([counted?.voteCount, counted?.weightSum, counted?.weightedValueSum], [1, 1, 4]);
  });

  test('the answer says nothing about how the photo is doing', async () => {
    const { handler } = setUp([openPost('user-2', 'post-1', { voteCount: 3, weightSum: 3, weightedValueSum: 12 })]);
    assert.deepEqual(Object.keys(bodyOf(await handler(vote('post-1', 5)))).sort(), ['postID', 'value']);
  });

  test('a voter has one vote on a post', async () => {
    const { handler, open } = setUp([openPost('user-2', 'post-1')]);
    await handler(vote('post-1', 5));
    const second = await handler(vote('post-1', 1));
    assert.equal(second.statusCode, 409);
    assert.equal(bodyOf(second).code, 'alreadyVoted');
    assert.equal(open.get('post-1')?.weightedValueSum, 5);
  });

  test('a user cannot vote on their own photo', async () => {
    const { handler, votes } = setUp([openPost('user-1', 'post-1')]);
    const result = await handler(vote('post-1', 5));
    assert.equal(result.statusCode, 403);
    assert.equal(bodyOf(result).code, 'ownPost');
    assert.equal(votes.size, 0);
  });

  test('a vote that is not a whole number of stars on the scale is refused', async () => {
    const { handler, votes } = setUp([openPost('user-2', 'post-1')]);
    for (const value of [0, 6, 3.5, '5', null]) {
      assert.equal((await handler(vote('post-1', value))).statusCode, 400, String(value));
    }
    const noBody = { ...vote('post-1', 3), body: undefined };
    assert.equal((await handler(noBody)).statusCode, 400);
    const notJSON = { ...vote('post-1', 3), body: 'five' };
    assert.equal((await handler(notJSON)).statusCode, 400);
    assert.equal(votes.size, 0);
  });

  test('a post that is not open takes no vote', async () => {
    const done = openPost('user-2', 'post-1', { voteCount: 5, weightSum: 5, weightedValueSum: 20 });
    const { handler, setClock, votes } = setUp([done]);
    const missing = await handler(vote('post-9', 4));
    assert.equal(missing.statusCode, 410);
    assert.equal(bodyOf(missing).code, 'votingClosed');
    setClock('2026-11-27T12:00:00.000Z');
    const closed = await handler(vote('post-1', 4));
    assert.equal(closed.statusCode, 410);
    assert.equal(bodyOf(closed).code, 'votingClosed');
    assert.equal(votes.size, 0);
  });

  test('a post past its window still takes the votes it is short of', async () => {
    const short = openPost('user-2', 'post-1', { voteCount: 4, weightSum: 4, weightedValueSum: 16 });
    const { handler, setClock } = setUp([short]);
    setClock('2026-12-01T00:00:00.000Z');
    assert.equal((await handler(vote('post-1', 4))).statusCode, 200);
    // That vote was the fifth, so the post is closed to the next voter.
    assert.equal((await handler(vote('post-1', 4, voter2))).statusCode, 410);
  });

  test('a deleted account cannot vote', async () => {
    const { handler, deleteAccount } = setUp([openPost('user-2', 'post-1')]);
    deleteAccount();
    const result = await handler(vote('post-1', 4));
    assert.equal(result.statusCode, 410);
    assert.equal(bodyOf(result).code, 'accountDeleted');
  });

  test('a caller who is not signed in, a bad id, and any other route are refused', async () => {
    const { handler } = setUp([openPost('user-2', 'post-1')]);
    assert.equal((await handler(vote('post-1', 4, null))).statusCode, 401);
    assert.equal((await handler(vote('post/1', 4))).statusCode, 400);
    assert.equal((await handler(apiEvent({ routeKey: 'DELETE /votes/{postID}' }))).statusCode, 404);
  });
});
