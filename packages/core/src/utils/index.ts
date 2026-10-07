export function toISO8601String(date: Date): string {
  return date.toISOString();
}

export function getValueFromSetCookie(headers: Headers, key: string): string | null {
  const setCookie = headers.get('set-cookie');
  if (!setCookie) {
    return null;
  }

  const match = setCookie.match(new RegExp(`${key}=([^;]+)`));
  if (!match) {
    return null;
  }

  return match[1] ?? null;
}

export type CredentialKind = 'bearer_jwt' | 'bearer_opaque' | 'cookie' | 'none';

/**
 * Classifies credential shape for routing and log correlation. Does not validate or authorize a credential.
 */
export function getCredentialKind(headers: Headers): CredentialKind {
  const authorization = headers.get('Authorization');
  if (authorization?.startsWith('Bearer ')) {
    return authorization.slice(7).split('.').length === 3 ? 'bearer_jwt' : 'bearer_opaque';
  }

  return headers.get('Cookie') == null ? 'none' : 'cookie';
}

export function bearerTokenFrom(headers: Headers): string | null {
  const authorization = headers.get('Authorization');
  if (authorization == null) {
    return null;
  }
  if (!authorization.startsWith('Bearer ')) {
    return null;
  }

  return authorization.slice(7);
}

/**
 * Names an unexpected caught value for log correlation, e.g. `Error`, `TypeError`, `String`, `Object`.
 */
export function describeErrorKind<T>(error: T): string {
  if (error instanceof Error) {
    return error.name;
  }

  return Object.prototype.toString.call(error).slice('[object '.length, -1);
}
