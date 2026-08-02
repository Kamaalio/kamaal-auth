import { SignJWT, type JWK, exportJWK, generateKeyPair } from 'jose';

import type { AuthConfig } from '../config.js';
import { ONE_DAY_IN_SECONDS } from '../constants.js';
import type {
  AuthCredentials,
  AuthHookContext,
  AuthHookResult,
  AuthHooks,
  AuthSession,
  AuthUser,
  EmailPasswordSignInInput,
  EmailPasswordSignUpInput,
  IssuedToken,
  SessionLookupResult,
  VerificationKeys,
} from '../hooks/types.js';
import { bearerTokenFrom } from '../utils/index.js';

export const SESSION_COOKIE_NAME = 'better-auth.session_token';

export interface InMemoryAuthOptions {
  issuer?: string;
  audience?: string;
  sessionExpiresInSeconds?: number;
  sessionUpdateAgeSeconds?: number;
  jwtExpiresInSeconds?: number;
}

interface StoredUser extends AuthUser {
  password: string;
}

interface StoredSession extends AuthSession {
  userId: string;
}

export interface InMemoryAuthStore {
  users: Map<string, StoredUser>;
  sessions: Map<string, StoredSession>;
  /** Signs a JWT for an existing session. Useful for building an expired or otherwise hand-crafted token in a test. */
  signToken(
    sessionToken: string,
    overrides?: { claims?: Record<string, unknown>; expiresInSeconds?: number },
  ): Promise<string>;
  publicJwk: JWK;
}

export interface InMemoryAuth {
  hooks: AuthHooks;
  config: AuthConfig;
  store: InMemoryAuthStore;
}

/**
 * A dependency-free {@link AuthHooks} implementation backed by two maps and a generated Ed25519 keypair.
 *
 * The point of the hook boundary is that the router can be tested without a database or an auth library, so this is
 * what the package's own suite runs against.
 */
