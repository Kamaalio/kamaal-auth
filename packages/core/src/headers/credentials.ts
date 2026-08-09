import { AUTH_HEADER_NAMES } from '../constants.js';
import type { AuthCredentials } from '../hooks/types.js';

/**
 * Serializes credentials into the response headers a native client persists.
 *
 * The Swift `KamaalAuthClient` package parses exactly these four headers, so this function and its Swift counterpart
 * are two halves of one contract.
 */
export function buildCredentialHeaders(credentials: AuthCredentials, into?: Headers): Headers {
  const headers = into ?? new Headers();
  headers.set('content-type', 'application/json');
  headers.set(AUTH_HEADER_NAMES.authToken, credentials.authToken);
  headers.set(AUTH_HEADER_NAMES.authTokenExpiry, Math.floor(credentials.authTokenExpiresInSeconds).toString());
  headers.set(AUTH_HEADER_NAMES.sessionToken, credentials.sessionToken);
  headers.set(AUTH_HEADER_NAMES.sessionUpdateAge, Math.floor(credentials.sessionUpdateAgeSeconds).toString());

  return headers;
}

/** Inverse of {@link buildCredentialHeaders}. Returns `null` when any required header is missing or malformed. */
export function parseCredentialHeaders(headers: Headers): AuthCredentials | null {
  const authToken = headers.get(AUTH_HEADER_NAMES.authToken);
  const sessionToken = headers.get(AUTH_HEADER_NAMES.sessionToken);
  const authTokenExpiry = toFiniteNumber(headers.get(AUTH_HEADER_NAMES.authTokenExpiry));
  const sessionUpdateAge = toFiniteNumber(headers.get(AUTH_HEADER_NAMES.sessionUpdateAge));
  if (authToken == null || sessionToken == null || authTokenExpiry == null || sessionUpdateAge == null) return null;

  return {
    authToken,
    sessionToken,
    authTokenExpiresInSeconds: authTokenExpiry,
    sessionUpdateAgeSeconds: sessionUpdateAge,
  };
}

function toFiniteNumber(value: string | null): number | null {
  if (value == null) return null;

  const parsed = Number(value);

  return Number.isFinite(parsed) ? parsed : null;
}
