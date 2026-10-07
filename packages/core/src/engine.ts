import type { StandardSchemaV1 } from '@standard-schema/spec';
import { createRemoteJWKSet, decodeJwt } from 'jose';

import type { AuthConfig } from './config.js';
import { AUTH_HEADER_NAMES, AUTH_OPENAPI_TAG, AUTH_ROUTE_PATHS, STATUS_CODES, type StatusCode } from './constants.js';
import { AuthError, SessionNotFound, defaultAuthErrorRenderer, hookError } from './errors/index.js';
import { buildCredentialHeaders } from './headers/credentials.js';
import type {
  AuthHookContext,
  AuthHooks,
  AuthUser,
  EmailPasswordSignInInput,
  EmailPasswordSignUpInput,
} from './hooks/types.js';
import type { JsonValue } from './json-value.js';
import { AUTH_EVENTS, type AuthEvent } from './logging/index.js';
import { EmailPasswordSignInSchema, EmailPasswordSignUpSchema } from './schemas/payloads.js';
import { type AuthSchemas, buildAuthSchemas } from './schemas/responses.js';
import { type AuthSessionResponse, type SessionResolverOptions, resolveSession } from './session.js';
import { bearerTokenFrom, getCredentialKind, toISO8601String } from './utils/index.js';

/**
 * What a server adapter turns into a response. Framework-shaped enough to be trivial to send, and nothing more.
 *
 * The status is a type parameter so an adapter that types responses per status code — `hono-standard-openapi`
 * does — still sees the literal each operation actually returns.
 */
export interface AuthResponsePayload<S extends StatusCode = StatusCode> {
  status: S;
  body: JsonValue;
  headers?: Headers | undefined;
}

/**
 * Expected failures come back rather than being thrown.
 *
 * An adapter decides how its framework unwinds an error; the engine only decides that one happened, and what it says.
 */
export type AuthOutcome<T> = { ok: true; value: T } | { ok: false; error: AuthError };

type OkPayload = AuthResponsePayload<typeof STATUS_CODES.OK>;

type CreatedPayload = AuthResponsePayload<typeof STATUS_CODES.CREATED>;

export interface SessionExtras<
  TExtrasSchema extends StandardSchemaV1<unknown, Record<string, JsonValue>> = StandardSchemaV1<
    unknown,
    Record<string, JsonValue>
  >,
  TLocals = unknown,
> {
  /**
   * Folded into the user object of every session and auth response, and into the OpenAPI document.
   *
   * Any Standard Schema library works — the adapter composes it alongside the package's own user schema rather
   * than merging shapes, so this schema never needs to be a Zod schema.
   */
  schema: TExtrasSchema;
  /** Return type is pinned to `schema`, so the two cannot drift apart. */
  resolve: (
    c: AuthHookContext<TLocals>,
    args: { userId: string },
  ) => Promise<StandardSchemaV1.InferOutput<TExtrasSchema>>;
}

export interface CreateAuthEngineOptions<
  TUser extends AuthUser,
  TSignUpInput extends EmailPasswordSignUpInput,
  TSignInInput extends EmailPasswordSignInInput,
  TExtrasSchema extends StandardSchemaV1<unknown, Record<string, JsonValue>>,
  TLocals,
> {
  hooks: AuthHooks<TUser, TSignUpInput, TSignInInput, TLocals>;
  config: AuthConfig;
  /**
   * Payload schemas. Override when the corresponding hook input is wider than the package default, so the adapter
   * validates every field the hook expects. Any Standard Schema library works.
   */
  payloadSchemas?: {
    signUp: StandardSchemaV1<unknown, TSignUpInput>;
    signIn: StandardSchemaV1<unknown, TSignInInput>;
  };
  sessionExtras?: SessionExtras<TExtrasSchema, TLocals>;
}

/**
 * Every auth operation, expressed against {@link AuthHookContext} and plain `Response` data.
 *
 * This is the whole package minus delivery: a server adapter builds a hook context out of its own request object,
 * calls these, and turns an {@link AuthResponsePayload} into a response and an {@link AuthError} into whatever its
 * framework throws.
 */
export interface AuthEngine<
  TSignUpInput extends EmailPasswordSignUpInput = EmailPasswordSignUpInput,
  TSignInInput extends EmailPasswordSignInInput = EmailPasswordSignInInput,
  TLocals = unknown,
