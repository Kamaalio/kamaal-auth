import KamaalAuthClient
import SwiftUI
import Testing

@testable import KamaalAuthUI

@Suite("Auth Sign In Screen Focused Field Snapshot Tests")
@MainActor
struct AuthSignInScreenFocusedFieldSnapshotTests {
    @Test
    func `Keeps the focused sign up password visible in a compact viewport`() async {
        let configuration = KamaalAuthConfiguration(appName: "App")
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(), configuration: configuration,
            cachedSessionStore: CachedUserSessionStoreSpy())
        let model = AuthSignInScreenModel(configuration: configuration)
        model.mode = .signUp
        model.name = "Jane Doe"
        model.email = "jane@example.com"
        model.verifyEmail = "jane@example.com"
        #expect(model.mode == .signUp)
        #expect(!model.canAdvanceToSubmit)

        await assertScreenSnapshot(testName: #function, compact: true) {
            NavigationStack { AuthSignInScreen(model: model, initialFocus: .password) }
                .environment(auth)
        }
    }
}
