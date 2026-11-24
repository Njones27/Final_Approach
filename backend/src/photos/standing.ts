import { BatchGetCommand, type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { deletedAccountSortKey, partitionKey, photoSortKey } from '../shared/keys.ts';
import type { ImageStanding } from './sweeper.ts';

/** Reads the photo and the account marker together, with no stale copies. */
export async function standingOf(
  client: Pick<DynamoDBDocumentClient, 'send'>,
  table: string,
  userID: string,
  photoID: string,
): Promise<ImageStanding> {
  const pk = partitionKey(userID);
  const photoKey = photoSortKey(photoID);
  const result = await client.send(
    new BatchGetCommand({
      RequestItems: {
        [table]: {
          Keys: [
            { pk, sk: deletedAccountSortKey },
            { pk, sk: photoKey },
          ],
          ConsistentRead: true,
        },
      },
    }),
  );
  // A read that did not finish says nothing about the photo, so it fails
  // and S3 delivers the event again.
  if (Object.keys(result.UnprocessedKeys ?? {}).length > 0) {
    throw new Error('The photo lookup did not finish.');
  }
  const items = result.Responses?.[table] ?? [];
  if (items.some((item) => item['sk'] === deletedAccountSortKey)) return 'unwanted';
  const photo = items.find((item) => item['sk'] === photoKey);
  return photo && photo['deletedAt'] === undefined ? 'wanted' : 'unwanted';
}
