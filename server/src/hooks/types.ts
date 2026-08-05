import type { AuthLogger } from '../logging/index.js';

/**
 * What a hook is handed on every call.
 *
 * `request` is a clone of the incoming raw request, so a hook is free to forward it straight to an auth library's
 * handler without the router losing its own copy of the body.
 */
export interface AuthHookContext {
  readonly request: Request;
  readonly headers: Headers;
  readonly requestId: string | undefined;
  readonly logger: AuthLogger;
  /** App-owned per-request state, supplied by `createAuthModule({ locals })`. Opaque to this package. */
  readonly locals: unknown;
}

export interface AuthUser {
  id: string;
  email: string;
  name: string;
  emailVerified: boolean;
  createdAt: Date;
}

export interface AuthSession {
  expiresAt: Date;
  createdAt: Date;
  updatedAt: Date;
}

/**
 * Everything a native client needs to persist after a successful sign-in or sign-up.
 *
 * Serialized by the package into the `set-auth-token` header family.
 */
export interface AuthCredentials {
  /** Opaque session token. Also surfaced as `token` on the sign-in/sign-up response body. */
  sessionToken: string;
  /** Short-lived JWT used to authenticate subsequent API calls. */
  authToken: string;
  authTokenExpiresInSeconds: number;
  sessionUpdateAgeSeconds: number;
}

export interface AuthHookFailure {
  /** Verbatim upstream code, e.g. `INVALID_EMAIL_OR_PASSWORD`. Mapped onto a status by the package. */
  code: string;
  message: string;
  headers?: Headers;
}

export type AuthHookResult<T> = { ok: true; value: T } | { ok: false; error: AuthHookFailure };

export function authHookSuccess<T>(value: T): AuthHookResult<T> {
  return { ok: true, value };
}

export function authHookFailure<T>(error: AuthHookFailure): AuthHookResult<T> {
  return { ok: false, error };
}

export interface EmailPasswordSignUpInput {
  email: string;
  password: string;
  name: string;
  callbackURL?: string | undefined;
}

export interface EmailPasswordSignInInput {
  email: string;
  password: string;
  callbackURL?: string | undefined;
}

export interface AuthenticatedResult<TUser extends AuthUser> {
  user: TUser;
  credentials: AuthCredentials;
}

export interface SessionLookupResult<TUser extends AuthUser> {
  user: TUser;
  session: AuthSession;
}

export interface SignOutResult {
  /** Merged into the response. Typically carries the expired session cookie the auth library set. */
  headers?: Headers | undefined;
}

export interface IssuedToken {
  token: string;
  expiresInSeconds?: number | undefined;
  /** Echoed back into `set-session-token` when present, so a refresh can rotate the session token. */
  sessionToken?: string | undefined;
}

export interface VerificationKeys {
  keys: ReadonlyArray<Record<string, unknown>>;
}

/**
 * The operations a consumer implements. This is the entire coupling surface between the package and whatever auth
 * library the consumer runs.
 *
 * Hooks return results rather than throwing so the package never has to guess what an app-thrown error meant.
 */
export interface AuthHooks<
  TUser extends AuthUser = AuthUser,
  TSignUpInput extends EmailPasswordSignUpInput = EmailPasswordSignUpInput,
  TSignInInput extends EmailPasswordSignInInput = EmailPasswordSignInInput,
> {
  signUp(c: AuthHookContext, input: TSignUpInput): Promise<AuthHookResult<AuthenticatedResult<TUser>>>;

  signIn(c: AuthHookContext, input: TSignInInput): Promise<AuthHookResult<AuthenticatedResult<TUser>>>;

  /**
   * Ends the session.
   *
   * Returned headers are merged into the 200 response, which is how an auth library's session-clearing cookie
   * reaches a cookie-based client. Sign-out is expected to succeed even with no active session.
   */
  signOut(c: AuthHookContext): Promise<AuthHookResult<SignOutResult>>;

  /** Cookie or opaque-token session lookup. A `null` value means "no session", which becomes a 401. */
  getSession(c: AuthHookContext): Promise<AuthHookResult<SessionLookupResult<TUser> | null>>;

  /** Issue or refresh the JWT for the bearer session token on the request. */
  issueToken(c: AuthHookContext): Promise<AuthHookResult<IssuedToken>>;

  /** Serves the public JWKS document. Returned raw because consumers typically proxy their auth library. */
  jwks(c: AuthHookContext): Promise<Response>;

  /**
   * Local-JWKS escape hatch, used instead of the remote JWKS set when `config.isTest` is on.
   *
   * This is what keeps key storage in the consumer: the app reads its own `jwks` table and hands back the keys.
   */
  verificationKeys?(c: AuthHookContext): Promise<VerificationKeys>;

  /** Catch-all for auth-library endpoints the package does not model. Mounted last, on GET and POST. */
  fallback?(c: AuthHookContext): Promise<Response>;
}
