import type {
  APIGatewayProxyEventV2WithJWTAuthorizer,
  APIGatewayProxyStructuredResultV2,
} from 'aws-lambda';

export type ApiEvent = APIGatewayProxyEventV2WithJWTAuthorizer;
export type ApiResult = APIGatewayProxyStructuredResultV2;

/** The signed in user a request came from. */
export interface Caller {
  /** The user pool's id for the user. Every record and image is filed under it. */
  readonly userID: string;
  /** The name the user pool knows the user by, which deleting the user needs. */
  readonly username: string;
}

/**
 * The caller named by the token that API Gateway already verified. An access
 * token carries `username` and an id token carries `cognito:username`.
 */
export function callerOf(event: ApiEvent): Caller | undefined {
  const claims = event.requestContext.authorizer?.jwt?.claims;
  if (!claims) return undefined;
  const userID = claims['sub'];
  const username = claims['username'] ?? claims['cognito:username'];
  if (typeof userID !== 'string' || userID === '') return undefined;
  if (typeof username !== 'string' || username === '') return undefined;
  return { userID, username };
}

/** The request body as text, whether or not API Gateway encoded it. */
export function bodyText(event: ApiEvent): string | undefined {
  if (event.body === undefined) return undefined;
  return event.isBase64Encoded ? Buffer.from(event.body, 'base64').toString('utf8') : event.body;
}

export function json(statusCode: number, body: unknown): ApiResult {
  return {
    statusCode,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
    body: JSON.stringify(body),
  };
}

export function noContent(): ApiResult {
  return { statusCode: 204 };
}

/**
 * A reason the app acts on. Two refusals can share a status, such as a
 * deleted photo and a deleted account, so the app reads this and not the
 * message, which is free to change.
 */
export type ProblemCode =
  | 'notSignedIn'
  | 'photoDeleted'
  | 'accountDeleted'
  | 'photoNotSaved'
  | 'imageHasLocation'
  | 'alreadyVoted'
  | 'votingClosed'
  | 'ownPost'
  | 'notPosted'
  | 'unknownSpot';

/**
 * An error the app can show or act on. The message never echoes stored
 * data. The code is there only when the app does something about it.
 */
export function problem(statusCode: number, message: string, code?: ProblemCode): ApiResult {
  return json(statusCode, code === undefined ? { message } : { message, code });
}

export const notSignedIn = (): ApiResult => problem(401, 'Sign in to continue.', 'notSignedIn');
export const accountGone = (): ApiResult =>
  problem(410, 'This account was deleted.', 'accountDeleted');
export const photoGone = (): ApiResult => problem(410, 'This photo was deleted.', 'photoDeleted');
export const notFound = (): ApiResult => problem(404, 'There is nothing at this address.');
