import { rulesFromSettings } from './rules.ts';
import { makePreSignUp } from './triggers.ts';

export const handler = makePreSignUp(rulesFromSettings());
