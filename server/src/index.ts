export {
  AUTH_HEADER_NAMES,
  AUTH_OPENAPI_TAG,
  AUTH_ROUTE_PATHS,
  MIME_TYPES,
  ONE_DAY_IN_SECONDS,
  STATUS_CODES,
  type StatusCode,
} from './constants.js';

export type { AuthConfig, AuthJwtConfig, AuthSessionConfig } from './config.js';

export {
  AUTH_ERROR_STATUSES,
  AuthHttpError,
  SessionNotFound,
  defaultAuthErrorRenderer,
  type AuthErrorInfo,
  type AuthErrorRenderer,
} from './errors/index.js';

export { buildCredentialHeaders, parseCredentialHeaders } from './headers/credentials.js';

export {
  authHookFailure,
  authHookSuccess,
  type AuthCredentials,
  type AuthHookContext,
  type AuthHookFailure,
  type AuthHookResult,
  type AuthHooks,
  type AuthSession,
  type AuthUser,
  type AuthenticatedResult,
  type EmailPasswordSignInInput,
  type EmailPasswordSignUpInput,
  type IssuedToken,
  type SessionLookupResult,
  type SignOutResult,
  type VerificationKeys,
} from './hooks/types.js';

export {
  defineAuthHooks,
  type AuthSessionOf,
  type AuthUserOf,
  type CredentialsOf,
  type SignInInputOf,
  type SignUpInputOf,
} from './hooks/infer.js';

export { AUTH_EVENTS, noopAuthLogger, type AuthLogFields, type AuthLogger } from './logging/index.js';

export {
  AUTH_SESSION_CONTEXT_KEY,
  type AuthHonoEnv,
  type AuthSessionResponse,
  type AuthVariables,
} from './middleware/session.js';

export {
  EmailPasswordSignInSchema,
  EmailPasswordSignUpSchema,
  SignOutResponseSchema,
  type EmailPasswordSignIn,
  type EmailPasswordSignUp,
  type SignOutResponse,
} from './schemas/payloads.js';

export { AuthenticationHeaders, TokenHeaders } from './schemas/headers.js';

export { DefaultErrorResponseSchema, DefaultValidationErrorResponseSchema } from './schemas/errors.js';

export { buildAuthSchemas, type AuthSchemas, type BaseUser, type SessionResponseOf } from './schemas/responses.js';

export {
  createAuthModule,
  type AuthModule,
  type AuthRouteDeps,
  type CreateAuthModuleOptions,
  type SessionExtras,
} from './router/factory.js';

export {
  bearerTokenFrom,
  getCredentialKind,
  getValueFromSetCookie,
  toISO8601String,
  type CredentialKind,
} from './utils/index.js';
