import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { SESSION_COOKIE_NAME } from './better-auth-harness.js';
import { createIntegrationHarness, type IntegrationHarness } from './harness.js';
import { jsonInit, validSignUpPayload } from './http.js';

/** better-auth's `session.token` column stores only the id portion of a signed `id.signature` cookie value. */
function rawSessionId(signedSessionToken: string): string {
  return signedSessionToken.split('.')[0] ?? signedSessionToken;
}

async function signUp(harness: IntegrationHarness) {
  const payload = validSignUpPayload();
  const response = await harness.request('/sign-up/email', jsonInit(payload));

  return {
    payload,
    authToken: response.headers.get('set-auth-token') ?? '',
    sessionToken: response.headers.get('set-session-token') ?? '',
  };
}

describe('session (real better-auth + SQLite)', () => {
  let harness: IntegrationHarness;

  beforeEach(async () => {
    harness = await createIntegrationHarness();
  });

  afterEach(() => {
    harness.close();
  });

  it('resolves a session from the bearer JWT, verified against the real JWKS better-auth persisted', async () => {
    const { payload, authToken } = await signUp(harness);

    const response = await harness.request('/session', { headers: { Authorization: `Bearer ${authToken}` } });

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.user.email).toBe(payload.email);
  });

  it('resolves a session from the session cookie, falling back to the getSession hook', async () => {
    const { payload, sessionToken } = await signUp(harness);

    const response = await harness.request('/session', {
      headers: { Cookie: `${SESSION_COOKIE_NAME}=${sessionToken}` },
    });

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.user.email).toBe(payload.email);
  });

  it('rejects an unauthenticated request with 401', async () => {
    const response = await harness.request('/session');

    expect(response.status).toBe(401);
    const body = await response.json();
    expect(body.code).toBe('SESSION_NOT_FOUND');
  });

  it('resolves a still-valid JWT even after its underlying session row is gone, since JWT auth never re-checks it', async () => {
    const { payload, authToken, sessionToken } = await signUp(harness);
    harness.instance.db.prepare('DELETE FROM session WHERE token = ?').run(rawSessionId(sessionToken));

    const response = await harness.request('/session', { headers: { Authorization: `Bearer ${authToken}` } });

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.user.email).toBe(payload.email);
  });

  it('rejects a cookie session once the underlying session row is gone, since that path re-checks it', async () => {
    const { sessionToken } = await signUp(harness);
    harness.instance.db.prepare('DELETE FROM session WHERE token = ?').run(rawSessionId(sessionToken));

    const response = await harness.request('/session', {
      headers: { Cookie: `${SESSION_COOKIE_NAME}=${sessionToken}` },
    });

    expect(response.status).toBe(401);
  });
});
