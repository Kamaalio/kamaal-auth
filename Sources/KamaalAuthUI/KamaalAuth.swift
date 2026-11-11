import Foundation
import KamaalAuthClient
import KamaalLogger
import KamaalUtils
import Observation

private let logger = KamaalLogger(from: KamaalAuth.self)

/// Owns authentication state and drives the shared sign-in flow.
///
/// - Example:
///   ```swift
///   let auth = KamaalAuth(client: client, configuration: .init(appName: "TCG"))
///   ```
@MainActor
@Observable
public final class KamaalAuth {
    private let client: KamaalAuthClient
    private let waitBeforeSessionRetry: @MainActor (Duration) async -> Void

    let configuration: KamaalAuthConfiguration

    @ObservationIgnored private var cachedSessionStore: CachedUserSessionStore
    @ObservationIgnored private var sessionStateContinuations:
        [UUID: AsyncStream<KamaalAuthSessionState>.Continuation] = [:]
    @ObservationIgnored private var currentSessionState: KamaalAuthSessionState

    /// The authenticated session loaded from the client or its same-day cache.
    public private(set) var session: UserSession?
    /// Whether stored credentials are being validated before displaying an auth state.
    public private(set) var initiallyValidatingToken: Bool
    private(set) var canRetrySessionRestore = false
    @ObservationIgnored private var sessionRestoreAttempt: UUID?

    /// Creates an auth state using the supplied client and app configuration.
    ///
    /// - Example:
    ///   ```swift
    ///   let auth = KamaalAuth(client: client, configuration: .init(appName: "My App"))
    ///   ```
    public convenience init(client: any KamaalAuthClient, configuration: KamaalAuthConfiguration) {
        self.init(
            client: client,
            configuration: configuration,
            cachedSessionStore: UserDefaultsCachedUserSessionStore(configuration: configuration)
        )
    }

    init(
        client: any KamaalAuthClient,
        configuration: KamaalAuthConfiguration,
        cachedSessionStore: CachedUserSessionStore,
        waitBeforeSessionRetry: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.client = client
        self.configuration = configuration
        self.cachedSessionStore = cachedSessionStore
        self.waitBeforeSessionRetry = waitBeforeSessionRetry
        let hasCredentials = client.hasValidCredentials
        initiallyValidatingToken = hasCredentials
        currentSessionState = hasCredentials ? .validatingCredentials : .unauthenticated
        if hasCredentials {
            let attempt = UUID()
            sessionRestoreAttempt = attempt
            Task { await restoreSession(attempt: attempt, retryDelaysInMilliseconds: [500, 1_000, 2_000]) }
        }
    }

    /// Whether an authenticated session is available to the auth gate.
    ///
    /// - Example:
    ///   ```swift
    ///   if auth.isLoggedIn { showAuthenticatedContent() }
    ///   ```
    public var isLoggedIn: Bool { session != nil }

