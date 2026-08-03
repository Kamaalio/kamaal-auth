//
//  KamaalAuthClientTests.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore
import KamaalAuthTestSupport
import Testing

@testable import KamaalAuthClient

private let credentialsKey = "test.credentials"

private func makeClient(
    hooks: MockAuthRequestHooks,
    store: InMemoryCredentialsStore = InMemoryCredentialsStore()
) -> (KamaalAuthClientImpl, InMemoryCredentialsStore) {
    (KamaalAuthClientImpl(hooks: hooks, credentialsKey: credentialsKey, credentialsStore: store), store)
}

@discardableResult
private func storeCredentials(
    in store: InMemoryCredentialsStore,
    authTokenExpiryDate: Date = Date.now.addingTimeInterval(604_800),
    lastSessionUpdate: Date = .now,
    sessionExpiryDate: Date? = Date.now.addingTimeInterval(2_592_000)
) throws -> Credentials {
    let credentials = Credentials(
        authToken: "stored.auth.token",
        authTokenExpiryDate: authTokenExpiryDate,
        sessionToken: "stored-session-token",
        sessionUpdateAge: 86_400,
        lastSessionUpdate: lastSessionUpdate,
        sessionExpiryDate: sessionExpiryDate,
    )
    try store.store(credentials, forKey: credentialsKey)

    return credentials
}

private func sampleSession(expiresAt: Date = .distantFuture) -> AuthSession {
    AuthSession(
        id: "user_1",
        name: "John Doe",
        email: "john.doe@example.com",
        emailVerified: true,
        createdAt: .now,
        expiresAt: expiresAt,
        extras: ["preferred_currency": .string("EUR")],
    )
}

@Suite("Sign up")
struct SignUpTests {
    @Test("Persists the credentials the hook returned")
    func persistsCredentials() async throws {
        let hooks = MockAuthRequestHooks().stub(.signUp, with: .success(MockAuthRequestHooks.credentials()))
        let (client, store) = makeClient(hooks: hooks)

        let result = await client.signUp(with: .init(email: "a@b.com", password: "Password1!", name: "John Doe"))

        #expect(try result.get() == ())
        let credentials = try #require(try store.credentials(forKey: credentialsKey))
        #expect(credentials.authToken == "header.payload.signature")
        #expect(credentials.sessionToken == "session-token")
    }

    @Test("Maps a 409 onto a conflict")
    func mapsConflict() async {
        let hooks = MockAuthRequestHooks()
            .stub(.signUp, with: .failure(.init(status: 409, code: "USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL")))
        let (client, _) = makeClient(hooks: hooks)

        let result = await client.signUp(with: .init(email: "a@b.com", password: "Password1!", name: "John Doe"))

        guard case .failure(.conflict) = result else {
            Issue.record("Expected a conflict, got \(result)")
            return
        }
    }

    @Test("Surfaces the field-level validation issues from a 400")
    func surfacesValidationIssues() async {
        let issue = AuthValidationIssue(code: "too_small", path: ["password"], message: "Too short")
        let hooks = MockAuthRequestHooks()
            .stub(.signUp, with: .failure(.init(status: 400, code: "INVALID_PAYLOAD", validations: [issue])))
        let (client, _) = makeClient(hooks: hooks)

        let result = await client.signUp(with: .init(email: "a@b.com", password: "x", name: "John Doe"))

        guard case .failure(.badRequest(let validations)) = result else {
            Issue.record("Expected a bad request, got \(result)")
            return
        }
        #expect(validations.first?.field == "password")
        #expect(validations.first?.message == "Too short")
    }
}

@Suite("Sign in")
struct SignInTests {
    @Test("Reports rejected credentials as a bad request with no field errors")
    func reportsRejectedCredentials() async {
        let hooks = MockAuthRequestHooks()
            .stub(.signIn, with: .failure(.init(status: 401, code: "INVALID_EMAIL_OR_PASSWORD")))
        let (client, _) = makeClient(hooks: hooks)

        let result = await client.signIn(with: .init(email: "a@b.com", password: "nope"))

        guard case .failure(.badRequest(let validations)) = result else {
            Issue.record("Expected a bad request, got \(result)")
            return
        }
        #expect(validations.isEmpty)
    }

