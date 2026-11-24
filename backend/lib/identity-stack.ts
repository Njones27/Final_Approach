import { Duration, RemovalPolicy, Stack, type StackProps } from 'aws-cdk-lib';
import { AccountRecovery, UserPool, type UserPoolClient } from 'aws-cdk-lib/aws-cognito';
import type { Construct } from 'constructs';
import { backendFunction } from './functions.ts';
import type { StageSettings } from './stages.ts';

export interface IdentityStackProps extends StackProps {
  readonly stage: StageSettings;
}

/**
 * The user pool. It has no passwords in use. A user signs in with Apple,
 * and four small functions check Apple's token on the pool's behalf. See
 * `src/auth/triggers.ts`.
 */
export class IdentityStack extends Stack {
  readonly users: UserPool;
  readonly appClient: UserPoolClient;

  constructor(scope: Construct, id: string, props: IdentityStackProps) {
    super(scope, id, props);
    const { stage } = props;
    const keep = stage.keepDataOnStackDelete;

    const appleRules = {
      APPLE_AUDIENCE: stage.appleAudience,
      MAX_APPLE_TOKEN_AGE_SECONDS: String(stage.maxAppleTokenAgeSeconds),
    };
    const trigger = (name: string, environment?: Record<string, string>) =>
      backendFunction(this, name, {
        source: `auth/${name[0]?.toLowerCase()}${name.slice(1)}.ts`,
        stage,
        ...(environment ? { environment } : {}),
      });

    this.users = new UserPool(this, 'Users', {
      selfSignUpEnabled: true,
      signInCaseSensitive: true,
      accountRecovery: AccountRecovery.NONE,
      deletionProtection: keep,
      removalPolicy: keep ? RemovalPolicy.RETAIN : RemovalPolicy.DESTROY,
      lambdaTriggers: {
        preSignUp: trigger('PreSignUp', appleRules),
        defineAuthChallenge: trigger('DefineAuthChallenge'),
        createAuthChallenge: trigger('CreateAuthChallenge'),
        verifyAuthChallengeResponse: trigger('VerifyAuthChallenge', appleRules),
      },
    });

    this.appClient = this.users.addClient('App', {
      // The custom flow is the only way in, so the password a sign up must
      // carry can never be used.
      authFlows: { custom: true },
      disableOAuth: true,
      generateSecret: false,
      preventUserExistenceErrors: true,
      enableTokenRevocation: true,
      accessTokenValidity: Duration.minutes(stage.accessTokenMinutes),
      idTokenValidity: Duration.minutes(stage.accessTokenMinutes),
      refreshTokenValidity: Duration.days(stage.refreshTokenDays),
    });
  }
}
