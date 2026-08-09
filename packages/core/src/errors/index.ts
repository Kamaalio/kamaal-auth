import { DEFAULT_REQUEST_ID_HEADER_NAME, STATUS_CODES, type StatusCode } from '../constants.js';

/**
 * Maps an upstream auth error code onto an HTTP status.
 *
 * Codes are plain strings so the package never has to import an auth library's error enum. Consumers extend or
 * override this through `AuthConfig.errorStatuses`.
 */
export const AUTH_ERROR_STATUSES: Record<string, StatusCode> = {
  USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL: STATUS_CODES.CONFLICT,
  INVALID_EMAIL_OR_PASSWORD: STATUS_CODES.UNAUTHORIZED,
  MISSING_OR_NULL_ORIGIN: STATUS_CODES.UNAUTHORIZED,
};

export interface AuthErrorInfo {
  status: StatusCode;
  code: string;
  message: string;
  context?: unknown;
  headers?: Headers;
  requestId?: string;
}

export type AuthErrorRenderer = (info: AuthErrorInfo) => Response;

export function defaultAuthErrorRenderer(info: AuthErrorInfo): Response {
  const headers = info.headers ?? new Headers();
  headers.set('Content-Type', 'application/json');
  if (info.requestId != null) {
    headers.set(DEFAULT_REQUEST_ID_HEADER_NAME, info.requestId);
  }

  const body = JSON.stringify({ message: info.message, code: info.code, context: info.context });

  return new Response(body, { status: info.status, headers });
}

/**
 * An expected auth failure, carrying its own already-rendered response.
 *
 * Deliberately a plain `Error`: a server adapter re-wraps it in whatever exception type its framework unwinds on
 * (`AuthHttpError` in the Hono package), rather than this package picking a framework by picking a base class.
 */
export class AuthError extends Error {
  readonly status: StatusCode;
  readonly code: string;
  readonly context?: unknown;

  readonly #response: Response;

  constructor(info: AuthErrorInfo, render: AuthErrorRenderer = defaultAuthErrorRenderer) {
    super(info.message);
    this.name = 'AuthError';
    this.status = info.status;
    this.code = info.code;
    this.context = info.context;
    this.#response = render(info);
  }

  getResponse(): Response {
    return this.#response;
  }
}

export class SessionNotFound extends AuthError {
  constructor(options?: { requestId?: string; render?: AuthErrorRenderer }) {
    super(
      {
        status: STATUS_CODES.UNAUTHORIZED,
        code: 'SESSION_NOT_FOUND',
        message: 'Unauthorized',
        requestId: options?.requestId,
      },
      options?.render,
    );
    this.name = 'SessionNotFound';
  }
}
