import { OpenAPIHono, z } from '@hono/zod-openapi';
import { beforeEach, describe, expect, it } from 'vitest';

import { AUTH_HEADER_NAMES } from '../constants.js';
import { parseCredentialHeaders } from '../headers/credentials.js';
import { createAuthModule } from './factory.js';
import { SESSION_COOKIE_NAME, createInMemoryAuth, type InMemoryAuth } from '../testing/index.js';
import type { AuthHonoEnv } from '../middleware/session.js';

const BASE_PATH = '/app-api/auth';
const ORIGIN = 'http://localhost';

const SIGN_UP_BODY = { email: 'john.doe@example.com', password: 'SecurePassword123!', name: 'John Doe' };

interface Harness {
  app: OpenAPIHono<AuthHonoEnv>;
  auth: InMemoryAuth;
  request: (path: string, init?: RequestInit) => Promise<Response>;
}

async function createHarness(
  configure?: (auth: InMemoryAuth) => Parameters<typeof createAuthModule>[0],
): Promise<Harness> {
  const auth = await createInMemoryAuth();
  const module = createAuthModule(
    configure?.(auth) ?? {
      hooks: auth.hooks,
      config: auth.config,
      requestId: () => 'test-request-id',
    },
  );

  const app = new OpenAPIHono<AuthHonoEnv>();
  app.route(BASE_PATH, module.router);

  return {
    app,
    auth,
    request: (path, init) => app.request(new Request(`${ORIGIN}${BASE_PATH}${path}`, init)),
  };
}

function jsonInit(body: unknown, headers?: Record<string, string>): RequestInit {
  return {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  };
}

async function signUp(harness: Harness, body: unknown = SIGN_UP_BODY): Promise<Response> {
  return harness.request('/sign-up/email', jsonInit(body));
}

describe('sign up', () => {
  it('creates an account and returns 201 with the user', async () => {
    const harness = await createHarness();

    const response = await signUp(harness);

    expect(response.status).toBe(201);
    const body = await response.json();
    expect(body.user).toMatchObject({
      email: SIGN_UP_BODY.email,
      name: SIGN_UP_BODY.name,
      email_verified: false,
    });
    expect(body.token).toBeTypeOf('string');
  });

  it('emits the full credential header contract', async () => {
    const harness = await createHarness();

    const response = await signUp(harness);

    const credentials = parseCredentialHeaders(response.headers);
    expect(credentials).not.toBeNull();
    expect(credentials?.authToken.split('.')).toHaveLength(3);
    expect(credentials?.sessionToken).toBeTypeOf('string');
    expect(credentials?.authTokenExpiresInSeconds).toBeGreaterThan(0);
    expect(credentials?.sessionUpdateAgeSeconds).toBeGreaterThan(0);
  });

  it('maps a duplicate email onto 409 with the upstream code', async () => {
    const harness = await createHarness();
    await signUp(harness);

    const response = await signUp(harness);

    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ code: 'USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL' });
  });

  it.each([
    ['a malformed email', { ...SIGN_UP_BODY, email: 'not-an-email' }, 'email'],
    ['a short password', { ...SIGN_UP_BODY, password: 'short' }, 'password'],
    ['a single-word name', { ...SIGN_UP_BODY, name: 'John' }, 'name'],
    ['a padded name', { ...SIGN_UP_BODY, name: ' John Doe ' }, 'name'],
  ])('rejects %s with a field-level validation issue', async (_label, body, field) => {
    const harness = await createHarness();

    const response = await signUp(harness, body);

    expect(response.status).toBe(400);
    const payload = await response.json();
    expect(payload.code).toBe('INVALID_PAYLOAD');
    expect(payload.context.validations.some((issue: { path: string[] }) => issue.path.includes(field))).toBe(true);
  });

  it('puts the request id on the error response', async () => {
    const harness = await createHarness();

    const response = await signUp(harness, { ...SIGN_UP_BODY, email: 'nope' });

    expect(response.headers.get('Request-Id')).toBe('test-request-id');
  });
});

