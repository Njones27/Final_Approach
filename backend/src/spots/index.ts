import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { S3Client } from '@aws-sdk/client-s3';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { numberSetting, setting } from '../shared/settings.ts';
import { makeAwsSpotPhotoStore } from './awsStore.ts';
import { catalog } from './catalog.ts';
import { makeSpotsHandler } from './handler.ts';

const imageLinkSeconds = numberSetting('IMAGE_LINK_SECONDS');

/** The function behind the spot routes. */
export const handler = makeSpotsHandler({
  airports: catalog,
  store: makeAwsSpotPhotoStore({
    dynamo: DynamoDBDocumentClient.from(new DynamoDBClient({})),
    s3: new S3Client({}),
    tableName: setting('TABLE_NAME'),
    bucketName: setting('BUCKET_NAME'),
    imageLinkSeconds,
  }),
  photosPerSpot: numberSetting('PHOTOS_PER_SPOT'),
  imageLinkSeconds,
  grid: {
    placeCellsPerDegree: numberSetting('PLACE_CELLS_PER_DEGREE'),
    areaTilesPerDegree: numberSetting('AREA_TILES_PER_DEGREE'),
  },
  areaReadLimit: numberSetting('AREA_READ_LIMIT'),
  placesPerAnswer: numberSetting('PLACES_PER_ANSWER'),
});
