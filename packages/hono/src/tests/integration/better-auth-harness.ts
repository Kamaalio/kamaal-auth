import { DatabaseSync } from 'node:sqlite';

import {
  type AuthCredentials,
  type AuthHookContext,
  type AuthHookResult,
  type AuthUser,
  ONE_DAY_IN_SECONDS,
  defineAuthHooks,
  getValueFromSetCookie,
} from '@kamaalio/kamaal-auth-core';
import { betterAuth } from 'better-auth';
import { getMigrations } from 'better-auth/db/migration';
import { bearer, jwt } from 'better-auth/plugins';
import { type JWTPayload, decodeJwt } from 'jose';
import { z } from 'zod';

export const ISSUER = 'http://kamaal-auth.test';
export const BASE_PATH = '/app-api/auth';
export const SESSION_EXPIRES_IN_SECONDS = ONE_DAY_IN_SECONDS * 30;
export const SESSION_UPDATE_AGE_SECONDS = ONE_DAY_IN_SECONDS;
export const JWT_EXPIRES_IN_SECONDS = ONE_DAY_IN_SECONDS * 7;
export const SESSION_COOKIE_NAME = 'better-auth.session_token';

function createBetterAuth(db: DatabaseSync) {
  return betterAuth({
    database: db,
    baseURL: ISSUER,
    basePath: BASE_PATH,
    emailAndPassword: { enabled: true, requireEmailVerification: false },
    trustedOrigins: ['kamaal-auth-test://'],
    session: { expiresIn: SESSION_EXPIRES_IN_SECONDS, updateAge: SESSION_UPDATE_AGE_SECONDS },
    plugins: [
      bearer(),
      jwt({
        jwt: {
          issuer: ISSUER,
          audience: ISSUER,
          expirationTime: `${JWT_EXPIRES_IN_SECONDS}s`,
          definePayload: async ({ user, session }) => ({
            email: user.email,
            name: user.name,
            emailVerified: user.emailVerified,
            sessionExpiresAt: Math.floor(session.expiresAt.getTime() / 1000),
            sessionCreatedAt: Math.floor(session.createdAt.getTime() / 1000),
            sessionUpdatedAt: Math.floor(session.updatedAt.getTime() / 1000),
          }),
        },
      }),
    ],
  });
}

export type Auth = ReturnType<typeof createBetterAuth>;

export interface AuthLocals {
  auth: Auth;
  db: DatabaseSync;
}

export interface BetterAuthTestInstance {
  auth: Auth;
  db: DatabaseSync;
  close: () => void;
}

/** A real better-auth instance backed by an in-memory SQLite database, migrated and ready to use. */
export async function createBetterAuthTestInstance(): Promise<BetterAuthTestInstance> {
  const db = new DatabaseSync(':memory:');
  const auth = createBetterAuth(db);

  const { runMigrations } = await getMigrations(auth.options);
  await runMigrations();

  return { auth, db, close: () => db.close() };
}

const BetterAuthErrorSchema = z.object({ code: z.string(), message: z.string() });

const BetterAuthUserSchema = z.object({
  id: z.string(),
  email: z.email(),
  name: z.string(),
  emailVerified: z.boolean(),
  createdAt: z.coerce.date(),
});

const BetterAuthAuthenticatedSchema = z.object({ user: BetterAuthUserSchema });

const TokenResponseSchema = z.object({ token: z.string() });

const PublicJWKSchema = z.object({ kty: z.string() }).catchall(z.unknown());

type Context = AuthHookContext<AuthLocals>;

const JwksRowSchema = z.object({ id: z.string(), publicKey: z.string() });

/** Every hook in this harness runs against a request the test suite built with `locals` set. */
function localsOf(c: Context): AuthLocals {
  if (c.locals == null) {
    throw new Error('AuthHookContext.locals was not provided.');
  }

  return c.locals;
}