describe('sign in', () => {
  it('returns 200 and fresh credentials for valid credentials', async () => {
    const harness = await createHarness();
    await signUp(harness);

    const response = await harness.request(
      '/sign-in/email',
      jsonInit({ email: SIGN_UP_BODY.email, password: SIGN_UP_BODY.password }),
    );

    expect(response.status).toBe(200);
    expect(parseCredentialHeaders(response.headers)).not.toBeNull();
  });

  it('maps bad credentials onto 401', async () => {
    const harness = await createHarness();
    await signUp(harness);

    const response = await harness.request(
      '/sign-in/email',
      jsonInit({ email: SIGN_UP_BODY.email, password: 'WrongPassword1!' }),
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: 'INVALID_EMAIL_OR_PASSWORD' });
  });
});

describe('session', () => {
  let harness: Harness;
  let credentials: ReturnType<typeof parseCredentialHeaders>;

  beforeEach(async () => {
    harness = await createHarness();
    credentials = parseCredentialHeaders((await signUp(harness)).headers);
  });

  it('resolves a session from a bearer JWT', async () => {
    const response = await harness.request('/session', {
      headers: { Authorization: `Bearer ${credentials?.authToken}` },
    });

    expect(response.status).toBe(200);
    expect((await response.json()).user.email).toBe(SIGN_UP_BODY.email);
  });

  it('resolves a session from the session cookie', async () => {
    const response = await harness.request('/session', {
      headers: { Cookie: `${SESSION_COOKIE_NAME}=${credentials?.sessionToken}` },
    });

    expect(response.status).toBe(200);
    expect((await response.json()).user.email).toBe(SIGN_UP_BODY.email);
  });

  it('falls back to the session hook when the bearer token is opaque rather than a JWT', async () => {
    const response = await harness.request('/session', {
      headers: { Authorization: `Bearer ${credentials?.sessionToken}` },
    });

    expect(response.status).toBe(200);
  });

  it('rejects an unauthenticated request with 401', async () => {
    const response = await harness.request('/session');

    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: 'SESSION_NOT_FOUND' });
  });

  it('accepts a token that predates the session claims, falling back to exp and iat', async () => {
    const [sessionToken] = [...harness.auth.store.sessions.keys()];
    const legacyToken = await harness.auth.store.signToken(sessionToken ?? '', {
      claims: { sessionExpiresAt: undefined, sessionCreatedAt: undefined, sessionUpdatedAt: undefined },
    });

    const response = await harness.request('/session', { headers: { Authorization: `Bearer ${legacyToken}` } });

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.session.expires_at).toBeTypeOf('string');
    expect(body.session.created_at).toBeTypeOf('string');
  });

  it('rejects a JWT whose payload is missing required claims', async () => {
    const [sessionToken] = [...harness.auth.store.sessions.keys()];
    const brokenToken = await harness.auth.store.signToken(sessionToken ?? '', { claims: { email: 42 } });

    const response = await harness.request('/session', { headers: { Authorization: `Bearer ${brokenToken}` } });

    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: 'INVALID_JWT_PAYLOAD' });
  });
});

describe('token', () => {
  it('issues a token and re-emits the credential headers', async () => {
    const harness = await createHarness();
    const credentials = parseCredentialHeaders((await signUp(harness)).headers);

    const response = await harness.request('/token', {
      headers: { Authorization: `Bearer ${credentials?.sessionToken}` },
    });

    expect(response.status).toBe(200);
    expect((await response.json()).token.split('.')).toHaveLength(3);
    expect(response.headers.get(AUTH_HEADER_NAMES.sessionToken)).toBe(credentials?.sessionToken);
  });

  it('rejects an unknown session with 401', async () => {
    const harness = await createHarness();

    const response = await harness.request('/token', { headers: { Authorization: 'Bearer nope' } });

    expect(response.status).toBe(401);
  });
});

describe('sign out', () => {
  it('invalidates the session', async () => {
    const harness = await createHarness();
    const credentials = parseCredentialHeaders((await signUp(harness)).headers);
    const authHeaders = { Cookie: `${SESSION_COOKIE_NAME}=${credentials?.sessionToken}` };

    const signOutResponse = await harness.request('/sign-out', { method: 'POST', headers: authHeaders });
    expect(signOutResponse.status).toBe(200);

    const sessionResponse = await harness.request('/session', { headers: authHeaders });
    expect(sessionResponse.status).toBe(401);
  });
});

