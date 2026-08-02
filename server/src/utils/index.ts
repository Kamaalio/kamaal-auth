export function toISO8601String(date: Date): string {
  return date.toISOString();
}

export function getValueFromSetCookie(headers: Headers, key: string): string | null {
  const setCookie = headers.get('set-cookie');
  if (!setCookie) return null;

  const match = setCookie.match(new RegExp(`${key}=([^;]+)`));
  if (!match) return null;

  return match[1] ?? null;
}

export type CredentialKind = 'bearer_jwt' | 'bearer_opaque' | 'cookie' | 'none';

/**
 * Classifies how a request presented its credentials, for log correlation only. Never used for authorization.
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
  if (authorization == null) return null;
  if (!authorization.startsWith('Bearer ')) return null;

  return authorization.slice(7);
}
