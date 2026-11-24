import { numberSetting, setting } from '../shared/settings.ts';
import { appleKeys, type AppleTokenRules } from './appleToken.ts';

/** The token rules the stack passed to this function. */
export function rulesFromSettings(): AppleTokenRules {
  return {
    audience: setting('APPLE_AUDIENCE'),
    maxTokenAgeSeconds: numberSetting('MAX_APPLE_TOKEN_AGE_SECONDS'),
    keys: appleKeys(),
  };
}
