//
//  MiddlewareTests.swift
//  KamaalAuth
//

import Foundation
import HTTPTypes
import KamaalAuthClient
import KamaalAuthCore
import KamaalAuthTestSupport
import OpenAPIRuntime
import Testing

@testable import KamaalAuthOpenAPI

private let credentialsKey = "test.credentials"
private let baseURL = URL(fileURLWithPath: "/mock-server")

@discardableResult
private func storeCredentials(
    in store: InMemoryCredentialsStore,
    authToken: String = "stored.auth.token",
    authTokenExpiryDate: Date = Date.now.addingTimeInterval(604_800),
    lastSessionUpdate: Date = .now,
    sessionExpiryDate: Date? = Date.now.addingTimeInterval(2_592_000)
) throws -> Credentials {
    let credentials = Credentials(
        authToken: authToken,
        authTokenExpiryDate: authTokenExpiryDate,
        sessionToken: "stored-session-token",
        sessionUpdateAge: 86_400,
        lastSessionUpdate: lastSessionUpdate,
        sessionExpiryDate: sessionExpiryDate,
    )
    try store.store(credentials, forKey: credentialsKey)

    return credentials
}

private func makeProvider(
    store: InMemoryCredentialsStore,
    issued: AuthCredentialHeaders? = MockAuthRequestHooks.credentials(authToken: "refreshed.jwt.token")
) -> AuthTokenProvider {
    AuthTokenProvider(credentialsKey: credentialsKey, credentialsStore: store) {
        guard let issued else { return .failure(AuthRequestFailure(status: 401)) }

        return .success(issued)
    }
}

/// Runs one request through a middleware and reports the request that came out the other side.
private func intercept(
    _ middleware: some ClientMiddleware,
    request: HTTPRequest = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/app-api/cards")
) async throws -> HTTPRequest {
    nonisolated(unsafe) var forwarded: HTTPRequest?
    _ = try await middleware.intercept(request, body: nil, baseURL: baseURL, operationID: "test") { request, _, _ in
        forwarded = request

        return (HTTPResponse(status: .ok), nil)
    }

    return try #require(forwarded)
}

@Suite("Authorization middleware")
struct AuthorizationMiddlewareTests {
    @Test("Attaches the stored JWT as a bearer token")
    func attachesStoredToken() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)

        let forwarded = try await intercept(AuthorizationMiddleware(tokenProvider: makeProvider(store: store)))

        #expect(forwarded.headerFields[.authorization] == "Bearer stored.auth.token")
    }

    @Test("Refreshes first when the stored token is nearly expired")
    func refreshesWhenExpiring() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store, authTokenExpiryDate: Date.now.addingTimeInterval(60))

        let forwarded = try await intercept(AuthorizationMiddleware(tokenProvider: makeProvider(store: store)))

        #expect(forwarded.headerFields[.authorization] == "Bearer refreshed.jwt.token")
    }

    @Test("Passes the request through untouched when nothing is stored")
    func passesThroughWithoutCredentials() async throws {
        let store = InMemoryCredentialsStore()

        let forwarded = try await intercept(AuthorizationMiddleware(tokenProvider: makeProvider(store: store)))

        #expect(forwarded.headerFields[.authorization] == nil)
    }

    @Test("Passes through and clears credentials once the session has expired")
    func clearsExpiredSession() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store, sessionExpiryDate: .distantPast)

        let forwarded = try await intercept(AuthorizationMiddleware(tokenProvider: makeProvider(store: store)))

        #expect(forwarded.headerFields[.authorization] == nil)
        #expect(try store.credentials(forKey: credentialsKey) == nil)
    }

    @Test("Passes through when a needed refresh fails")
    func passesThroughWhenRefreshFails() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store, authTokenExpiryDate: Date.now.addingTimeInterval(60))

        let middleware = AuthorizationMiddleware(tokenProvider: makeProvider(store: store, issued: nil))
        let forwarded = try await intercept(middleware)

        #expect(forwarded.headerFields[.authorization] == nil)
    }

    @Test("Leaves the rest of the request alone")
    func leavesRequestAlone() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)
        var request = HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/app-api/cards")
        request.headerFields[.contentType] = "application/json"

        let forwarded = try await intercept(
            AuthorizationMiddleware(tokenProvider: makeProvider(store: store)),
            request: request,
        )

        #expect(forwarded.method == .post)
        #expect(forwarded.path == "/app-api/cards")
        #expect(forwarded.headerFields[.contentType] == "application/json")
    }
}

@Suite("Session token middleware")
struct SessionTokenMiddlewareTests {
    @Test("Attaches the session token rather than the JWT")
    func attachesSessionToken() async throws {
        let store = InMemoryCredentialsStore()
        try storeCredentials(in: store)

        let forwarded = try await intercept(
            SessionTokenMiddleware(credentialsKey: credentialsKey, credentialsStore: store))

        #expect(forwarded.headerFields[.authorization] == "Bearer stored-session-token")
    }

    @Test("Never refreshes, so minting a token cannot recurse")
    func neverRefreshes() async throws {
        let store = InMemoryCredentialsStore()
        // Both conditions that would make the authorization middleware refresh.
        try storeCredentials(
            in: store,
            authTokenExpiryDate: Date.now.addingTimeInterval(60),
            lastSessionUpdate: Date.now.addingTimeInterval(-90_000),
        )

        let forwarded = try await intercept(
            SessionTokenMiddleware(credentialsKey: credentialsKey, credentialsStore: store))

        #expect(forwarded.headerFields[.authorization] == "Bearer stored-session-token")
    }

    @Test("Passes the request through untouched when nothing is stored")
    func passesThroughWithoutCredentials() async throws {
        let store = InMemoryCredentialsStore()

        let forwarded = try await intercept(
            SessionTokenMiddleware(credentialsKey: credentialsKey, credentialsStore: store))

        #expect(forwarded.headerFields[.authorization] == nil)
    }
}
