import type { AuthSessionResponse } from '@kamaalio/kamaal-auth-core';

export const AUTH_SESSION_CONTEXT_KEY = 'kamaalAuthSession';

/** Hono `Variables` contribution. Apps mixing this router into their own env should intersect with this. */
export interface AuthVariables {
  [AUTH_SESSION_CONTEXT_KEY]?: AuthSessionResponse;
}

export interface AuthHonoEnv {
  Variables: AuthVariables;
}
