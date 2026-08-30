import assert from 'node:assert/strict';

import { decodeJwt } from 'jose';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createIntegrationHarness, type IntegrationHarness } from './harness.js';
import { jsonInit, validSignUpPayload } from './http.js';

const UserRowSchema = z.object({ id: z.string(), email: z.string(), name: z.string() });
const AccountRowSchema = z.object({ password: z.string() });

describe('sign-up (real better-auth + SQLite)', () => {
  let harness: IntegrationHarness;

  beforeEach(async () => {
    harness = await createIntegrationHarness();
  });

  afterEach(() => {
    harness.close();
  });

  it('persists a real user row and returns working credentials', async () => {
    const payload = validSignUpPayload();

    const response = await harness.request('/sign-up/email', jsonInit(payload));

    expect(response.status).toBe(201);
    const body = await response.json();
    expect(body.user.email).toBe(payload.email);
    expect(body.token).toBeTypeOf('string');

    const userRow = harness.instance.db.prepare('SELECT id, email, name FROM user WHERE email = ?').get(payload.email);
    assert(userRow != null, 'expected sign-up to persist a user row');
    const persistedUser = UserRowSchema.parse(userRow);
    expect(persistedUser.email).toBe(payload.email);
    expect(persistedUser.name).toBe(payload.name);

    const accountRows = harness.instance.db
      .prepare('SELECT password FROM account WHERE userId = ?')
      .all(persistedUser.id)
      .map(row => AccountRowSchema.parse(row));
    expect(accountRows).toHaveLength(1);
    expect(accountRows[0]?.password).toBeTruthy();
    expect(accountRows[0]?.password).not.toBe(payload.password);

    const authToken = response.headers.get('set-auth-token');
    expect(authToken).toBeTruthy();
    const decoded = decodeJwt(authToken ?? '');
    expect(decoded.sub).toBe(persistedUser.id);
    expect(Number(response.headers.get('set-auth-token-expiry'))).toBeGreaterThan(0);
  });

  it('rejects a duplicate email without duplicating persisted rows', async () => {
    const payload = validSignUpPayload();
    await harness.request('/sign-up/email', jsonInit(payload));

    const response = await harness.request('/sign-up/email', jsonInit(payload));

    expect(response.status).toBe(409);
    const body = await response.json();
    expect(body.code).toBe('USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL');
    const persistedUsers = harness.instance.db.prepare('SELECT id FROM user WHERE email = ?').all(payload.email);
    expect(persistedUsers).toHaveLength(1);
  });
});
