import Foundation
import Observation

@MainActor
@Observable
final class AuthSignInScreenModel {
    var mode = Mode.login {
        didSet {
            guard mode != oldValue else { return }
            fieldErrors = [:]
            dismissToast()
        }
    }
    var name = "" { didSet { revalidateIfNeeded(.name) } }
    var email = "" { didSet { revalidateIfNeeded(.email) } }
    var verifyEmail = "" { didSet { revalidateIfNeeded(.verifyEmail) } }
    var password = "" { didSet { revalidateIfNeeded(.password) } }
    var verifyPassword = "" { didSet { revalidateIfNeeded(.verifyPassword) } }
    private(set) var fieldErrors: [AuthValidationField: String] = [:]
    private(set) var isSubmitting = false
    private(set) var toast: Toast?
    private let configuration: KamaalAuthConfiguration
    @ObservationIgnored private var toastDismissalTask: Task<Void, Never>?

    init(configuration: KamaalAuthConfiguration) { self.configuration = configuration }

    func validate(_ field: AuthValidationField) {
        guard mode == .signUp || !field.requiresSignUp else {
            fieldErrors[field] = nil
            return
        }
        fieldErrors[field] = validationIssue(for: field)?.message
    }

    func submit(using auth: KamaalAuth) async {
        guard !isSubmitting else { return }
        let validationIssues = validationIssues()
        if !validationIssues.isEmpty {
            applyFieldErrors(from: validationIssues)
            showErrorToast(message: KamaalAuthOperationError.validation(validationIssues).message)
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let result: Result<Void, KamaalAuthOperationError> =
            switch mode {
            case .login: await auth.signIn(email: email, password: password)
            case .signUp: await auth.signUp(name: name, email: email, password: password)
            }
        switch result {
        case .failure(let error):
            if case .validation(let issues) = error { applyFieldErrors(from: issues) }
            showErrorToast(message: error.message)
        case .success: dismissToast()
        }
    }

    func dismissToast() {
        toastDismissalTask?.cancel()
        toastDismissalTask = nil
        toast = nil
    }

    private func validationIssues() -> [KamaalAuthValidationIssue] {
        switch mode {
        case .login: KamaalAuthValidator.signInIssues(email: email, password: password)
        case .signUp:
            KamaalAuthValidator.signUpIssues(name: name, email: email, password: password)
                + [
                    KamaalAuthValidator.verifyEmailIssue(email: email, verifyEmail: verifyEmail),
                    KamaalAuthValidator.verifyPasswordIssue(password: password, verifyPassword: verifyPassword),
                ].compactMap(\.self)
        }
    }

    private func validationIssue(for field: AuthValidationField) -> KamaalAuthValidationIssue? {
        switch field {
        case .email: KamaalAuthValidator.emailIssue(email)
        case .verifyEmail: KamaalAuthValidator.verifyEmailIssue(email: email, verifyEmail: verifyEmail)
        case .password: KamaalAuthValidator.passwordIssue(password)
        case .verifyPassword:
            KamaalAuthValidator.verifyPasswordIssue(password: password, verifyPassword: verifyPassword)
        case .name: KamaalAuthValidator.nameIssue(name)
        }
    }

    private func revalidateIfNeeded(_ field: AuthValidationField) {
        guard fieldErrors[field] != nil else { return }
        validate(field)
    }
    private func applyFieldErrors(from issues: [KamaalAuthValidationIssue]) {
        fieldErrors = Dictionary(issues.map { ($0.field, $0.message) }, uniquingKeysWith: { first, _ in first })
    }
    private func showErrorToast(message: String) {
        toastDismissalTask?.cancel()
        toast = Toast(title: String(localized: "Authentication failed"), message: message)
        toastDismissalTask = Task {
            try? await Task.sleep(for: configuration.toastDismissalDelay)
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case login
        case signUp
        var id: Self { self }
        var title: String {
            switch self {
            case .login: String(localized: "Login")
            case .signUp: String(localized: "Sign Up")
            }
        }
    }
}

extension AuthValidationField {
    fileprivate var requiresSignUp: Bool {
        switch self {
        case .email, .password: false
        case .name, .verifyEmail, .verifyPassword: true
        }
    }
}
