import { rulesFromSettings } from './rules.ts';
import { makeVerifyAuthChallenge } from './triggers.ts';

export const handler = makeVerifyAuthChallenge(rulesFromSettings());
