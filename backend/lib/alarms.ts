import { Duration } from 'aws-cdk-lib';
import { Alarm, ComparisonOperator, TreatMissingData, type IMetric } from 'aws-cdk-lib/aws-cloudwatch';
import { SnsAction } from 'aws-cdk-lib/aws-cloudwatch-actions';
import type { ITopic } from 'aws-cdk-lib/aws-sns';
import type { Construct } from 'constructs';
import type { StageSettings } from './stages.ts';

/** The length of one alarm period for a stage. */
export function alarmPeriod(stage: StageSettings): Duration {
  return Duration.minutes(stage.alarmPeriodMinutes);
}

export interface CountAlarmProps {
  readonly stage: StageSettings;
  /** The topic the alarm tells. */
  readonly alerts: ITopic;
  /** What the alarm watches, in a few words. It ends the alarm's name. */
  readonly watches: string;
  /** A count of something that should not happen, summed over one alarm period. */
  readonly metric: IMetric;
  /** The count in one period that sets the alarm off. */
  readonly threshold: number;
  /** What the owner reads in the message, which says where to look. */
  readonly description: string;
}

/**
 * An alarm on a count of something that should not happen. It goes off when
 * one period reaches the threshold, and it tells the alerts topic. A period
 * with no data is a quiet period and not an alarm.
 */
export function countAlarm(scope: Construct, id: string, props: CountAlarmProps): Alarm {
  const alarm = new Alarm(scope, id, {
    alarmName: `final-approach-${props.stage.name}-${props.watches}`,
    alarmDescription: props.description,
    metric: props.metric,
    threshold: props.threshold,
    evaluationPeriods: 1,
    comparisonOperator: ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    treatMissingData: TreatMissingData.NOT_BREACHING,
  });
  alarm.addAlarmAction(new SnsAction(props.alerts));
  return alarm;
}
