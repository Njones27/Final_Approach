import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { makeCloser, type CloserStore } from '../src/votes/closer.ts';
import type { OpenPost } from '../src/votes/store.ts';

const rules = { scaleMax: 5, minVotes: 5 };
const post = (postID: string, voteCount: number, total: number, closesAt = '2026-11-27T12:00:00.000Z'): OpenPost => ({
  ownerID: 'user-2',
  photoID: `photo-of-${postID}`,
  postID,
  closesAt,
  voteCount,
  weightSum: voteCount,
  weightedValueSum: total,
});

function setUp(pages: OpenPost[][], changed: string[] = []) {
  const closed: { postID: string; score: number; finalizedAt: string }[] = [];
  const asked: (Record<string, unknown> | undefined)[] = [];
  const store: CloserStore = {
    async page(startKey) {
      asked.push(startKey);
      const index = startKey ? Number(startKey['page']) : 0;
      return { posts: pages[index] ?? [], ...(index + 1 < pages.length ? { next: { page: index + 1 } } : {}) };
    },
    async close(closing, score, finalizedAt) {
      if (changed.includes(closing.postID)) return false;
      closed.push({ postID: closing.postID, score, finalizedAt });
      return true;
    },
  };
  const handler = makeCloser({ store, rules, now: () => new Date('2026-11-27T12:00:00.000Z') });
  return { closed, asked, handler };
}

describe('closing posts whose voting has ended', () => {
  test('a finished post gets its final score, from the votes alone', async () => {
    const { closed, handler } = setUp([[post('post-1', 5, 20)]]);
    assert.deepEqual(await handler(), { closed: 1, stillOpen: 0 });
    assert.deepEqual(closed, [{ postID: 'post-1', score: 75, finalizedAt: '2026-11-27T12:00:00.000Z' }]);
  });

  test('a post inside its window, or short of votes, is left open', async () => {
    const { closed, handler } = setUp([
      [post('post-1', 9, 40, '2026-11-27T12:00:00.001Z'), post('post-2', 4, 20), post('post-3', 0, 0)],
    ]);
    assert.deepEqual(await handler(), { closed: 0, stillOpen: 3 });
    assert.deepEqual(closed, []);
  });

  test('every page of open posts is read', async () => {
    const { closed, asked, handler } = setUp([[post('post-1', 5, 25)], [post('post-2', 4, 4)], [post('post-3', 6, 6)]]);
    assert.deepEqual(await handler(), { closed: 2, stillOpen: 1 });
    assert.deepEqual(asked, [undefined, { page: 1 }, { page: 2 }]);
    assert.deepEqual(closed.map((entry) => [entry.postID, entry.score]), [['post-1', 100], ['post-3', 0]]);
  });

  test('a post that changed since it was read is left for the next run', async () => {
    const { closed, handler } = setUp([[post('post-1', 5, 20), post('post-2', 5, 20)]], ['post-1']);
    assert.deepEqual(await handler(), { closed: 1, stillOpen: 0 });
    assert.deepEqual(closed.map((entry) => entry.postID), ['post-2']);
  });
});
