//
//  KamaalAuthClientTests.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore
import KamaalAuthTestSupport
import Testing

@testable import KamaalAuthClient

/// Never dialed: `MockAuthTransport` answers every request without touching the network.
private let serverURL = URL(fileURLWithPath: "/mock-server")
private let credentialsKey = "test.credentials"
private let paths = AuthPaths(basePath: AuthDefaults.basePath)

private let userJSON = """
    {
      "id": "user_1",
      "name": "John Doe",
      "email": "john.doe@example.com",
      "email_verified": true,
      "created_at": "2026-07-07T10:30:00.000Z"
    }
    """

private func makeClient(
    transport: MockAuthTransport,
    store: InMemoryCredentialsStore = InMemoryCredentialsStore(),
    sendsSessionCookie: Bool = false
) -> (KamaalAuthClientImpl, InMemoryCredentialsStore) {
    let configuration = KamaalAuthClientConfiguration(
        serverURL: serverURL,
        originScheme: .explicit("testapp"),
        credentialsKey: credentialsKey,
        credentialsStore: store,
        sendsSessionCookie: sendsSessionCookie,
    )

    return (KamaalAuthClientImpl(configuration: configuration, transport: transport), store)
}

private func storedCredentials(
    in store: InMemoryCredentialsStore,
    authTokenExpiryDate: Date = Date.now.addingTimeInterval(604_800),
    lastSessionUpdate: Date = .now,
    sessionExpiryDate: Date? = Date.now.addingTimeInterval(2_592_000)
) throws {
    try store.store(
        Credentials(
            authToken: "stored.auth.token",
            authTokenExpiryDate: authTokenExpiryDate,
            sessionToken: "stored-session-token",
            sessionUpdateAge: 86_400,
            lastSessionUpdate: lastSessionUpdate,
            sessionExpiryDate: sessionExpiryDate,
        ),
        forKey: credentialsKey,
    )
}

