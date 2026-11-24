/** The stages the backend can be deployed as. Each one is its own AWS account. */
export type StageName = 'beta' | 'prod';

/**
 * The one place a deploy by GitHub Actions may come from.
 *
 * GitHub names the owner and the repository in its token by name and by
 * id. The ids never change and are never given to anyone else, so a
 * renamed or deleted repository whose name is taken by someone else still
 * cannot deploy. All four are public. `GET /repos/<owner>/<repository>` on
 * GitHub's API returns them.
 *
 * The last part says which jobs of that repository may deploy. It is a
 * branch or a GitHub environment, and never both, because GitHub writes
 * only one of them into the token.
 */
export type DeploySource = DeployRepository & (DeployFromBranch | DeployFromEnvironment);

export interface DeployRepository {
  /** The owner's name as GitHub writes it, with its capital letters. */
  readonly owner: string;
  readonly ownerID: number;
  /** The repository's name as GitHub writes it, with its capital letters. */
  readonly repository: string;
  readonly repositoryID: number;
}

/** A job that runs for a push to this branch, and names no environment. */
export interface DeployFromBranch {
  readonly branch: string;
}

/**
 * A job that names this GitHub environment.
 *
 * The token of such a job does not say which branch it runs for. The
 * environment's own settings on GitHub must therefore allow only the
 * branch that may deploy, and name who approves a deploy. The steps are in
 * `docs/backend.md`.
 */
export interface DeployFromEnvironment {
  readonly environment: string;
}

/** The subject GitHub writes into the token of a job the source allows. The role matches it exactly. */
export function deploySubject(source: DeploySource): string {
  const repository = `repo:${source.owner}@${source.ownerID}/${source.repository}@${source.repositoryID}`;
  return 'environment' in source
    ? `${repository}:environment:${source.environment}`
    : `${repository}:ref:refs/heads/${source.branch}`;
}

/** Where a source allows a deploy from, in words. */
export function deploySourceInWords(source: DeploySource): string {
  const repository = `${source.owner}/${source.repository}`;
  return 'environment' in source
    ? `${repository}, environment ${source.environment}`
    : `${repository}, branch ${source.branch}`;
}

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
  /**
   * How long a posted photo stays open for votes. Changing it moves the
   * end of the window for photos posted from then on.
   */
  readonly votingWindowHours: number;
  /** A vote is a whole number of stars from 1 to this. */
  readonly voteScaleMax: number;
  /**
   * The votes a post needs before its grade is final. A post that reaches
   * the end of its window with fewer stays open until it has them.
   */
  readonly minVotesToFinalize: number;
  /** How many photos one answer of the voting queue holds. */
  readonly votingQueueSize: number;
  /** How many open posts one request reads to fill the queue. */
  readonly votingQueueReadLimit: number;
  /** How often finished posts are closed and taken out of the queue. */
  readonly closerMinutes: number;
  readonly accessTokenMinutes: number;
  readonly refreshTokenDays: number;
  /** Requests per second the API allows across all callers, and the burst above it. */
  readonly requestsPerSecond: number;
  readonly requestBurst: number;
  readonly logRetentionDays: number;
  /** The length of one alarm period. An alarm goes off on the count in one period. */
  readonly alarmPeriodMinutes: number;
  /** Failed runs of one function in a period that set its alarm off. */
  readonly functionErrorsToAlarm: number;
  /**
   * Refused sign ups in a period that set the alarm off. A refused sign up
   * counts as a failed run, and anyone can send one, so one is not news.
   */
  readonly signUpRefusalsToAlarm: number;
  /** Answers of 500 and above from the API in a period that set its alarm off. */
  readonly serverErrorsToAlarm: number;
  /** What the stage's account may cost in a month, in US dollars, before the owner is told. */
  readonly monthlyBudgetUSD: number;
  /**
   * The shares of the budget, in percent of money already spent, at which
   * the owner is told. The owner is also told when the month is on course
   * to go over.
   */
  readonly budgetAlertPercents: readonly number[];
  /**
   * Where GitHub Actions may deploy this stage from. A stage without it has
   * no role for GitHub to use, so it can only be deployed by hand.
   */
  readonly deployFrom?: DeploySource;
}

const shared = {
  appleAudience: 'com.finalapproach.app',
  maxAppleTokenAgeSeconds: 600,
  uploadLinkSeconds: 300,
  imageLinkSeconds: 900,
  maxImageBytes: 8 * 1024 * 1024,
  maxDocumentBytes: 32 * 1024,
  photosPerPage: 100,
  votingWindowHours: 72,
  voteScaleMax: 5,
  minVotesToFinalize: 5,
  votingQueueSize: 10,
  votingQueueReadLimit: 50,
  closerMinutes: 15,
  accessTokenMinutes: 60,
  refreshTokenDays: 365,
  requestsPerSecond: 50,
  requestBurst: 100,
  logRetentionDays: 30,
  alarmPeriodMinutes: 5,
  functionErrorsToAlarm: 1,
  signUpRefusalsToAlarm: 20,
  serverErrorsToAlarm: 1,
  budgetAlertPercents: [50, 100],
} as const;

/** This repository on GitHub. */
const repository: DeployRepository = {
  owner: 'Njones27',
  ownerID: 153565100,
  repository: 'Final_Approach',
  repositoryID: 1468200614,
};

export const stages: Record<StageName, StageSettings> = {
  beta: {
    ...shared,
    name: 'beta',
    keepDataOnStackDelete: false,
    monthlyBudgetUSD: 10,
    // Every change that reaches main goes to beta with nobody asked.
    deployFrom: { ...repository, branch: 'main' },
  },
  prod: {
    ...shared,
    name: 'prod',
    keepDataOnStackDelete: true,
    monthlyBudgetUSD: 20,
    // A deploy to prod waits for the approval that the `prod` environment
    // on GitHub asks for, so prod trusts that environment and not a branch.
    deployFrom: { ...repository, environment: 'prod' },
  },
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
