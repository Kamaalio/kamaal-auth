import { decodeJwt } from 'jose';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { createIntegrationHarness, type IntegrationHarness } from './harness.js';
import { jsonInit, validSignUpPayload } from './http.js';

describe('token (real better-auth + SQLite)', () => {
  let harness: IntegrationHarness;

  beforeEach(async () => {
    harness = await createIntegrationHarness();
  });

  afterEach(() => {
    harness.close();
  });

  it('issues a fresh JWT for an opaque bearer session token', async () => {
    const signUpResponse = await harness.request('/sign-up/email', jsonInit(validSignUpPayload()));
    const sessionToken = signUpResponse.headers.get('set-session-token') ?? '';
    const signUpBody = await signUpResponse.json();

    const response = await harness.request('/token', { headers: { Authorization: `Bearer ${sessionToken}` } });

    expect(response.status).toBe(200);
    const body = await response.json();
    const decoded = decodeJwt(body.token);
    expect(decoded.sub).toBe(signUpBody.user.id);
    expect(response.headers.get('set-session-token')).toBe(sessionToken);
  });

  it('rejects an unknown session with 401', async () => {
    const response = await harness.request('/token', { headers: { Authorization: 'Bearer nope' } });

    expect(response.status).toBe(401);
  });
});
