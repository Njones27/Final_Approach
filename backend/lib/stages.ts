/** The stages the backend can be deployed as. Each one is its own AWS account. */
export type StageName = 'beta' | 'prod';

/**
 * Everything that differs between stages, and every limit that may need
 * tuning. Limits live here as data so none is buried in a handler.
 */
export interface StageSettings {
  readonly name: StageName;
  /** The app's bundle id, which Apple writes into an identity token as its audience. */
  readonly appleAudience: string;
  /** The oldest Apple identity token that sign in accepts. */
  readonly maxAppleTokenAgeSeconds: number;
  /** True keeps the table, the bucket, and the user pool when a stack is deleted. */
  readonly keepDataOnStackDelete: boolean;
  /** How long a link to upload one image works. */
  readonly uploadLinkSeconds: number;
  /** How long a link to read one image works. */
  readonly imageLinkSeconds: number;
  /** The largest image the backend accepts. */
  readonly maxImageBytes: number;
  /** The largest photo record the backend accepts, as JSON. */
  readonly maxDocumentBytes: number;
  /** How many photos one page of the collection holds. */
  readonly photosPerPage: number;
  readonly accessTokenMinutes: number;
  readonly refreshTokenDays: number;
  /** Requests per second the API allows across all callers, and the burst above it. */
  readonly requestsPerSecond: number;
  readonly requestBurst: number;
  readonly logRetentionDays: number;
}

const shared = {
  appleAudience: 'com.finalapproach.app',
  maxAppleTokenAgeSeconds: 600,
  uploadLinkSeconds: 300,
  imageLinkSeconds: 900,
  maxImageBytes: 8 * 1024 * 1024,
  maxDocumentBytes: 32 * 1024,
  photosPerPage: 100,
  accessTokenMinutes: 60,
  refreshTokenDays: 365,
  requestsPerSecond: 50,
  requestBurst: 100,
  logRetentionDays: 30,
} as const;

export const stages: Record<StageName, StageSettings> = {
  beta: { ...shared, name: 'beta', keepDataOnStackDelete: false },
  prod: { ...shared, name: 'prod', keepDataOnStackDelete: true },
};

export function isStageName(value: unknown): value is StageName {
  return typeof value === 'string' && Object.hasOwn(stages, value);
}

/**
 * How long the marker of a deleted account is kept. It must outlive every
 * access token issued before the delete, so a token that is still valid
 * cannot write new data for an account that is gone.
 */
export function deletedAccountMarkerSeconds(stage: StageSettings): number {
  return stage.accessTokenMinutes * 60 * 2 + stage.uploadLinkSeconds;
}