    @Test("Reports any other 401 as an unavailable session")
    func reportsOther401AsSessionUnavailable() async {
        let hooks = MockAuthRequestHooks().stub(.signIn, with: .failure(.init(status: 401, code: "SOMETHING_ELSE")))
        let (client, _) = makeClient(hooks: hooks)

        let result = await client.signIn(with: .init(email: "a@b.com", password: "nope"))

        guard case .failure(.sessionUnavailable) = result else {
            Issue.record("Expected sessionUnavailable, got \(result)")
            return
        }
    }

    @Test("Clears stale credentials even when the sign in fails")
    func clearsStaleCredentialsOnFailure() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks().stub(.signIn, with: .failure(.init(status: 401, code: "SOMETHING_ELSE")))
        let (client, _) = makeClient(hooks: hooks, store: store)

        _ = await client.signIn(with: .init(email: "a@b.com", password: "nope"))

        #expect(try store.credentials(forKey: credentialsKey) == nil)
    }
}

@Suite("Session")
struct SessionTests {
    @Test("Returns the session and preserves app-specific fields as extras")
    func preservesExtras() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks().stubSession(.success(sampleSession()))
        let (client, _) = makeClient(hooks: hooks, store: store)

        let session = try (await client.session()).get()

        #expect(session.email == "john.doe@example.com")
        #expect(session.extras["preferred_currency"]?.stringValue == "EUR")
    }

    @Test("Decodes extras into an app-supplied type")
    func decodesExtrasIntoType() throws {
        struct Preferences: Decodable {
            let preferredCurrency: String

            private enum CodingKeys: String, CodingKey {
                case preferredCurrency = "preferred_currency"
            }
        }

        #expect(try sampleSession().decodeExtras(as: Preferences.self).preferredCurrency == "EUR")
    }

    @Test("Deletes credentials and reports unauthorized on a 401")
    func deletesCredentialsOnUnauthorized() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks().stubSession(.failure(.init(status: 401)))
        let (client, _) = makeClient(hooks: hooks, store: store)

        let result = await client.session()

        guard case .failure(.unauthorized) = result else {
            Issue.record("Expected unauthorized, got \(result)")
            return
        }
        #expect(try store.credentials(forKey: credentialsKey) == nil)
    }

    @Test("Keeps credentials when the failure is not an auth failure")
    func keepsCredentialsOnServerError() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks().stubSession(.failure(.init(status: 503)))
        let (client, _) = makeClient(hooks: hooks, store: store)

        _ = await client.session()

        #expect(try store.credentials(forKey: credentialsKey) != nil)
    }

    @Test("Reports unauthorized without calling the hook when nothing is stored")
    func reportsUnauthorizedWithoutCredentials() async {
        let hooks = MockAuthRequestHooks()
        let (client, _) = makeClient(hooks: hooks)

        let result = await client.session()

        guard case .failure(.unauthorized) = result else {
            Issue.record("Expected unauthorized, got \(result)")
            return
        }
        #expect(hooks.callCount(.session) == 0)
    }

    @Test("Caches the session expiry so the next launch can answer offline")
    func cachesSessionExpiry() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store, sessionExpiryDate: nil)
        let expiresAt = Date.now.addingTimeInterval(2_592_000)
        let hooks = MockAuthRequestHooks().stubSession(.success(sampleSession(expiresAt: expiresAt)))
        let (client, _) = makeClient(hooks: hooks, store: store)

        _ = await client.session()

        #expect(try store.credentials(forKey: credentialsKey)?.sessionExpiryDate == expiresAt)
    }
}

@Suite("Credential validity")
struct CredentialValidityTests {
    @Test("Reports no valid credentials when nothing is stored")
    func reportsNoCredentials() {
        let (client, _) = makeClient(hooks: MockAuthRequestHooks())

        #expect(client.hasValidCredentials == false)
    }

    @Test("Reports valid credentials while the session is live")
    func reportsValidCredentials() throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let (client, _) = makeClient(hooks: MockAuthRequestHooks(), store: store)

