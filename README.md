# kamaal-auth

Shared auth stack for multiple apps, so an improvement lands once instead of twice.

One repo, three published artifacts:

| Artifact      | Name                                                                | Consumed as                                        |
| ------------- | ------------------------------------------------------------------- | -------------------------------------------------- |
| npm package   | `@kamaalio/kamaal-auth-core` (in [`packages/core/`](packages/core)) | the auth engine, with no server library of its own |
| npm package   | `@kamaalio/kamaal-auth-hono` (in [`packages/hono/`](packages/hono)) | a mountable Hono auth router                       |
| Swift package | `KamaalAuth` (at the repo root)                                     | `KamaalAuth`                                       |

The two npm packages release in lockstep under the same semver tag used by SwiftPM.

### Why the split

`kamaal-auth-core` holds everything worth sharing: the hook contract, session resolution and JWT verification, the
credential-header wire format, error-to-status mapping and the OpenAPI schemas. It expresses every operation against a
plain `Request`, so it has no opinion about how requests reach it.

`kamaal-auth-hono` is the adapter: route definitions, a session middleware, and the translation between a Hono
`Context` and the engine. Supporting another server library means writing another adapter of about that size, not
another auth package.

A Hono app depends on `kamaal-auth-hono` alone — it re-exports everything `kamaal-auth-core` exports, so there is one
package to add and one package to import from. Add `kamaal-auth-core` directly only if you are writing a new adapter,
or using the engine without a server library at all.

## Two things this package deliberately does not own

**It does not own your database schema.** Your app defines and migrates its own `user` / `session` / `account` /
`verification` / `jwks` tables and keeps them fully visible. Nothing here reads or writes them.

**It does not make requests, or accept a `better-auth` instance.** You supply _hook functions_ implementing the auth operations, and the
package derives its types from those signatures. `better-auth`, `drizzle-orm`, and your database driver never enter this
package's dependency graph — which is why two apps on different `better-auth` versions can share it.

`kamaal-auth-core`'s only dependencies are `zod`, `@asteasolutions/zod-to-openapi`, and `jose`, all as peers.
`kamaal-auth-hono` adds `hono` and `@hono/zod-openapi`, also as peers, on top of the core package.

## Server usage

```ts
import { createAuthModule, defineAuthHooks } from '@kamaalio/kamaal-auth-hono';

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

All artifacts use one version line. GitHub Actions publishes the npm packages after a bare semver tag (`<version>`) is
pushed, and SwiftPM resolves that same tag directly from the repository.

To release all packages, create and push one tag:

```sh
git tag <version>
git push origin <version>
```

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

## Swift usage

Same idea as the server: you supply the requests, the package supplies everything worth sharing. `import KamaalAuth`
is the only import an app needs — it re-exports the credential storage layer, the networking client, the OpenAPI
middleware, and the SwiftUI screens as one module. Test targets additionally import `KamaalAuthTestSupport` for
`MockAuthRequestHooks`.

Implement `AuthRequestHooks` with your own generated client, and the client layer owns credential storage, the
refresh policy, expiry rules, session modelling and error semantics.

```swift
struct MyAuthHooks: AuthRequestHooks {
    let client: Client  // your generated OpenAPI client

    func signIn(_ payload: SignInPayload) async -> AuthRequestOutcome<AuthCredentialHeaders> {
        // call your client, then hand the response headers over
        guard let headers = AuthCredentialHeaders(headers: response.headers) else {
            return .failure(AuthRequestFailure(status: 500))
        }
        return .success(headers)
    }
    // signUp, signOut, session, issueToken likewise
}

let auth = KamaalAuthClientImpl(hooks: MyAuthHooks(client: client), credentialsKey: "\(bundleID).credentials")
```

`KamaalAuthUI` provides the shared sign-in/sign-up flow and gates app content until authentication completes:

```swift
@State private var auth = KamaalAuth(
    client: client,
    configuration: KamaalAuthConfiguration(appName: "My App")
)

Text("Signed in")
    .kamaalAuth(auth)
```

Because the requests live in your app, this package has no HTTP stack, no transport, and no knowledge of your code
generation. Its only dependency is `KamaalSwift`.

`AuthErrorBody.failure(status:body:)` turns an error response into an `AuthRequestFailure`, including the field-level
validations, so each app does not re-derive the envelope.

To authenticate your app's other requests, ask for a token that is guaranteed fresh — it refreshes first when the
stored one is stale or nearly expired:

```swift
if let token = await auth.validAuthToken() {
    request.headerFields[.authorization] = "Bearer \(token)"
}
```

App-specific user fields ride along untouched. Anything the package does not model is preserved on
`AuthSession.extras`:

```swift
let currency = session.extras["preferred_currency"]?.stringValue
let preferences = try session.decodeExtras(as: Preferences.self)
```

> Credentials stored in an older shape fail to decode, which reads as signed out. Adopting this package costs each app
> one forced re-login.
