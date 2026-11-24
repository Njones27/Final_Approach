import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';
import type {
  CreateAuthChallengeTriggerEvent,
  DefineAuthChallengeTriggerEvent,
  PreSignUpTriggerEvent,
  VerifyAuthChallengeResponseTriggerEvent,
} from 'aws-lambda';
import { SignJWT, createLocalJWKSet, exportJWK, generateKeyPair, type JWTVerifyGetKey } from 'jose';
import { appleIssuer, appleSubject, type AppleTokenRules } from '../src/auth/appleToken.ts';
import {
  createAuthChallenge,
  defineAuthChallenge,
  makePreSignUp,
  makeVerifyAuthChallenge,
} from '../src/auth/triggers.ts';

const audience = 'com.finalapproach.app';
const now = new Date('2026-11-24T12:00:00Z');
const seconds = (date: Date) => Math.floor(date.getTime() / 1000);

type Signer = Awaited<ReturnType<typeof generateKeyPair>>['privateKey'];
let appleKey: Signer;
let otherKey: Signer;
let keys: JWTVerifyGetKey;
let rules: AppleTokenRules;

before(async () => {
  const apple = await generateKeyPair('RS256');
  const other = await generateKeyPair('RS256');
  appleKey = apple.privateKey;
  otherKey = other.privateKey;
  keys = createLocalJWKSet({ keys: [{ ...(await exportJWK(apple.publicKey)), kid: 'apple-1', alg: 'RS256' }] });
  rules = { audience, maxTokenAgeSeconds: 600, keys, now };
});

interface TokenParts {
  readonly subject?: string | null;
  readonly issuer?: string;
  readonly audience?: string;
  readonly issuedSecondsAgo?: number;
  readonly livesSeconds?: number;
  readonly key?: Signer;
}

/** A token shaped like the one Sign in with Apple gives the app. */
function token(parts: TokenParts = {}): Promise<string> {
  const issuedAt = seconds(now) - (parts.issuedSecondsAgo ?? 5);
  let jwt = new SignJWT({})
    .setProtectedHeader({ alg: 'RS256', kid: 'apple-1' })
    .setIssuer(parts.issuer ?? appleIssuer)
    .setAudience(parts.audience ?? audience)
    .setIssuedAt(issuedAt)
    .setExpirationTime(issuedAt + (parts.livesSeconds ?? 86400));
  if (parts.subject !== null) jwt = jwt.setSubject(parts.subject ?? '001234.abcdef.0123');
  return jwt.sign(parts.key ?? appleKey);
}

describe('checking an Apple identity token', () => {
  test('a fresh token for this app gives Apple’s id for the user', async () => {
    assert.equal(await appleSubject(await token(), rules), '001234.abcdef.0123');
  });

  test('a token signed by anyone but Apple is refused', async () => {
    await assert.rejects(appleSubject(await token({ key: otherKey }), rules));
  });

  test('a token from another issuer is refused', async () => {
    await assert.rejects(appleSubject(await token({ issuer: 'https://example.com' }), rules));
  });

  test('a token made for another app is refused', async () => {
    await assert.rejects(appleSubject(await token({ audience: 'com.example.other' }), rules));
  });

  test('an expired token is refused', async () => {
    await assert.rejects(appleSubject(await token({ issuedSecondsAgo: 120, livesSeconds: 60 }), rules));
  });

  test('a token older than the rules allow is refused, though Apple still honors it', async () => {
    await assert.rejects(appleSubject(await token({ issuedSecondsAgo: 601 }), rules));
    assert.equal(await appleSubject(await token({ issuedSecondsAgo: 590 }), rules), '001234.abcdef.0123');
  });

  test('a token that names no user is refused', async () => {
    await assert.rejects(appleSubject(await token({ subject: null }), rules), /names no user/);
  });

  test('text that is not a token is refused', async () => {
    await assert.rejects(appleSubject('not-a-token', rules));
    await assert.rejects(appleSubject('', rules));
  });

  test('a token with no signature is refused', async () => {
    const [header, payload] = (await token()).split('.');
    const unsigned = Buffer.from(JSON.stringify({ alg: 'none' })).toString('base64url');
    await assert.rejects(appleSubject(`${unsigned}.${payload}.`, rules));
    await assert.rejects(appleSubject(`${header}.${payload}.`, rules));
  });
});