> {
  config: AuthConfig;
  schemas: AuthSchemas;
  /** Resolved OpenAPI naming, so an adapter does not have to re-apply the same defaults. */
  openApi: { tag: string; securitySchemeName: string };
  /** The schemas an adapter should validate request bodies against, after `payloadSchemas` defaulting. */
  payloadSchemas: { signUp: StandardSchemaV1<unknown, TSignUpInput>; signIn: StandardSchemaV1<unknown, TSignInInput> };

  /** Resolves the caller's session and folds in `sessionExtras`. */
  resolveSession(c: AuthHookContext<TLocals>): Promise<AuthOutcome<AuthSessionResponse>>;
  signUp(c: AuthHookContext<TLocals>, input: TSignUpInput): Promise<AuthOutcome<CreatedPayload>>;
  signIn(c: AuthHookContext<TLocals>, input: TSignInInput): Promise<AuthOutcome<OkPayload>>;
  signOut(c: AuthHookContext<TLocals>): Promise<AuthOutcome<OkPayload>>;
  /** Renders an already-resolved session. Pure, because the adapter's middleware has done the work by then. */
  sessionResponse(session: AuthSessionResponse): OkPayload;
  issueToken(c: AuthHookContext<TLocals>): Promise<AuthOutcome<OkPayload>>;
  jwks(c: AuthHookContext<TLocals>): Promise<Response>;
  /** `null` when the consumer supplied no `fallback` hook, which an adapter should render as a 404. */
  fallback(c: AuthHookContext<TLocals>): Promise<Response | null>;
  hasFallback: boolean;

  /** Errors an adapter raises on the engine's behalf, so they read in the same envelope as every other failure. */
  invalidPayload(issues: readonly unknown[], requestId?: string): AuthError;
  sessionNotFound(requestId?: string): AuthError;
}

export function createAuthEngine<
  TUser extends AuthUser,
  TSignUpInput extends EmailPasswordSignUpInput,
  TSignInInput extends EmailPasswordSignInInput,
  TExtrasSchema extends StandardSchemaV1<unknown, Record<string, JsonValue>> = StandardSchemaV1<
    unknown,
    Record<string, JsonValue>
  >,
  TLocals = unknown,
>(
  options: CreateAuthEngineOptions<TUser, TSignUpInput, TSignInInput, TExtrasSchema, TLocals> & {
    payloadSchemas: {
      signUp: StandardSchemaV1<unknown, TSignUpInput>;
      signIn: StandardSchemaV1<unknown, TSignInInput>;
    };
  },
): AuthEngine<TSignUpInput, TSignInInput, TLocals>;
export function createAuthEngine<
  TUser extends AuthUser,
  TExtrasSchema extends StandardSchemaV1<unknown, Record<string, JsonValue>> = StandardSchemaV1<
    unknown,
    Record<string, JsonValue>
  >,
  TLocals = unknown,
>(
  options: CreateAuthEngineOptions<TUser, EmailPasswordSignUpInput, EmailPasswordSignInInput, TExtrasSchema, TLocals>,
): AuthEngine<EmailPasswordSignUpInput, EmailPasswordSignInInput, TLocals>;
export function createAuthEngine<
  TUser extends AuthUser,
  TExtrasSchema extends StandardSchemaV1<unknown, Record<string, JsonValue>>,
  TLocals,
