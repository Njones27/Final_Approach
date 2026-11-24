/**
 * Where a user's data lives. Every record sits under the user's partition
 * and every image under the user's folder, so deleting an account is one
 * sweep of each.
 */

/** The sort key of the marker left behind by a deleted account. */
export const deletedAccountSortKey = 'ACCOUNT#DELETED';

/** Every photo's sort key starts with this. */
export const photoSortKeyPrefix = 'PHOTO#';

/**
 * A photo id becomes part of a storage path, so only plain letters, numbers,
 * hyphens, and underscores are allowed. The app uses the same rule for its
 * file names.
 */
export function isUsablePhotoID(id: unknown): id is string {
  return typeof id === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(id);
}

export function partitionKey(userID: string): string {
  return `USER#${userID}`;
}

export function photoSortKey(photoID: string): string {
  return `${photoSortKeyPrefix}${photoID}`;
}

export function isPhotoSortKey(sortKey: string): boolean {
  return sortKey.startsWith(photoSortKeyPrefix);
}

/**
 * Every post's sort key starts with this. A post is the record that puts
 * one photo in front of other users. It sits under its owner's partition,
 * so deleting the account removes it with everything else.
 */
export const postSortKeyPrefix = 'POST#';

export function postSortKey(photoID: string): string {
  return `${postSortKeyPrefix}${photoID}`;
}

/**
 * The index that finds the posts still open for votes, across all users.
 * A post carries `votingKey` only while it is open, so a closed post drops
 * out of the index by itself. `postID` is a random id that names the post
 * to a voter without naming its owner.
 */
export const votingIndex = {
  name: 'Voting',
  partitionKey: 'votingKey',
  sortKey: 'postID',
  /** The one value `votingKey` takes. */
  open: 'OPEN',
} as const;

/**
 * The index that finds the graded photos shown at one spot, best first.
 *
 * A post carries `spotKey` only while its owner shows it at a spot, and
 * `finalScore` only once its grade is final. An index holds a record only
 * when the record has both of the index's keys. So a photo still being
 * voted on is never listed, and a photo taken off its spot drops out by
 * itself. Deleting the post or the account removes it like any record.
 */
export const spotIndex = {
  name: 'Spot',
  partitionKey: 'spotKey',
  sortKey: 'finalScore',
} as const;

export function spotKey(spotID: string): string {
  return `SPOT#${spotID}`;
}

/** The folder that holds every image a user uploaded. */
export function userFolder(userID: string): string {
  return `users/${userID}/`;
}

export function imageKey(userID: string, photoID: string): string {
  return `${userFolder(userID)}photos/${photoID}.jpg`;
}

/** The user and photo an image belongs to, read back from where it is stored. */
export function parseImageKey(key: string): { userID: string; photoID: string } | undefined {
  const match = /^users\/([^/]+)\/photos\/([A-Za-z0-9_-]{1,80})\.jpg$/.exec(key);
  if (!match || match[1] === undefined || match[2] === undefined) return undefined;
  return { userID: match[1], photoID: match[2] };
}

/**
 * Every vote's sort key starts with this. A vote sits under its voter's
 * partition, so deleting the voter's account removes it. It names the post
 * by its random id and never names the post's owner.
 */
export const voteSortKeyPrefix = 'VOTE#';

export function voteSortKey(postID: string): string {
  return `${voteSortKeyPrefix}${postID}`;
}

/** A post id is made by the backend, as letters, numbers, and hyphens. */
export function isUsablePostID(id: unknown): id is string {
  return typeof id === 'string' && /^[A-Za-z0-9-]{1,80}$/.test(id);
}

/** The user a partition key belongs to. */
export function userOfPartitionKey(pk: string): string | undefined {
  return pk.startsWith('USER#') ? pk.slice('USER#'.length) : undefined;
}