@Suite("Sign up")
struct SignUpTests {
    @Test("Persists the credentials carried by the response headers")
    func persistsCredentials() async throws {
        let transport = MockAuthTransport(responses: [
            paths.signUp: [.authenticated(status: 201, json: #"{"token":"session-token","user":\#(userJSON)}"#)]
        ])
        let (client, store) = makeClient(transport: transport)

        let result = await client.signUp(with: .init(email: "a@b.com", password: "Password1!", name: "John Doe"))

        #expect(try result.get() == ())
        let credentials = try #require(try store.credentials(forKey: credentialsKey))
        #expect(credentials.authToken == "header.payload.signature")
        #expect(credentials.sessionToken == "session-token")
    }

    @Test("Maps a 409 onto a conflict")
    func mapsConflict() async {
        let transport = MockAuthTransport(responses: [
            paths.signUp: [.init(status: 409, json: #"{"code":"USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL"}"#)]
        ])
        let (client, _) = makeClient(transport: transport)

        let result = await client.signUp(with: .init(email: "a@b.com", password: "Password1!", name: "John Doe"))

        guard case .failure(.conflict) = result else {
            Issue.record("Expected a conflict, got \(result)")
            return
        }
    }

    @Test("Surfaces field-level validation issues from a 400")
    func surfacesValidationIssues() async {
        let body = """
            {"message":"Invalid payload","code":"INVALID_PAYLOAD","context":{"validations":[
              {"code":"too_small","path":["password"],"message":"Too short"}
            ]}}
            """
        let transport = MockAuthTransport(responses: [paths.signUp: [.init(status: 400, json: body)]])
        let (client, _) = makeClient(transport: transport)

        let result = await client.signUp(with: .init(email: "a@b.com", password: "x", name: "John Doe"))

        guard case .failure(.badRequest(let validations)) = result else {
            Issue.record("Expected a bad request, got \(result)")
            return
        }
        #expect(validations.count == 1)
        #expect(validations.first?.field == "password")
        #expect(validations.first?.message == "Too short")
    }

    @Test("Fails when the response omits the credential headers")
    func failsWithoutCredentialHeaders() async {
        let transport = MockAuthTransport(responses: [
            paths.signUp: [.init(status: 201, json: #"{"token":"t","user":\#(userJSON)}"#)]
        ])
        let (client, _) = makeClient(transport: transport)

        let result = await client.signUp(with: .init(email: "a@b.com", password: "Password1!", name: "John Doe"))

        guard case .failure(.credentialsUnavailable) = result else {
            Issue.record("Expected credentialsUnavailable, got \(result)")
            return
        }
    }
}

@Suite("Sign in")
struct SignInTests {
    @Test("Reports rejected credentials as a bad request with no field errors")
    func reportsRejectedCredentials() async {
        let transport = MockAuthTransport(responses: [
            paths.signIn: [.init(status: 401, json: #"{"code":"INVALID_EMAIL_OR_PASSWORD"}"#)]
        ])
        let (client, _) = makeClient(transport: transport)

        let result = await client.signIn(with: .init(email: "a@b.com", password: "nope"))

        guard case .failure(.badRequest(let validations)) = result else {
            Issue.record("Expected a bad request, got \(result)")
            return
        }
        #expect(validations.isEmpty)
    }

    @Test("Reports any other 401 as an unavailable session")
    func reportsOther401AsSessionUnavailable() async {
        let transport = MockAuthTransport(responses: [
            paths.signIn: [.init(status: 401, json: #"{"code":"SOMETHING_ELSE"}"#)]
        ])
        let (client, _) = makeClient(transport: transport)

        let result = await client.signIn(with: .init(email: "a@b.com", password: "nope"))

        guard case .failure(.sessionUnavailable) = result else {
            Issue.record("Expected sessionUnavailable, got \(result)")
            return
        }
    }

    @Test("Clears stale credentials before signing in")
    func clearsStaleCredentials() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store)
        let transport = MockAuthTransport(responses: [
            paths.signIn: [.authenticated(status: 200, json: #"{"token":"session-token","user":\#(userJSON)}"#)]
        ])
        let (client, _) = makeClient(transport: transport, store: store)

        _ = await client.signIn(with: .init(email: "a@b.com", password: "Password1!"))

        let credentials = try #require(try store.credentials(forKey: credentialsKey))
        #expect(credentials.authToken == "header.payload.signature")
    }
}

@Suite("Session")
struct SessionTests {
    @Test("Decodes the session and preserves unknown user fields as extras")
    func preservesExtras() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store)
        let body = """
            {"session":{"expires_at":"2026-08-12T12:08:28.382Z","created_at":"2026-08-05T12:08:28.382Z",
            "updated_at":"2026-08-05T12:08:28.382Z"},
            "user":{"id":"user_1","name":"John Doe","email":"john.doe@example.com","email_verified":true,
            "created_at":"2026-07-07T10:30:00.000Z","preferred_currency":"EUR",
            "has_preferred_currency_preference":true}}
            """
        let transport = MockAuthTransport(responses: [paths.session: [.init(status: 200, json: body)]])
        let (client, _) = makeClient(transport: transport, store: store)

        let session = try (await client.session()).get()

        #expect(session.email == "john.doe@example.com")
        #expect(session.extras["preferred_currency"]?.stringValue == "EUR")
        #expect(session.extras["has_preferred_currency_preference"]?.boolValue == true)
        #expect(session.extras["email"] == nil)
    }

    @Test("Decodes extras into an app-supplied type")
    func decodesExtrasIntoType() throws {
        struct Preferences: Decodable {
            let preferredCurrency: String

            private enum CodingKeys: String, CodingKey {
                case preferredCurrency = "preferred_currency"
            }
        }

        let session = AuthSession(
            id: "1",
            name: "John Doe",
            email: "a@b.com",
            emailVerified: true,
            createdAt: .now,
            expiresAt: .distantFuture,
            extras: ["preferred_currency": .string("EUR")],
        )

        #expect(try session.decodeExtras(as: Preferences.self).preferredCurrency == "EUR")
    }

    @Test("Deletes credentials and reports unauthorized on a 401")
    func deletesCredentialsOnUnauthorized() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store)
        let transport = MockAuthTransport(responses: [paths.session: [.init(status: 401, json: "{}")]])
        let (client, _) = makeClient(transport: transport, store: store)

        let result = await client.session()

        guard case .failure(.unauthorized) = result else {
            Issue.record("Expected unauthorized, got \(result)")
            return
        }
        #expect(try store.credentials(forKey: credentialsKey) == nil)
    }

    @Test("Reports unauthorized without a request when nothing is stored")
    func reportsUnauthorizedWithoutCredentials() async {
        let transport = MockAuthTransport()
        let (client, _) = makeClient(transport: transport)

        let result = await client.session()

        guard case .failure(.unauthorized) = result else {
            Issue.record("Expected unauthorized, got \(result)")
            return
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("Caches the session expiry so the next launch can answer offline")
    func cachesSessionExpiry() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store, sessionExpiryDate: nil)
        let body = """
            {"session":{"expires_at":"2026-08-12T12:08:28.382Z","created_at":"2026-08-05T12:08:28.382Z",
            "updated_at":"2026-08-05T12:08:28.382Z"},"user":\(userJSON)}
            """
        let transport = MockAuthTransport(responses: [paths.session: [.init(status: 200, json: body)]])
        let (client, _) = makeClient(transport: transport, store: store)

        _ = await client.session()

        #expect(try store.credentials(forKey: credentialsKey)?.sessionExpiryDate != nil)
    }
}

@Suite("Credential validity")
struct CredentialValidityTests {
    @Test("Reports no valid credentials when nothing is stored")
    func reportsNoCredentials() {
        let (client, _) = makeClient(transport: MockAuthTransport())

        #expect(client.hasValidCredentials == false)
    }

    @Test("Reports valid credentials while the session is live")
    func reportsValidCredentials() throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store)
        let (client, _) = makeClient(transport: MockAuthTransport(), store: store)

        #expect(client.hasValidCredentials)
    }

    @Test("Reports invalid credentials once the session has expired")
    func reportsExpiredSession() throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store, sessionExpiryDate: .distantPast)
        let (client, _) = makeClient(transport: MockAuthTransport(), store: store)

        #expect(client.hasValidCredentials == false)
    }
}

@Suite("Token refresh")
struct TokenRefreshTests {
    @Test("Authorizes the token endpoint with the session token, not the JWT")
    func authorizesWithSessionToken() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store)
        let transport = MockAuthTransport(responses: [
            paths.token: [.authenticated(status: 200, json: #"{"token":"new.jwt.token"}"#)]
        ])
        let (client, _) = makeClient(transport: transport, store: store)

        _ = await client.refreshToken()

        let request = try #require(transport.requests(forPath: paths.token).first)
        #expect(request.header("Authorization") == "Bearer stored-session-token")
    }

    @Test("Refreshes before signing a request when the auth token is about to expire")
    func refreshesBeforeSigning() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store, authTokenExpiryDate: Date.now.addingTimeInterval(60))
        let transport = MockAuthTransport(responses: [
            paths.token: [
                .authenticated(status: 200, json: #"{"token":"x"}"#, authToken: "refreshed.jwt.token")
            ],
            paths.session: [
                .init(
                    status: 200,
                    json: """
                        {"session":{"expires_at":"2026-08-12T12:08:28.382Z",
                        "created_at":"2026-08-05T12:08:28.382Z","updated_at":"2026-08-05T12:08:28.382Z"},
                        "user":\(userJSON)}
                        """,
                )
            ],
        ])
        let (client, _) = makeClient(transport: transport, store: store)

        _ = await client.session()

        #expect(transport.requests(forPath: paths.token).count == 1)
        let sessionRequest = try #require(transport.requests(forPath: paths.session).first)
        #expect(sessionRequest.header("Authorization") == "Bearer refreshed.jwt.token")
    }

    @Test("Does not refresh when the auth token is still fresh")
    func doesNotRefreshWhenFresh() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store)
        let transport = MockAuthTransport(responses: [
            paths.session: [
                .init(
                    status: 200,
                    json: """
                        {"session":{"expires_at":"2026-08-12T12:08:28.382Z",
                        "created_at":"2026-08-05T12:08:28.382Z","updated_at":"2026-08-05T12:08:28.382Z"},
                        "user":\(userJSON)}
                        """,
                )
            ]
        ])
        let (client, _) = makeClient(transport: transport, store: store)

