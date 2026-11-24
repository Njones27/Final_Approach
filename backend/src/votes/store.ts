import type { Tally } from './standing.ts';

/** A post as the voting side sees it. The owner is known here and is never sent on. */
export interface OpenPost extends Tally {
  readonly ownerID: string;
  readonly photoID: string;
  readonly postID: string;
  readonly closesAt: string;
}

/** One vote as it is kept. */
export interface Vote {
  readonly postID: string;
  readonly value: number;
  /** The voter's weight when the vote was cast. */
  readonly weight: number;
  readonly votedAt: string;
}

/** What became of a vote. */
export type VoteOutcome = 'counted' | 'alreadyVoted' | 'votingClosed' | 'accountDeleted';

/** Where votes are kept. The handler is tested against an in-memory one. */
export interface VoteStore {
  /**
   * Some of the posts that carry the open mark, starting from a place
   * picked at random so that no post is always first. A post can carry
   * the mark for a while after its voting has ended.
   */
  openPosts(startAfter: string, limit: number): Promise<readonly OpenPost[]>;
  /** One post that carries the open mark, by the id voters know it by. */
  openPost(postID: string): Promise<OpenPost | undefined>;
  /** Which of these posts the voter has already voted on. */
  votedOn(voterID: string, postIDs: readonly string[]): Promise<ReadonlySet<string>>;
  /**
   * Counts one vote. The vote and the post's totals change together or
   * not at all. A voter has one vote on a post, and a post that has closed
   * takes no more.
   */
  cast(voterID: string, post: OpenPost, vote: Vote, now: Date): Promise<VoteOutcome>;
  /** A link that reads the post's image. */
  imageLink(post: OpenPost): Promise<string>;
}
