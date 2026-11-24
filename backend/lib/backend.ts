import type { Environment } from 'aws-cdk-lib';
import type { Construct } from 'constructs';
import { AlertsStack } from './alerts-stack.ts';
import { ApiStack } from './api-stack.ts';
import { DeployStack } from './deploy-stack.ts';
import { IdentityStack } from './identity-stack.ts';
import type { StageSettings } from './stages.ts';
import { StorageStack } from './storage-stack.ts';

export interface Backend {
  readonly alerts: AlertsStack;
  readonly storage: StorageStack;
  readonly identity: IdentityStack;
  readonly api: ApiStack;
  /** Only in a stage that GitHub Actions may deploy. */
  readonly deploy?: DeployStack;
}

/**
 * The whole backend for one stage. Data that must outlive a code change
 * sits in its own stacks, apart from the API that changes often.
 */
export function buildBackend(scope: Construct, stage: StageSettings, env?: Environment): Backend {
  const name = (part: string) => `FinalApproach-${stage.name}-${part}`;
  const shared = {
    ...(env ? { env } : {}),
    tags: { app: 'final-approach', stage: stage.name },
    terminationProtection: stage.keepDataOnStackDelete,
  };

  // The alerts topic comes first, because every other stack tells it.
  const alerts = new AlertsStack(scope, name('Alerts'), { ...shared, stage });
  const storage = new StorageStack(scope, name('Storage'), { ...shared, stage, alerts: alerts.topic });
  const identity = new IdentityStack(scope, name('Identity'), { ...shared, stage, alerts: alerts.topic });
  const api = new ApiStack(scope, name('Api'), {
    ...shared,
    stage,
    table: storage.table,
    images: storage.images,
    users: identity.users,
    appClient: identity.appClient,
    alerts: alerts.topic,
  });
  const deploy = stage.deployFrom
    ? new DeployStack(scope, name('Deploy'), { ...shared, stage, source: stage.deployFrom })
    : undefined;
  return { alerts, storage, identity, api, ...(deploy ? { deploy } : {}) };
}
