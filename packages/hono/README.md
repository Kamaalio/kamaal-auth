# @kamaalio/kamaal-auth-hono

A mountable [Hono](https://hono.dev/) authentication router. It adapts [`@kamaalio/kamaal-auth-core`](https://www.npmjs.com/package/@kamaalio/kamaal-auth-core) to Hono and re-exports the core package, so this is the only Kamaal Auth package most Hono applications need to install.

Your application supplies the hooks that call its auth library and database. This package supplies route registration, session middleware, OpenAPI route definitions, request validation, and conversion between Hono contexts and the framework-neutral engine.

## Install

```sh
npm install @kamaalio/kamaal-auth-hono hono @hono/zod-openapi zod
```

Node.js 24 or newer is required.

## Quick start

```ts
import { OpenAPIHono } from '@hono/zod-openapi';
import { authHookSuccess, createAuthModule, defineAuthHooks } from '@kamaalio/kamaal-auth-hono';

const hooks = defineAuthHooks({
  async signUp(c, input) {
    return authHookSuccess(await appAuth.signUp(c.request, input));
  },
  async signIn(c, input) {
    return authHookSuccess(await appAuth.signIn(c.request, input));
  },
  async signOut(c) {
    return authHookSuccess({ headers: await appAuth.signOut(c.request) });
  },
  async getSession(c) {
    return authHookSuccess(await appAuth.getSession(c.request));
  },
  async issueToken(c) {
    return authHookSuccess(await appAuth.issueToken(c.request));
  },
  async jwks(c) {
    return appAuth.jwks(c.request);
  },
});

const app = new OpenAPIHono();
const auth = createAuthModule({
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

app.route('/api/auth', auth.router);
```

The hooks are intentionally application-owned: they can call any auth library, use any database, and return `authHookFailure` when that dependency reports an expected failure. See the core package for the full hook contract and standalone-engine use.

## Routes

Mounting the router registers these relative paths:

| Method | Path             | Purpose                                  |
| ------ | ---------------- | ---------------------------------------- |
| `POST` | `/sign-up/email` | Create an account and return credentials |
| `POST` | `/sign-in/email` | Authenticate with email and password     |
| `POST` | `/sign-out`      | End the current session                  |
| `GET`  | `/session`       | Return the authenticated session         |
| `GET`  | `/token`         | Issue or refresh a bearer JWT            |
| `GET`  | `/jwks`          | Serve the public JWKS document           |

Successful sign-in, sign-up, and token responses use the shared credential headers: `set-auth-token`, `set-auth-token-expiry`, `set-session-token`, and `set-session-update-age`.

## Protect application routes

Use `requireSessionMiddleware` before routes that require a session, then retrieve the resolved session with `getSession`. Session resolution is cached for the lifetime of the Hono request.

```ts
app.get('/api/me', auth.requireSessionMiddleware, c => {
  const session = auth.getSession(c);
  return c.json({ user: session.user });
});
```

Bearer JWTs are verified with the configured JWKS. Opaque bearer tokens and cookie sessions fall back to your `getSession` hook.

## Integration points

Pass `router` when your app already has an `OpenAPIHono` instance and its validation hook/error envelope should also govern the auth routes. `locals`, `logger`, and `requestId` derive per-request values for every hook. `payloadSchemas` supports wider sign-in/sign-up payloads, `sessionExtras` extends session responses and OpenAPI schemas, and `extraRoutes` mounts app-owned routes with the auth schemas and session middleware available.

The optional `fallback` hook receives unmatched GET and POST auth paths after the built-in routes, which is useful for forwarding auth-library endpoints not represented by this router.

## License

MIT
