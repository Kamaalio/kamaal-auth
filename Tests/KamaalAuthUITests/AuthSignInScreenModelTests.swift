import KamaalAuthClient
import Testing

@testable import KamaalAuthUI

@Suite("Auth Sign In Screen Model Tests")
@MainActor
struct AuthSignInScreenModelTests {
    @Test
    func `Allows submit focus for valid login without sign up fields`() {
        let model = AuthSignInScreenModel(configuration: .init(appName: "Test"))
        model.email = "jane@example.com"
        model.password = "password123"
        #expect(model.canAdvanceToSubmit)
    }

    @Test
    func `Allows submit focus for valid sign up`() {
        let model = makeValidSignUpModel()
        #expect(model.canAdvanceToSubmit)
    }

    @Test(arguments: [AuthSignInScreenModel.Mode.login, .signUp])
    func `Rejects submit focus for untouched empty fields`(_ mode: AuthSignInScreenModel.Mode) {
        let model = AuthSignInScreenModel(configuration: .init(appName: "Test"))
        model.mode = mode
        #expect(model.fieldErrors.isEmpty)
        #expect(!model.canAdvanceToSubmit)
    }

    @Test(arguments: [
        (AuthValidationField.name, ""), (.email, "invalid"), (.verifyEmail, "other@example.com"),
        (.password, "short"), (.verifyPassword, "different123"),
    ])
    func `Rejects submit focus when any sign up field is invalid`(_ field: AuthValidationField, _ value: String) {
        let model = makeValidSignUpModel()
        model[keyPath: inputKeyPath(for: field)] = value
        #expect(model.fieldErrors.isEmpty)
        #expect(!model.canAdvanceToSubmit)
    }

    @Test(arguments: [(AuthValidationField.email, "invalid"), (.password, "short")])
    func `Rejects submit focus when a login field is invalid`(_ field: AuthValidationField, _ value: String) {
        let model = makeValidSignUpModel()
        model.mode = .login
        model[keyPath: inputKeyPath(for: field)] = value
        #expect(model.fieldErrors.isEmpty)
        #expect(!model.canAdvanceToSubmit)
    }

    @Test(arguments: [AuthSignInScreenModel.Mode.login, .signUp])
    func `Rejects submit focus while submitting and restores it afterward`(_ mode: AuthSignInScreenModel.Mode) async {
        let model = makeValidSignUpModel()
        model.mode = mode
        let client = SubmissionCheckingClient {
            #expect(model.isSubmitting)
            #expect(!model.canAdvanceToSubmit)
        }
        let auth = KamaalAuth(
            client: client, configuration: .init(appName: "Test"), cachedSessionStore: CachedUserSessionStoreSpy())

        await model.submit(using: auth)

        #expect(!model.isSubmitting)
        #expect(model.canAdvanceToSubmit)
    }

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

    private func makeValidSignUpModel() -> AuthSignInScreenModel {
        let model = AuthSignInScreenModel(configuration: .init(appName: "Test"))
        model.mode = .signUp
        model.name = "Jane Doe"
        model.email = "jane@example.com"
        model.verifyEmail = "jane@example.com"
        model.password = "password123"
        model.verifyPassword = "password123"
        return model
    }

    private func inputKeyPath(for field: AuthValidationField) -> ReferenceWritableKeyPath<AuthSignInScreenModel, String>
    {
        switch field {
        case .name: \.name
        case .email: \.email
        case .verifyEmail: \.verifyEmail
        case .password: \.password
        case .verifyPassword: \.verifyPassword
        }
    }
}

private struct SubmissionCheckingClient: KamaalAuthClient {
    let onSubmit: @MainActor @Sendable () -> Void
    private let preview = PreviewKamaalAuthClient()

    var hasValidCredentials: Bool { false }
    func validAuthToken() async -> String? { nil }
    func refreshToken() async -> Result<Void, SessionErrors> { await preview.refreshToken() }
    func session() async -> Result<AuthSession, SessionErrors> { await preview.session() }
    func signOut() async -> Result<Void, SignOutErrors> { await preview.signOut() }

    func signIn(with payload: SignInPayload) async -> Result<Void, SignInErrors> {
        await onSubmit()
        return await preview.signIn(with: payload)
    }

    func signUp(with payload: SignUpPayload) async -> Result<Void, SignUpErrors> {
        await onSubmit()
        return await preview.signUp(with: payload)
    }
}
