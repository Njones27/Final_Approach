import { App } from 'aws-cdk-lib';
import { buildBackend } from '../lib/backend.ts';
import { isStageName, stages } from '../lib/stages.ts';

const app = new App();

// The stage is named on the command line, as in `cdk synth -c stage=beta`.
// There is no default, so a deploy can never land in a stage by accident.
const stageName: unknown = app.node.tryGetContext('stage');
if (!isStageName(stageName)) {
  throw new Error(`Name a stage with -c stage=<name>. The stages are ${Object.keys(stages).join(' and ')}.`);
}

// The account and region come from the credentials in use. Nothing here
// names an account, so the same code deploys to beta and to prod.
const account = process.env['CDK_DEFAULT_ACCOUNT'];
const region = process.env['CDK_DEFAULT_REGION'];
buildBackend(app, stages[stageName], account && region ? { account, region } : undefined);
