import type { AuthError } from '@kamaalio/kamaal-auth-core';
import { HTTPException } from 'hono/http-exception';

/**
 * A core {@link AuthError}, dressed as the exception Hono unwinds on.
 *
 * Subclassing `HTTPException` is what lets an app's own `onError` handler fall through to
 * `err.getResponse()` without knowing anything about this package.
 */
export class AuthHttpError extends HTTPException {
  readonly code: string;
  readonly context?: unknown;

  constructor(error: AuthError) {
    super(error.status, { res: error.getResponse(), message: error.message });
    this.name = 'AuthHttpError';
    this.code = error.code;
    this.context = error.context;
  }
}
