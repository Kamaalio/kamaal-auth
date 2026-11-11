import KamaalAuthClient
import SwiftUI
import Testing

@testable import KamaalAuthUI

@Suite("Auth Sign In Screen Snapshot Tests")
@MainActor
struct AuthSignInScreenSnapshotTests {
    @Test
    func `Renders the sign in screen`() async {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        await assertScreenSnapshot(testName: #function) { Text("Signed in").kamaalAuth(auth) }
    }

    @Test
    func `Renders the signed in screen after signing up`() async {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        _ = await auth.signUp(name: "Jane Doe", email: "jane@example.com", password: "Password123!")
        #expect(auth.isLoggedIn)
        await assertScreenSnapshot(testName: #function) { Text("Signed in").kamaalAuth(auth) }
    }

    @Test
    func `Renders the retry screen when session restoration is unavailable`() async throws {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(outcome: .serverUnavailable, hasValidCredentials: true),
            configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy(),
            waitBeforeSessionRetry: { _ in })
        await yield(until: { auth.canRetrySessionRestore })
        try #require(auth.canRetrySessionRestore)
        await assertScreenSnapshot(testName: #function) { Text("Signed in").kamaalAuth(auth) }
    }

    private var configuration: KamaalAuthConfiguration { .init(appName: "App") }
}
