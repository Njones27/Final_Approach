import {
  accountGone,
  callerOf,
  json,
  notFound,
  notSignedIn,
  photoGone,
  problem,
  type ApiEvent,
  type ApiResult,
} from '../shared/http.ts';
import { isUsablePhotoID } from '../shared/keys.ts';
import { standingOf, type VotingRules } from '../votes/standing.ts';
import { checkImageForLocation } from './imageCheck.ts';
import type { PostStore, StoredPost } from './store.ts';

export interface PostHandlerSettings {
  readonly store: PostStore;
  /** How long a post stays open for votes. */
  readonly votingWindowHours: number;
  readonly rules: VotingRules;
  readonly now: () => Date;
  /** Makes the random id a new post is known by. */
  readonly newPostID: () => string;
}

const photoNotSaved = (): ApiResult =>
  problem(409, 'Save the photo and its image before posting it.', 'photoNotSaved');

/**
 * What the owner is told about a post. The post's own id is for voters and
 * is left out. Voting is blind, so the score is there only once it is
 * final. Until then the owner sees how many votes are in and nothing more.
 */
function answer(post: StoredPost, now: Date, rules: VotingRules) {
  // A score that was written down stands, even if the rules change later.
  const standing =
    post.finalScore === undefined
      ? standingOf(post, now, rules)
      : ({ status: 'final', score: post.finalScore } as const);
  return {
    photoID: post.photoID,
    postedAt: post.postedAt,
    closesAt: post.closesAt,
    voteCount: post.voteCount,
    ...standing,
  };
}

/**
 * Posts the signed in user's own photos and lists their posts. Posting
 * never asks how the photo did in the technical check. The check is advice
 * to its owner, and every posted photo goes to the vote.
 */
export function makePostsHandler(settings: PostHandlerSettings) {
  const { store } = settings;

  async function post(userID: string, photoID: string): Promise<ApiResult> {
    // Other users will see this image, so it must not say where it was
    // taken. The check runs on every post, whether or not the photo is
    // marked undisclosed, because the image is never where a place is shown.
    const image = await store.imageBytes(userID, photoID);
    if (!image) return photoNotSaved();
    const check = checkImageForLocation(image);
    if (check === 'notJPEG') return problem(422, 'The image is not a JPEG that can be posted.');
    if (check === 'carriesLocation') {
      return problem(422, 'The image has a location written inside it.', 'imageHasLocation');
    }

    const postedAt = settings.now();
    const closesAt = new Date(postedAt.getTime() + settings.votingWindowHours * 60 * 60 * 1000);
    const result = await store.post(userID, {
      photoID,
      postID: settings.newPostID(),
      postedAt: postedAt.toISOString(),
      closesAt: closesAt.toISOString(),
    });
    switch (result.outcome) {
      case 'accountDeleted':
        return accountGone();
      case 'photoDeleted':
        return photoGone();
      case 'photoNotSaved':
        return photoNotSaved();
      default:
        return json(200, answer(result.post, postedAt, settings.rules));
    }
  }

  async function list(event: ApiEvent, userID: string): Promise<ApiResult> {
    const after = event.queryStringParameters?.['after'];
    if (after !== undefined && !isUsablePhotoID(after)) {
      return problem(400, 'The page marker is not usable.');
    }
    const page = await store.list(userID, after);
    const now = settings.now();
    return json(200, {
      posts: page.posts.map((post) => answer(post, now, settings.rules)),
      minVotes: settings.rules.minVotes,
      nextAfter: page.nextAfter,
    });
  }

  return async function handler(event: ApiEvent): Promise<ApiResult> {
    const caller = callerOf(event);
    if (!caller) return notSignedIn();

    if (event.routeKey === 'GET /posts') return list(event, caller.userID);
    if (event.routeKey !== 'PUT /posts/{photoID}') return notFound();

    const photoID = event.pathParameters?.['photoID'];
    if (!isUsablePhotoID(photoID)) return problem(400, 'The photo id is not usable.');
    return post(caller.userID, photoID);
  };
}
