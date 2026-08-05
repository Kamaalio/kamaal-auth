import { OpenAPIHono, type z } from '@hono/zod-openapi';
import type { Context, MiddlewareHandler } from 'hono';
import { cloneRawRequest } from 'hono/request';
import { createRemoteJWKSet, decodeJwt } from 'jose';

import type { AuthConfig } from '../config.js';
import { AUTH_HEADER_NAMES, AUTH_OPENAPI_TAG, AUTH_ROUTE_PATHS, STATUS_CODES, type StatusCode } from '../constants.js';
import { AUTH_ERROR_STATUSES, AuthHttpError, SessionNotFound, defaultAuthErrorRenderer } from '../errors/index.js';
import { buildCredentialHeaders } from '../headers/credentials.js';
import type {
  AuthHookContext,
  AuthHookFailure,
  AuthHooks,
  AuthUser,
  EmailPasswordSignInInput,
  EmailPasswordSignUpInput,
} from '../hooks/types.js';
import { AUTH_EVENTS, type AuthLogger, noopAuthLogger } from '../logging/index.js';
import {
  AUTH_SESSION_CONTEXT_KEY,
  type AuthHonoEnv,
  type AuthSessionResponse,
  resolveSession,
} from '../middleware/session.js';
import { DefaultErrorResponseSchema, DefaultValidationErrorResponseSchema } from '../schemas/errors.js';
import { EmailPasswordSignInSchema, EmailPasswordSignUpSchema } from '../schemas/payloads.js';
import { type AuthSchemas, buildAuthSchemas } from '../schemas/responses.js';
import { buildAuthRoutes } from './routes.js';
import { bearerTokenFrom, getCredentialKind, toISO8601String } from '../utils/index.js';

export interface SessionExtras<ExtrasShape extends z.ZodRawShape> {
  /** Merged into the user object of every session and auth response, and into the OpenAPI document. */
  schema: z.ZodObject<ExtrasShape>;
  /** Return type is pinned to `schema`, so the two cannot drift apart. */
  resolve: (c: AuthHookContext, args: { userId: string }) => Promise<z.infer<z.ZodObject<ExtrasShape>>>;
}

export interface AuthRouteDeps<ExtrasShape extends z.ZodRawShape> {
  schemas: AuthSchemas<ExtrasShape>;
  requireSessionMiddleware: MiddlewareHandler<AuthHonoEnv>;
  getSession: (c: Context<AuthHonoEnv>) => AuthSessionResponse;
  hookContext: (c: Context<AuthHonoEnv>) => Promise<AuthHookContext>;
  config: AuthConfig;
}

export interface CreateAuthModuleOptions<
  TUser extends AuthUser,
  TSignUpInput extends EmailPasswordSignUpInput,
  TSignInInput extends EmailPasswordSignInInput,
  ExtrasShape extends z.ZodRawShape,
> {
  hooks: AuthHooks<TUser, TSignUpInput, TSignInInput>;
  config: AuthConfig;
  /**
   * Router to register the auth routes on.
   *
   * Supply the app's own router so its `defaultHook` — and therefore its validation-error envelope — governs these
   * routes too. Without one the package builds its own, which is only right for an app that has no factory of its own.
   */
  router?: OpenAPIHono<AuthHonoEnv>;
  logger?: (c: Context<AuthHonoEnv>) => AuthLogger;
  locals?: (c: Context<AuthHonoEnv>) => unknown;
  requestId?: (c: Context<AuthHonoEnv>) => string | undefined;
  /**
   * Payload schemas. Override when the corresponding hook input is wider than the package default, so the router
   * validates every field the hook expects.
   */
  payloadSchemas?: {
    signUp?: z.ZodType<TSignUpInput>;
    signIn?: z.ZodType<TSignInInput>;
  };
  sessionExtras?: SessionExtras<ExtrasShape>;
  /** Mount app-owned routes on the same router, with the package's schemas and middleware handed back. */
  extraRoutes?: (router: OpenAPIHono<AuthHonoEnv>, deps: AuthRouteDeps<ExtrasShape>) => void;
}

export interface AuthModule<ExtrasShape extends z.ZodRawShape> {
  router: OpenAPIHono<AuthHonoEnv>;
  requireSessionMiddleware: MiddlewareHandler<AuthHonoEnv>;
  getSession: (c: Context<AuthHonoEnv>) => AuthSessionResponse;
  hookContext: (c: Context<AuthHonoEnv>) => Promise<AuthHookContext>;
  schemas: AuthSchemas<ExtrasShape>;
  config: AuthConfig;
}

