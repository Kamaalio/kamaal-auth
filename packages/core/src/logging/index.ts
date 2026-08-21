import type { CredentialKind } from '../utils/index.js';

export const AUTH_EVENTS = {
  signUpSucceeded: 'auth.sign_up.succeeded',
  signInSucceeded: 'auth.sign_in.succeeded',
  signOutSucceeded: 'auth.sign_out.succeeded',
  sessionLookup: 'auth.session.lookup',
  jwtVerification: 'auth.jwt.verification',
  tokenIssued: 'auth.token.issued',
  tokenRejected: 'auth.token.rejected',
} as const;

export type AuthEvent = (typeof AUTH_EVENTS)[keyof typeof AUTH_EVENTS];

/**
 * Every field an event in this package may log.
 *
 * One flat type rather than a per-event discriminated union: fields are optional, so any `AUTH_EVENTS` member can be
 * logged without per-event bookkeeping, while `event` staying a closed union and there being no index signature
 * still makes an unknown field or event name a compile error at every call site.
 */
export interface AuthLogFields {
  event: AuthEvent;
  outcome: 'failure' | 'success';
  route?: string;
  user_id?: string;
  error_code?: string;
  error_name?: string;
  credential_kind?: CredentialKind;
  status_code?: number;
  session_expires_in_s?: number;
  session_age_s?: number;
}

/**
 * The slice of a structured logger this package needs.
 *
 * Deliberately narrow so a pino logger satisfies it as-is: `info(fields, message)` already matches.
 */
export interface AuthLogger {
  info(fields: AuthLogFields, message: string): void;
  warn(fields: AuthLogFields, message: string): void;
  error(fields: AuthLogFields, message: string): void;
}

export const noopAuthLogger: AuthLogger = {
  info: () => {},
  warn: () => {},
  error: () => {},
};
