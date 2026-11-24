import { fileURLToPath } from 'node:url';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { Architecture, Runtime, type IFunction } from 'aws-cdk-lib/aws-lambda';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import { LogGroup, type RetentionDays } from 'aws-cdk-lib/aws-logs';
import type { ITopic } from 'aws-cdk-lib/aws-sns';
import type { Construct } from 'constructs';
import { alarmPeriod, countAlarm } from './alarms.ts';
import type { StageSettings } from './stages.ts';

export interface BackendFunctionProps {
  /** The handler file, as a path under `src`. */
  readonly source: string;
  readonly stage: StageSettings;
  readonly environment?: Record<string, string>;
  readonly timeout?: Duration;
  /** The topic that is told when the function fails. */
  readonly alerts: ITopic;
  /**
   * Failed runs in one alarm period that set the alarm off, for a function
   * that fails on purpose. Left out, the stage's own number is used.
   */
  readonly errorsToAlarm?: number;
}

/**
 * One Lambda function with the defaults every function here shares. Its
 * code and its SDK are bundled together, so what runs is what was tested.
 * Every function gets an alarm on its failed runs, so one added later is
 * watched with nothing more to write.
 */
export function backendFunction(scope: Construct, id: string, props: BackendFunctionProps): NodejsFunction {
  const logGroup = new LogGroup(scope, `${id}Logs`, {
    retention: props.stage.logRetentionDays as RetentionDays,
    removalPolicy: RemovalPolicy.DESTROY,
  });
  const fn = new NodejsFunction(scope, id, {
    entry: fileURLToPath(new URL(`../src/${props.source}`, import.meta.url)),
    handler: 'handler',
    runtime: Runtime.NODEJS_22_X,
    architecture: Architecture.ARM_64,
    memorySize: 256,
    timeout: props.timeout ?? Duration.seconds(10),
    logGroup,
    ...(props.environment ? { environment: props.environment } : {}),
    bundling: { externalModules: [], minify: true, sourceMap: false },
  });
  countAlarm(scope, `${id}Errors`, {
    stage: props.stage,
    alerts: props.alerts,
    watches: `${id}-errors`,
    metric: fn.metricErrors({ period: alarmPeriod(props.stage), statistic: 'Sum' }),
    threshold: props.errorsToAlarm ?? props.stage.functionErrorsToAlarm,
    description: `The ${id} function of the ${props.stage.name} backend failed. Its log group says why.`,
  });
  return fn;
}

/** Every image key the backend writes, as a pattern for a policy. */
export const userImages = 'users/*';

/**
 * Lets a function take the named actions on one resource and nothing more.
 * Each function gets only what its code calls.
 */
export function allow(
  fn: IFunction,
  actions: string[],
  resource: string,
  conditions?: Record<string, Record<string, unknown>>,
): void {
  fn.addToRolePolicy(
    new PolicyStatement({ actions, resources: [resource], ...(conditions ? { conditions } : {}) }),
  );
}
