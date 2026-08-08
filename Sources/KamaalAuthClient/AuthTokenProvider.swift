//
//  AuthTokenProvider.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore
import KamaalLogger

private let logger = KamaalLogger(from: AuthTokenProvider.self)

/// Hands out an auth token that is safe to sign a request with, refreshing it first when it has gone stale.
///
/// Split out of ``KamaalAuthClientImpl`` because a request middleware needs exactly this and nothing else. A client
/// built from hooks that themselves run through that middleware would be circular; a provider depends only on the
/// credentials store and a way to mint a token from a session token, so it can be built first.
public struct AuthTokenProvider: Sendable {
    private let store: any CredentialsStore
    private let key: String
    private let issueToken: @Sendable () async -> AuthRequestOutcome<AuthCredentialHeaders>

    public init(
        credentialsKey: String,
        credentialsStore: any CredentialsStore,
        issueToken: @escaping @Sendable () async -> AuthRequestOutcome<AuthCredentialHeaders>
    ) {
        key = credentialsKey
        store = credentialsStore
        self.issueToken = issueToken
    }

    /// Whether stored credentials exist and their session has not expired.
    public var hasValidCredentials: Bool {
        guard let credentials = storedCredentials() else { return false }

        return !credentials.sessionHasExpired
    }

    public func credentials() -> Credentials? {
        storedCredentials()
    }

    /// A token safe to sign a request with, or `nil` when the caller should proceed unauthenticated.
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

        switch await issueToken() {
        case .success(let headers):
            do {
                try persist(headers, keepingSessionExpiry: credentials.sessionExpiryDate)
            } catch {
                return .failure(.unknown(status: 500, payload: nil, cause: error))
            }
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

    /// Saves credentials, throwing on failure.
    ///
    /// Callers must surface this rather than swallow it: credentials that were not saved leave the user looking
    /// signed in on this launch and signed out on the next, with no token in between.
    func persist(_ headers: AuthCredentialHeaders, keepingSessionExpiry sessionExpiry: Date? = nil) throws {
        do {
            try store.store(headers.credentials(keepingSessionExpiry: sessionExpiry), forKey: key)
        } catch {
            logger.error("Couldn't save the credentials; reason=\(error)")
            throw error
        }
    }

    /// Records the session expiry so ``hasValidCredentials`` can answer on the next launch without a network call.
    func cacheSessionExpiry(_ expiresAt: Date) {
        guard let credentials = storedCredentials() else { return }

        do {
            try store.store(credentials.settingSessionExpiryDate(expiresAt), forKey: key)
        } catch {
            logger.warning("Couldn't cache the session expiry date; reason=\(error)")
        }
    }

    func deleteCredentials(reason: String) {
        do {
            try store.delete(forKey: key)
            logger.info("Cleared authentication credentials; reason=\(reason)")
        } catch {
            logger.error("Couldn't clear the credentials; reason=\(error)")
        }
    }

    private func storedCredentials() -> Credentials? {
        do {
            return try store.credentials(forKey: key)
        } catch {
            logger.error("Couldn't read stored credentials; treating as signed out; reason=\(error)")

            return nil
        }
    }
}
