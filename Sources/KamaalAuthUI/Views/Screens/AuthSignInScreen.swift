import SwiftUI

struct AuthSignInScreen: View {
    @Environment(KamaalAuth.self) private var auth
    @State private var model: AuthSignInScreenModel
    @FocusState private var focusedField: AuthValidationField?
    private let initialFocus: AuthValidationField?

    init(model: AuthSignInScreenModel, initialFocus: AuthValidationField? = nil) {
        _model = State(initialValue: model)
        self.initialFocus = initialFocus
    }

    init(configuration: KamaalAuthConfiguration) {
        _model = State(initialValue: AuthSignInScreenModel(configuration: configuration))
        initialFocus = nil
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
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
                            }.id(AuthValidationField.name)
                        }
                        AuthFormField(label: "Email", error: model.fieldErrors[.email]) {
                            TextField("jane@example.com", text: $model.email).textContentType(.emailAddress)
                                .authEmailInput().focused($focusedField, equals: .email).submitLabel(.next).onSubmit {
                                    focusedField = model.mode == .signUp ? .verifyEmail : .password
                                }
                        }.id(AuthValidationField.email)
                        if model.mode == .signUp {
                            AuthFormField(label: "Verify email", error: model.fieldErrors[.verifyEmail]) {
                                TextField("jane@example.com", text: $model.verifyEmail).textContentType(.emailAddress)
                                    .authEmailInput().focused($focusedField, equals: .verifyEmail).submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                            }.id(AuthValidationField.verifyEmail)
                        }
                        AuthFormField(label: "Password", error: model.fieldErrors[.password]) {
                            SecureField("8–128 characters", text: $model.password).textContentType(
                                model.mode == .login ? .password : .newPassword
                            ).focused($focusedField, equals: .password).submitLabel(model.mode == .signUp ? .next : .go)
                                .onSubmit {
                                    if model.mode == .signUp { focusedField = .verifyPassword } else { submit() }
                                }
                        }.id(AuthValidationField.password)
                        if model.mode == .signUp {
                            AuthFormField(label: "Verify password", error: model.fieldErrors[.verifyPassword]) {
                                SecureField("8–128 characters", text: $model.verifyPassword).textContentType(
                                    .newPassword
                                )
                                .focused($focusedField, equals: .verifyPassword).submitLabel(.go).onSubmit(submit)
                            }.id(AuthValidationField.verifyPassword)
                        }
                    }
                    AuthSubmitButton(title: model.mode.title, isLoading: model.isSubmitting, action: submit)
                }.frame(maxWidth: 420).padding(32).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(initialFocus == nil ? .top : .bottom)
            .disabled(model.isSubmitting)
            .onAppear {
                if let initialFocus {
                    focusedField = initialFocus
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollProxy.scrollTo(initialFocus, anchor: .center)
                    }
                }
            }
            .onChange(of: focusedField) { oldValue, newValue in
                if let oldValue, oldValue != newValue { model.validate(oldValue) }
                if let newValue { scrollProxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .authToast(model.toast, dismiss: model.dismissToast)
    }

    private func submit() {
        focusedField = nil
        Task { await model.submit(using: auth) }
    }
}
