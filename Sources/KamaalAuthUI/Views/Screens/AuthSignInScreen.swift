import SwiftUI

struct AuthSignInScreen: View {
    @Environment(KamaalAuth.self) private var auth
    @State private var model: AuthSignInScreenModel
    @FocusState private var focusedField: AuthValidationField?
    @FocusState private var submitFocused: Bool
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
                                .onKeyPress(.tab, phases: .down) { handleLastFieldTab($0, field: .password) }
                        }.id(AuthValidationField.password)
                        if model.mode == .signUp {
                            AuthFormField(label: "Verify password", error: model.fieldErrors[.verifyPassword]) {
                                SecureField("8–128 characters", text: $model.verifyPassword).textContentType(
                                    .newPassword
                                )
                                .focused($focusedField, equals: .verifyPassword).submitLabel(.go).onSubmit(submit)
                                .onKeyPress(.tab, phases: .down) { handleLastFieldTab($0, field: .verifyPassword) }
                            }.id(AuthValidationField.verifyPassword)
                        }
                    }
                    AuthSubmitButton(
                        title: model.mode.title, isLoading: model.isSubmitting, focused: $submitFocused, action: submit
                    ).id(ScrollTarget.submit)
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
                if let newValue {
                    submitFocused = false
                    scrollProxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onChange(of: submitFocused) { _, isFocused in
                if isFocused {
                    focusedField = nil
                    scrollProxy.scrollTo(ScrollTarget.submit, anchor: .center)
                }
            }
            .onChange(of: model.mode) { _, _ in
                submitFocused = false
            }
        }
        .authToast(model.toast, dismiss: model.dismissToast)
    }

    private var firstField: AuthValidationField {
        switch model.mode {
        case .login: .email
        case .signUp: .name
        }
    }

    private var lastField: AuthValidationField {
        switch model.mode {
        case .login: .password
        case .signUp: .verifyPassword
        }
    }

    private func submit() {
        focusedField = nil
        submitFocused = false
        Task { await model.submit(using: auth) }
    }

    private func handleLastFieldTab(_ press: KeyPress, field: AuthValidationField) -> KeyPress.Result {
        guard !press.modifiers.contains(.shift) else { return .ignored }
        guard field == lastField else { return .ignored }
        model.validate(field)
        if model.canAdvanceToSubmit {
            focusedField = nil
            submitFocused = true
        } else {
            submitFocused = false
            focusedField = firstField
        }
        return .handled
    }

    private enum ScrollTarget: Hashable {
        case submit
    }
}
