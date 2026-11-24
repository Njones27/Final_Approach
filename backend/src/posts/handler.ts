import {
  accountGone,
  bodyText,
  callerOf,
  json,
  noContent,
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
import type { PostStore, SpotShowing, StoredPost } from './store.ts';

export interface PostHandlerSettings {
  readonly store: PostStore;
  /** How long a post stays open for votes. */
  readonly votingWindowHours: number;
  readonly rules: VotingRules;
  readonly now: () => Date;
  /** Makes the random id a new post is known by. */
  readonly newPostID: () => string;
  /** True for the id of a spot that is listed. */
  readonly isListedSpot: (spotID: string) => boolean;
  /** The longest an aircraft type or an airline shown at a spot may be. */
  readonly shownTextMaxLength: number;
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
    // The owner is told where the photo is shown, so the app can keep it
    // in line with what the owner chose.
    ...(post.shownAt ? { shownAt: post.shownAt } : {}),
  };
}

/**
 * A line of text to show beside a photo, or why it cannot be shown.
 * Nothing but a short line of plain text is kept, because other users
 * will read it.
 */
function shownText(value: unknown, longest: number): string | undefined | 'unusable' {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') return 'unusable';
  const text = value.trim();
  if (text === '') return undefined;
  // A control character has no place in a name and can hide what follows it.
  if (text.length > longest || /[\u0000-\u001f\u007f]/.test(text)) return 'unusable';
  return text;
}

function objectIn(body: string | undefined): Record<string, unknown> | undefined {
  if (body === undefined || body === '' || body.length > 2048) return undefined;
  try {
    const parsed: unknown = JSON.parse(body);
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : undefined;
  } catch {
    return undefined;
  }
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

  /**
   * Shows one of the user's posted photos on a spot's page. Only the spot,
   * the aircraft type, and the airline are taken, and only these are ever
   * shown. The app sends this for a photo whose owner disclosed its place.
   */
  async function show(event: ApiEvent, userID: string, photoID: string): Promise<ApiResult> {
    const body = objectIn(bodyText(event));
    const spotID = body?.['spotID'];
    if (typeof spotID !== 'string' || spotID === '') {
      return problem(400, 'Name the spot to show the photo at.');
    }
    if (!settings.isListedSpot(spotID)) return problem(404, 'This spot is not listed.', 'unknownSpot');
    const aircraftType = shownText(body?.['aircraftType'], settings.shownTextMaxLength);
    const airline = shownText(body?.['airline'], settings.shownTextMaxLength);
    if (aircraftType === 'unusable' || airline === 'unusable') {
      return problem(400, `An aircraft type or an airline is plain text of up to ${settings.shownTextMaxLength} characters.`);
    }
    const showing: SpotShowing = {
      spotID,
      ...(aircraftType === undefined ? {} : { aircraftType }),
      ...(airline === undefined ? {} : { airline }),
    };
    const outcome = await store.showAtSpot(userID, photoID, showing);
    if (outcome === 'notPosted') {
      return problem(409, 'Post the photo before showing it at a spot.', 'notPosted');
    }
    return json(200, { photoID, shownAt: showing });
  }

  return async function handler(event: ApiEvent): Promise<ApiResult> {
    const caller = callerOf(event);
    if (!caller) return notSignedIn();

    if (event.routeKey === 'GET /posts') return list(event, caller.userID);
    const routes = ['PUT /posts/{photoID}', 'PUT /posts/{photoID}/spot', 'DELETE /posts/{photoID}/spot'];
    if (!routes.includes(event.routeKey)) return notFound();

    const photoID = event.pathParameters?.['photoID'];
    if (!isUsablePhotoID(photoID)) return problem(400, 'The photo id is not usable.');
    if (event.routeKey === 'PUT /posts/{photoID}/spot') return show(event, caller.userID, photoID);
    if (event.routeKey === 'DELETE /posts/{photoID}/spot') {
      await store.hideFromSpots(caller.userID, photoID);
      return noContent();
    }
    return post(caller.userID, photoID);
  };
}
