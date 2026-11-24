import { callerOf, noContent, notFound, notSignedIn, type ApiEvent, type ApiResult } from '../shared/http.ts';
import type { AccountStore } from './store.ts';

export interface AccountHandlerSettings {
  readonly store: AccountStore;
  readonly now: () => Date;
}

/** Deletes the signed in user's account and everything stored for it. */
export function makeAccountHandler(settings: AccountHandlerSettings) {
  return async function handler(event: ApiEvent): Promise<ApiResult> {
    const caller = callerOf(event);
    if (!caller) return notSignedIn();
    if (event.routeKey !== 'DELETE /account') return notFound();
    await settings.store.deleteEverything(caller, settings.now());
    return noContent();
  };
}
