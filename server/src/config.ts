import type { z } from '@hono/zod-openapi';

import type { StatusCode } from './constants.js';
import type { AuthErrorRenderer } from './errors/index.js';

export interface AuthJwtConfig {
  issuer: string;
  audience: string;
  /** Fallback lifetime used when an issued token carries no `exp` claim. */
  expiresInSeconds: number;
  jwksUrl: URL;
}

export interface AuthSessionConfig {
  expiresInSeconds: number;
  updateAgeSeconds: number;
}

export interface AuthConfig {
  /** Where the router is mounted, e.g. `/app-api/auth`. Used for log correlation, not for routing. */
  basePath: string;
  /** Origins the native clients send, e.g. `['myapp://']`. Surfaced in the OpenAPI description. */
  trustedOrigins: readonly string[];
  session: AuthSessionConfig;
  jwt: AuthJwtConfig;
  /**
   * Verify JWTs against `hooks.verificationKeys` instead of the remote JWKS set.
   *
   * Exists because a test suite has no reachable JWKS endpoint. Never enable in production.
   */
  isTest?: boolean;
  openApi?: {
    tag?: string;
    securitySchemeName?: string;
  };
  /** Renders package errors in the app's own envelope. Defaults to `{ message, code, context }` + a Request-Id header. */
  errorResponse?: AuthErrorRenderer;
  /** Extends or overrides the upstream-code to HTTP-status table. */
  errorStatuses?: Record<string, StatusCode>;
  /**
   * Error schemas used in the OpenAPI document.
   *
   * Pass the app's own schemas when it already registers components named `ErrorResponse` or
   * `ValidationErrorResponse`, otherwise the same component name gets registered twice.
   */
  errorSchemas?: {
    error?: z.ZodType;
    validation?: z.ZodType;
  };
}
