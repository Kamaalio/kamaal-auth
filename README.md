# kamaal-auth

Shared auth stack for [Kowalski](https://github.com/kamaal111/Kowalski) and [TCG](https://github.com/kamaal111/TCG), so an
improvement lands once instead of twice.

One repo, two published artifacts:

| Artifact      | Name                                             | Consumed as                                          |
| ------------- | ------------------------------------------------ | ---------------------------------------------------- |
| npm package   | `@kamaalio/kamaal-auth` (in [`server/`](server)) | a mountable Hono auth router                         |
| Swift package | `KamaalAuth` (at the repo root)                  | `KamaalAuthCore`, `KamaalAuthClient`, `KamaalAuthUI` |

## Two things this package deliberately does not own

**It does not own your database schema.** Your app defines and migrates its own `user` / `session` / `account` /
`verification` / `jwks` tables and keeps them fully visible. Nothing here reads or writes them.

**It does not accept a `better-auth` instance.** You supply _hook functions_ implementing the auth operations, and the
package derives its types from those signatures. `better-auth`, `drizzle-orm`, and your database driver never enter this
package's dependency graph — which is why two apps on different `better-auth` versions can share it.

The server package's only dependencies are `hono`, `@hono/zod-openapi`, `zod`, and `jose`, all as peers.

## Server usage

```ts
import { createAuthModule, defineAuthHooks } from '@kamaalio/kamaal-auth';

const hooks = defineAuthHooks({
  async signIn(c, input) {
    /* call your better-auth instance, return { ok: true, value: { user, credentials } } */
  },
  async signUp(c, input) {
    /* … */
  },
  async signOut(c) {
    /* … */
  },
  async getSession(c) {
    /* … */
  },
  async issueToken(c) {
    /* … */
  },
  async jwks(c) {
    /* … */
  },
});

const auth = createAuthModule({
  hooks,
  config: {
    basePath: '/app-api/auth',
    trustedOrigins: ['myapp://'],
    session: { expiresInSeconds: THIRTY_DAYS, updateAgeSeconds: ONE_DAY },
    jwt: { issuer, audience, expiresInSeconds: SEVEN_DAYS, jwksUrl },
  },
});

app.route('/app-api/auth', auth.router);
```

Apps with extra per-user state extend the session response without the package knowing what it is:

```ts
sessionExtras: {
  schema: z.object({ preferred_currency: CurrencyShape, has_preferred_currency_preference: z.boolean() }),
  resolve: async (c, { userId }) => ({ /* … */ }),
},
extraRoutes: (router, deps) => router.openapi(preferencesRoute(deps.schemas.SessionResponseSchema), handler),
```

## Releasing

Two independent version lines out of one repo:

```sh
just release-npm 0.1.0   # tags npm/0.1.0 -> publishes to npm
just release-spm 0.1.0   # tags 0.1.0     -> SwiftPM resolves it
```

SwiftPM only resolves bare semver tags, so it ignores `npm/*` entirely. Use the `just` recipes rather than tagging by
hand — a bare tag pushed when you meant an npm release publishes nothing and silently cuts a Swift release instead.

Because both artifacts implement two ends of the same wire contract (notably the `set-auth-token` /
`set-auth-token-expiry` / `set-session-token` / `set-session-update-age` headers), keep this table current:

| npm          | SPM          |
| ------------ | ------------ |
| _unreleased_ | _unreleased_ |

## Development

```sh
just            # list commands
just prepare    # install modules
just ready      # quality + tests, both languages
```
