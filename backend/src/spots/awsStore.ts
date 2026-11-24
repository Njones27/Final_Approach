import { GetObjectCommand, type S3Client } from '@aws-sdk/client-s3';
import { QueryCommand, type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { imageKey, spotIndex, spotKey, userOfPartitionKey } from '../shared/keys.ts';
import type { SpotPhoto, SpotPhotoStore } from './store.ts';

export interface AwsSpotPhotoStoreSettings {
  readonly dynamo: Pick<DynamoDBDocumentClient, 'send'>;
  readonly s3: S3Client;
  readonly tableName: string;
  readonly bucketName: string;
  readonly imageLinkSeconds: number;
}

/** A post as a spot's page needs it, or nothing for a record that is not one. */
export function spotPhotoOf(item: Record<string, unknown>): SpotPhoto | undefined {
  const ownerID = userOfPartitionKey(String(item['pk']));
  const postID = item['postID'];
  const photoID = item['photoID'];
  const score = item[spotIndex.sortKey];
  if (ownerID === undefined || typeof postID !== 'string' || typeof photoID !== 'string') return undefined;
  if (typeof score !== 'number') return undefined;
  const aircraftType = item['aircraftType'];
  const airline = item['airline'];
  return {
    postID,
    ownerID,
    photoID,
    score,
    ...(typeof aircraftType === 'string' ? { aircraftType } : {}),
    ...(typeof airline === 'string' ? { airline } : {}),
  };
}

/** The photos shown at spots, read from the index of the DynamoDB table. */
export function makeAwsSpotPhotoStore(settings: AwsSpotPhotoStoreSettings): SpotPhotoStore {
  return {
    async photosAt(spotID, limit) {
      const result = await settings.dynamo.send(
        new QueryCommand({
          TableName: settings.tableName,
          IndexName: spotIndex.name,
          KeyConditionExpression: '#spot = :spot',
          ExpressionAttributeNames: { '#spot': spotIndex.partitionKey },
          ExpressionAttributeValues: { ':spot': spotKey(spotID) },
          // The index is sorted by the grade, so reading it backwards
          // gives the best photo first.
          ScanIndexForward: false,
          Limit: limit,
        }),
      );
      return (result.Items ?? []).flatMap((item) => {
        const photo = spotPhotoOf(item);
        return photo ? [photo] : [];
      });
    },

    imageLink(photo) {
      return getSignedUrl(
        settings.s3,
        new GetObjectCommand({ Bucket: settings.bucketName, Key: imageKey(photo.ownerID, photo.photoID) }),
        { expiresIn: settings.imageLinkSeconds },
      );
    },
  };
}
