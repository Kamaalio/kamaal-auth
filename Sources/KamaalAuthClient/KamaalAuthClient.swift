//
//  KamaalAuthClient.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore
import KamaalLogger

private let logger = KamaalLogger(from: KamaalAuthClientImpl.self)

public protocol KamaalAuthClient: Sendable {
    /// Whether stored credentials exist and their session has not expired.
    var hasValidCredentials: Bool { get }

    /// A JWT safe to sign a request with, refreshing first when the stored one is stale or nearly expired.
    ///
    /// This is the seam for an app's own request pipeline: a middleware calls this and attaches the result.
    func validAuthToken() async -> String?

    func refreshToken() async -> Result<Void, SessionErrors>
    func session() async -> Result<AuthSession, SessionErrors>
    func signIn(with payload: SignInPayload) async -> Result<Void, SignInErrors>
    func signUp(with payload: SignUpPayload) async -> Result<Void, SignUpErrors>
    func signOut() async -> Result<Void, SignOutErrors>
}

public struct KamaalAuthClientImpl: KamaalAuthClient {
    private let hooks: any AuthRequestHooks
    private let store: any CredentialsStore
    private let key: String

    public init(hooks: any AuthRequestHooks, credentialsKey: String, credentialsStore: any CredentialsStore) {
        self.hooks = hooks
        store = credentialsStore
        key = credentialsKey
    }

    public init(hooks: any AuthRequestHooks, credentialsKey: String) {
        self.init(hooks: hooks, credentialsKey: credentialsKey, credentialsStore: KeychainCredentialsStore())
    }

    public var hasValidCredentials: Bool {
        guard let credentials = storedCredentials() else { return false }

        return !credentials.sessionHasExpired
    }

    public func validAuthToken() async -> String? {
        guard let credentials = storedCredentials() else { return nil }

        guard !credentials.sessionHasExpired else {
            deleteCredentials(reason: "session_expired")

            return nil
        }

        guard credentials.shouldUpdateSession || credentials.authTokenWillExpireSoon() else {
            return credentials.authToken
        }

        let reason = credentials.shouldUpdateSession ? "session_update_age" : "auth_token_expiring"
        logger.info("Refreshing the authentication token; reason=\(reason); credential=session_token")

        guard case .success = await refreshToken() else { return nil }

        return storedCredentials()?.authToken
    }

    public func refreshToken() async -> Result<Void, SessionErrors> {
        guard let credentials = storedCredentials() else { return .failure(.unauthorized) }

        switch await hooks.issueToken(sessionToken: credentials.sessionToken) {
        case .success(let headers):
            persist(headers, keepingSessionExpiry: credentials.sessionExpiryDate)
            logger.info("Authentication token refresh completed; credential=session_token")

            return .success(())
        case .failure(let failure):
            guard failure.status == 401 || failure.status == 404 else {
                return .failure(.unknown(status: failure.status, payload: failure.code, cause: failure.cause))
            }
            deleteCredentials(reason: "refresh_rejected")

            return .failure(.unauthorized)
        }
    }

    public func session() async -> Result<AuthSession, SessionErrors> {
        guard storedCredentials() != nil else { return .failure(.unauthorized) }

        switch await hooks.session() {
        case .success(let session):
            cacheSessionExpiry(session.expiresAt)

            return .success(session)
        case .failure(let failure):
            guard failure.status == 401 || failure.status == 404 else {
                return .failure(.unknown(status: failure.status, payload: failure.code, cause: failure.cause))
            }
            deleteCredentials(reason: "session_rejected")

            return .failure(.unauthorized)
        }
    }

    public func signIn(with payload: SignInPayload) async -> Result<Void, SignInErrors> {
        // Drop any stale credentials first so a failed sign-in cannot leave the previous user signed in.
        deleteCredentials(reason: "signing_in")

        switch await hooks.signIn(payload) {
        case .success(let headers):
            persist(headers)
            logger.info("Sign in completed and the session details were saved.")

            return .success(())
        case .failure(let failure):
            switch failure.status {
            case 400: return .failure(.badRequest(validations: failure.validations))
            case 401 where failure.code == AuthErrorCode.invalidEmailOrPassword.rawValue:
                return .failure(.badRequest(validations: []))
            case 401:
                logger.warning("Sign in was authorized but the session could not be established afterward.")

                return .failure(.sessionUnavailable)
            default:
                return .failure(.unknown(status: failure.status, payload: failure.code, cause: failure.cause))
            }
        }
    }

    public func signUp(with payload: SignUpPayload) async -> Result<Void, SignUpErrors> {
        switch await hooks.signUp(payload) {
        case .success(let headers):
            persist(headers)
            logger.info("Account creation completed and the session details were saved.")

            return .success(())
        case .failure(let failure):
            switch failure.status {
            case 400: return .failure(.badRequest(validations: failure.validations))
            case 409: return .failure(.conflict)
            case 401:
                logger.warning("Account creation was authorized but the session could not be established afterward.")

                return .failure(.sessionUnavailable)
            default:
                return .failure(.unknown(status: failure.status, payload: failure.code, cause: failure.cause))
            }
        }
    }

    public func signOut() async -> Result<Void, SignOutErrors> {
        let outcome = await hooks.signOut()

        // Clear locally whatever the server said: a user who asked to sign out should end up signed out even when the
        // server is unreachable.
        deleteCredentials(reason: "signed_out")

        guard case .failure(let failure) = outcome else { return .success(()) }

        logger.warning("Sign out request failed; local credentials cleared anyway; status=\(failure.status)")

        return .failure(.unknown(status: failure.status, payload: failure.code, cause: failure.cause))
    }

    private func storedCredentials() -> Credentials? {
        do {
            return try store.credentials(forKey: key)
        } catch {
            logger.error("Couldn't read stored credentials; treating as signed out; reason=\(error)")

            return nil
        }
    }

    private func persist(_ headers: AuthCredentialHeaders, keepingSessionExpiry sessionExpiry: Date? = nil) {
        do {
            try store.store(headers.credentials(keepingSessionExpiry: sessionExpiry), forKey: key)
        } catch {
            logger.error("Couldn't save the credentials; reason=\(error)")
        }
    }

    /// Records the session expiry so `hasValidCredentials` can answer on the next launch without a network call.
    private func cacheSessionExpiry(_ expiresAt: Date) {
        guard let credentials = storedCredentials() else { return }

        do {
            try store.store(credentials.settingSessionExpiryDate(expiresAt), forKey: key)
        } catch {
            logger.warning("Couldn't cache the session expiry date; reason=\(error)")
        }
    }

    private func deleteCredentials(reason: String) {
        do {
            try store.delete(forKey: key)
            logger.info("Cleared authentication credentials; reason=\(reason)")
        } catch {
            logger.error("Couldn't clear the credentials; reason=\(error)")
        }
    }
}
