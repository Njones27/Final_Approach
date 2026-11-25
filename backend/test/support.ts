import type { ApiEvent } from '../src/shared/http.ts';

export interface EventParts {
  readonly routeKey: string;
  readonly claims?: Record<string, string> | null;
  readonly body?: string;
  readonly photoID?: string;
  readonly spotID?: string;
  readonly placeID?: string;
  readonly query?: Record<string, string>;
  readonly isBase64Encoded?: boolean;
}

export const signedInClaims = { sub: 'user-1', username: 'apple-user-1' };

/** A request as API Gateway hands it to a function, with only the parts the handlers read. */
export function apiEvent(parts: EventParts): ApiEvent {
  const claims = parts.claims === undefined ? signedInClaims : parts.claims;
  return {
    routeKey: parts.routeKey,
    body: parts.body,
    isBase64Encoded: parts.isBase64Encoded ?? false,
    pathParameters:
      parts.photoID !== undefined
        ? { photoID: parts.photoID }
        : parts.spotID !== undefined
          ? { spotID: parts.spotID }
          : parts.placeID !== undefined
            ? { placeID: parts.placeID }
            : undefined,
    queryStringParameters: parts.query,
    requestContext: { authorizer: claims ? { jwt: { claims, scopes: [] } } : undefined },
  } as unknown as ApiEvent;
}

interface Command {
  readonly constructor: { readonly name: string };
  readonly input: unknown;
}

export interface SentCommand {
  readonly name: string;
  readonly input: any;
}

/**
 * A stand in for an AWS client. It records each command and answers from
 * the replies queued for that command's name. A reply that is an Error is
 * thrown, and a command with no reply left gets an empty answer.
 */
export function fakeClient(replies: Record<string, unknown[]> = {}) {
  const sent: SentCommand[] = [];
  const queues = new Map(Object.entries(replies).map(([name, list]) => [name, [...list]]));
  return {
    sent,
    named: (name: string) => sent.filter((command) => command.name === name),
    send: (async (command: Command) => {
      const name = command.constructor.name;
      sent.push({ name, input: command.input });
      const reply = queues.get(name)?.shift();
      if (reply instanceof Error) throw reply;
      return reply ?? {};
    }) as any,
  };
}

/** An error named the way the AWS SDK names its own. */
export function awsError(name: string, extra: Record<string, unknown> = {}): Error {
  return Object.assign(new Error(name), { name, ...extra });
}
