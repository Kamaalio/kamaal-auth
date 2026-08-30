import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createIntegrationHarness, type IntegrationHarness } from './harness.js';

const JwksRowSchema = z.object({ id: z.string() });

describe('jwks (real better-auth + SQLite)', () => {
  let harness: IntegrationHarness;

  beforeEach(async () => {
    harness = await createIntegrationHarness();
  });

  afterEach(() => {
    harness.close();
  });

  it("serves better-auth's own JWKS document", async () => {
    const response = await harness.request('/jwks');

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.keys).toHaveLength(1);
    expect(body.keys[0].kty).toBeTruthy();

    const persistedKeys = harness.instance.db
      .prepare('SELECT id FROM jwks')
      .all()
      .map(row => JwksRowSchema.parse(row));
    expect(body.keys[0].kid).toBe(persistedKeys[0]?.id);
  });
});
