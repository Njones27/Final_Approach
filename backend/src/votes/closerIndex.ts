import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { numberSetting, setting } from '../shared/settings.ts';
import { makeAwsCloserStore } from './awsStore.ts';
import { makeCloser } from './closer.ts';

const rules = { scaleMax: numberSetting('VOTE_SCALE_MAX'), minVotes: numberSetting('MIN_VOTES') };

/** The function the schedule calls to close posts whose voting has ended. */
export const handler = makeCloser({
  store: makeAwsCloserStore({
    dynamo: DynamoDBDocumentClient.from(new DynamoDBClient({})),
    tableName: setting('TABLE_NAME'),
    minVotes: rules.minVotes,
  }),
  rules,
  now: () => new Date(),
});
