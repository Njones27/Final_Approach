import type {
  CreateAuthChallengeTriggerEvent,
  DefineAuthChallengeTriggerEvent,
  PreSignUpTriggerEvent,
  VerifyAuthChallengeResponseTriggerEvent,
} from 'aws-lambda';
import { appleSubject, type AppleTokenRules } from './appleToken.ts';

/**
 * Sign in with Apple, for a user pool that has no passwords.
 *
 * The app shows Apple's own sign in sheet and gets an identity token. The
 * user's name in the pool is Apple's id for them. To sign in, the app
 * answers one challenge with the token, and the pool issues its own tokens
 * when the token is Apple's and names the same user.
 */

/** The name of the one challenge, which the app answers with the identity token. */
export const appleChallenge = 'APPLE_IDENTITY_TOKEN';

/** The key the app passes the identity token under when it signs a user up. */
export const signUpTokenKey = 'identityToken';

/**
 * Lets a new user in only with a valid Apple token for the same name, so
 * nobody can fill the pool with made up users.
 */
export function makePreSignUp(rules: AppleTokenRules) {
  return async function handler(event: PreSignUpTriggerEvent): Promise<PreSignUpTriggerEvent> {
    // A user an administrator creates by hand needs no Apple token.
    if (event.triggerSource !== 'PreSignUp_SignUp') return event;

    const token = event.request.validationData?.[signUpTokenKey];
    if (!token) throw new Error('Signing up needs an Apple identity token.');
    let subject: string;
    try {
      subject = await appleSubject(token, rules);
    } catch {
      throw new Error('The Apple identity token was not accepted.');
    }
    if (subject !== event.userName) throw new Error('The Apple identity token is for another user.');

    event.response.autoConfirmUser = true;
    return event;
  };
}

/** Decides the next step. There is one challenge and one try at it. */
export async function defineAuthChallenge(
  event: DefineAuthChallengeTriggerEvent,
): Promise<DefineAuthChallengeTriggerEvent> {
  const { session } = event.request;
  const last = session.at(-1);
  if (event.request.userNotFound) {
    event.response.issueTokens = false;
    event.response.failAuthentication = true;
  } else if (session.length === 0) {
    event.response.issueTokens = false;
    event.response.failAuthentication = false;
    event.response.challengeName = 'CUSTOM_CHALLENGE';
  } else if (
    session.length === 1 &&
    last?.challengeName === 'CUSTOM_CHALLENGE' &&
    last.challengeResult === true
  ) {
    event.response.issueTokens = true;
    event.response.failAuthentication = false;
  } else {
    event.response.issueTokens = false;
    event.response.failAuthentication = true;
  }
  return event;
}

/** Tells the app which challenge to answer. The answer itself is the proof. */
export async function createAuthChallenge(
  event: CreateAuthChallengeTriggerEvent,
): Promise<CreateAuthChallengeTriggerEvent> {
  event.response.publicChallengeParameters = { challenge: appleChallenge };
  event.response.privateChallengeParameters = { challenge: appleChallenge };
  event.response.challengeMetadata = appleChallenge;
  return event;
}

/** Accepts the answer when it is a valid Apple token for the user signing in. */
export function makeVerifyAuthChallenge(rules: AppleTokenRules) {
  return async function handler(
    event: VerifyAuthChallengeResponseTriggerEvent,
  ): Promise<VerifyAuthChallengeResponseTriggerEvent> {
    let correct = false;
    try {
      const subject = await appleSubject(event.request.challengeAnswer, rules);
      correct = subject === event.userName;
    } catch {
      correct = false;
    }
    event.response.answerCorrect = correct;
    return event;
  };
}