        _ = await client.session()

        #expect(transport.requests(forPath: paths.token).isEmpty)
    }

    @Test("Deletes credentials when the refresh is rejected")
    func deletesCredentialsOnRejectedRefresh() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store)
        let transport = MockAuthTransport(responses: [paths.token: [.init(status: 401, json: "{}")]])
        let (client, _) = makeClient(transport: transport, store: store)

        _ = await client.refreshToken()

        #expect(try store.credentials(forKey: credentialsKey) == nil)
    }
}

@Suite("Sign out")
struct SignOutTests {
    @Test("Clears the stored credentials")
    func clearsCredentials() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store)
        let transport = MockAuthTransport(responses: [paths.signOut: [.init(status: 200, json: "{}")]])
        let (client, _) = makeClient(transport: transport, store: store)

        let result = await client.signOut()

        #expect(try result.get() == ())
        #expect(try store.credentials(forKey: credentialsKey) == nil)
    }

    @Test("Clears credentials even when the server is unreachable")
    func clearsCredentialsWhenServerFails() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store)
        let transport = MockAuthTransport(fallback: .init(status: 503, json: "{}"))
        let (client, _) = makeClient(transport: transport, store: store)

        _ = await client.signOut()

        #expect(try store.credentials(forKey: credentialsKey) == nil)
    }
}

