import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { SESSION_COOKIE_NAME } from './better-auth-harness.js';
import { createIntegrationHarness, type IntegrationHarness } from './harness.js';
import { jsonInit, validSignUpPayload } from './http.js';

describe('sign-out (real better-auth + SQLite)', () => {
  let harness: IntegrationHarness;

  beforeEach(async () => {
    harness = await createIntegrationHarness();
  });

  afterEach(() => {
    harness.close();
  });

  it('ends a cookie session and invalidates it for future requests', async () => {
    const signUpResponse = await harness.request('/sign-up/email', jsonInit(validSignUpPayload()));
    const sessionToken = signUpResponse.headers.get('set-session-token') ?? '';

    const signOutResponse = await harness.request('/sign-out', {
      method: 'POST',
      headers: { Cookie: `${SESSION_COOKIE_NAME}=${sessionToken}` },
    });

    expect(signOutResponse.status).toBe(200);
    expect(signOutResponse.headers.get('set-cookie')).toContain(`${SESSION_COOKIE_NAME}=`);

    const sessionResponse = await harness.request('/session', {
      headers: { Cookie: `${SESSION_COOKIE_NAME}=${sessionToken}` },
    });
    expect(sessionResponse.status).toBe(401);
  });

  it('succeeds with no active session', async () => {
    const response = await harness.request('/sign-out', { method: 'POST' });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({});
  });
});
