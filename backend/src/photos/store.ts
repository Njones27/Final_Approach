/** One photo as the backend keeps it. */
export interface StoredPhoto {
  readonly photoID: string;
  /** The app's own record of the photo, as JSON. Only its owner may read it. */
  readonly documentJSON: string;
  /** When the backend last saved the record, as an ISO 8601 time. */
  readonly updatedAt: string;
}

/** The trace a deleted photo leaves, so the user's other devices drop it too. */
export interface DeletedPhoto {
  readonly photoID: string;
  readonly deletedAt: string;
}

export interface PhotoPage {
  readonly photos: readonly StoredPhoto[];
  readonly deleted: readonly DeletedPhoto[];
  /** The id to pass as `after` for the next page, when there is one. */
  readonly nextAfter?: string;
}

/** Why a write was turned away. */
export type WriteOutcome = 'saved' | 'photoDeleted' | 'accountDeleted';

/** Where photos are kept. The handler is tested against an in-memory one. */
export interface PhotoStore {
  /**
   * Saves a photo record. A photo that was deleted stays deleted, and an
   * account that was deleted takes no new photos.
   */
  save(userID: string, photo: StoredPhoto): Promise<WriteOutcome>;
  list(userID: string, after?: string): Promise<PhotoPage>;
  /**
   * Deletes a photo and its image. The record is marked deleted first and
   * the image goes second. If the image cannot be removed the call fails,
   * and the app tries the delete again.
   */
  remove(userID: string, photoID: string, deletedAt: string): Promise<WriteOutcome>;
  /** A link that accepts one JPEG of exactly this size. */
  uploadLink(userID: string, photoID: string, imageBytes: number): Promise<string>;
  /** A link that reads the photo's image. */
  imageLink(userID: string, photoID: string): Promise<string>;
}
