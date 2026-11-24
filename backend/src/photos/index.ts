import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { S3Client } from '@aws-sdk/client-s3';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { numberSetting, setting } from '../shared/settings.ts';
import { makeAwsPhotoStore } from './awsStore.ts';
import { makePhotosHandler } from './handler.ts';

const uploadLinkSeconds = numberSetting('UPLOAD_LINK_SECONDS');
const imageLinkSeconds = numberSetting('IMAGE_LINK_SECONDS');

/** The function behind the photo routes. */
export const handler = makePhotosHandler({
  store: makeAwsPhotoStore({
    dynamo: DynamoDBDocumentClient.from(new DynamoDBClient({})),
    s3: new S3Client({}),
    tableName: setting('TABLE_NAME'),
    bucketName: setting('BUCKET_NAME'),
    photosPerPage: numberSetting('PHOTOS_PER_PAGE'),
    uploadLinkSeconds,
    imageLinkSeconds,
  }),
  limits: {
    maxDocumentBytes: numberSetting('MAX_DOCUMENT_BYTES'),
    maxImageBytes: numberSetting('MAX_IMAGE_BYTES'),
  },
  uploadLinkSeconds,
  imageLinkSeconds,
  now: () => new Date(),
});
