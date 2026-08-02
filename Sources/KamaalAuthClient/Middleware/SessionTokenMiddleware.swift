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

/// Authorizes the token endpoint with the long-lived session token instead of the JWT.
///
/// Matching is on the request path rather than a generated operation identifier, so this stays usable from an app's
/// own generated client without depending on its codegen output.
public struct SessionTokenMiddleware: ClientMiddleware {
    let configuration: KamaalAuthClientConfiguration

    public init(configuration: KamaalAuthClientConfiguration) {
        self.configuration = configuration
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard configuration.paths.isTokenPath(request.path) else { return try await next(request, body, baseURL) }

        let credentials = try configuration.credentialsStore.credentials(forKey: configuration.credentialsKey)
        guard let credentials else { return try await next(request, body, baseURL) }

        var authorized = request
        authorized.headerFields[.authorization] = "Bearer \(credentials.sessionToken)"
        logger.info("Attached authentication credential; credential=session_token; operationID=\(operationID)")

        return try await next(authorized, body, baseURL)
    }
}
