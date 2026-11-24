/** The running totals of the votes on one post. */
export interface Tally {
  readonly voteCount: number;
  /** The sum of the voters' weights. */
  readonly weightSum: number;
  /** The sum of each vote's value times its voter's weight. */
  readonly weightedValueSum: number;
}

export const emptyTally: Tally = { voteCount: 0, weightSum: 0, weightedValueSum: 0 };

/** The rules of the vote. They come from the stage settings. */
export interface VotingRules {
  /** A vote is a whole number from 1 to this. */
  readonly scaleMax: number;
  /** The votes a post needs before its grade is final. */
  readonly minVotes: number;
}

/**
 * Where a post stands. The score is there only once the grade is final,
 * because voting is blind until then.
 */
export type Standing =
  | { readonly status: 'voting' }
  | { readonly status: 'final'; readonly score: number };

/** Whether a value is one a voter may give. */
export function isUsableVote(value: unknown, rules: VotingRules): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= rules.scaleMax;
}

/**
 * The grade the votes give, from 0 to 100. It is the weighted average of
 * the votes, stretched so that the lowest vote is 0 and the highest is 100.
 * Nothing else takes part in it. The technical check is advice to the
 * photographer and never moves this number.
 */
export function scoreOf(tally: Tally, rules: VotingRules): number {
  if (tally.weightSum <= 0 || rules.scaleMax <= 1) return 0;
  const average = tally.weightedValueSum / tally.weightSum;
  const score = ((average - 1) / (rules.scaleMax - 1)) * 100;
  return Math.round(Math.min(100, Math.max(0, score)));
}

/**
 * Whether a post still takes votes. It does until its window has ended
 * and it has the votes it needs. A post that reaches the end of its window
 * short of votes stays open, and the vote that brings it to the minimum
 * closes it.
 */
export function isOpen(post: { readonly closesAt: string } & Tally, now: Date, rules: VotingRules): boolean {
  return now.toISOString() < post.closesAt || post.voteCount < rules.minVotes;
}

export function standingOf(
  post: { readonly closesAt: string } & Tally,
  now: Date,
  rules: VotingRules,
): Standing {
  return isOpen(post, now, rules) ? { status: 'voting' } : { status: 'final', score: scoreOf(post, rules) };
}