    /// Returns a replaying stream of this instance's authentication lifecycle.
    ///
    /// Each subscriber receives the current state first, then every later state transition. Cancel the consuming task
    /// when the surrounding feature is no longer needed.
    ///
    /// - Returns: A stream beginning with the current ``KamaalAuthSessionState``.
    ///
    /// - Example:
    ///   ```swift
    ///   for await state in auth.sessionStates() {
    ///       if case .unauthenticated = state { showSignInPrompt() }
    ///   }
    ///   ```
    public func sessionStates() -> AsyncStream<KamaalAuthSessionState> {
        let identifier = UUID()
        let currentSessionState = currentSessionState

        return AsyncStream(bufferingPolicy: .unbounded) { [weak self] continuation in
            continuation.yield(currentSessionState)
            self?.sessionStateContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.removeSessionStateContinuation(identifier) }
            }
        }
    }

    /// Signs in with validated credentials, then loads the authenticated session.
    ///
    /// - Returns: A UI-ready error when validation, credentials, or session loading fails.
    /// - Example:
    ///   ```swift
    ///   let result = await auth.signIn(email: "jane@example.com", password: "Password123!")
    ///   ```
    public func signIn(email: String, password: String) async -> Result<Void, KamaalAuthOperationError> {
        let validationIssues = KamaalAuthValidator.signInIssues(email: email, password: password)
        guard validationIssues.isEmpty else { return .failure(.validation(validationIssues)) }
        switch await client.signIn(with: SignInPayload(email: email, password: password)) {
        case .failure(.badRequest(let validations)):
            guard !validations.isEmpty else { return .failure(.invalidCredentials) }
            return .failure(.validation(mapValidationIssues(validations)))
        case .failure(.sessionUnavailable): return .failure(.sessionUnavailable)
        case .failure(.credentialsUnavailable(let cause)):
            return handleCredentialsUnavailable(operation: "Sign in", cause: cause)
        case .failure(.unknown): return handleUnknownAuthError(operation: "Sign in")
        case .success: return await completeAuthSuccess(operation: "Sign in")
        }
    }

    /// Creates an account with validated details, then loads the authenticated session.
    ///
    /// - Returns: A UI-ready error when validation, account creation, or session loading fails.
    /// - Example:
    ///   ```swift
    ///   let result = await auth.signUp(name: "Jane Doe", email: "jane@example.com", password: "Password123!")
    ///   ```
    public func signUp(name: String, email: String, password: String) async -> Result<Void, KamaalAuthOperationError> {
        let validationIssues = KamaalAuthValidator.signUpIssues(name: name, email: email, password: password)
        guard validationIssues.isEmpty else { return .failure(.validation(validationIssues)) }
        switch await client.signUp(with: SignUpPayload(email: email, password: password, name: name)) {
        case .failure(.badRequest(let validations)): return .failure(.validation(mapValidationIssues(validations)))
        case .failure(.conflict): return .failure(.emailAlreadyInUse)
        case .failure(.sessionUnavailable): return .failure(.sessionUnavailable)
        case .failure(.credentialsUnavailable(let cause)):
            return handleCredentialsUnavailable(operation: "Account creation", cause: cause)
        case .failure(.unknown): return handleUnknownAuthError(operation: "Account creation")
        case .success: return await completeAuthSuccess(operation: "Account creation")
        }
    }

    /// Signs out on the server, then clears the local session so the auth gate presents sign in again.
    ///
    /// Local state is cleared even when the server request fails, so people who ask to sign out always end up signed
    /// out.
    ///
    /// - Example:
    ///   ```swift
    ///   await auth.signOut()
    ///   ```
    public func signOut() async {
        sessionRestoreAttempt = nil
        canRetrySessionRestore = false
        if case .failure(let failure) = await client.signOut() {
            logger.warning("Sign out request failed; clearing the local session anyway; reason=\(failure)")
        }
        initiallyValidatingToken = false
        session = nil
        cachedSessionStore.cachedSession = nil
        setSessionState(.unauthenticated)
        logger.info("Signed out.")
    }

    func retrySessionRestore() async {
        guard canRetrySessionRestore, !initiallyValidatingToken else { return }

        let attempt = UUID()
        sessionRestoreAttempt = attempt
        initiallyValidatingToken = true
        canRetrySessionRestore = false
        await restoreSession(attempt: attempt)
    }

    private func restoreSession(attempt: UUID, retryDelaysInMilliseconds: [Int] = []) async {
        guard sessionRestoreAttempt == attempt else { return }

        if let cachedSession = getCachedSessionIfLoadedToday() {
            setSession(cachedSession)
            return
        }

        var result = await fetchSession()
        for delay in retryDelaysInMilliseconds {
            guard case .failure(.serverUnavailable) = result, sessionRestoreAttempt == attempt else { break }

            let jitter = Int.random(in: 0...(delay / 4))
            await waitBeforeSessionRetry(.milliseconds(delay + jitter))
            guard sessionRestoreAttempt == attempt else { return }

            result = await fetchSession()
        }
        guard sessionRestoreAttempt == attempt else { return }

        sessionRestoreAttempt = nil
        initiallyValidatingToken = false
        switch result {
        case .success(let session): setSession(session)
        case .failure(.unauthorized):
            cachedSessionStore.cachedSession = nil
            setSessionState(.unauthenticated)
        case .failure(.serverUnavailable): canRetrySessionRestore = true
        }
    }

    private func fetchSession() async -> Result<UserSession, KamaalAuthFeatureSessionError> {
        await client.session()
            .map { UserSession(name: $0.name, email: $0.email, expiresAt: $0.expiresAt) }
            .mapError {
                switch $0 {
                case .unauthorized:
                    logger.warning("Couldn't load the authenticated session; reason=\($0)")
                    return .unauthorized(context: $0)
                case .unknown:
                    logger.error("Couldn't load the authenticated session from the server; reason=\($0)")
                    return .serverUnavailable(context: $0)
                }
            }
    }

    private func loadAuthenticatedSession() async -> Result<Void, KamaalAuthOperationError> {
        switch await fetchSession() {
        case .failure(.serverUnavailable): return .failure(.serverUnavailable)
        case .failure(.unauthorized): return .failure(.sessionUnavailable)
        case .success(let session):
            setSession(session)
            return .success(())
        }
    }

    private func completeAuthSuccess(operation: String) async -> Result<Void, KamaalAuthOperationError> {
        logger.info("\(operation) completed; loading the new session.")
        return await loadAuthenticatedSession()
    }

    private func handleCredentialsUnavailable(operation: String, cause: Error) -> Result<Void, KamaalAuthOperationError>
    {
        logger.error(label: "\(operation) details could not be saved", error: cause)
        return .failure(.credentialsUnavailable)
    }

    private func handleUnknownAuthError(operation: String) -> Result<Void, KamaalAuthOperationError> {
        logger.error("\(operation) failed while communicating with the server.")
        return .failure(.serverUnavailable)
    }

    private func mapValidationIssues(_ issues: [AuthValidationIssue]) -> [KamaalAuthValidationIssue] {
        issues.compactMap { issue in
            guard let path = issue.path.last else { return nil }
            guard let field = AuthValidationField(rawValue: path) else { return nil }
            return KamaalAuthValidationIssue(field: field, message: issue.message)
        }
    }

    private func setSession(_ session: UserSession) {
        sessionRestoreAttempt = nil
        initiallyValidatingToken = false
        canRetrySessionRestore = false
        self.session = session
        cachedSessionStore.cachedSession = CachedUserSession(session: session, cachedAt: .now)
        setSessionState(.authenticated(session))
        logger.info("Loaded the authenticated session.")
    }

    private func setSessionState(_ state: KamaalAuthSessionState) {
        guard currentSessionState != state else { return }

        currentSessionState = state
        for continuation in sessionStateContinuations.values { continuation.yield(state) }
    }

    private func removeSessionStateContinuation(_ identifier: UUID) {
        sessionStateContinuations[identifier] = nil
    }

    private func getCachedSessionIfLoadedToday() -> UserSession? {
        guard let cachedSession = cachedSessionStore.cachedSession else { return nil }
        guard Calendar.current.isDate(cachedSession.cachedAt, inSameDayAs: .now) else { return nil }
        guard !cachedSession.session.hasExpired else { return nil }
        return cachedSession.session
    }
}

protocol CachedUserSessionStore { var cachedSession: CachedUserSession? { get set } }

@MainActor
private final class UserDefaultsCachedUserSessionStore: CachedUserSessionStore {
    private let key: String
    var cachedSession: CachedUserSession? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(CachedUserSession.self, from: data)
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }

    init(configuration: KamaalAuthConfiguration) { key = "\(configuration.storageNamespace).cachedSession" }
}

private enum KamaalAuthFeatureSessionError: Error {
    case serverUnavailable(context: Error?)
    case unauthorized(context: Error?)
}
