import type { S3Event } from 'aws-lambda';
import { parseImageKey } from '../shared/keys.ts';

/** Whether an image that just arrived still has a photo to belong to. */
export type ImageStanding = 'wanted' | 'unwanted';

export interface SweeperSettings {
  /** Looks up whether the photo, and its account, still exist. */
  readonly standing: (userID: string, photoID: string) => Promise<ImageStanding>;
  readonly removeImage: (key: string) => Promise<void>;
}

/**
 * Runs each time an image lands in the bucket.
 *
 * An upload link stays usable for a few minutes, so an image can arrive
 * after its photo or its whole account was deleted. Deleting must remove
 * the stored images, so an image with nothing to belong to is removed here.
 */
export function makeSweeper(settings: SweeperSettings) {
  return async function handler(event: S3Event): Promise<void> {
    for (const record of event.Records) {
      // S3 writes the key as it would appear in a web address.
      const key = decodeURIComponent(record.s3.object.key.replaceAll('+', ' '));
      const image = parseImageKey(key);
      // Only the upload links write to the bucket, and they always use this
      // shape. Anything else was put there by hand and is left alone.
      if (!image) continue;
      if ((await settings.standing(image.userID, image.photoID)) === 'unwanted') {
        await settings.removeImage(key);
      }
    }
  };
}