describe('signing up', () => {
  const signUp = (userName: string, identityToken?: string, triggerSource = 'PreSignUp_SignUp') =>
    ({
      triggerSource,
      userName,
      request: { userAttributes: {}, ...(identityToken ? { validationData: { identityToken } } : {}) },
      response: { autoConfirmUser: false, autoVerifyEmail: false, autoVerifyPhone: false },
    }) as unknown as PreSignUpTriggerEvent;

  test('a valid token for the same user is let in and confirmed', async () => {
    const result = await makePreSignUp(rules)(signUp('001234.abcdef.0123', await token()));
    assert.equal(result.response.autoConfirmUser, true);
  });

  test('a sign up with no token is refused', async () => {
    await assert.rejects(makePreSignUp(rules)(signUp('001234.abcdef.0123')), /needs an Apple identity token/);
  });

  test('a sign up with a bad token is refused', async () => {
    const bad = await token({ key: otherKey });
    await assert.rejects(makePreSignUp(rules)(signUp('001234.abcdef.0123', bad)), /was not accepted/);
  });

  test('a valid token cannot sign up under another name', async () => {
    await assert.rejects(makePreSignUp(rules)(signUp('someone-else', await token())), /for another user/);
  });

  test('a user an administrator creates is left as it is', async () => {
    const result = await makePreSignUp(rules)(signUp('tester', undefined, 'PreSignUp_AdminCreateUser'));
    assert.equal(result.response.autoConfirmUser, false);
  });
});

describe('deciding the next step of a sign in', () => {
  const define = (session: { challengeName: string; challengeResult: boolean }[], userNotFound = false) =>
    ({ request: { userAttributes: {}, session, userNotFound }, response: {} }) as unknown as DefineAuthChallengeTriggerEvent;
  const step = async (...args: Parameters<typeof define>) => (await defineAuthChallenge(define(...args))).response;

  test('a new sign in gets the one challenge', async () => {
    assert.deepEqual(await step([]), {
      issueTokens: false,
      failAuthentication: false,
      challengeName: 'CUSTOM_CHALLENGE',
    });
  });

  test('a correct answer gets tokens', async () => {
    const response = await step([{ challengeName: 'CUSTOM_CHALLENGE', challengeResult: true }]);
    assert.deepEqual(response, { issueTokens: true, failAuthentication: false });
  });

  test('a wrong answer fails, with no second try', async () => {
    const response = await step([{ challengeName: 'CUSTOM_CHALLENGE', challengeResult: false }]);
    assert.deepEqual(response, { issueTokens: false, failAuthentication: true });
  });

  test('any other history fails', async () => {
    const right = { challengeName: 'CUSTOM_CHALLENGE', challengeResult: true };
    assert.equal((await step([right, right])).issueTokens, false);
    assert.equal((await step([{ challengeName: 'SRP_A', challengeResult: true }])).issueTokens, false);
    assert.equal((await step([{ challengeName: 'PASSWORD_VERIFIER', challengeResult: true }])).failAuthentication, true);
  });

  test('a user the pool does not know fails', async () => {
    assert.deepEqual(await step([], true), { issueTokens: false, failAuthentication: true });
  });
});

describe('the challenge', () => {
  test('names what the app must answer with', async () => {
    const event = { request: {}, response: {} } as unknown as CreateAuthChallengeTriggerEvent;
    const { response } = await createAuthChallenge(event);
    assert.deepEqual(response.publicChallengeParameters, { challenge: 'APPLE_IDENTITY_TOKEN' });
  });

  const answer = (userName: string, challengeAnswer: string) =>
    ({ userName, request: { challengeAnswer }, response: {} }) as unknown as VerifyAuthChallengeResponseTriggerEvent;
  const isCorrect = async (userName: string, challengeAnswer: string) =>
    (await makeVerifyAuthChallenge(rules)(answer(userName, challengeAnswer))).response.answerCorrect;

  test('is passed by a valid token for the user signing in', async () => {
    assert.equal(await isCorrect('001234.abcdef.0123', await token()), true);
  });

  test('is failed by a valid token for a different user', async () => {
    assert.equal(await isCorrect('someone-else', await token()), false);
  });

  test('is failed by a bad token, without an error', async () => {
    assert.equal(await isCorrect('001234.abcdef.0123', await token({ key: otherKey })), false);
    assert.equal(await isCorrect('001234.abcdef.0123', 'not-a-token'), false);
    assert.equal(await isCorrect('001234.abcdef.0123', await token({ issuedSecondsAgo: 601 })), false);
  });
});
