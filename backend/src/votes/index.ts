import { randomUUID } from 'node:crypto';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { S3Client } from '@aws-sdk/client-s3';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { numberSetting, setting } from '../shared/settings.ts';
import { makeAwsVoteStore } from './awsStore.ts';
import { makeVotesHandler } from './handler.ts';

const imageLinkSeconds = numberSetting('IMAGE_LINK_SECONDS');
const rules = { scaleMax: numberSetting('VOTE_SCALE_MAX'), minVotes: numberSetting('MIN_VOTES') };

/** The function behind the voting routes. */
export const handler = makeVotesHandler({
  store: makeAwsVoteStore({
    dynamo: DynamoDBDocumentClient.from(new DynamoDBClient({})),
    s3: new S3Client({}),
    tableName: setting('TABLE_NAME'),
    bucketName: setting('BUCKET_NAME'),
    minVotes: rules.minVotes,
    imageLinkSeconds,
  }),
  rules,
  queueSize: numberSetting('VOTING_QUEUE_SIZE'),
  queueReadLimit: numberSetting('VOTING_QUEUE_READ_LIMIT'),
  // Every voter counts the same until reputation exists.
  voteWeight: 1,
  imageLinkSeconds,
  now: () => new Date(),
  randomID: randomUUID,
});
