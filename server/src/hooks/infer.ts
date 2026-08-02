import type {
  AuthHookResult,
  AuthHooks,
  AuthSession,
  AuthUser,
  EmailPasswordSignInInput,
  EmailPasswordSignUpInput,
} from './types.js';

/**
 * Identity helper that pins a hooks object to its literal shape.
 *
 * Everything the router knows about a consumer's user and payload types is inferred back out of the object passed
 * here, which is why the package needs no types from the underlying auth library.
 */
export function defineAuthHooks<
  TUser extends AuthUser,
  TSignUpInput extends EmailPasswordSignUpInput,
  TSignInInput extends EmailPasswordSignInInput,
  H extends AuthHooks<TUser, TSignUpInput, TSignInInput>,
>(hooks: H): H {
  return hooks;
}

type SuccessValue<T> = Extract<T, { ok: true }> extends AuthHookResult<infer V> ? V : never;

type AwaitedSuccess<T> = SuccessValue<Awaited<T>>;

export type AuthUserOf<H> = H extends { getSession: (c: never) => infer R }
  ? NonNullable<AwaitedSuccess<R>> extends { user: infer U }
    ? U
    : never
  : never;

export type AuthSessionOf<H> = H extends { getSession: (c: never) => infer R }
  ? NonNullable<AwaitedSuccess<R>> extends { session: infer S }
    ? S
    : AuthSession
  : AuthSession;

export type SignUpInputOf<H> = H extends { signUp: (c: never, input: infer I) => unknown } ? I : never;

export type SignInInputOf<H> = H extends { signIn: (c: never, input: infer I) => unknown } ? I : never;

export type CredentialsOf<H> = H extends { signIn: (c: never, input: never) => infer R }
  ? AwaitedSuccess<R> extends { credentials: infer C }
    ? C
    : never
  : never;
