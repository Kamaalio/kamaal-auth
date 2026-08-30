import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { createIntegrationHarness, type IntegrationHarness } from './harness.js';
import { jsonInit } from './http.js';

describe('payload validation (real better-auth + SQLite)', () => {
  let harness: IntegrationHarness;

  beforeEach(async () => {
    harness = await createIntegrationHarness();
  });

  afterEach(() => {
    harness.close();
  });

  it('rejects an empty sign-up body before it ever reaches better-auth', async () => {
    const response = await harness.request('/sign-up/email', jsonInit({}));

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.code).toBe('INVALID_PAYLOAD');
    const persistedUsers = harness.instance.db.prepare('SELECT id FROM user').all();
    expect(persistedUsers).toHaveLength(0);
  });

  it('rejects a malformed email', async () => {
    const response = await harness.request(
      '/sign-up/email',
      jsonInit({ email: 'not-an-email', password: 'SecurePassword123!', name: 'Test User' }),
    );

    expect(response.status).toBe(400);
  });

  it('rejects a short password', async () => {
    const response = await harness.request(
      '/sign-up/email',
      jsonInit({ email: 'test@example.com', password: 'short', name: 'Test User' }),
    );

    expect(response.status).toBe(400);
  });
});
