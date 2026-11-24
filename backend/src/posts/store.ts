import type { Tally } from '../votes/standing.ts';

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
 * What a post shows on a spot's page, by its owner's choice. These are the
 * only things about a photo, beside its image and grade, that another user
 * is ever sent. There is no name, no registration, and no position.
 */
export interface SpotShowing {
  /** The listed spot the photo was taken at. */
  readonly spotID: string;
  readonly aircraftType?: string;
  readonly airline?: string;
}

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
   * Shows a posted photo at a spot, in place of anything it showed before.
   * A photo that is not posted is turned away.
   */
  showAtSpot(userID: string, photoID: string, showing: SpotShowing): Promise<'shown' | 'notPosted'>;
  /** Takes a photo off its spot. A photo shown nowhere is left as it is. */
  hideFromSpots(userID: string, photoID: string): Promise<void>;
}