        #expect(client.hasValidCredentials)
    }

    @Test("Reports invalid credentials once the session has expired")
    func reportsExpiredSession() throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store, sessionExpiryDate: .distantPast)
        let (client, _) = makeClient(hooks: MockAuthRequestHooks(), store: store)

        #expect(client.hasValidCredentials == false)
    }
}

@Suite("Token refresh")
struct TokenRefreshTests {
    @Test("Refreshes using the session token, never the stored JWT")
    func refreshesWithSessionToken() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks().stub(.issueToken, with: .success(MockAuthRequestHooks.credentials()))
        let (client, _) = makeClient(hooks: hooks, store: store)

        _ = await client.refreshToken()

        #expect(hooks.lastCall(.issueToken)?.sessionToken == "stored-session-token")
    }

    @Test("Carries the known session expiry across a refresh")
    func carriesSessionExpiry() async throws {
        let store = InMemoryCredentialsStore()
        let existing = try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks().stub(.issueToken, with: .success(MockAuthRequestHooks.credentials()))
        let (client, _) = makeClient(hooks: hooks, store: store)

        _ = await client.refreshToken()

        #expect(try store.credentials(forKey: credentialsKey)?.sessionExpiryDate == existing.sessionExpiryDate)
    }

    @Test("Deletes credentials when the refresh is rejected")
    func deletesCredentialsOnRejectedRefresh() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks().stub(.issueToken, with: .failure(.init(status: 401)))
        let (client, _) = makeClient(hooks: hooks, store: store)

        _ = await client.refreshToken()

        #expect(try store.credentials(forKey: credentialsKey) == nil)
    }

    @Test("Keeps credentials when the refresh fails for a non-auth reason")
    func keepsCredentialsOnRefreshServerError() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks().stub(.issueToken, with: .failure(.init(status: 503)))
        let (client, _) = makeClient(hooks: hooks, store: store)

        _ = await client.refreshToken()

        #expect(try store.credentials(forKey: credentialsKey) != nil)
    }
}

@Suite("Valid auth token")
struct ValidAuthTokenTests {
    @Test("Returns the stored token without refreshing when it is fresh")
    func returnsStoredTokenWhenFresh() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks()
        let (client, _) = makeClient(hooks: hooks, store: store)

        #expect(await client.validAuthToken() == "stored.auth.token")
        #expect(hooks.callCount(.issueToken) == 0)
    }

    @Test("Refreshes first when the auth token is about to expire")
    func refreshesWhenExpiring() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store, authTokenExpiryDate: Date.now.addingTimeInterval(60))
        let hooks = MockAuthRequestHooks()
            .stub(.issueToken, with: .success(MockAuthRequestHooks.credentials(authToken: "refreshed.jwt.token")))
        let (client, _) = makeClient(hooks: hooks, store: store)

        #expect(await client.validAuthToken() == "refreshed.jwt.token")
        #expect(hooks.callCount(.issueToken) == 1)
    }

    @Test("Refreshes first when the session is due for an update")
    func refreshesWhenSessionStale() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store, lastSessionUpdate: Date.now.addingTimeInterval(-90_000))
        let hooks = MockAuthRequestHooks()
            .stub(.issueToken, with: .success(MockAuthRequestHooks.credentials(authToken: "refreshed.jwt.token")))
        let (client, _) = makeClient(hooks: hooks, store: store)

        #expect(await client.validAuthToken() == "refreshed.jwt.token")
    }

    @Test("Returns nothing and clears credentials once the session has expired")
    func clearsOnExpiredSession() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store, sessionExpiryDate: .distantPast)
        let hooks = MockAuthRequestHooks()
        let (client, _) = makeClient(hooks: hooks, store: store)

        #expect(await client.validAuthToken() == nil)
        #expect(try store.credentials(forKey: credentialsKey) == nil)
        #expect(hooks.callCount(.issueToken) == 0)
    }

    @Test("Returns nothing when nothing is stored")
    func returnsNothingWithoutCredentials() async {
        let (client, _) = makeClient(hooks: MockAuthRequestHooks())

        #expect(await client.validAuthToken() == nil)
    }

    @Test("Returns nothing when the refresh fails")
    func returnsNothingWhenRefreshFails() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store, authTokenExpiryDate: Date.now.addingTimeInterval(60))
        let hooks = MockAuthRequestHooks().stub(.issueToken, with: .failure(.init(status: 401)))
        let (client, _) = makeClient(hooks: hooks, store: store)

        #expect(await client.validAuthToken() == nil)
    }
}

