import {
  accountGone,
  bodyText,
  callerOf,
  json,
  noContent,
  notFound,
  notSignedIn,
  problem,
  type ApiEvent,
  type ApiResult,
} from '../shared/http.ts';
import { isUsablePhotoID } from '../shared/keys.ts';
import { imageContentType, parsePhotoUpload, type PhotoLimits } from './document.ts';
import type { PhotoStore } from './store.ts';

export interface PhotoHandlerSettings {
  readonly store: PhotoStore;
  readonly limits: PhotoLimits;
  readonly uploadLinkSeconds: number;
  readonly imageLinkSeconds: number;
  readonly now: () => Date;
}

/**
 * Saves, lists, and deletes the signed in user's own photos. No route here
 * reads another user's data, so a private location never leaves its owner.
 */
export function makePhotosHandler(settings: PhotoHandlerSettings) {
  const { store, limits } = settings;

  async function save(event: ApiEvent, userID: string, photoID: string): Promise<ApiResult> {
    const upload = parsePhotoUpload(bodyText(event), photoID, limits);
    if (!upload.ok) return problem(400, upload.message);

    const updatedAt = settings.now().toISOString();
    const outcome = await store.save(userID, {
      photoID,
      documentJSON: upload.value.documentJSON,
      updatedAt,
    });
    if (outcome === 'accountDeleted') return accountGone();
    if (outcome === 'photoDeleted') return problem(410, 'This photo was deleted.');

    const { imageBytes } = upload.value;
    if (imageBytes === undefined) return json(200, { photoID, updatedAt });
    return json(200, {
      photoID,
      updatedAt,
      upload: {
        url: await store.uploadLink(userID, photoID, imageBytes),
        method: 'PUT',
        headers: { 'Content-Type': imageContentType, 'Content-Length': String(imageBytes) },
        expiresInSeconds: settings.uploadLinkSeconds,
      },
    });
  }

  async function list(event: ApiEvent, userID: string): Promise<ApiResult> {
    const after = event.queryStringParameters?.['after'];
    if (after !== undefined && !isUsablePhotoID(after)) {
      return problem(400, 'The page marker is not usable.');
    }
    const page = await store.list(userID, after);
    const photos = await Promise.all(
      page.photos.map(async (photo) => ({
        photoID: photo.photoID,
        document: JSON.parse(photo.documentJSON) as unknown,
        updatedAt: photo.updatedAt,
        imageURL: await store.imageLink(userID, photo.photoID),
      })),
    );
    return json(200, {
      photos,
      deleted: page.deleted,
      nextAfter: page.nextAfter,
      imageLinkExpiresInSeconds: settings.imageLinkSeconds,
    });
  }

  async function remove(userID: string, photoID: string): Promise<ApiResult> {
    const outcome = await store.remove(userID, photoID, settings.now().toISOString());
    return outcome === 'accountDeleted' ? accountGone() : noContent();
  }

  return async function handler(event: ApiEvent): Promise<ApiResult> {
    const caller = callerOf(event);
    if (!caller) return notSignedIn();

    if (event.routeKey === 'GET /photos') return list(event, caller.userID);

    const photoID = event.pathParameters?.['photoID'];
    if (!isUsablePhotoID(photoID)) return problem(400, 'The photo id is not usable.');
    switch (event.routeKey) {
      case 'PUT /photos/{photoID}':
        return save(event, caller.userID, photoID);
      case 'DELETE /photos/{photoID}':
        return remove(caller.userID, photoID);
      default:
        return notFound();
    }
  };
}
