import { describe, expect, it } from 'vitest';

import { AUTH_HEADER_NAMES } from '../constants.js';
import { buildCredentialHeaders, parseCredentialHeaders } from './credentials.js';

const CREDENTIALS = {
  sessionToken: 'f21wcpz7Aokmlh2MB632MZpTgfruPc62',
  authToken: 'eyJhbGciOiJFZERTQSJ9.eyJzdWIiOiIxIn0.signature',
  authTokenExpiresInSeconds: 604800,
  sessionUpdateAgeSeconds: 86400,
};

describe('buildCredentialHeaders', () => {
  it('writes the four headers the Swift client reads', () => {
    const headers = buildCredentialHeaders(CREDENTIALS);

    expect(headers.get(AUTH_HEADER_NAMES.authToken)).toBe(CREDENTIALS.authToken);
    expect(headers.get(AUTH_HEADER_NAMES.authTokenExpiry)).toBe('604800');
    expect(headers.get(AUTH_HEADER_NAMES.sessionToken)).toBe(CREDENTIALS.sessionToken);
    expect(headers.get(AUTH_HEADER_NAMES.sessionUpdateAge)).toBe('86400');
    expect(headers.get('content-type')).toBe('application/json');
  });

  it('writes whole seconds so the client never has to parse a decimal', () => {
    const headers = buildCredentialHeaders({ ...CREDENTIALS, authTokenExpiresInSeconds: 604800.9 });

    expect(headers.get(AUTH_HEADER_NAMES.authTokenExpiry)).toBe('604800');
  });

  it('merges into existing headers rather than replacing them', () => {
    const existing = new Headers({ 'x-custom': 'kept' });

    const headers = buildCredentialHeaders(CREDENTIALS, existing);

    expect(headers.get('x-custom')).toBe('kept');
    expect(headers.get(AUTH_HEADER_NAMES.authToken)).toBe(CREDENTIALS.authToken);
  });
});

describe('parseCredentialHeaders', () => {
  it('round trips what buildCredentialHeaders wrote', () => {
    expect(parseCredentialHeaders(buildCredentialHeaders(CREDENTIALS))).toEqual(CREDENTIALS);
  });

  it.each([
    AUTH_HEADER_NAMES.authToken,
    AUTH_HEADER_NAMES.authTokenExpiry,
    AUTH_HEADER_NAMES.sessionToken,
    AUTH_HEADER_NAMES.sessionUpdateAge,
  ])('returns null when %s is missing', headerName => {
    const headers = buildCredentialHeaders(CREDENTIALS);
    headers.delete(headerName);

    expect(parseCredentialHeaders(headers)).toBeNull();
  });

  it('returns null when a numeric header is not a number', () => {
    const headers = buildCredentialHeaders(CREDENTIALS);
    headers.set(AUTH_HEADER_NAMES.authTokenExpiry, 'soon');

    expect(parseCredentialHeaders(headers)).toBeNull();
  });
});
