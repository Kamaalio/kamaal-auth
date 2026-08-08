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
    private let tokens: AuthTokenProvider

    public init(hooks: any AuthRequestHooks, credentialsKey: String, credentialsStore: any CredentialsStore) {
        self.hooks = hooks
        tokens = AuthTokenProvider(credentialsKey: credentialsKey, credentialsStore: credentialsStore) {
            await hooks.issueToken()
        }
    }

    public init(hooks: any AuthRequestHooks, credentialsKey: String) {
        self.init(hooks: hooks, credentialsKey: credentialsKey, credentialsStore: KeychainCredentialsStore())
    }

    /// Builds a client that shares an already-constructed provider.
    ///
    /// Use this when a request middleware was wired with the same provider, so both refresh through one place.
    public init(hooks: any AuthRequestHooks, tokenProvider: AuthTokenProvider) {
        self.hooks = hooks
        tokens = tokenProvider
    }

    public var hasValidCredentials: Bool {
        tokens.hasValidCredentials
    }

    public func validAuthToken() async -> String? {
        await tokens.validAuthToken()
    }

    public func refreshToken() async -> Result<Void, SessionErrors> {
        await tokens.refreshToken()
    }

    public func session() async -> Result<AuthSession, SessionErrors> {
        guard tokens.credentials() != nil else { return .failure(.unauthorized) }

        switch await hooks.session() {
        case .success(let session):
            tokens.cacheSessionExpiry(session.expiresAt)

            return .success(session)
        case .failure(let failure):
            guard failure.status == 401 || failure.status == 404 else {
                return .failure(.unknown(status: failure.status, payload: failure.code, cause: failure.cause))
            }
            tokens.deleteCredentials(reason: "session_rejected")

            return .failure(.unauthorized)
        }
    }

    public func signIn(with payload: SignInPayload) async -> Result<Void, SignInErrors> {
        // Drop any stale credentials first so a failed sign-in cannot leave the previous user signed in.
        tokens.deleteCredentials(reason: "signing_in")

        switch await hooks.signIn(payload) {
        case .success(let headers):
            do {
                try tokens.persist(headers)
            } catch {
                return .failure(.credentialsUnavailable(cause: error))
            }
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
            do {
                try tokens.persist(headers)
            } catch {
                return .failure(.credentialsUnavailable(cause: error))
            }
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
        tokens.deleteCredentials(reason: "signed_out")

        guard case .failure(let failure) = outcome else { return .success(()) }

        logger.warning("Sign out request failed; local credentials cleared anyway; status=\(failure.status)")

        return .failure(.unknown(status: failure.status, payload: failure.code, cause: failure.cause))
    }
}