export async function createInMemoryAuth(options: InMemoryAuthOptions = {}): Promise<InMemoryAuth> {
  const issuer = options.issuer ?? 'https://kamaal-auth.test';
  const audience = options.audience ?? issuer;
  const sessionExpiresInSeconds = options.sessionExpiresInSeconds ?? ONE_DAY_IN_SECONDS * 30;
  const sessionUpdateAgeSeconds = options.sessionUpdateAgeSeconds ?? ONE_DAY_IN_SECONDS;
  const jwtExpiresInSeconds = options.jwtExpiresInSeconds ?? ONE_DAY_IN_SECONDS * 7;

  const { publicKey, privateKey } = await generateKeyPair('EdDSA', { crv: 'Ed25519', extractable: true });
  const publicJwk = { ...(await exportJWK(publicKey)), kid: 'test-key', alg: 'EdDSA', use: 'sig' };

  const users = new Map<string, StoredUser>();
  const sessions = new Map<string, StoredSession>();

  async function signToken(
    sessionToken: string,
    overrides?: { claims?: Record<string, unknown>; expiresInSeconds?: number },
  ): Promise<string> {
    const session = sessions.get(sessionToken);
    if (session == null) throw new Error(`Unknown session token: ${sessionToken}`);

    const user = findUserById(session.userId);
    if (user == null) throw new Error(`Unknown user: ${session.userId}`);

    const nowInSeconds = Math.floor(Date.now() / 1000);

    return new SignJWT({
      email: user.email,
      name: user.name,
      emailVerified: user.emailVerified,
      sessionExpiresAt: Math.floor(session.expiresAt.getTime() / 1000),
      sessionCreatedAt: Math.floor(session.createdAt.getTime() / 1000),
      sessionUpdatedAt: Math.floor(session.updatedAt.getTime() / 1000),
      ...overrides?.claims,
    })
      .setProtectedHeader({ alg: 'EdDSA', kid: 'test-key' })
      .setSubject(user.id)
      .setIssuer(issuer)
      .setAudience(audience)
      .setIssuedAt(nowInSeconds)
      .setExpirationTime(nowInSeconds + (overrides?.expiresInSeconds ?? jwtExpiresInSeconds))
      .sign(privateKey);
  }

  function findUserById(id: string): StoredUser | null {
    for (const user of users.values()) {
      if (user.id === id) return user;
    }

    return null;
  }

  function resolveSessionToken(c: AuthHookContext): string | null {
    const bearer = bearerTokenFrom(c.headers);
    if (bearer != null) return bearer;

    const cookie = c.headers.get('Cookie');
    if (cookie == null) return null;

    return cookie.match(new RegExp(`${SESSION_COOKIE_NAME}=([^;]+)`))?.[1] ?? null;
  }

  async function startSession(user: StoredUser): Promise<AuthCredentials> {
    const sessionToken = `session_${crypto.randomUUID()}`;
    const now = new Date();
    sessions.set(sessionToken, {
      userId: user.id,
      createdAt: now,
      updatedAt: now,
      expiresAt: new Date(now.getTime() + sessionExpiresInSeconds * 1000),
    });

    return {
      sessionToken,
      authToken: await signToken(sessionToken),
      authTokenExpiresInSeconds: jwtExpiresInSeconds,
      sessionUpdateAgeSeconds,
    };
  }

  function toAuthUser(user: StoredUser): AuthUser {
    return {
      id: user.id,
      email: user.email,
      name: user.name,
      emailVerified: user.emailVerified,
      createdAt: user.createdAt,
    };
  }

  const hooks: AuthHooks = {
    async signUp(_c, input: EmailPasswordSignUpInput) {
      if (users.has(input.email)) {
        return {
          ok: false,
          error: {
            code: 'USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL',
            message: 'User already exists. Use another email.',
          },
        };
      }

      const user: StoredUser = {
        id: `user_${crypto.randomUUID()}`,
        email: input.email,
        name: input.name,
        emailVerified: false,
        createdAt: new Date(),
        password: input.password,
      };
      users.set(user.email, user);

      return { ok: true, value: { user: toAuthUser(user), credentials: await startSession(user) } };
    },

    async signIn(_c, input: EmailPasswordSignInInput) {
      const user = users.get(input.email);
      if (user == null || user.password !== input.password) {
        return { ok: false, error: { code: 'INVALID_EMAIL_OR_PASSWORD', message: 'Invalid email or password' } };
      }

      return { ok: true, value: { user: toAuthUser(user), credentials: await startSession(user) } };
    },

    async signOut(c) {
      const sessionToken = resolveSessionToken(c);
      if (sessionToken != null) sessions.delete(sessionToken);

      return { ok: true, value: undefined };
    },

    async getSession(c): Promise<AuthHookResult<SessionLookupResult<AuthUser> | null>> {
      const sessionToken = resolveSessionToken(c);
      if (sessionToken == null) return { ok: true, value: null };

      const session = sessions.get(sessionToken);
      if (session == null) return { ok: true, value: null };
      if (session.expiresAt.getTime() <= Date.now()) return { ok: true, value: null };

      const user = findUserById(session.userId);
      if (user == null) return { ok: true, value: null };

      return {
        ok: true,
        value: {
          user: toAuthUser(user),
          session: { expiresAt: session.expiresAt, createdAt: session.createdAt, updatedAt: session.updatedAt },
        },
      };
    },

    async issueToken(c): Promise<AuthHookResult<IssuedToken>> {
      const sessionToken = resolveSessionToken(c);
      if (sessionToken == null || !sessions.has(sessionToken)) {
        return { ok: false, error: { code: 'SESSION_NOT_FOUND', message: 'Session not found' } };
      }

      return {
        ok: true,
        value: { token: await signToken(sessionToken), expiresInSeconds: jwtExpiresInSeconds, sessionToken },
      };
    },

    async jwks() {
      return Response.json({ keys: [publicJwk] });
    },

    async verificationKeys(): Promise<VerificationKeys> {
      return { keys: [publicJwk] };
    },
  };

  const config: AuthConfig = {
    basePath: '/app-api/auth',
    trustedOrigins: ['kamaal-auth-test://'],
    session: { expiresInSeconds: sessionExpiresInSeconds, updateAgeSeconds: sessionUpdateAgeSeconds },
    jwt: { issuer, audience, expiresInSeconds: jwtExpiresInSeconds, jwksUrl: new URL('/jwks', issuer) },
    isTest: true,
  };

  return { hooks, config, store: { users, sessions, signToken, publicJwk } };
}