>(
  options: CreateAuthEngineOptions<TUser, EmailPasswordSignUpInput, EmailPasswordSignInInput, TExtrasSchema, TLocals>,
): AuthEngine<EmailPasswordSignUpInput, EmailPasswordSignInInput, TLocals> {
  const { hooks, config } = options;
  const render = config.errorResponse ?? defaultAuthErrorRenderer;
  const schemas = buildAuthSchemas();
  const remoteJwks = createRemoteJWKSet(config.jwt.jwksUrl);
  const resolverOptions: SessionResolverOptions = { hooks, config, render, remoteJwks };
  const payloadSchemas = {
    signUp: options.payloadSchemas?.signUp ?? EmailPasswordSignUpSchema,
    signIn: options.payloadSchemas?.signIn ?? EmailPasswordSignInSchema,
  };

  async function withExtras(
    c: AuthHookContext<TLocals>,
    user: AuthSessionResponse['user'],
  ): Promise<AuthSessionResponse['user']> {
    const sessionExtras = options.sessionExtras;
    if (sessionExtras == null) {
      return user;
    }

    const extras = await sessionExtras.resolve(c, { userId: user.id });

    return { ...user, ...extras };
  }

  /** Only {@link AuthError} is an expected failure; anything else is a bug and keeps unwinding. */
  async function outcomeOf<T>(run: () => Promise<T>): Promise<AuthOutcome<T>> {
    try {
      return { ok: true, value: await run() };
    } catch (error) {
      if (error instanceof AuthError) {
        return { ok: false, error };
      }

      throw error;
    }
  }

  async function authenticated<S extends StatusCode>(
    c: AuthHookContext<TLocals>,
    result: Awaited<
      ReturnType<AuthHooks<TUser, EmailPasswordSignUpInput, EmailPasswordSignInInput, TLocals>['signIn']>
    >,
    args: { status: S; event: AuthEvent; message: string; routePath: string },
  ): Promise<AuthOutcome<AuthResponsePayload<S>>> {
    if (!result.ok) {
      return { ok: false, error: hookError(result.error, config, c.requestId) };
    }

    const { user, credentials } = result.value;
    c.logger.info(
      { event: args.event, route: `${config.basePath}${args.routePath}`, outcome: 'success' },
      args.message,
    );

    return {
      ok: true,
      value: {
        status: args.status,
        body: { token: credentials.sessionToken, user: await withExtras(c, mapUser(user)) },
        headers: buildCredentialHeaders(credentials),
      },
    };
  }

  return {
    config,
    schemas,
    openApi: {
      tag: config.openApi?.tag ?? AUTH_OPENAPI_TAG,
      securitySchemeName: config.openApi?.securitySchemeName ?? 'bearerAuth',
    },
    payloadSchemas,
    hasFallback: hooks.fallback != null,

    async resolveSession(c) {
      return outcomeOf(async () => {
        const session = await resolveSession(c, resolverOptions);

        return { ...session, user: await withExtras(c, session.user) };
      });
    },

    async signUp(c, input) {
      return authenticated(c, await hooks.signUp(c, input), {
        status: STATUS_CODES.CREATED,
        event: AUTH_EVENTS.signUpSucceeded,
        message: 'Created account and signed in successfully.',
        routePath: AUTH_ROUTE_PATHS.signUp,
      });
    },

    async signIn(c, input) {
      return authenticated(c, await hooks.signIn(c, input), {
        status: STATUS_CODES.OK,
        event: AUTH_EVENTS.signInSucceeded,
        message: 'Signed in with email and password.',
        routePath: AUTH_ROUTE_PATHS.signIn,
      });
    },

    async signOut(c) {
      const result = await hooks.signOut(c);
      if (!result.ok) {
        return { ok: false, error: hookError(result.error, config, c.requestId) };
      }

      c.logger.info(
        {
          event: AUTH_EVENTS.signOutSucceeded,
          route: `${config.basePath}${AUTH_ROUTE_PATHS.signOut}`,
          outcome: 'success',
        },
        'Signed out successfully.',
      );

      // Carries through whatever the hook set, notably the auth library's expired session cookie.
      return { ok: true, value: { status: STATUS_CODES.OK, body: {}, headers: result.value.headers } };
    },

    sessionResponse(session) {
      return { status: STATUS_CODES.OK, body: { ...session } };
    },

    async issueToken(c) {
      const result = await hooks.issueToken(c);
      if (!result.ok) {
        const error = hookError(result.error, config, c.requestId);
        const fields = {
          event: error.status >= 500 ? AUTH_EVENTS.tokenFailed : AUTH_EVENTS.tokenRejected,
          outcome: 'failure' as const,
          error_code: error.code,
          credential_kind: getCredentialKind(c.headers),
          status_code: error.status,
        };
        if (error.status >= 500) {
          c.logger.error(fields, 'Authentication token issuance failed.');
        } else {
          c.logger.warn(fields, 'Authentication token request was rejected.');
        }

        return { ok: false, error };
      }

      const issued = result.value;
      const headers = buildTokenHeaders({
        authToken: issued.token,
        authTokenExpiresInSeconds: issued.expiresInSeconds ?? expiryFromJwt(issued.token, config),
        sessionToken: issued.sessionToken ?? bearerTokenFrom(c.headers),
        sessionUpdateAgeSeconds: config.session.updateAgeSeconds,
      });

      c.logger.info(
        {
          event: AUTH_EVENTS.tokenIssued,
          route: `${config.basePath}${AUTH_ROUTE_PATHS.token}`,
          outcome: 'success',
        },
        'Issued an authentication token.',
      );

      return { ok: true, value: { status: STATUS_CODES.OK, body: { token: issued.token }, headers } };
    },

    async jwks(c) {
      return hooks.jwks(c);
    },

    async fallback(c) {
      return (await hooks.fallback?.(c)) ?? null;
    },

    invalidPayload(issues, requestId) {
      return new AuthError(
        {
          status: STATUS_CODES.BAD_REQUEST,
          code: 'INVALID_PAYLOAD',
          message: 'Invalid payload',
          context: { validations: issues },
          requestId,
        },
        render,
      );
    },

    sessionNotFound(requestId) {
      return new SessionNotFound({ requestId, render });
    },
  };
}

function mapUser(user: AuthUser): AuthSessionResponse['user'] {
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    email_verified: user.emailVerified,
    created_at: toISO8601String(user.createdAt),
  };
}

function buildTokenHeaders(args: {
  authToken: string;
  authTokenExpiresInSeconds: number;
  sessionToken: string | null;
  sessionUpdateAgeSeconds: number;
}): Headers {
  if (args.sessionToken != null) {
    return buildCredentialHeaders({
      authToken: args.authToken,
      authTokenExpiresInSeconds: args.authTokenExpiresInSeconds,
      sessionToken: args.sessionToken,
      sessionUpdateAgeSeconds: args.sessionUpdateAgeSeconds,
    });
  }

  const headers = new Headers();
  headers.set('content-type', 'application/json');
  headers.set(AUTH_HEADER_NAMES.authToken, args.authToken);
  headers.set(AUTH_HEADER_NAMES.authTokenExpiry, Math.floor(args.authTokenExpiresInSeconds).toString());

  return headers;
}

function expiryFromJwt(token: string, config: AuthConfig): number {
  try {
    const exp = decodeJwt(token).exp;
    if (exp != null) {
      return exp - Math.floor(Date.now() / 1000);
    }
  } catch {
    // Fall through to the configured default.
  }

  return config.jwt.expiresInSeconds;
}
