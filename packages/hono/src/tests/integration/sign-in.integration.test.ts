import assert from 'node:assert/strict';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createIntegrationHarness, type IntegrationHarness } from './harness.js';
import { jsonInit, validSignUpPayload } from './http.js';

const UserRowSchema = z.object({ id: z.string() });

describe('sign-in (real better-auth + SQLite)', () => {
  let harness: IntegrationHarness;

  beforeEach(async () => {
    harness = await createIntegrationHarness();
  });

  afterEach(() => {
    harness.close();
  });

  it('returns fresh credentials for correct credentials', async () => {
    const signUp = validSignUpPayload();
    await harness.request('/sign-up/email', jsonInit(signUp));

    const response = await harness.request(
      '/sign-in/email',
      jsonInit({ email: signUp.email, password: signUp.password }),
    );

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.user.email).toBe(signUp.email);
    expect(response.headers.get('set-auth-token')).toBeTruthy();
  });

  it('mints a session distinct from the one sign-up created', async () => {
    const signUp = validSignUpPayload();
    const signUpResponse = await harness.request('/sign-up/email', jsonInit(signUp));
    const signUpSessionToken = signUpResponse.headers.get('set-session-token');

    const signInResponse = await harness.request(
      '/sign-in/email',
      jsonInit({ email: signUp.email, password: signUp.password }),
    );

    expect(signInResponse.headers.get('set-session-token')).not.toBe(signUpSessionToken);
    const userRow = harness.instance.db.prepare('SELECT id FROM user WHERE email = ?').get(signUp.email);
    assert(userRow != null, 'expected sign-up to persist a user row');
    const persistedUser = UserRowSchema.parse(userRow);
    const sessions = harness.instance.db.prepare('SELECT id FROM session WHERE userId = ?').all(persistedUser.id);
    expect(sessions).toHaveLength(2);
  });

  it('rejects an unknown email with 401', async () => {
    const response = await harness.request(
      '/sign-in/email',
      jsonInit({ email: 'nobody@example.com', password: 'SecurePassword123!' }),
    );

    expect(response.status).toBe(401);
    const body = await response.json();
    expect(body.code).toBe('INVALID_EMAIL_OR_PASSWORD');
  });

  it('rejects a wrong password with 401', async () => {
    const signUp = validSignUpPayload();
    await harness.request('/sign-up/email', jsonInit(signUp));

    const response = await harness.request(
      '/sign-in/email',
      jsonInit({ email: signUp.email, password: 'WrongPassword1!' }),
    );

    expect(response.status).toBe(401);
    const body = await response.json();
    expect(body.code).toBe('INVALID_EMAIL_OR_PASSWORD');
  });
});
