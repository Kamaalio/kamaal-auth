import KamaalAuthClient
import Testing

@testable import KamaalAuthUI

@Suite("KamaalAuth Tests")
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
