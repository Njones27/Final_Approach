import { scoreOf, isOpen, type VotingRules } from './standing.ts';
import type { OpenPost } from './store.ts';

/** What the closer needs of the place posts are kept. */
export interface CloserStore {
  /** One page of the posts that carry the open mark, and where the next starts. */
  page(startKey?: Record<string, unknown>): Promise<{
    readonly posts: readonly OpenPost[];
    readonly next?: Record<string, unknown>;
  }>;
  /**
   * Writes the final score on a post and takes its open mark off. False
   * means the post changed since it was read and was left as it is.
   */
  close(post: OpenPost, score: number, finalizedAt: string): Promise<boolean>;
}

export interface CloserSettings {
  readonly store: CloserStore;
  readonly rules: VotingRules;
  readonly now: () => Date;
}

/**
 * Runs on a schedule and closes each post whose voting has ended.
 *
 * A post stops taking votes by the rules alone, the moment its window has
 * ended and it has the votes it needs. This function only writes that
 * down. It keeps the final score on the post and takes the post out of the
 * index of open posts, so the voting queue stays short.
 */
export function makeCloser(settings: CloserSettings) {
  return async function handler(): Promise<{ closed: number; stillOpen: number }> {
    const now = settings.now();
    let closed = 0;
    let stillOpen = 0;
    let startKey: Record<string, unknown> | undefined;
    do {
      const page = await settings.store.page(startKey);
      for (const post of page.posts) {
        if (isOpen(post, now, settings.rules)) {
          stillOpen += 1;
        } else if (await settings.store.close(post, scoreOf(post, settings.rules), now.toISOString())) {
          closed += 1;
        }
      }
      startKey = page.next;
    } while (startKey);
    return { closed, stillOpen };
  };
}
