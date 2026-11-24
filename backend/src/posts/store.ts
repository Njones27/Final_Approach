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

export interface PostPage {
  readonly posts: readonly Post[];
  /** The photo id to pass as `after` for the next page, when there is one. */
  readonly nextAfter?: string;
}

/**
 * What became of a request to post. A photo is posted once, so a second
 * request finds the first post and changes nothing.
 */
export type PostOutcome =
  | { readonly outcome: 'posted' | 'alreadyPosted'; readonly post: Post }
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
}
