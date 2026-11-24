import { CfnOutput, DefaultStackSynthesizer, Duration, Stack, type StackProps } from 'aws-cdk-lib';
import { CfnOIDCProvider, FederatedPrincipal, PolicyStatement, Role } from 'aws-cdk-lib/aws-iam';
import type { Construct } from 'constructs';
import type { DeploySource, StageSettings } from './stages.ts';

/** Where GitHub Actions gets the token that says which repository and branch a job runs for. */
export const githubTokenHost = 'token.actions.githubusercontent.com';

/** Who a GitHub token must be made for before this account takes it. */
export const githubTokenAudience = 'sts.amazonaws.com';

/** The roles a CDK bootstrap makes that a deploy of this app uses. */
export const bootstrapRolesForDeploy = ['deploy-role', 'file-publishing-role', 'lookup-role'] as const;

export interface DeployStackProps extends StackProps {
  readonly stage: StageSettings;
  readonly source: DeploySource;
}

/**
 * Lets GitHub Actions deploy this stage with no AWS keys stored in GitHub.
 *
 * A job proves which repository and branch it runs for with a short lived
 * token from GitHub. The role here takes that token only from the one
 * branch named in the stage settings, and can do one thing, which is to
 * take on the roles the CDK bootstrap made for deploying.
 *
 * This stack is deployed by hand by the account's owner. The deploy
 * workflow leaves it alone, so a change to who may deploy never deploys
 * itself.
 */
export class DeployStack extends Stack {
  readonly role: Role;

  constructor(scope: Construct, id: string, props: DeployStackProps) {
    super(scope, id, props);
    const { stage, source } = props;

    const github = new CfnOIDCProvider(this, 'GitHub', {
      url: `https://${githubTokenHost}`,
      clientIdList: [githubTokenAudience],
    });

    this.role = new Role(this, 'GitHubDeploy', {
      roleName: `FinalApproach-${stage.name}-GitHubDeploy`,
      description: `Lets GitHub Actions deploy the ${stage.name} stage from ${source.repository}, branch ${source.branch}.`,
      maxSessionDuration: Duration.hours(1),
      assumedBy: new FederatedPrincipal(
        github.attrArn,
        {
          // Both must match exactly. A pull request, a fork, and any other
          // branch each get a different subject, so none of them gets in.
          StringEquals: {
            [`${githubTokenHost}:aud`]: githubTokenAudience,
            [`${githubTokenHost}:sub`]: `repo:${source.repository}:ref:refs/heads/${source.branch}`,
          },
        },
        'sts:AssumeRoleWithWebIdentity',
      ),
    });

    const qualifier = DefaultStackSynthesizer.DEFAULT_QUALIFIER;
    this.role.addToPolicy(
      new PolicyStatement({
        actions: ['sts:AssumeRole'],
        resources: bootstrapRolesForDeploy.map(
          (name) =>
            `arn:${this.partition}:iam::${this.account}:role/cdk-${qualifier}-${name}-${this.account}-${this.region}`,
        ),
      }),
    );

    new CfnOutput(this, 'DeployRoleArn', { value: this.role.roleArn });
  }
}
