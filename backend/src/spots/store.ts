import type { CameraSettings } from '../posts/camera.ts';
import type { ShownWhere } from '../posts/store.ts';

/** One graded photo its owner shows at a spot or a place. */
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
  readonly camera?: CameraSettings;
}

/** A shown photo together with where it is shown, as the map needs it. */
export interface PlacedPhoto extends SpotPhoto {
  readonly where: ShownWhere;
}

/** Where the photos shown to other users are kept. The handler is tested against an in-memory one. */
export interface SpotPhotoStore {
  /**
   * The graded photos shown under one key of the `Spot` index, which is a
   * listed spot's or a place's, best first, up to a limit.
   */
  photosAt(shownKey: string, limit: number): Promise<readonly SpotPhoto[]>;
  /**
   * The graded photos shown in each of some tiles of the map, best first,
   * up to a limit for each tile.
   */
  photosIn(areaKeys: readonly string[], limitPerArea: number): Promise<readonly PlacedPhoto[]>;
  /** A link to the photo's image that works for a short time. */
  imageLink(photo: SpotPhoto): Promise<string>;
}
