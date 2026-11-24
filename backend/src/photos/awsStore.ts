import { DeleteObjectCommand, GetObjectCommand, PutObjectCommand, type S3Client } from '@aws-sdk/client-s3';
import { QueryCommand, TransactWriteCommand, type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import {
  deletedAccountSortKey,
  imageKey,
  partitionKey,
  photoSortKey,
  photoSortKeyPrefix,
} from '../shared/keys.ts';
import { imageContentType } from './document.ts';
import type { DeletedPhoto, PhotoPage, PhotoStore, StoredPhoto, WriteOutcome } from './store.ts';

export interface AwsPhotoStoreSettings {
  readonly dynamo: Pick<DynamoDBDocumentClient, 'send'>;
  readonly s3: S3Client;
  readonly tableName: string;
  readonly bucketName: string;
  readonly photosPerPage: number;
  readonly uploadLinkSeconds: number;
  readonly imageLinkSeconds: number;
}

/** The order of the two parts of every write, which names the one that failed. */
const accountCheckIndex = 0;

function isCancelledTransaction(error: unknown): error is { CancellationReasons?: { Code?: string }[] } {
  return error instanceof Error && error.name === 'TransactionCanceledException';
}

/** Photos kept in the DynamoDB table and the S3 bucket. */
export function makeAwsPhotoStore(settings: AwsPhotoStoreSettings): PhotoStore {
  const { dynamo, s3, tableName, bucketName } = settings;

  /**
   * Writes one photo item, but only while the account still exists. Both
   * conditions are checked in one transaction, so a delete of the account
   * that lands at the same moment cannot leave a stray record behind.
   */
  async function write(
    userID: string,
    item: Record<string, unknown>,
    condition?: string,
  ): Promise<WriteOutcome> {
    const pk = partitionKey(userID);
    try {
      await dynamo.send(
        new TransactWriteCommand({
          TransactItems: [
            {
              ConditionCheck: {
                TableName: tableName,
                Key: { pk, sk: deletedAccountSortKey },
                ConditionExpression: 'attribute_not_exists(pk)',
              },
            },
            {
              Put: {
                TableName: tableName,
                Item: { pk, ...item },
                ...(condition ? { ConditionExpression: condition } : {}),
              },
            },
          ],
        }),
      );
      return 'saved';
    } catch (error) {
      if (!isCancelledTransaction(error)) throw error;
      const accountCheck = error.CancellationReasons?.[accountCheckIndex]?.Code;
      return accountCheck === 'ConditionalCheckFailed' ? 'accountDeleted' : 'photoDeleted';
    }
  }

  return {
    save(userID, photo) {
      return write(
        userID,
        {
          sk: photoSortKey(photo.photoID),
          photoID: photo.photoID,
          documentJSON: photo.documentJSON,
          updatedAt: photo.updatedAt,
        },
        'attribute_not_exists(deletedAt)',
      );
    },

    async list(userID, after): Promise<PhotoPage> {
      const pk = partitionKey(userID);
      const result = await dynamo.send(
        new QueryCommand({
          TableName: tableName,
          KeyConditionExpression: 'pk = :pk AND begins_with(sk, :photos)',
          ExpressionAttributeValues: { ':pk': pk, ':photos': photoSortKeyPrefix },
          Limit: settings.photosPerPage,
          // The page marker holds only a photo id. The partition is always
          // the caller's own, so a marker cannot reach into another account.
          ...(after ? { ExclusiveStartKey: { pk, sk: photoSortKey(after) } } : {}),
        }),
      );

      const photos: StoredPhoto[] = [];
      const deleted: DeletedPhoto[] = [];
      for (const item of result.Items ?? []) {
        const photoID = String(item['photoID']);
        if (typeof item['deletedAt'] === 'string') {
          deleted.push({ photoID, deletedAt: item['deletedAt'] });
        } else {
          photos.push({
            photoID,
            documentJSON: String(item['documentJSON']),
            updatedAt: String(item['updatedAt']),
          });
        }
      }
      const lastKey = result.LastEvaluatedKey?.['sk'];
      const nextAfter =
        typeof lastKey === 'string' ? lastKey.slice(photoSortKeyPrefix.length) : undefined;
      return { photos, deleted, ...(nextAfter ? { nextAfter } : {}) };
    },

    async remove(userID, photoID, deletedAt) {
      // The record is replaced by a marker that holds nothing but the id,
      // so another device that still has the photo cannot bring it back.
      // The marker goes first. An upload that lands after it is removed by
      // the sweeper, and one that landed before it is removed here.
      const outcome = await write(userID, { sk: photoSortKey(photoID), photoID, deletedAt });
      if (outcome !== 'saved') return outcome;
      await s3.send(new DeleteObjectCommand({ Bucket: bucketName, Key: imageKey(userID, photoID) }));
      return 'saved';
    },

    uploadLink(userID, photoID, imageBytes) {
      return getSignedUrl(
        s3,
        new PutObjectCommand({
          Bucket: bucketName,
          Key: imageKey(userID, photoID),
          ContentType: imageContentType,
          ContentLength: imageBytes,
        }),
        {
          expiresIn: settings.uploadLinkSeconds,
          // Signing the type and the length makes S3 refuse anything but a
          // JPEG of the size the backend agreed to. The length is signed
          // without being named. It is named so that stays true.
          signableHeaders: new Set(['content-type', 'content-length']),
        },
      );
    },

    imageLink(userID, photoID) {
      return getSignedUrl(
        s3,
        new GetObjectCommand({ Bucket: bucketName, Key: imageKey(userID, photoID) }),
        { expiresIn: settings.imageLinkSeconds },
      );
    },
  };
}
