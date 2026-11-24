import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';

/** Who issues every Sign in with Apple identity token. */
export const appleIssuer = 'https://appleid.apple.com';

const appleKeysURL = new URL('https://appleid.apple.com/auth/keys');

export interface AppleTokenRules {
  /** The app's bundle id. A token made for another app is refused. */
  readonly audience: string;
  /** The oldest token accepted, which limits how long a copied token is of use. */
  readonly maxTokenAgeSeconds: number;
  /** Where Apple's public keys come from. Tests pass their own. */
  readonly keys: JWTVerifyGetKey;
  readonly now?: Date;
}

let cachedAppleKeys: JWTVerifyGetKey | undefined;

/** Apple's public keys, fetched once and kept while the function stays warm. */
export function appleKeys(): JWTVerifyGetKey {
  cachedAppleKeys ??= createRemoteJWKSet(appleKeysURL);
  return cachedAppleKeys;
}

/**
 * Checks an identity token from Sign in with Apple and returns Apple's id
 * for the user. It throws when the token is not Apple's, is for another
 * app, has expired, or is older than the rules allow.
 */
export async function appleSubject(token: string, rules: AppleTokenRules): Promise<string> {
  const { payload } = await jwtVerify(token, rules.keys, {
    issuer: appleIssuer,
    audience: rules.audience,
    algorithms: ['RS256'],
    maxTokenAge: rules.maxTokenAgeSeconds,
    ...(rules.now ? { currentDate: rules.now } : {}),
  });
  if (typeof payload.sub !== 'string' || payload.sub === '') {
    throw new Error('The identity token names no user.');
  }
  return payload.sub;
}
