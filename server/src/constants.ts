export type GetRecordValues<T extends Record<string, unknown>> = T[keyof T];

export type StatusCode = GetRecordValues<typeof STATUS_CODES>;

export const STATUS_CODES = {
  OK: 200,
  CREATED: 201,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  INTERNAL_SERVER_ERROR: 500,
} as const;

export const MIME_TYPES = { JSON: 'application/json' } as const;

export const ONE_DAY_IN_SECONDS = 60 * 60 * 24;

export const AUTH_OPENAPI_TAG = 'Authentication';

export const DEFAULT_REQUEST_ID_HEADER_NAME = 'Request-Id';

/**
 * The response headers a native client reads to persist its credentials.
 *
 * This is the wire contract shared with the `KamaalAuthClient` Swift package. Changing a name here is a breaking
 * change on both sides.
 */
export const AUTH_HEADER_NAMES = {
  authToken: 'set-auth-token',
  authTokenExpiry: 'set-auth-token-expiry',
  sessionToken: 'set-session-token',
  sessionUpdateAge: 'set-session-update-age',
} as const;

export const AUTH_ROUTE_PATHS = {
  signUp: '/sign-up/email',
  signIn: '/sign-in/email',
  signOut: '/sign-out',
  session: '/session',
  token: '/token',
  jwks: '/jwks',
} as const;