@Suite("Request decoration")
struct RequestDecorationTests {
    @Test("Sends the configured origin scheme")
    func sendsOrigin() async throws {
        let store = InMemoryCredentialsStore()
        try storedCredentials(in: store)
        let transport = MockAuthTransport(responses: [paths.session: [.init(status: 401, json: "{}")]])
        let (client, _) = makeClient(transport: transport, store: store)

        _ = await client.session()

        let request = try #require(transport.requests(forPath: paths.session).first)
        #expect(request.header("Origin") == "testapp://")
    }

    @Test("Sends the session cookie only when configured to")
    func sendsSessionCookieWhenConfigured() async throws {
        let body =
            #"{"session":{"expires_at":"2026-08-12T12:08:28.382Z","created_at":"2026-08-05T12:08:28.382Z","updated_at":"2026-08-05T12:08:28.382Z"},"user":\#(userJSON)}"#

        for sendsCookie in [true, false] {
            let store = InMemoryCredentialsStore()
            try storedCredentials(in: store)
            let transport = MockAuthTransport(responses: [paths.session: [.init(status: 200, json: body)]])
            let (client, _) = makeClient(transport: transport, store: store, sendsSessionCookie: sendsCookie)

            _ = await client.session()

            let request = try #require(transport.requests(forPath: paths.session).first)
            let cookie = request.header("Cookie")
            #expect((cookie?.contains("better-auth.session_token=stored-session-token") ?? false) == sendsCookie)
        }
    }
}

@Suite("Auth paths")
struct AuthPathsTests {
    @Test("Builds the endpoints under the configured base path")
    func buildsEndpoints() {
        let paths = AuthPaths(basePath: "/api/auth")

        #expect(paths.signUp == "/api/auth/sign-up/email")
        #expect(paths.signIn == "/api/auth/sign-in/email")
        #expect(paths.session == "/api/auth/session")
        #expect(paths.token == "/api/auth/token")
    }

    @Test("Tolerates a trailing slash on the base path")
    func tolerationsTrailingSlash() {
        #expect(AuthPaths(basePath: "/api/auth/").token == "/api/auth/token")
    }

    @Test("Matches the token path, ignoring a query string")
    func matchesTokenPath() {
        let paths = AuthPaths(basePath: "/api/auth")

        #expect(paths.isTokenPath("/api/auth/token"))
        #expect(paths.isTokenPath("/api/auth/token?refresh=1"))
        #expect(paths.isTokenPath("/api/auth/session") == false)
        #expect(paths.isTokenPath(nil) == false)
    }
}
