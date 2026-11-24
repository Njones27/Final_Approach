/** One graded photo its owner shows at a spot. */
export interface SpotPhoto {
  /** The post's random id, which names the photo without naming its owner. */
  readonly postID: string;
  /** Used only to find the image. It is never sent to anyone. */
  readonly ownerID: string;
  /** Used only to find the image. It is never sent to anyone. */
  readonly photoID: string;
  /** The grade the votes gave, from 0 to 100. */
  readonly score: number;
  readonly aircraftType?: string;
  readonly airline?: string;
}

/** Where the photos shown at spots are kept. The handler is tested against an in-memory one. */
export interface SpotPhotoStore {
  /** The graded photos shown at a spot, best first, up to a limit. */
  photosAt(spotID: string, limit: number): Promise<readonly SpotPhoto[]>;
  /** A link to the photo's image that works for a short time. */
  imageLink(photo: SpotPhoto): Promise<string>;
}
