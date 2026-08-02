export type AuthLogFields = Record<string, unknown>;

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

export const AUTH_EVENTS = {
  signUpSucceeded: 'auth.sign_up.succeeded',
  signInSucceeded: 'auth.sign_in.succeeded',
  signOutSucceeded: 'auth.sign_out.succeeded',
  sessionLookup: 'auth.session.lookup',
  jwtVerification: 'auth.jwt.verification',
  tokenIssued: 'auth.token.issued',
  tokenRejected: 'auth.token.rejected',
} as const;

export const noopAuthLogger: AuthLogger = {
  info: () => {},
  warn: () => {},
  error: () => {},
};
