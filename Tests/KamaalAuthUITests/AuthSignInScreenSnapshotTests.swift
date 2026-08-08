import KamaalAuthClient
import SwiftUI
import Testing

@testable import KamaalAuthUI

@Suite("Auth Sign In Screen Snapshot Tests")
@MainActor
struct AuthSignInScreenSnapshotTests {
    @Test
    func `Renders the sign in screen`() {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        assertScreenSnapshot(testName: #function) { Text("Signed in").kamaalAuth(auth) }
    }

    @Test
    func `Renders the signed in screen after signing up`() async {
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        _ = await auth.signUp(name: "Jane Doe", email: "jane@example.com", password: "Password123!")
        #expect(auth.isLoggedIn)
        assertScreenSnapshot(testName: #function) { Text("Signed in").kamaalAuth(auth) }
    }

    private var configuration: KamaalAuthConfiguration { .init(appName: "App") }
}
