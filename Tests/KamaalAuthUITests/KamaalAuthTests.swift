import Foundation
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

    @Test
    func `Retries startup restoration without asking the user to sign in`() async {
        let client = SessionRestoreClient()
        let auth = makeRestoringAuth(client: client)
        var states = auth.sessionStates().makeAsyncIterator()

        #expect(await states.next() == .validatingCredentials)
        await yield(until: { auth.canRetrySessionRestore })
        #expect(auth.canRetrySessionRestore)
        #expect(!auth.initiallyValidatingToken)
        #expect(!auth.isLoggedIn)
        #expect(client.sessionRequests == 4)

        let retry = Task { await auth.retrySessionRestore() }
        await yield(until: { client.hasPendingRetry })
        #expect(auth.initiallyValidatingToken)
        await auth.retrySessionRestore()
        client.finishRetry(with: .success(PreviewKamaalAuthClient.sampleSession))
        await retry.value

        let session = UserSession(name: "John Doe", email: "john.doe@example.com", expiresAt: .distantFuture)
        #expect(await states.next() == .authenticated(session))
        #expect(auth.session == session)
        #expect(!auth.canRetrySessionRestore)
        #expect(!auth.initiallyValidatingToken)
        #expect(client.sessionRequests == 5)
        #expect(client.signInRequests == 0)
    }

    @Test
    func `Automatically restores the session after a temporary startup failure`() async {
        let client = SessionRestoreClient(initialFailures: 1)
        var retryDelays: [Duration] = []
        let auth = makeRestoringAuth(client: client) { retryDelays.append($0) }

        await yield(until: { client.hasPendingRetry })
        #expect(auth.initiallyValidatingToken)
        #expect(!auth.canRetrySessionRestore)
        #expect(retryDelays.count == 1)
        #expect(retryDelays.allSatisfy { (.milliseconds(500)...(.milliseconds(625))).contains($0) })

        client.finishRetry(with: .success(PreviewKamaalAuthClient.sampleSession))
        await yield(until: { !auth.initiallyValidatingToken })

        #expect(auth.isLoggedIn)
        #expect(!auth.canRetrySessionRestore)
        #expect(client.sessionRequests == 2)
    }

    @Test
    func `Stops automatic retries when the server rejects the session`() async {
        let client = SessionRestoreClient(initialFailures: 1)
        let auth = makeRestoringAuth(client: client)
        var states = auth.sessionStates().makeAsyncIterator()
        #expect(await states.next() == .validatingCredentials)

        await yield(until: { client.hasPendingRetry })
        client.finishRetry(with: .failure(.unauthorized))

        #expect(await states.next() == .unauthenticated)
        #expect(!auth.canRetrySessionRestore)
        #expect(client.sessionRequests == 2)
    }

    @Test
    func `Shows sign-in when the retry confirms the session is gone`() async {
        let client = SessionRestoreClient()
        let auth = makeRestoringAuth(client: client)
        var states = auth.sessionStates().makeAsyncIterator()
        #expect(await states.next() == .validatingCredentials)
        await yield(until: { auth.canRetrySessionRestore })

        let retry = Task { await auth.retrySessionRestore() }
        await yield(until: { client.hasPendingRetry })
        client.finishRetry(with: .failure(.unauthorized))
        await retry.value

        #expect(await states.next() == .unauthenticated)
        #expect(!auth.canRetrySessionRestore)
        #expect(!auth.initiallyValidatingToken)
        #expect(!auth.isLoggedIn)
    }

    @Test
    func `Ignores a pending startup retry after sign-out`() async {
        let client = SessionRestoreClient()
        let auth = makeRestoringAuth(client: client)
        var states = auth.sessionStates().makeAsyncIterator()
        #expect(await states.next() == .validatingCredentials)
        await yield(until: { auth.canRetrySessionRestore })

        let retry = Task { await auth.retrySessionRestore() }
        await yield(until: { client.hasPendingRetry })
        await auth.signOut()
        client.finishRetry(with: .success(PreviewKamaalAuthClient.sampleSession))
        await retry.value

        #expect(await states.next() == .unauthenticated)
        #expect(!auth.isLoggedIn)
        #expect(!auth.canRetrySessionRestore)
        #expect(!auth.initiallyValidatingToken)
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

    private func makeRestoringAuth(
        client: SessionRestoreClient, waitBeforeSessionRetry: @escaping @MainActor (Duration) async -> Void = { _ in }
    ) -> KamaalAuth {
        let oldSession = UserSession(name: "Cached", email: "cached@example.com", expiresAt: .distantFuture)
        let cache = CachedUserSessionStoreSpy(
            cachedSession: CachedUserSession(session: oldSession, cachedAt: .distantPast))
        return KamaalAuth(
            client: client, configuration: configuration, cachedSessionStore: cache,
            waitBeforeSessionRetry: waitBeforeSessionRetry)
    }

    private var configuration: KamaalAuthConfiguration { .init(appName: "Test") }
}

@MainActor
private final class SessionRestoreClient: KamaalAuthClient {
    nonisolated let hasValidCredentials = true
    private let initialFailures: Int
    private(set) var sessionRequests = 0
    private(set) var signInRequests = 0
    private var retry: CheckedContinuation<Result<AuthSession, SessionErrors>, Never>?
    var hasPendingRetry: Bool { retry != nil }

    init(initialFailures: Int = 4) { self.initialFailures = initialFailures }

    @MainActor
    func session() async -> Result<AuthSession, SessionErrors> {
        sessionRequests += 1
        if sessionRequests <= initialFailures {
            return .failure(.unknown(status: 503, payload: nil, cause: nil))
        }
        guard sessionRequests == initialFailures + 1 else {
            Issue.record("A second retry began while one was already running.")
            return .failure(.unauthorized)
        }
        return await withCheckedContinuation { retry = $0 }
    }

    func finishRetry(with result: Result<AuthSession, SessionErrors>) {
        let pendingRetry = retry
        retry = nil
        pendingRetry?.resume(returning: result)
    }

    func validAuthToken() async -> String? { nil }

    func refreshToken() async -> Result<Void, SessionErrors> { .success(()) }

    @MainActor
    func signIn(with payload: SignInPayload) async -> Result<Void, SignInErrors> {
        signInRequests += 1
        return .success(())
    }

    func signUp(with payload: SignUpPayload) async -> Result<Void, SignUpErrors> { .success(()) }

    func signOut() async -> Result<Void, SignOutErrors> { .success(()) }
}

@MainActor
final class CachedUserSessionStoreSpy: CachedUserSessionStore {
    var cachedSession: CachedUserSession?
    init(cachedSession: CachedUserSession? = nil) { self.cachedSession = cachedSession }
}

@MainActor
func yield(until condition: @MainActor () -> Bool, iterations: Int = 1_000) async {
    var count = 0
    while !condition(), count < iterations {
        await Task.yield()
        count += 1
    }
}
