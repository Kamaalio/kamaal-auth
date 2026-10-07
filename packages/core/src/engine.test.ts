import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AUTH_HEADER_NAMES, STATUS_CODES } from './constants.js';
import { createAuthEngine, type AuthEngine, type AuthOutcome } from './engine.js';
import { AuthError, type AuthErrorInfo } from './errors/index.js';
import { parseCredentialHeaders } from './headers/credentials.js';
import type { AuthCredentials, AuthHookContext } from './hooks/types.js';
import { AUTH_EVENTS, noopAuthLogger } from './logging/index.js';
import { createInMemoryAuth, type InMemoryAuth } from './testing/index.js';

/**
 * The engine driven with nothing but a `Request` — no server library in sight.
 *
 * This is the whole point of the core/adapter split, so it is worth asserting directly rather than only through the
 * Hono package's router suite.
 */
describe('createAuthEngine', () => {
  const SIGN_UP_INPUT = { email: 'ada@example.com', password: 'SecurePassword123!', name: 'Ada Lovelace' };

  let auth: InMemoryAuth;
  let engine: AuthEngine;

  beforeEach(async () => {
    auth = await createInMemoryAuth();
    engine = createAuthEngine({ hooks: auth.hooks, config: auth.config });
  });

  function contextOf(headers: Record<string, string> = {}): AuthHookContext {
    const request = new Request('https://kamaal-auth.test/app-api/auth/session', { headers });

    return { request, headers: request.headers, requestId: 'request-1', logger: noopAuthLogger, locals: undefined };
  }

  function expectOk<T>(outcome: AuthOutcome<T>): T {
    if (!outcome.ok) {
      throw new Error(`Expected an ok outcome, got ${outcome.error.code}`);
    }

    return outcome.value;
  }

  function expectError(outcome: AuthOutcome<unknown>): AuthError {
    if (outcome.ok) {
      throw new Error('Expected a failed outcome');
    }

    return outcome.error;
  }

  async function signUp(): Promise<AuthCredentials> {
    const payload = expectOk(await engine.signUp(contextOf(), SIGN_UP_INPUT));
    const credentials = parseCredentialHeaders(payload.headers ?? new Headers());
    if (credentials == null) {
      throw new Error('Sign up did not return credentials');
    }

    return credentials;
  }

  it('signs a user up and returns credentials on the shared header contract', async () => {
    const payload = expectOk(await engine.signUp(contextOf(), SIGN_UP_INPUT));

    expect(payload.status).toBe(STATUS_CODES.CREATED);
    expect(payload.headers?.get(AUTH_HEADER_NAMES.authToken)).toEqual(expect.any(String));
    expect(payload.body).toMatchObject({ user: { email: SIGN_UP_INPUT.email, name: SIGN_UP_INPUT.name } });
  });

  it('maps an upstream failure code onto its configured status', async () => {
    await signUp();

    const error = expectError(await engine.signUp(contextOf(), SIGN_UP_INPUT));

    expect(error).toBeInstanceOf(AuthError);
    expect(error.code).toBe('USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL');
    expect(error.status).toBe(STATUS_CODES.CONFLICT);
    expect(error.getResponse().status).toBe(STATUS_CODES.CONFLICT);
  });

  it('resolves a session from the issued bearer JWT', async () => {
    const { authToken } = await signUp();

    const session = expectOk(await engine.resolveSession(contextOf({ Authorization: `Bearer ${authToken}` })));

    expect(session.user.email).toBe(SIGN_UP_INPUT.email);
    expect(engine.sessionResponse(session)).toEqual({ status: STATUS_CODES.OK, body: session });
  });

  it('refuses to resolve a session for an unauthenticated caller', async () => {
    const error = expectError(await engine.resolveSession(contextOf()));

    expect(error.code).toBe('SESSION_NOT_FOUND');
    expect(error.status).toBe(STATUS_CODES.UNAUTHORIZED);
  });

  it('refreshes the auth token for a session token', async () => {
    const { sessionToken } = await signUp();

    const payload = expectOk(await engine.issueToken(contextOf({ Authorization: `Bearer ${sessionToken}` })));

    expect(payload.status).toBe(STATUS_CODES.OK);
    expect(payload.headers?.get(AUTH_HEADER_NAMES.sessionToken)).toBe(sessionToken);
    expect(payload.body).toMatchObject({ token: expect.any(String) });
  });

  it.each([
    ['issueToken', AUTH_EVENTS.tokenFailed],
    ['resolveSession', AUTH_EVENTS.sessionLookup],
  ] as const)(
    'logs %s provider failures at error severity without credentials or upstream messages',
    async (operation, event) => {
      const upstreamMessage = 'Sensitive upstream detail';
      const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
      const providerFailure = { ok: false, error: { code: 'PROVIDER_UNAVAILABLE', message: upstreamMessage } } as const;
      vi.spyOn(auth.hooks, 'issueToken').mockResolvedValue(providerFailure);
      vi.spyOn(auth.hooks, 'getSession').mockResolvedValue(providerFailure);

      const error = expectError(
        await engine[operation]({ ...contextOf({ Authorization: 'Bearer private-session-token' }), logger }),
      );

      expect(error.status).toBe(500);
      expect(logger.error).toHaveBeenCalledWith(
        {
          event,
          outcome: 'failure',
          error_code: 'PROVIDER_UNAVAILABLE',
          credential_kind: 'bearer_opaque',
          status_code: 500,
        },
        expect.any(String),
      );
      expect(logger.warn).not.toHaveBeenCalled();
      expect(JSON.stringify(logger.error.mock.calls)).not.toContain('private-session-token');
      expect(JSON.stringify(logger.error.mock.calls)).not.toContain(upstreamMessage);
    },
  );

  it.each(['issueToken', 'resolveSession'] as const)(
    'uses the configured renderer and status override for %s failures',
    async operation => {
      const providerFailure = {
        ok: false,
        error: { code: 'ACCESS_DENIED', message: 'Forbidden', headers: new Headers({ 'X-Provider': 'test' }) },
      } as const;
      vi.spyOn(auth.hooks, 'issueToken').mockResolvedValue(providerFailure);
      vi.spyOn(auth.hooks, 'getSession').mockResolvedValue(providerFailure);
      const render = vi.fn((info: AuthErrorInfo) => new Response('custom envelope', { status: info.status }));
      const customEngine = createAuthEngine({
        hooks: auth.hooks,
        config: { ...auth.config, errorStatuses: { ACCESS_DENIED: 403 }, errorResponse: render },
      });

      const error = expectError(await customEngine[operation](contextOf()));

      expect(error.status).toBe(403);
      await expect(error.getResponse().text()).resolves.toBe('custom envelope');
      expect(render).toHaveBeenCalledWith({
        status: 403,
        code: 'ACCESS_DENIED',
        message: 'Forbidden',
        requestId: 'request-1',
        headers: expect.any(Headers),
      });
    },
  );

  it('ends the session on sign out, and stops issuing tokens for it', async () => {
    const { sessionToken } = await signUp();
    const authenticated = contextOf({ Authorization: `Bearer ${sessionToken}` });

    const signedOut = expectOk(await engine.signOut(authenticated));

    expect(signedOut.status).toBe(STATUS_CODES.OK);
    expect(expectError(await engine.issueToken(authenticated)).code).toBe('SESSION_NOT_FOUND');
  });

  it('serves the JWKS document straight from the hook', async () => {
    const response = await engine.jwks(contextOf());

    await expect(response.json()).resolves.toEqual({ keys: [auth.store.publicJwk] });
  });
});
