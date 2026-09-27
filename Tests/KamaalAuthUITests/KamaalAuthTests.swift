import KamaalAuthClient
import Testing

@testable import KamaalAuthUI

// Session state streams never finish, so a missed transition would otherwise hang the whole test run.
@Suite("KamaalAuth Tests", .timeLimit(.minutes(1)))
@MainActor
struct KamaalAuthTests {
    @Test
    func `Does not validate when credentials are missing`() {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        #expect(auth.initiallyValidatingToken == false)
        #expect(auth.isLoggedIn == false)
    }

    @Test
    func `Loads a session when credentials are valid`() async {
        let cache = CachedUserSessionStoreSpy()
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(hasValidCredentials: true), configuration: configuration,
            cachedSessionStore: cache)
        await yield(until: { !auth.initiallyValidatingToken })
        #expect(auth.isLoggedIn)
        #expect(cache.cachedSession?.session.name == "John Doe")
    }

    @Test
    func `Uses a same day cached session`() async {
        let cached = UserSession(name: "Cached", email: "cached@example.com", expiresAt: .distantFuture)
        let cache = CachedUserSessionStoreSpy(cachedSession: CachedUserSession(session: cached, cachedAt: .now))
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(hasValidCredentials: true), configuration: configuration,
            cachedSessionStore: cache)
        await yield(until: { !auth.initiallyValidatingToken })
        #expect(auth.session == cached)
    }

    @Test(arguments: [
        PreviewAuthOutcome.invalidCredentials, .emailAlreadyInUse, .sessionUnavailable, .serverUnavailable,
    ])
    func `Maps sign in errors`(_ outcome: PreviewAuthOutcome) async {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(outcome: outcome), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        let result = await auth.signIn(email: "jane@example.com", password: "password123")
        #expect((try? result.get()) == nil)
    }

    @Test
    func `Replays unauthenticated state when credentials are missing`() async {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        var states = auth.sessionStates().makeAsyncIterator()

        #expect(await states.next() == .unauthenticated)
    }

    @Test
    func `Publishes validation and authenticated states when stored credentials are valid`() async {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(hasValidCredentials: true), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        var states = auth.sessionStates().makeAsyncIterator()

        #expect(await states.next() == .validatingCredentials)
        #expect(
            await states.next()
                == .authenticated(
                    .init(
                        name: "John Doe",
                        email: "john.doe@example.com",
                        expiresAt: .distantFuture,
                    ))
        )
    }

    @Test(arguments: [AuthSignInScreenModel.Mode.login, .signUp])
    func `Publishes authenticated state after successful interactive authentication`(
        _ mode: AuthSignInScreenModel.Mode,
    ) async throws {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        var states = auth.sessionStates().makeAsyncIterator()
        _ = await states.next()

        let result: Result<Void, KamaalAuthOperationError>
        switch mode {
        case .login: result = await auth.signIn(email: "jane@example.com", password: "password123")
        case .signUp: result = await auth.signUp(name: "Jane Doe", email: "jane@example.com", password: "password123")
        }

        try result.get()
        #expect(
            await states.next()
                == .authenticated(
                    .init(
                        name: "John Doe",
                        email: "john.doe@example.com",
                        expiresAt: .distantFuture,
                    ))
        )
    }

    @Test
    func `Signs out and clears the session`() async {
        let cache = CachedUserSessionStoreSpy()
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(hasValidCredentials: true), configuration: configuration,
            cachedSessionStore: cache)
        await yield(until: { !auth.initiallyValidatingToken })
        #expect(auth.isLoggedIn)

        await auth.signOut()

        #expect(auth.isLoggedIn == false)
        #expect(auth.session == nil)
        #expect(cache.cachedSession == nil)
    }

    @Test
    func `Clears the local session even when the server sign out fails`() async {
        let cached = UserSession(name: "Cached", email: "cached@example.com", expiresAt: .distantFuture)
        let cache = CachedUserSessionStoreSpy(cachedSession: CachedUserSession(session: cached, cachedAt: .now))
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(outcome: .serverUnavailable, hasValidCredentials: true),
            configuration: configuration, cachedSessionStore: cache)
        await yield(until: { !auth.initiallyValidatingToken })
        #expect(auth.isLoggedIn)

        await auth.signOut()

        #expect(auth.isLoggedIn == false)
        #expect(cache.cachedSession == nil)
    }

    @Test
    func `Publishes unauthenticated state after signing out`() async throws {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        var states = auth.sessionStates().makeAsyncIterator()
        _ = await states.next()
        try await auth.signIn(email: "jane@example.com", password: "password123").get()
        _ = await states.next()

        await auth.signOut()

        #expect(await states.next() == .unauthenticated)
    }

    private var configuration: KamaalAuthConfiguration { .init(appName: "Test") }
}

@MainActor
final class CachedUserSessionStoreSpy: CachedUserSessionStore {
    var cachedSession: CachedUserSession?
    init(cachedSession: CachedUserSession? = nil) { self.cachedSession = cachedSession }
}

@MainActor
private func yield(until condition: @MainActor () -> Bool, iterations: Int = 1_000) async {
    var count = 0
    while !condition(), count < iterations {
        await Task.yield()
        count += 1
    }
}
