import { GetObjectCommand, type S3Client } from '@aws-sdk/client-s3';
import { QueryCommand, type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { cameraOf } from '../posts/camera.ts';
import { areaIndex, imageKey, spotIndex, userOfPartitionKey } from '../shared/keys.ts';
import type { PlacedPhoto, SpotPhoto, SpotPhotoStore } from './store.ts';

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
  const camera = cameraOf(item);
  return {
    postID,
    ownerID,
    photoID,
    score,
    ...(typeof aircraftType === 'string' ? { aircraftType } : {}),
    ...(typeof airline === 'string' ? { airline } : {}),
    ...(camera ? { camera } : {}),
  };
}

/** A post as the map needs it, or nothing for a record that says nowhere it is shown. */
export function placedPhotoOf(item: Record<string, unknown>): PlacedPhoto | undefined {
  const photo = spotPhotoOf(item);
  if (!photo) return undefined;
  const spotID = item['spotID'];
  const placeID = item['placeID'];
  if (typeof spotID === 'string') return { ...photo, where: { spotID } };
  if (typeof placeID === 'string') return { ...photo, where: { placeID } };
  return undefined;
}

/** The photos shown to other users, read from two indexes of the DynamoDB table. */
export function makeAwsSpotPhotoStore(settings: AwsSpotPhotoStoreSettings): SpotPhotoStore {
  /** One key of an index, read backwards, so the best photo is first. */
  async function best(
    index: { readonly name: string; readonly partitionKey: string },
    key: string,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const result = await settings.dynamo.send(
      new QueryCommand({
        TableName: settings.tableName,
        IndexName: index.name,
        KeyConditionExpression: '#key = :key',
        ExpressionAttributeNames: { '#key': index.partitionKey },
        ExpressionAttributeValues: { ':key': key },
        // Both indexes are sorted by the grade.
        ScanIndexForward: false,
        Limit: limit,
      }),
    );
    return result.Items ?? [];
  }

  return {
    async photosAt(shownKey, limit) {
      return (await best(spotIndex, shownKey, limit)).flatMap((item) => {
        const photo = spotPhotoOf(item);
        return photo ? [photo] : [];
      });
    },

    async photosIn(areaKeys, limitPerArea) {
      const tiles = await Promise.all(areaKeys.map((key) => best(areaIndex, key, limitPerArea)));
      return tiles.flat().flatMap((item) => {
        const photo = placedPhotoOf(item);
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
