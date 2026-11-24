import {
  accountGone,
  bodyText,
  callerOf,
  json,
  notFound,
  notSignedIn,
  problem,
  type ApiEvent,
  type ApiResult,
} from '../shared/http.ts';
import { isUsablePostID } from '../shared/keys.ts';
import { isOpen, isUsableVote, type VotingRules } from './standing.ts';
import type { VoteStore } from './store.ts';

export interface VoteHandlerSettings {
  readonly store: VoteStore;
  readonly rules: VotingRules;
  /** How many posts one answer of the queue holds. */
  readonly queueSize: number;
  /** How many open posts one request reads to fill the queue. */
  readonly queueReadLimit: number;
  /** The weight of one vote. Every voter has the same weight until reputation exists. */
  readonly voteWeight: number;
  readonly imageLinkSeconds: number;
  readonly now: () => Date;
  /** A random id, used as the place the queue starts reading from. */
  readonly randomID: () => string;
}

const votingClosed = (): ApiResult => problem(410, 'Voting on this photo has closed.', 'votingClosed');

function valueIn(body: string | undefined): unknown {
  if (body === undefined || body === '' || body.length > 1024) return undefined;
  try {
    const parsed: unknown = JSON.parse(body);
    return typeof parsed === 'object' && parsed !== null ? (parsed as Record<string, unknown>)['value'] : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Hands a voter photos to vote on and counts their votes.
 *
 * Voting is blind. A voter is shown the image and the post's random id
 * and nothing else. No name, no place, no vote count, and no score leave
 * here. A user never sees their own photo in the queue and cannot vote on
 * it.
 */
export function makeVotesHandler(settings: VoteHandlerSettings) {
  const { store, rules } = settings;

  async function queue(voterID: string): Promise<ApiResult> {
    const now = settings.now();
    const read = await store.openPosts(settings.randomID(), settings.queueReadLimit);
    const candidates = read.filter((post) => post.ownerID !== voterID && isOpen(post, now, rules));
    const voted = await store.votedOn(voterID, candidates.map((post) => post.postID));
    const chosen = candidates.filter((post) => !voted.has(post.postID)).slice(0, settings.queueSize);
    const posts = await Promise.all(
      chosen.map(async (post) => ({ postID: post.postID, imageURL: await store.imageLink(post) })),
    );
    return json(200, {
      posts,
      scaleMax: rules.scaleMax,
      imageLinkExpiresInSeconds: settings.imageLinkSeconds,
    });
  }

  async function vote(event: ApiEvent, voterID: string, postID: string): Promise<ApiResult> {
    const value = valueIn(bodyText(event));
    if (!isUsableVote(value, rules)) {
      return problem(400, `A vote is a whole number from 1 to ${rules.scaleMax}.`);
    }

    const post = await store.openPost(postID);
    const now = settings.now();
    if (!post || !isOpen(post, now, rules)) return votingClosed();
    if (post.ownerID === voterID) return problem(403, 'You cannot vote on your own photo.', 'ownPost');

    const outcome = await store.cast(
      voterID,
      post,
      { postID, value, weight: settings.voteWeight, votedAt: now.toISOString() },
      now,
    );
    switch (outcome) {
      case 'accountDeleted':
        return accountGone();
      case 'alreadyVoted':
        return problem(409, 'You have already voted on this photo.', 'alreadyVoted');
      case 'votingClosed':
        return votingClosed();
      default:
        return json(200, { postID, value });
    }
  }

  return async function handler(event: ApiEvent): Promise<ApiResult> {
    const caller = callerOf(event);
    if (!caller) return notSignedIn();

    if (event.routeKey === 'GET /votes/queue') return queue(caller.userID);
    if (event.routeKey !== 'PUT /votes/{postID}') return notFound();

    const postID = event.pathParameters?.['postID'];
    if (!isUsablePostID(postID)) return problem(400, 'The post id is not usable.');
    return vote(event, caller.userID, postID);
  };
}
