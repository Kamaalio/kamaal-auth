import { type JWTPayload, type JWTVerifyGetKey, createLocalJWKSet, jwtVerify } from 'jose';
import { z } from 'zod';

import type { AuthConfig } from './config.js';
import { AUTH_EVENTS } from './logging/index.js';
import { STATUS_CODES } from './constants.js';
import { AuthError, type AuthErrorRenderer, SessionNotFound } from './errors/index.js';
import type { AuthHookContext, AuthHooks } from './hooks/types.js';
import { bearerTokenFrom, getCredentialKind, toISO8601String } from './utils/index.js';

export interface AuthSessionResponse {
  session: { expires_at: string; created_at: string; updated_at: string };
  user: {
    id: string;
    created_at: string;
    email: string;
    email_verified: boolean;
    name: string;
    [key: string]: unknown;
  };
}

/**
 * The JWT claims this package understands.
 *
 * The three session claims are optional on purpose: tokens issued before a consumer started embedding them stay
 * verifiable until they expire naturally, falling back to the standard `exp` / `iat` claims.
 */
const AuthJWTPayloadSchema = z
  .object({
    sub: z.string(),
    email: z.email(),
    name: z.string(),
    emailVerified: z.boolean(),
    sessionExpiresAt: z.number().optional(),
    sessionCreatedAt: z.number().optional(),
    sessionUpdatedAt: z.number().optional(),
  })
  .loose();

const PublicJWKSchema = z.object({ kty: z.string() }).catchall(z.unknown());

/** Everything session resolution needs, given a hook context. Independent of any server framework. */
export interface SessionResolverOptions {
  hooks: AuthHooks;
  config: AuthConfig;
  render: AuthErrorRenderer;
  remoteJwks: JWTVerifyGetKey;
}

/**
 * Resolves the caller's session from a bearer JWT, falling back to the `getSession` hook.
 *
 * Throws {@link AuthError} when a session cannot be established. Caching a resolved session per request is the
 * adapter's job, since only it knows where per-request state lives.
 */
export async function resolveSession(
  c: AuthHookContext,
  options: SessionResolverOptions,
): Promise<AuthSessionResponse> {
  const fromJwt = await resolveSessionFromJwt(c, options);
  if (fromJwt != null) return fromJwt;

  return resolveSessionFromHook(c, options);
}

async function resolveSessionFromJwt(
  c: AuthHookContext,
  options: SessionResolverOptions,
): Promise<AuthSessionResponse | null> {
  const token = bearerTokenFrom(c.headers);
  if (token == null) return null;

  const keys = await getVerificationKeys(c, options);

  let payload: JWTPayload;
  try {
    const verified = await jwtVerify(token, keys, {
      issuer: options.config.jwt.issuer,
      audience: options.config.jwt.audience,
    });
    payload = verified.payload;
  } catch (error) {
    c.logger.warn(
      {
        event: AUTH_EVENTS.jwtVerification,
        outcome: 'failure',
        error_name: error instanceof Error ? error.name : typeof error,
        error_code: error instanceof Error ? error.name : typeof error,
        credential_kind: getCredentialKind(c.headers),
      },
      'Authentication token verification failed.',
    );

    return null;
  }

  const parsed = AuthJWTPayloadSchema.safeParse(payload);
  if (!parsed.success) {
    c.logger.warn(
      {
        event: AUTH_EVENTS.jwtVerification,
        outcome: 'failure',
        error_code: 'INVALID_JWT_PAYLOAD',
        credential_kind: getCredentialKind(c.headers),
      },
      'Authentication token payload was invalid.',
    );
    throw new AuthError(
      {
        status: STATUS_CODES.UNAUTHORIZED,
        code: 'INVALID_JWT_PAYLOAD',
        message: 'Invalid JWT payload',
        requestId: c.requestId,
      },
      options.render,
    );
  }

  const claims = parsed.data;
  c.logger.info(
    { event: AUTH_EVENTS.jwtVerification, user_id: claims.sub, outcome: 'success' },
    'Verified authentication token.',
  );

  const nowInSeconds = Math.floor(Date.now() / 1000);

  return {
    session: {
      expires_at: fromEpochSeconds(claims.sessionExpiresAt ?? payload.exp ?? nowInSeconds),
      created_at: fromEpochSeconds(claims.sessionCreatedAt ?? payload.iat ?? nowInSeconds),
      updated_at: fromEpochSeconds(claims.sessionUpdatedAt ?? payload.iat ?? nowInSeconds),
    },
    user: {
      id: claims.sub,
      name: claims.name,
      email: claims.email,
      email_verified: claims.emailVerified,
      created_at: fromEpochSeconds(payload.iat ?? 0),
    },
  };
}

async function resolveSessionFromHook(
  c: AuthHookContext,
  options: SessionResolverOptions,
): Promise<AuthSessionResponse> {
  const result = await options.hooks.getSession(c);
  if (!result.ok || result.value == null) {
    c.logger.warn(
      {
        event: AUTH_EVENTS.sessionLookup,
        outcome: 'failure',
        error_code: result.ok ? 'SESSION_NOT_FOUND' : result.error.code,
        credential_kind: getCredentialKind(c.headers),
      },
      'Authenticated user session was not found.',
    );

    throw new SessionNotFound({ requestId: c.requestId, render: options.render });
  }

  const { user, session } = result.value;
  c.logger.info(
    {
      event: AUTH_EVENTS.sessionLookup,
      user_id: user.id,
      outcome: 'success',
      session_expires_in_s: Math.floor((session.expiresAt.getTime() - Date.now()) / 1000),
      session_age_s: Math.floor((Date.now() - session.createdAt.getTime()) / 1000),
    },
    'Retrieved the authenticated user session.',
  );

  return {
    session: {
      expires_at: toISO8601String(session.expiresAt),
      created_at: toISO8601String(session.createdAt),
      updated_at: toISO8601String(session.updatedAt),
    },
    user: {
      id: user.id,
      name: user.name,
      email: user.email,
      email_verified: user.emailVerified,
      created_at: toISO8601String(user.createdAt),
    },
  };
}

async function getVerificationKeys(c: AuthHookContext, options: SessionResolverOptions): Promise<JWTVerifyGetKey> {
  if (options.config.isTest !== true) return options.remoteJwks;

  const result = await options.hooks.verificationKeys?.(c);
  if (result == null) {
    throw new Error('config.isTest is enabled but hooks.verificationKeys was not provided');
  }

  return createLocalJWKSet({ keys: result.keys.map(key => PublicJWKSchema.parse(key)) });
}

function fromEpochSeconds(seconds: number): string {
  return toISO8601String(new Date(seconds * 1000));
}
