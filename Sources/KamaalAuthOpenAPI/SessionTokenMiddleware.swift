//
//  SessionTokenMiddleware.swift
//  KamaalAuth
//

import Foundation
import HTTPTypes
import KamaalAuthCore
import KamaalLogger
import OpenAPIRuntime

private let logger = KamaalLogger(from: SessionTokenMiddleware.self)

/// Authorizes with the long-lived session token rather than the JWT.
///
/// Install this only on the client used to mint tokens.
///
/// It reads the credentials store directly instead of going through ``AuthTokenProvider``, for two reasons: a
/// provider would refresh, and a refresh that authorizes itself through a refreshing middleware never terminates;
/// and the provider is built *from* the token client, so depending on it here would be a construction cycle.
public struct SessionTokenMiddleware: ClientMiddleware {
    let credentialsKey: String
    let credentialsStore: any CredentialsStore

    public init(credentialsKey: String, credentialsStore: any CredentialsStore) {
        self.credentialsKey = credentialsKey
        self.credentialsStore = credentialsStore
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let credentials: Credentials?
        do {
            credentials = try credentialsStore.credentials(forKey: credentialsKey)
        } catch {
            logger.error("Couldn't read stored credentials; sending unauthenticated; reason=\(error)")
            credentials = nil
        }
        guard let credentials else { return try await next(request, body, baseURL) }

        var authorized = request
        authorized.headerFields[.authorization] = "Bearer \(credentials.sessionToken)"
        logger.info("Attached authentication credential; credential=session_token; operationID=\(operationID)")

        return try await next(authorized, body, baseURL)
    }
}
