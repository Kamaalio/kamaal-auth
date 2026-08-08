import KamaalAuthClient
import Testing

@testable import KamaalAuthUI

@Suite("Auth Sign In Screen Model Tests")
@MainActor
struct AuthSignInScreenModelTests {
    @Test
    func `Clears corrected validation errors`() {
        let model = AuthSignInScreenModel(configuration: .init(appName: "Test"))
        model.email = "invalid"
        model.validate(.email)
        #expect(model.fieldErrors[.email] == "Enter a valid email address.")
        model.email = "jane@example.com"
        #expect(model.fieldErrors[.email] == nil)
    }

    @Test
    func `Shows verification errors without requesting authentication`() async {
        let model = AuthSignInScreenModel(configuration: .init(appName: "Test"))
        let auth = KamaalAuth(
            client: PreviewKamaalAuthClient(), configuration: .init(appName: "Test"),
            cachedSessionStore: CachedUserSessionStoreSpy())
        model.mode = .signUp
        model.name = "Jane Doe"
        model.email = "jane@example.com"
        model.verifyEmail = "other@example.com"
        model.password = "password123"
        model.verifyPassword = "password123"
        await model.submit(using: auth)
        #expect(model.fieldErrors[.verifyEmail] == "Email addresses do not match.")
        #expect(model.toast?.message == "Please correct the highlighted fields.")
    }
}
