import type { Caller } from '../shared/http.ts';

/** Removes everything the backend holds for one user. */
export interface AccountStore {
  /**
   * Deletes the user's images, records, and sign in. It is safe to call
   * again after a failure, and it picks up where it stopped.
   */
  deleteEverything(caller: Caller, now: Date): Promise<void>;
}
