//
//  AuthorizationMiddleware.swift
//  KamaalAuth
//

import Foundation
import HTTPTypes
import KamaalAuthCore
import KamaalLogger
import OpenAPIRuntime

private let logger = KamaalLogger(from: AuthorizationMiddleware.self)

/// Signs requests with the stored JWT, refreshing it first when it is stale or close to expiring.
///
/// Plug this into an app's own generated OpenAPI client so non-auth requests are authenticated the same way.
public struct AuthorizationMiddleware: ClientMiddleware {
    let configuration: KamaalAuthClientConfiguration
    let tokenRefresher: TokenRefresher

    public init(configuration: KamaalAuthClientConfiguration, transport: any ClientTransport) {
        self.configuration = configuration
        tokenRefresher = TokenRefresher(
            http: AuthHTTPClient(
                serverURL: configuration.serverURL,
                transport: transport,
                middlewares: [
                    SessionTokenMiddleware(configuration: configuration),
                    OriginHeaderMiddleware(configuration: configuration),
                ],
            ),
            configuration: configuration,
        )
    }

    init(configuration: KamaalAuthClientConfiguration, tokenRefresher: TokenRefresher) {
        self.configuration = configuration
        self.tokenRefresher = tokenRefresher
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        // The token endpoint authenticates with the session token, not the JWT. Signing it here would recurse.
        guard !configuration.paths.isTokenPath(request.path) else { return try await next(request, body, baseURL) }

        let store = configuration.credentialsStore
        guard let credentials = try store.credentials(forKey: configuration.credentialsKey) else {
            return try await next(request, body, baseURL)
        }

        guard !credentials.sessionHasExpired else {
            try store.delete(forKey: configuration.credentialsKey)
            logger.warning("Deleted authentication credentials; reason=session_expired")

            return try await next(request, body, baseURL)
        }

        let signingCredentials = try await refreshIfNeeded(credentials, operationID: operationID)
        var signed = request
        signed.headerFields[.authorization] = "Bearer \(signingCredentials.authToken)"
        if configuration.sendsSessionCookie {
            signed.headerFields[.cookie] = cookieValue(
                existing: signed.headerFields[.cookie],
                sessionToken: signingCredentials.sessionToken,
            )
        }
        logger.info("Attached authentication credential; credential=jwt; operationID=\(operationID)")

        return try await next(signed, body, baseURL)
    }

    private func refreshIfNeeded(_ credentials: Credentials, operationID: String) async throws -> Credentials {
        guard credentials.shouldUpdateSession || credentials.authTokenWillExpireSoon() else { return credentials }

        let reason = credentials.shouldUpdateSession ? "session_update_age" : "auth_token_expiring"
        let age = Int(Date.now.timeIntervalSince(credentials.lastSessionUpdate))
        let remaining = Int(credentials.authTokenExpiryDate.timeIntervalSinceNow)
        logger.info(
            "Refreshing the authentication token; reason=\(reason); credential=session_token; auth_token_age_s=\(age); auth_token_remaining_s=\(remaining)"
        )

        do {
            try await tokenRefresher.refreshToken().get()
        } catch {
            logger.warning("Authentication token refresh failed; operationID=\(operationID); error=\(error)")
            throw error
        }

        guard let refreshed = try tokenRefresher.credentials() else { throw SessionErrors.unauthorized }

        return refreshed
    }

    private func cookieValue(existing: String?, sessionToken: String) -> String {
        let sessionCookie = "\(AuthDefaults.sessionCookieName)=\(sessionToken)"
        guard let existing, !existing.isEmpty else { return sessionCookie }

        return "\(existing); \(sessionCookie)"
    }
}
