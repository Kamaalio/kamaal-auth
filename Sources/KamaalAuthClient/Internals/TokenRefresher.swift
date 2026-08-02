//
//  TokenRefresher.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore
import KamaalLogger

private let logger = KamaalLogger(from: TokenRefresher.self)

/// Mints a fresh JWT from the stored session token and persists the result.
struct TokenRefresher: Sendable {
    let http: AuthHTTPClient
    let configuration: KamaalAuthClientConfiguration

    var store: any CredentialsStore { configuration.credentialsStore }
    var key: String { configuration.credentialsKey }

    func refreshToken() async -> Result<Void, SessionErrors> {
        logger.info("Starting authentication token refresh; credential=session_token")

        let response: AuthHTTPClient.Response
        do {
            response = try await http.send(method: .get, path: configuration.paths.token, operationID: "authToken")
        } catch {
            logger.warning("Authentication token refresh request failed; status=503")

            return .failure(.unknown(status: 503, payload: nil, cause: error))
        }

        switch response.status {
        case 200: break
        case 401:
            logger.warning("Authentication token refresh rejected; credentials_deleted=true")

            return deleteCredentials(then: .unauthorized)
        default:
            logger.warning("Authentication token refresh received an unexpected status; status=\(response.status)")

            return .failure(
                .unknown(status: response.status, payload: String(data: response.body, encoding: .utf8), cause: nil))
        }

        do {
            guard try storeCredentials(from: response) else {
                logger.error("The token refresh response did not include valid session details to save.")

                return .failure(
                    .unknown(status: 500, payload: nil, cause: CredentialsStorageError.invalidResponseHeaders))
            }
        } catch {
            return .failure(.unknown(status: 500, payload: nil, cause: error))
        }

        logger.info("Authentication token refresh completed; credential=session_token")

        return .success(())
    }

    /// Persists the credentials carried by the four `set-*` response headers.
    /// - Returns: `false` when a required header is missing or malformed.
    @discardableResult
    func storeCredentials(from response: AuthHTTPClient.Response) throws -> Bool {
        guard let authToken = response.header(AuthHeaderNames.authToken),
            let sessionToken = response.header(AuthHeaderNames.sessionToken),
            let expiryHeader = response.header(AuthHeaderNames.authTokenExpiry),
            let updateAgeHeader = response.header(AuthHeaderNames.sessionUpdateAge),
            let expiresInSeconds = Int(expiryHeader),
            let sessionUpdateAge = Int(updateAgeHeader)
        else { return false }

        logger.info("Saving sign-in details securely.")

        let existing = try store.credentials(forKey: key)
        let credentials = Credentials(
            authToken: authToken,
            authTokenExpiryDate: Date.now.addingTimeInterval(TimeInterval(expiresInSeconds)),
            sessionToken: sessionToken,
            sessionUpdateAge: TimeInterval(sessionUpdateAge),
            lastSessionUpdate: .now,
            sessionExpiryDate: existing?.sessionExpiryDate,
        )
        try store.store(credentials, forKey: key)
        logger.info("Saved sign-in details securely.")

        return true
    }

    func credentials() throws -> Credentials? {
        try store.credentials(forKey: key)
    }

    func deleteCredentials<Success>(then error: SessionErrors) -> Result<Success, SessionErrors> {
        do {
            try store.delete(forKey: key)
            logger.warning("Deleted authentication credentials; reason=\(error)")
        } catch {
            return .failure(.unknown(status: 500, payload: nil, cause: error))
        }

        return .failure(error)
    }
}
