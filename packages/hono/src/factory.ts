import { OpenAPIHono, type z } from '@hono/zod-openapi';
import {
  AUTH_ROUTE_PATHS,
  type AuthConfig,
  type AuthHookContext,
  type AuthHooks,
  type AuthLogger,
  type AuthOutcome,
  type AuthResponsePayload,
  type AuthSchemas,
  type AuthSessionResponse,
  type StatusCode,
  type AuthUser,
  DefaultErrorResponseSchema,
  DefaultValidationErrorResponseSchema,
  type EmailPasswordSignInInput,
  type EmailPasswordSignUpInput,
  type SessionExtras,
  createAuthEngine,
  noopAuthLogger,
} from '@kamaalio/kamaal-auth-core';
import type { Context, MiddlewareHandler } from 'hono';
import { cloneRawRequest } from 'hono/request';

import { AUTH_SESSION_CONTEXT_KEY, type AuthHonoEnv } from './env.js';
import { AuthHttpError } from './errors.js';
import { buildAuthRoutes } from './routes.js';

export interface AuthRouteDeps<
  ExtrasShape extends z.ZodRawShape,
  TLocals = unknown,
  E extends AuthHonoEnv = AuthHonoEnv,
> {
  schemas: AuthSchemas<ExtrasShape>;
  requireSessionMiddleware: MiddlewareHandler<E>;
  getSession: (c: Context<E>) => AuthSessionResponse;
  hookContext: (c: Context<E>) => Promise<AuthHookContext<TLocals>>;
  config: AuthConfig;
}

export interface CreateAuthModuleOptions<
  TUser extends AuthUser,
  TSignUpInput extends EmailPasswordSignUpInput,
  TSignInInput extends EmailPasswordSignInInput,
  ExtrasShape extends z.ZodRawShape,
  TLocals,
  E extends AuthHonoEnv,
> {
  hooks: AuthHooks<TUser, TSignUpInput, TSignInInput, TLocals>;
  config: AuthConfig;
  /**
   * Router to register the auth routes on.
   *
   * Supply the app's own router so its `defaultHook` — and therefore its validation-error envelope — governs these
   * routes too. Without one the package builds its own, which is only right for an app that has no factory of its own.
   */
  router?: OpenAPIHono<E>;
  logger?: (c: Context<E>) => AuthLogger;
  /** Per-request state handed to every hook as `c.locals`. Its type flows through to the hooks. */
  locals?: (c: Context<E>) => TLocals;
  requestId?: (c: Context<E>) => string | undefined;
  /**
   * Payload schemas. Override when the corresponding hook input is wider than the package default, so the router
   * validates every field the hook expects.
   */
  payloadSchemas?: {
    signUp?: z.ZodType<TSignUpInput>;
    signIn?: z.ZodType<TSignInInput>;
  };
  sessionExtras?: SessionExtras<ExtrasShape, TLocals>;
  /** Mount app-owned routes on the same router, with the package's schemas and middleware handed back. */
  extraRoutes?: (router: OpenAPIHono<E>, deps: AuthRouteDeps<ExtrasShape, TLocals, E>) => void;
}

export interface AuthModule<ExtrasShape extends z.ZodRawShape, TLocals = unknown, E extends AuthHonoEnv = AuthHonoEnv> {
  router: OpenAPIHono<E>;
  requireSessionMiddleware: MiddlewareHandler<E>;
  getSession: (c: Context<E>) => AuthSessionResponse;
  hookContext: (c: Context<E>) => Promise<AuthHookContext<TLocals>>;
  schemas: AuthSchemas<ExtrasShape>;
  config: AuthConfig;
}

/**
 * Mounts the auth routes on a Hono router.
 *
 * Everything this does is translation: a Hono `Context` becomes an `AuthHookContext`, an engine
 * `AuthResponsePayload` becomes a JSON response, and an engine `AuthError` becomes a thrown `AuthHttpError`. The
 * decisions all live in `@kamaalio/kamaal-auth-core`.
 */
export function createAuthModule<
  TUser extends AuthUser,
  TSignUpInput extends EmailPasswordSignUpInput,
  TSignInInput extends EmailPasswordSignInInput,
  ExtrasShape extends z.ZodRawShape = z.ZodRawShape,
  TLocals = unknown,
  E extends AuthHonoEnv = AuthHonoEnv,
