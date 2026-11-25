import { Duration, RemovalPolicy, Stack, type StackProps } from 'aws-cdk-lib';
import { AttributeType, BillingMode, ProjectionType, Table } from 'aws-cdk-lib/aws-dynamodb';
import type { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import {
  BlockPublicAccess,
  Bucket,
  BucketEncryption,
  EventType,
  ObjectOwnership,
} from 'aws-cdk-lib/aws-s3';
import { LambdaDestination } from 'aws-cdk-lib/aws-s3-notifications';
import type { ITopic } from 'aws-cdk-lib/aws-sns';
import type { Construct } from 'constructs';
import { expiryAttribute } from '../src/account/awsStore.ts';
import { areaIndex, spotIndex, votingIndex } from '../src/shared/keys.ts';
import { allow, backendFunction, userImages } from './functions.ts';
import type { StageSettings } from './stages.ts';

export interface StorageStackProps extends StackProps {
  readonly stage: StageSettings;
  readonly alerts: ITopic;
}

/** The table of records and the bucket of images. */
export class StorageStack extends Stack {
  readonly table: Table;
  readonly images: Bucket;
  readonly sweeper: NodejsFunction;

  constructor(scope: Construct, id: string, props: StorageStackProps) {
    super(scope, id, props);
    const { stage } = props;
    const keep = stage.keepDataOnStackDelete;
    const removalPolicy = keep ? RemovalPolicy.RETAIN : RemovalPolicy.DESTROY;

    this.table = new Table(this, 'Records', {
      partitionKey: { name: 'pk', type: AttributeType.STRING },
      sortKey: { name: 'sk', type: AttributeType.STRING },
      billingMode: BillingMode.PAY_PER_REQUEST,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      timeToLiveAttribute: expiryAttribute,
      deletionProtection: keep,
      removalPolicy,
    });

    // The posts still open for votes, across all users. Only an open post
    // carries the index's key, so the index holds nothing else. A post
    // lives in its owner's partition, and the index follows it there, so a
    // deleted post or account leaves nothing behind in the index.
    this.table.addGlobalSecondaryIndex({
      indexName: votingIndex.name,
      partitionKey: { name: votingIndex.partitionKey, type: AttributeType.STRING },
      sortKey: { name: votingIndex.sortKey, type: AttributeType.STRING },
      projectionType: ProjectionType.ALL,
    });

    // The graded photos shown at each spot, best first. A post is in it
    // only while its owner shows it at a spot and its grade is final.
    this.table.addGlobalSecondaryIndex({
      indexName: spotIndex.name,
      partitionKey: { name: spotIndex.partitionKey, type: AttributeType.STRING },
      sortKey: { name: spotIndex.sortKey, type: AttributeType.NUMBER },
      projectionType: ProjectionType.ALL,
    });

    // The graded photos shown in each large tile of the map, best first,
    // which is how the map finds what is shown around a point. A post is
    // in it under the same two conditions as the index above.
    this.table.addGlobalSecondaryIndex({
      indexName: areaIndex.name,
      partitionKey: { name: areaIndex.partitionKey, type: AttributeType.STRING },
      sortKey: { name: areaIndex.sortKey, type: AttributeType.NUMBER },
      projectionType: ProjectionType.ALL,
    });

    // The bucket keeps no old versions. Deleting a photo or an account must
    // remove the stored image, and a versioned bucket would keep a copy.
    this.images = new Bucket(this, 'Images', {
      blockPublicAccess: BlockPublicAccess.BLOCK_ALL,
      objectOwnership: ObjectOwnership.BUCKET_OWNER_ENFORCED,
      encryption: BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      versioned: false,
      lifecycleRules: [{ abortIncompleteMultipartUploadAfter: Duration.days(1) }],
      removalPolicy,
      autoDeleteObjects: !keep,
    });

    // The sweeper lives here, beside the bucket that calls it.
    this.sweeper = backendFunction(this, 'Sweeper', {
      source: 'photos/sweeperIndex.ts',
      stage,
      alerts: props.alerts,
      environment: {
        TABLE_NAME: this.table.tableName,
        BUCKET_NAME: this.images.bucketName,
      },
    });
    allow(this.sweeper, ['dynamodb:BatchGetItem', 'dynamodb:GetItem'], this.table.tableArn);
    allow(this.sweeper, ['s3:DeleteObject'], this.images.arnForObjects(userImages));
    this.images.addEventNotification(EventType.OBJECT_CREATED, new LambdaDestination(this.sweeper), {
      prefix: 'users/',
    });
  }
}
