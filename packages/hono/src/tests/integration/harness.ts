import type { AuthConfig } from '@kamaalio/kamaal-auth-core';
import { StandardOpenAPIHono } from '@kamaalio/hono-standard-openapi';

import { createAuthModule } from '../../factory.js';
import type { AuthHonoEnv } from '../../env.js';
import {
  BASE_PATH,
  ISSUER,
  JWT_EXPIRES_IN_SECONDS,
  SESSION_EXPIRES_IN_SECONDS,
  SESSION_UPDATE_AGE_SECONDS,
  type AuthLocals,
  type BetterAuthTestInstance,
  betterAuthHooks,
  createBetterAuthTestInstance,
} from './better-auth-harness.js';

export interface IntegrationHarness {
  app: StandardOpenAPIHono<AuthHonoEnv>;
  instance: BetterAuthTestInstance;
  request: (path: string, init?: RequestInit) => Promise<Response>;
  close: () => void;
}

/** Mounts kamaal-auth against a real better-auth instance backed by an in-memory SQLite database. */
export async function createIntegrationHarness(): Promise<IntegrationHarness> {
  const instance = await createBetterAuthTestInstance();

  const config: AuthConfig = {
    basePath: BASE_PATH,
    trustedOrigins: ['kamaal-auth-test://'],
    session: { expiresInSeconds: SESSION_EXPIRES_IN_SECONDS, updateAgeSeconds: SESSION_UPDATE_AGE_SECONDS },
    jwt: {
      issuer: ISSUER,
      audience: ISSUER,
      expiresInSeconds: JWT_EXPIRES_IN_SECONDS,
      jwksUrl: new URL(`${BASE_PATH}/jwks`, ISSUER),
    },
    isTest: true,
  };

  const module = createAuthModule({
    hooks: betterAuthHooks,
    config,
    locals: (): AuthLocals => ({ auth: instance.auth, db: instance.db }),
    requestId: () => 'test-request-id',
  });

  const app = new StandardOpenAPIHono<AuthHonoEnv>();
  app.route(BASE_PATH, module.router);

  return {
    app,
    instance,
    request: (path, init) => Promise.resolve(app.request(new Request(`${ISSUER}${BASE_PATH}${path}`, init))),
    close: instance.close,
  };
}
