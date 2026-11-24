import type { Environment } from 'aws-cdk-lib';
import type { Construct } from 'constructs';
import { ApiStack } from './api-stack.ts';
import { IdentityStack } from './identity-stack.ts';
import type { StageSettings } from './stages.ts';
import { StorageStack } from './storage-stack.ts';

export interface Backend {
  readonly storage: StorageStack;
  readonly identity: IdentityStack;
  readonly api: ApiStack;
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

  const storage = new StorageStack(scope, name('Storage'), { ...shared, stage });
  const identity = new IdentityStack(scope, name('Identity'), { ...shared, stage });
  const api = new ApiStack(scope, name('Api'), {
    ...shared,
    stage,
    table: storage.table,
    images: storage.images,
    users: identity.users,
    appClient: identity.appClient,
  });
  return { storage, identity, api };
}