>(
  options: CreateAuthModuleOptions<TUser, TSignUpInput, TSignInInput, ExtrasShape, TLocals, E>,
): AuthModule<ExtrasShape, TLocals, E> {
  const engine = createAuthEngine<TUser, TSignUpInput, TSignInInput, ExtrasShape, TLocals>({
    hooks: options.hooks,
    config: options.config,
    ...(options.payloadSchemas != null ? { payloadSchemas: options.payloadSchemas } : {}),
    ...(options.sessionExtras != null ? { sessionExtras: options.sessionExtras } : {}),
  });
  const { config, schemas } = engine;

  const requestIdOf = (c: Context<E>) => options.requestId?.(c);
  const loggerOf = (c: Context<E>) => options.logger?.(c) ?? noopAuthLogger;

  async function hookContext(c: Context<E>): Promise<AuthHookContext<TLocals>> {
    return {
      request: await cloneRawRequest(c.req),
      headers: c.req.raw.headers,
      requestId: requestIdOf(c),
      logger: loggerOf(c),
      locals: options.locals?.(c) as TLocals,
    };
  }

  /** The one place an engine failure turns into something Hono unwinds on. */
  function unwrap<T>(outcome: AuthOutcome<T>): T {
    if (!outcome.ok) throw new AuthHttpError(outcome.error);

    return outcome.value;
  }

  function send<S extends StatusCode>(c: Context<E>, payload: AuthResponsePayload<S>) {
    return c.json(payload.body as never, { status: payload.status, headers: payload.headers });
  }

  const requireSessionMiddleware: MiddlewareHandler<E> = async (c, next) => {
    if (c.get(AUTH_SESSION_CONTEXT_KEY) == null) {
      c.set(AUTH_SESSION_CONTEXT_KEY, unwrap(await engine.resolveSession(await hookContext(c))));
    }
    await next();
  };

  function getSession(c: Context<E>): AuthSessionResponse {
    const session = c.get(AUTH_SESSION_CONTEXT_KEY);
    if (session == null) throw new AuthHttpError(engine.sessionNotFound(requestIdOf(c)));

    return session;
  }

  const routes = buildAuthRoutes({
    tag: engine.openApi.tag,
    securitySchemeName: engine.openApi.securitySchemeName,
    errorSchema: config.errorSchemas?.error ?? DefaultErrorResponseSchema,
    validationErrorSchema: config.errorSchemas?.validation ?? DefaultValidationErrorResponseSchema,
    signUpSchema: engine.payloadSchemas.signUp,
    signInSchema: engine.payloadSchemas.signIn,
    authResponseSchema: schemas.AuthResponseSchema,
    sessionResponseSchema: schemas.SessionResponseSchema,
    tokenResponseSchema: schemas.TokenResponseSchema,
    sessionMiddleware: requireSessionMiddleware,
  });

  const router =
    options.router ??
    new OpenAPIHono<E>({
      defaultHook: (result, c) => {
        if (result.success) return;

        throw new AuthHttpError(engine.invalidPayload(result.error.issues, requestIdOf(c as Context<E>)));
      },
    });

  router.get(AUTH_ROUTE_PATHS.jwks, async c => engine.jwks(await hookContext(c)));

  router.openapi(routes.signUp, async c => {
    const hookCtx = await hookContext(c);
    const input = engine.payloadSchemas.signUp.parse(c.req.valid('json'));

    return send(c, unwrap(await engine.signUp(hookCtx, input)));
  });

  router.openapi(routes.signIn, async c => {
    const hookCtx = await hookContext(c);
    const input = engine.payloadSchemas.signIn.parse(c.req.valid('json'));

    return send(c, unwrap(await engine.signIn(hookCtx, input)));
  });

  router.openapi(routes.signOut, async c => send(c, unwrap(await engine.signOut(await hookContext(c)))));

  router.openapi(routes.session, c => send(c, engine.sessionResponse(getSession(c))));

  router.openapi(routes.token, async c => send(c, unwrap(await engine.issueToken(await hookContext(c)))));

  options.extraRoutes?.(router, { schemas, requireSessionMiddleware, getSession, hookContext, config });

  if (engine.hasFallback) {
    router.on(['POST', 'GET'], '**', async c => (await engine.fallback(await hookContext(c))) ?? c.notFound());
  }

  return { router, requireSessionMiddleware, getSession, hookContext, schemas, config };
}
