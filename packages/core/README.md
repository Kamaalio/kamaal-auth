# @kamaalio/kamaal-auth-core

Framework-agnostic authentication engine for applications that provide their own auth implementation. It owns the HTTP-neutral auth contract: hook types, request validation, session resolution, JWT verification, credential headers, error mapping, and OpenAPI schemas.

It does not depend on an auth library, a server framework, or a database. Use this package directly when you are building a server adapter or need to run the engine against plain `Request` objects. Hono applications should normally install [`@kamaalio/kamaal-auth-hono`](https://www.npmjs.com/package/@kamaalio/kamaal-auth-hono), which re-exports this package.

## Install

```sh
npm install @kamaalio/kamaal-auth-core zod jose @asteasolutions/zod-to-openapi
```

Node.js 24 or newer is required.

## Define your hooks

Your application implements the operations that talk to its auth library and database. Hooks return `authHookSuccess` or `authHookFailure`, so the engine can turn known upstream failures into consistent HTTP responses without owning the underlying auth implementation.

```ts
import { authHookFailure, authHookSuccess, createAuthEngine, defineAuthHooks } from '@kamaalio/kamaal-auth-core';

const hooks = defineAuthHooks({
  async signUp(c, input) {
    const result = await appAuth.signUp(c.request, input);
    return result.ok ? authHookSuccess(result.value) : authHookFailure(result.error);
  },
  async signIn(c, input) {
    const result = await appAuth.signIn(c.request, input);
    return result.ok ? authHookSuccess(result.value) : authHookFailure(result.error);
  },
  async signOut(c) {
    return authHookSuccess({ headers: await appAuth.signOut(c.request) });
  },
  async getSession(c) {
    const session = await appAuth.getSession(c.request);
    return authHookSuccess(session);
  },
  async issueToken(c) {
    const result = await appAuth.issueToken(c.request);
    return result.ok ? authHookSuccess(result.value) : authHookFailure(result.error);
  },
  async jwks(c) {
    return appAuth.jwks(c.request);
  },
});

const engine = createAuthEngine({
  hooks,
  config: {
    basePath: '/api/auth',
    trustedOrigins: ['myapp://'],
    session: { expiresInSeconds: 60 * 60 * 24 * 30, updateAgeSeconds: 60 * 60 * 24 },
    jwt: {
      issuer: 'https://api.example.com',
      audience: 'myapp',
      expiresInSeconds: 60 * 60,
      jwksUrl: new URL('https://api.example.com/api/auth/jwks'),
    },
  },
});
```

An adapter creates an `AuthHookContext` from its incoming request, calls an engine operation such as `engine.signIn(context, input)`, and converts the returned `AuthResponsePayload` into its framework's response. Expected failures are returned as `AuthOutcome`; unexpected exceptions continue to throw.

## Contract

The default email/password operations are sign-up, sign-in, sign-out, session lookup, token issuance, and JWKS. Successful sign-in and sign-up responses include the user and opaque session token, and return credentials in these headers:

| Header                   | Meaning                       |
| ------------------------ | ----------------------------- |
| `set-auth-token`         | Short-lived bearer JWT        |
| `set-auth-token-expiry`  | JWT lifetime in seconds       |
| `set-session-token`      | Opaque session token          |
| `set-session-update-age` | Session update age in seconds |

`resolveSession` first verifies a bearer JWT against the configured JWKS and falls back to `getSession` for an opaque bearer token or cookie-based session. Set `config.isTest` only in tests and provide `verificationKeys` to verify against consumer-supplied local keys.

Use `payloadSchemas` when your sign-in or sign-up hook accepts fields beyond the built-in email/password payloads. `sessionExtras` adds app-owned fields to session and authenticated responses while preserving their schema in generated OpenAPI.

## Exports

The primary exports are `createAuthEngine`, `defineAuthHooks`, `authHookSuccess`, `authHookFailure`, `resolveSession`, credential-header helpers, OpenAPI schema builders, and the auth constants/types. `@kamaalio/kamaal-auth-core/testing` provides an in-memory auth implementation for adapter tests.

## License

MIT