export function createAuthModule<
  TUser extends AuthUser,
  TSignUpInput extends EmailPasswordSignUpInput,
  TSignInInput extends EmailPasswordSignInInput,
  ExtrasShape extends z.ZodRawShape = z.ZodRawShape,
>(options: CreateAuthModuleOptions<TUser, TSignUpInput, TSignInInput, ExtrasShape>): AuthModule<ExtrasShape> {
  const { hooks, config } = options;
  const render = config.errorResponse ?? defaultAuthErrorRenderer;
  const errorStatuses = { ...AUTH_ERROR_STATUSES, ...config.errorStatuses };
  const schemas = buildAuthSchemas<ExtrasShape>(options.sessionExtras?.schema.shape);
  const remoteJwks = createRemoteJWKSet(config.jwt.jwksUrl);

  const requestIdOf = (c: Context<AuthHonoEnv>) => options.requestId?.(c);
  const loggerOf = (c: Context<AuthHonoEnv>) => options.logger?.(c) ?? noopAuthLogger;

  async function hookContext(c: Context<AuthHonoEnv>): Promise<AuthHookContext> {
    return {
      request: await cloneRawRequest(c.req),
      headers: c.req.raw.headers,
      requestId: requestIdOf(c),
      logger: loggerOf(c),
      locals: options.locals?.(c),
    };
  }

  function failure(error: AuthHookFailure, requestId: string | undefined): AuthHttpError {
    const status: StatusCode = errorStatuses[error.code] ?? STATUS_CODES.INTERNAL_SERVER_ERROR;

    return new AuthHttpError(
      { status, code: error.code, message: error.message, headers: error.headers, requestId },
      render,
    );
  }

  async function withExtras(
    c: AuthHookContext,
    user: AuthSessionResponse['user'],
  ): Promise<AuthSessionResponse['user']> {
    const sessionExtras = options.sessionExtras;
    if (sessionExtras == null) return user;

    const extras = await sessionExtras.resolve(c, { userId: user.id });

    return { ...user, ...extras };
  }

  const requireSessionMiddleware: MiddlewareHandler<AuthHonoEnv> = async (c, next) => {
    const session = await resolveSession(c, { hooks, config, render, remoteJwks, hookContext });
    const hookCtx = await hookContext(c);
    c.set(AUTH_SESSION_CONTEXT_KEY, { ...session, user: await withExtras(hookCtx, session.user) });
    await next();
  };

  function getSession(c: Context<AuthHonoEnv>): AuthSessionResponse {
    const session = c.get(AUTH_SESSION_CONTEXT_KEY);
    if (session == null) {
      throw new SessionNotFound({ requestId: requestIdOf(c), render });
    }

    return session;
  }

  const signUpSchema: z.ZodType<TSignUpInput> =
    options.payloadSchemas?.signUp ?? (EmailPasswordSignUpSchema as unknown as z.ZodType<TSignUpInput>);
  const signInSchema: z.ZodType<TSignInInput> =
    options.payloadSchemas?.signIn ?? (EmailPasswordSignInSchema as unknown as z.ZodType<TSignInInput>);

  const routes = buildAuthRoutes({
    tag: config.openApi?.tag ?? AUTH_OPENAPI_TAG,
    securitySchemeName: config.openApi?.securitySchemeName ?? 'bearerAuth',
    errorSchema: config.errorSchemas?.error ?? DefaultErrorResponseSchema,
    validationErrorSchema: config.errorSchemas?.validation ?? DefaultValidationErrorResponseSchema,
    signUpSchema: options.payloadSchemas?.signUp ?? EmailPasswordSignUpSchema,
    signInSchema: options.payloadSchemas?.signIn ?? EmailPasswordSignInSchema,
    authResponseSchema: schemas.AuthResponseSchema,
    sessionResponseSchema: schemas.SessionResponseSchema,
    tokenResponseSchema: schemas.TokenResponseSchema,
    sessionMiddleware: requireSessionMiddleware,
  });

  const router =
    options.router ??
    new OpenAPIHono<AuthHonoEnv>({
      defaultHook: (result, c) => {
        if (result.success) return;

        throw new AuthHttpError(
          {
            status: STATUS_CODES.BAD_REQUEST,
            code: 'INVALID_PAYLOAD',
            message: 'Invalid payload',
            context: { validations: result.error.issues },
            requestId: requestIdOf(c),
          },
          render,
        );
      },
    });

  router.get(AUTH_ROUTE_PATHS.jwks, async c => hooks.jwks(await hookContext(c)));

  router.openapi(routes.signUp, async c => {
    const hookCtx = await hookContext(c);
    const result = await hooks.signUp(hookCtx, signUpSchema.parse(c.req.valid('json')));
    if (!result.ok) throw failure(result.error, hookCtx.requestId);

    const { user, credentials } = result.value;
    hookCtx.logger.info(
      { event: AUTH_EVENTS.signUpSucceeded, route: `${config.basePath}${routes.signUp.path}`, outcome: 'success' },
      'Created account and signed in successfully.',
    );

    return c.json(
      { token: credentials.sessionToken, user: await withExtras(hookCtx, mapUser(user)) },
      { status: STATUS_CODES.CREATED, headers: buildCredentialHeaders(credentials) },
    );
  });

  router.openapi(routes.signIn, async c => {
    const hookCtx = await hookContext(c);
    const result = await hooks.signIn(hookCtx, signInSchema.parse(c.req.valid('json')));
    if (!result.ok) throw failure(result.error, hookCtx.requestId);

    const { user, credentials } = result.value;
    hookCtx.logger.info(
      { event: AUTH_EVENTS.signInSucceeded, route: `${config.basePath}${routes.signIn.path}`, outcome: 'success' },
      'Signed in with email and password.',
    );

    return c.json(
      { token: credentials.sessionToken, user: await withExtras(hookCtx, mapUser(user)) },
      { status: STATUS_CODES.OK, headers: buildCredentialHeaders(credentials) },
    );
  });

  router.openapi(routes.signOut, async c => {
    const hookCtx = await hookContext(c);
    const result = await hooks.signOut(hookCtx);
    if (!result.ok) throw failure(result.error, hookCtx.requestId);

    hookCtx.logger.info(
      { event: AUTH_EVENTS.signOutSucceeded, route: `${config.basePath}${routes.signOut.path}`, outcome: 'success' },
      'Signed out successfully.',
    );

    // Carries through whatever the hook set, notably the auth library's expired session cookie.
    return c.json({}, { status: STATUS_CODES.OK, headers: result.value.headers });
  });

  router.openapi(routes.session, c => c.json(getSession(c), { status: STATUS_CODES.OK }));

  router.openapi(routes.token, async c => {
    const hookCtx = await hookContext(c);
    const result = await hooks.issueToken(hookCtx);
    if (!result.ok) {
      hookCtx.logger.warn(
        {
          event: AUTH_EVENTS.tokenRejected,
          outcome: 'failure',
          error_code: result.error.code,
          credential_kind: getCredentialKind(hookCtx.headers),
          status_code: STATUS_CODES.UNAUTHORIZED,
        },
        'Authentication token request was rejected.',
      );

      throw new SessionNotFound({ requestId: hookCtx.requestId, render });
    }

    const issued = result.value;
    const sessionToken = issued.sessionToken ?? bearerTokenFrom(hookCtx.headers);
    const headers = buildTokenHeaders({
      authToken: issued.token,
      authTokenExpiresInSeconds: issued.expiresInSeconds ?? expiryFromJwt(issued.token, config),
      sessionToken,
      sessionUpdateAgeSeconds: config.session.updateAgeSeconds,
    });

    hookCtx.logger.info(
      { event: AUTH_EVENTS.tokenIssued, route: `${config.basePath}${routes.token.path}`, outcome: 'success' },
      'Issued an authentication token.',
    );

    return c.json({ token: issued.token }, { status: STATUS_CODES.OK, headers });
  });

  options.extraRoutes?.(router, { schemas, requireSessionMiddleware, getSession, hookContext, config });

  if (hooks.fallback != null) {
    router.on(['POST', 'GET'], '**', async c => {
      const response = await hooks.fallback?.(await hookContext(c));

      return response ?? c.notFound();
    });
  }

  return { router, requireSessionMiddleware, getSession, hookContext, schemas, config };
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
    if (exp != null) return exp - Math.floor(Date.now() / 1000);
  } catch {
    // Fall through to the configured default.
  }

  return config.jwt.expiresInSeconds;
}
