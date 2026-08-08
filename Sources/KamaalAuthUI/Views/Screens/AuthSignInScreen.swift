import SwiftUI

struct AuthSignInScreen: View {
    @Environment(KamaalAuth.self) private var auth
    @State private var model: AuthSignInScreenModel
    @FocusState private var focusedField: FocusedField?

    init(model: AuthSignInScreenModel) {
        _model = State(initialValue: model)
    }

    init(configuration: KamaalAuthConfiguration) {
        _model = State(initialValue: AuthSignInScreenModel(configuration: configuration))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AuthSignInHeader(mode: model.mode, configuration: auth.configuration)
                Picker("Authentication mode", selection: $model.mode) {
                    ForEach(AuthSignInScreenModel.Mode.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented)
                VStack(spacing: 16) {
                    if model.mode == .signUp {
                        AuthFormField(label: "Name", error: model.fieldErrors[.name]) {
                            TextField("Jane Doe", text: $model.name).textContentType(.name).focused(
                                $focusedField, equals: .name
                            ).submitLabel(.next).onSubmit { focusedField = .email }
                        }
                    }
                    AuthFormField(label: "Email", error: model.fieldErrors[.email]) {
                        TextField("jane@example.com", text: $model.email).textContentType(.emailAddress)
                            .authEmailInput().focused($focusedField, equals: .email).submitLabel(.next).onSubmit {
                                focusedField = model.mode == .signUp ? .verifyEmail : .password
                            }
                    }
                    if model.mode == .signUp {
                        AuthFormField(label: "Verify email", error: model.fieldErrors[.verifyEmail]) {
                            TextField("jane@example.com", text: $model.verifyEmail).textContentType(.emailAddress)
                                .authEmailInput().focused($focusedField, equals: .verifyEmail).submitLabel(.next)
                                .onSubmit { focusedField = .password }
                        }
                    }
                    AuthFormField(label: "Password", error: model.fieldErrors[.password]) {
                        SecureField("8–128 characters", text: $model.password).textContentType(
                            model.mode == .login ? .password : .newPassword
                        ).focused($focusedField, equals: .password).submitLabel(model.mode == .signUp ? .next : .go)
                            .onSubmit { if model.mode == .signUp { focusedField = .verifyPassword } else { submit() } }
                    }
                    if model.mode == .signUp {
                        AuthFormField(label: "Verify password", error: model.fieldErrors[.verifyPassword]) {
                            SecureField("8–128 characters", text: $model.verifyPassword).textContentType(.newPassword)
                                .focused($focusedField, equals: .verifyPassword).submitLabel(.go).onSubmit(submit)
                        }
                    }
                }
                AuthSubmitButton(title: model.mode.title, isLoading: model.isSubmitting, action: submit)
            }.frame(maxWidth: 420).padding(32).frame(maxWidth: .infinity)
        }
        .disabled(model.isSubmitting)
        .onChange(of: focusedField) { oldValue, newValue in
            guard let oldValue, oldValue != newValue else { return }
            model.validate(oldValue.validationField)
        }
        .authToast(model.toast, dismiss: model.dismissToast)
    }

    private func submit() {
        focusedField = nil
        Task { await model.submit(using: auth) }
    }
}

private enum FocusedField: Hashable {
    case name, email, verifyEmail, password, verifyPassword
    var validationField: AuthValidationField {
        switch self {
        case .name: .name
        case .email: .email
        case .verifyEmail: .verifyEmail
        case .password: .password
        case .verifyPassword: .verifyPassword
        }
    }
}