@Suite("Sign out")
struct SignOutTests {
    @Test("Clears the stored credentials")
    func clearsCredentials() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks().stubSignOut(.success(()))
        let (client, _) = makeClient(hooks: hooks, store: store)

        let result = await client.signOut()

        #expect(try result.get() == ())
        #expect(try store.credentials(forKey: credentialsKey) == nil)
    }

    @Test("Clears credentials even when the server rejects the request")
    func clearsCredentialsWhenServerFails() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        let hooks = MockAuthRequestHooks().stubSignOut(.failure(.init(status: 503)))
        let (client, _) = makeClient(hooks: hooks, store: store)

        _ = await client.signOut()

        #expect(try store.credentials(forKey: credentialsKey) == nil)
    }
}

@Suite("Credential headers")
struct CredentialHeadersTests {
    private static let headers = [
        "set-auth-token": "header.payload.signature",
        "set-auth-token-expiry": "604800",
        "set-session-token": "session-token",
        "set-session-update-age": "86400",
    ]

    @Test("Parses the four headers the server writes")
    func parsesHeaders() throws {
        let parsed = try #require(AuthCredentialHeaders(headers: Self.headers))

        #expect(parsed.authToken == "header.payload.signature")
        #expect(parsed.authTokenExpiresInSeconds == 604_800)
        #expect(parsed.sessionToken == "session-token")
        #expect(parsed.sessionUpdateAgeSeconds == 86_400)
    }

    @Test("Matches header names case-insensitively")
    func matchesCaseInsensitively() {
        let shouted = Dictionary(uniqueKeysWithValues: Self.headers.map { ($0.key.uppercased(), $0.value) })

        #expect(AuthCredentialHeaders(headers: shouted) != nil)
    }

    @Test("Returns nil when a header is missing", arguments: Array(Self.headers.keys))
    func returnsNilWhenHeaderMissing(missing: String) {
        var headers = Self.headers
        headers.removeValue(forKey: missing)

        #expect(AuthCredentialHeaders(headers: headers) == nil)
    }

    @Test("Returns nil when a numeric header is not a number")
    func returnsNilForNonNumeric() {
        var headers = Self.headers
        headers["set-auth-token-expiry"] = "soon"

        #expect(AuthCredentialHeaders(headers: headers) == nil)
    }

    @Test("Turns headers into credentials that expire after the advertised lifetime")
    func buildsCredentials() throws {
        let parsed = try #require(AuthCredentialHeaders(headers: Self.headers))

        let credentials = parsed.credentials()

        #expect(credentials.authTokenHasExpired == false)
        #expect(credentials.authTokenExpiryDate.timeIntervalSinceNow > 604_000)
        #expect(credentials.sessionExpiryDate == nil)
    }
}

@Suite("Error body")
struct ErrorBodyTests {
    @Test("Extracts the code and field-level validations")
    func extractsValidations() {
        let body = Data(
            """
            {"message":"Invalid payload","code":"INVALID_PAYLOAD","context":{"validations":[
              {"code":"too_small","path":["password"],"message":"Too short"}
            ]}}
            """.utf8
        )

        let failure = AuthErrorBody.failure(status: 400, body: body)

        #expect(failure.status == 400)
        #expect(failure.code == "INVALID_PAYLOAD")
        #expect(failure.validations.first?.field == "password")
    }

    @Test("Falls back to the bare status when the body is not the expected envelope")
    func fallsBackForUnexpectedBody() {
        let failure = AuthErrorBody.failure(status: 500, body: Data("not json".utf8))

        #expect(failure.status == 500)
        #expect(failure.code == nil)
        #expect(failure.validations.isEmpty)
    }

    @Test("Falls back when there is no body at all")
    func fallsBackForMissingBody() {
        #expect(AuthErrorBody.failure(status: 503, body: nil).code == nil)
    }
}
