import { isUsablePhotoID } from '../shared/keys.ts';

/** The content type every upload link is signed for. */
export const imageContentType = 'image/jpeg';

/** The limits a photo is checked against. They come from the stage settings. */
export interface PhotoLimits {
  readonly maxDocumentBytes: number;
  readonly maxImageBytes: number;
}

/** What the app sends to save one photo. */
export interface PhotoUpload {
  /**
   * The photo as the app saves it. The backend keeps it for its owner and
   * does not read inside it. It can hold where the photo was taken, so it
   * must never be sent to another user as it is.
   */
  readonly documentJSON: string;
  /** The size of the image the app is about to upload, when it has one to send. */
  readonly imageBytes?: number;
}

export type Parsed<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly message: string };

const refused = (message: string): Parsed<never> => ({ ok: false, message });

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * Reads the body of a request to save a photo.
 *
 * The body is `{ "document": { ... }, "imageBytes": 123 }`. The document's
 * own id must match the id in the address, so one photo cannot be filed
 * under another's name.
 */
export function parsePhotoUpload(
  body: string | undefined,
  photoID: string,
  limits: PhotoLimits,
): Parsed<PhotoUpload> {
  if (!isUsablePhotoID(photoID)) return refused('The photo id is not usable.');
  if (body === undefined || body === '') return refused('The request has no body.');
  // The wrapper around the document is small, so a body much larger than
  // the document limit is refused before it is parsed.
  if (Buffer.byteLength(body, 'utf8') > limits.maxDocumentBytes + 1024) {
    return refused('The photo record is too large.');
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch {
    return refused('The request body is not JSON.');
  }
  if (!isPlainObject(parsed)) return refused('The request body must be an object.');

  const document = parsed['document'];
  if (!isPlainObject(document)) return refused('The request needs a document.');
  if (document['id'] !== photoID) return refused('The document id does not match the address.');

  const documentJSON = JSON.stringify(document);
  if (Buffer.byteLength(documentJSON, 'utf8') > limits.maxDocumentBytes) {
    return refused('The photo record is too large.');
  }

  const imageBytes = parsed['imageBytes'];
  if (imageBytes === undefined || imageBytes === null) {
    return { ok: true, value: { documentJSON } };
  }
  if (typeof imageBytes !== 'number' || !Number.isInteger(imageBytes) || imageBytes <= 0) {
    return refused('The image size must be a whole number of bytes above zero.');
  }
  if (imageBytes > limits.maxImageBytes) return refused('The image is too large.');
  return { ok: true, value: { documentJSON, imageBytes } };
}
