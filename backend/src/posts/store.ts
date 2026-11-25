import type { Tally } from '../votes/standing.ts';
import type { CameraSettings } from './camera.ts';

/** One photo put in front of other users for their votes. */
export interface Post {
  readonly photoID: string;
  /** A random id that names the post to a voter without naming its owner. */
  readonly postID: string;
  /** When the photo was posted, as an ISO 8601 time. */
  readonly postedAt: string;
  /** When the voting window ends, as an ISO 8601 time. */
  readonly closesAt: string;
}

/**
 * Where a photo is shown. It is either a listed spot or a place, which is
 * one small cell of the map for a photo taken away from the listed spots.
 */
export type ShownWhere =
  | { readonly spotID: string; readonly placeID?: undefined }
  | { readonly placeID: string; readonly spotID?: undefined };

/**
 * What a post shows to other users, by its owner's choice. These are the
 * only things about a photo, beside its image and grade, that another user
 * is ever sent. There is no name, no registration, and no position finer
 * than the place's cell.
 */
export type SpotShowing = ShownWhere & {
  readonly aircraftType?: string;
  readonly airline?: string;
  readonly camera?: CameraSettings;
};

/** A post as it is kept, with the votes counted on it so far. */
export interface StoredPost extends Post, Tally {
  /** The grade the votes gave, written down once voting has closed. */
  readonly finalScore?: number;
  /** Where the owner shows the photo. It is absent for a photo shown nowhere. */
  readonly shownAt?: SpotShowing;
}

export interface PostPage {
  readonly posts: readonly StoredPost[];
  /** The photo id to pass as `after` for the next page, when there is one. */
  readonly nextAfter?: string;
}

/**
 * What became of a request to post. A photo is posted once, so a second
 * request finds the first post and changes nothing.
 */
export type PostOutcome =
  | { readonly outcome: 'posted' | 'alreadyPosted'; readonly post: StoredPost }
  | { readonly outcome: 'photoNotSaved' | 'photoDeleted' | 'accountDeleted' };

/** Where posts are kept. The handler is tested against an in-memory one. */
export interface PostStore {
  /**
   * Posts a photo the user has saved. A photo with no record, a deleted
   * photo, and a deleted account are each turned away.
   */
  post(userID: string, post: Post): Promise<PostOutcome>;
  /** The user's own posts. */
  list(userID: string, after?: string): Promise<PostPage>;
  /** The photo's image as it is stored, or nothing when none has arrived. */
  imageBytes(userID: string, photoID: string): Promise<Uint8Array | undefined>;
  /**
   * Shows a posted photo at a spot or a place, in place of anything it
   * showed before. `areaKey` names the tile of the map it is found in. A
   * photo that is not posted is turned away.
   */
  showAtSpot(
    userID: string,
    photoID: string,
    showing: SpotShowing,
    areaKey: string,
  ): Promise<'shown' | 'notPosted'>;
  /** Takes a photo off its spot or place. A photo shown nowhere is left as it is. */
  hideFromSpots(userID: string, photoID: string): Promise<void>;
}