describe('jwks', () => {
  it('serves the document produced by the hook', async () => {
    const harness = await createHarness();

    const response = await harness.request('/jwks');

    expect(response.status).toBe(200);
    expect((await response.json()).keys).toHaveLength(1);
  });
});

describe('session extras', () => {
  const PreferencesSchema = z.object({
    preferred_currency: z.string(),
    has_preferred_currency_preference: z.boolean(),
  });

  async function createExtrasHarness(): Promise<Harness & { resolveCalls: string[] }> {
    const resolveCalls: string[] = [];
    const auth = await createInMemoryAuth();
    const module = createAuthModule({
      hooks: auth.hooks,
      config: auth.config,
      requestId: () => 'test-request-id',
      sessionExtras: {
        schema: PreferencesSchema,
        resolve: async (_c, { userId }) => {
          resolveCalls.push(userId);

          return { preferred_currency: 'EUR', has_preferred_currency_preference: true };
        },
      },
    });

    const app = new OpenAPIHono<AuthHonoEnv>();
    app.route(BASE_PATH, module.router);

    return {
      app,
      auth,
      resolveCalls,
      request: (path, init) => app.request(new Request(`${ORIGIN}${BASE_PATH}${path}`, init)),
    };
  }

  it('folds extras into the sign-up response', async () => {
    const harness = await createExtrasHarness();

    const body = await (await signUp(harness)).json();

    expect(body.user).toMatchObject({ preferred_currency: 'EUR', has_preferred_currency_preference: true });
  });

  it('folds extras into a JWT-authenticated session lookup', async () => {
    const harness = await createExtrasHarness();
    const credentials = parseCredentialHeaders((await signUp(harness)).headers);

    const response = await harness.request('/session', {
      headers: { Authorization: `Bearer ${credentials?.authToken}` },
    });

    expect(response.status).toBe(200);
    expect((await response.json()).user).toMatchObject({
      preferred_currency: 'EUR',
      has_preferred_currency_preference: true,
    });
  });

  it('folds extras into a cookie-authenticated session lookup', async () => {
    const harness = await createExtrasHarness();
    const credentials = parseCredentialHeaders((await signUp(harness)).headers);

    const response = await harness.request('/session', {
      headers: { Cookie: `${SESSION_COOKIE_NAME}=${credentials?.sessionToken}` },
    });

    expect((await response.json()).user).toMatchObject({ preferred_currency: 'EUR' });
  });

  it('resolves extras once per session lookup', async () => {
    const harness = await createExtrasHarness();
    const credentials = parseCredentialHeaders((await signUp(harness)).headers);
    harness.resolveCalls.length = 0;

    await harness.request('/session', { headers: { Authorization: `Bearer ${credentials?.authToken}` } });

    expect(harness.resolveCalls).toHaveLength(1);
  });

  it('publishes the extras in the OpenAPI document', async () => {
    const harness = await createExtrasHarness();
    harness.app.doc('/spec.json', { openapi: '3.1.0', info: { title: 'Test', version: '1' } });

    const spec = await (await harness.app.request(`${ORIGIN}/spec.json`)).json();

    expect(Object.keys(spec.components.schemas.UserSchema.properties)).toContain('preferred_currency');
  });
});

describe('extra routes', () => {
  it('mounts app-owned routes with the package schemas and middleware', async () => {
    const auth = await createInMemoryAuth();
    const module = createAuthModule({
      hooks: auth.hooks,
      config: auth.config,
      extraRoutes: (router, deps) => {
        router.get('/whoami', deps.requireSessionMiddleware, c => c.json({ id: deps.getSession(c).user.id }));
      },
    });

    const app = new OpenAPIHono<AuthHonoEnv>();
    app.route(BASE_PATH, module.router);
    const signUpResponse = await app.request(
      new Request(`${ORIGIN}${BASE_PATH}/sign-up/email`, jsonInit(SIGN_UP_BODY)),
    );
    const credentials = parseCredentialHeaders(signUpResponse.headers);

    const response = await app.request(
      new Request(`${ORIGIN}${BASE_PATH}/whoami`, {
        headers: { Authorization: `Bearer ${credentials?.authToken}` },
      }),
    );

    expect(response.status).toBe(200);
    expect((await response.json()).id).toBeTypeOf('string');
  });
});
