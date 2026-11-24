import { ArnFormat, CfnOutput, Stack, type StackProps } from 'aws-cdk-lib';
import { CfnBudget } from 'aws-cdk-lib/aws-budgets';
import { PolicyStatement, ServicePrincipal } from 'aws-cdk-lib/aws-iam';
import { Topic } from 'aws-cdk-lib/aws-sns';
import type { Construct } from 'constructs';
import type { StageSettings } from './stages.ts';

export interface AlertsStackProps extends StackProps {
  readonly stage: StageSettings;
}

/**
 * Where the stage tells its owner that something is wrong. It holds one
 * topic and the month's budget. Every alarm in the other stacks tells the
 * topic, and so does the budget.
 *
 * The topic has no subscriber here. The owner's email address is private
 * and this repository is public, so the owner subscribes by hand, once for
 * each account. The steps are in `docs/backend.md`.
 */
export class AlertsStack extends Stack {
  readonly topic: Topic;

  constructor(scope: Construct, id: string, props: AlertsStackProps) {
    super(scope, id, props);
    const { stage } = props;

    this.topic = new Topic(this, 'Alerts', {
      displayName: `Final Approach ${stage.name}`,
      enforceSSL: true,
    });

    // A topic with a policy of its own no longer takes a message from the
    // account's services by default. So the two that may write to it are
    // named, and each only for this account.
    const fromThisAccount = { StringEquals: { 'aws:SourceAccount': this.account } };
    this.topic.addToResourcePolicy(
      new PolicyStatement({
        sid: 'AlarmsOfThisAccount',
        actions: ['sns:Publish'],
        principals: [new ServicePrincipal('cloudwatch.amazonaws.com')],
        resources: [this.topic.topicArn],
        conditions: {
          ...fromThisAccount,
          ArnLike: {
            'aws:SourceArn': this.formatArn({
              service: 'cloudwatch',
              resource: 'alarm',
              resourceName: '*',
              arnFormat: ArnFormat.COLON_RESOURCE_NAME,
            }),
          },
        },
      }),
    );
    this.topic.addToResourcePolicy(
      new PolicyStatement({
        sid: 'BudgetsOfThisAccount',
        actions: ['sns:Publish'],
        principals: [new ServicePrincipal('budgets.amazonaws.com')],
        resources: [this.topic.topicArn],
        conditions: {
          ...fromThisAccount,
          // A budget belongs to no region, so its name has none.
          ArnLike: {
            'aws:SourceArn': this.formatArn({
              service: 'budgets',
              region: '',
              resource: '*',
              arnFormat: ArnFormat.NO_RESOURCE_NAME,
            }),
          },
        },
      }),
    );

    const tellTheTopic = [{ subscriptionType: 'SNS', address: this.topic.topicArn }];
    const budget = new CfnBudget(this, 'MonthlyCost', {
      budget: {
        budgetName: `final-approach-${stage.name}-monthly-cost`,
        budgetType: 'COST',
        timeUnit: 'MONTHLY',
        budgetLimit: { amount: stage.monthlyBudgetUSD, unit: 'USD' },
      },
      notificationsWithSubscribers: [
        // Money already spent this month.
        ...stage.budgetAlertPercents.map((percent) => ({
          notification: {
            notificationType: 'ACTUAL',
            comparisonOperator: 'GREATER_THAN',
            threshold: percent,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: tellTheTopic,
        })),
        // What the month is on course to cost.
        {
          notification: {
            notificationType: 'FORECASTED',
            comparisonOperator: 'GREATER_THAN',
            threshold: 100,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: tellTheTopic,
        },
      ],
    });
    // The budget is refused while the topic does not yet let it write.
    const policy = this.topic.node.tryFindChild('Policy');
    if (policy) budget.node.addDependency(policy);

    new CfnOutput(this, 'AlertsTopicArn', { value: this.topic.topicArn });
  }
}