/** Maps a real better-auth instance onto kamaal-auth's `AuthHooks`, the same shape a real consumer implements. */
export const betterAuthHooks = defineAuthHooks({
  async signUp(c: Context) {
    return authenticate(c);
  },

  async signIn(c: Context) {
    return authenticate(c);
  },

  async signOut(c: Context) {
    const response = await localsOf(c).auth.handler(c.request);

    return { ok: true, value: { headers: response.headers } };
  },

  async getSession(c: Context) {
    const result = await localsOf(c).auth.api.getSession({ headers: c.headers });
    if (result == null) {
      return { ok: true, value: null };
    }

    return {
      ok: true,
      value: {
        user: toAuthUser(result.user),
        session: {
          expiresAt: result.session.expiresAt,
          createdAt: result.session.createdAt,
          updatedAt: result.session.updatedAt,
        },
      },
    };
  },

  async issueToken(c: Context) {
    const response = await localsOf(c).auth.handler(c.request);
    if (!response.ok) {
      return { ok: false, error: { code: 'SESSION_NOT_FOUND', message: 'Session not found' } };
    }

    const { token } = TokenResponseSchema.parse(await response.json());

    return { ok: true, value: { token, expiresInSeconds: expiresInSeconds(token) } };
  },

  async jwks(c: Context) {
    return localsOf(c).auth.handler(c.request);
  },

  /** Reads the keys better-auth persisted directly, since there is no reachable JWKS endpoint in tests. */
  async verificationKeys(c: Context) {
    const rows = localsOf(c)
      .db.prepare('SELECT id, publicKey FROM jwks')
      .all()
      .map(row => JwksRowSchema.parse(row));

    return { keys: rows.map(row => ({ ...PublicJWKSchema.parse(JSON.parse(row.publicKey)), kid: row.id })) };
  },

  async fallback(c: Context) {
    return localsOf(c).auth.handler(c.request);
  },
});

async function authenticate(c: Context): Promise<AuthHookResult<{ user: AuthUser; credentials: AuthCredentials }>> {
  const response = await localsOf(c).auth.handler(c.request);
  const body: unknown = await response.json();

  const failure = BetterAuthErrorSchema.safeParse(body);
  if (failure.success) {
    return { ok: false, error: { ...failure.data, headers: response.headers } };
  }

  const sessionToken = getValueFromSetCookie(response.headers, SESSION_COOKIE_NAME);
  if (sessionToken == null) {
    return { ok: false, error: { code: 'MISSING_SESSION_TOKEN', message: 'Authentication response had no session' } };
  }

  const token = await mintToken(c, sessionToken);
  if (token == null) {
    return { ok: false, error: { code: 'MISSING_SESSION_TOKEN', message: 'Could not issue an authentication token' } };
  }

  return {
    ok: true,
    value: {
      user: toAuthUser(BetterAuthAuthenticatedSchema.parse(body).user),
      credentials: {
        sessionToken,
        authToken: token,
        authTokenExpiresInSeconds: expiresInSeconds(token),
        sessionUpdateAgeSeconds: SESSION_UPDATE_AGE_SECONDS,
      },
    },
  };
}

async function mintToken(c: Context, sessionToken: string): Promise<string | null> {
  const request = new Request(new URL(`${BASE_PATH}/token`, ISSUER), {
    method: 'GET',
    headers: new Headers({ Authorization: `Bearer ${sessionToken}` }),
  });
  const response = await localsOf(c).auth.handler(request);
  if (!response.ok) {
    return null;
  }

  return TokenResponseSchema.parse(await response.json()).token;
}

function toAuthUser(user: z.infer<typeof BetterAuthUserSchema>): AuthUser {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    emailVerified: user.emailVerified,
    createdAt: user.createdAt,
  };
}

function expiresInSeconds(token: string): number {
  let payload: JWTPayload | undefined;
  try {
    payload = decodeJwt(token);
  } catch {
    // Fall through to the configured default.
  }

  if (payload?.exp == null) {
    return JWT_EXPIRES_IN_SECONDS;
  }

  return payload.exp - Math.floor(Date.now() / 1000);
}
