//
//  AuthorizationMiddleware.swift
//  KamaalAuth
//

import Foundation
import HTTPTypes
import KamaalAuthClient
import KamaalLogger
import OpenAPIRuntime

private let logger = KamaalLogger(from: AuthorizationMiddleware.self)

/// Signs outgoing requests with the stored JWT, refreshing it first when it has gone stale.
///
/// Install this on the generated client that serves the rest of the API, so every request is authenticated the same
/// way. All the policy lives in ``AuthTokenProvider``; this only attaches what the provider hands back.
///
/// Requests without credentials pass through untouched. A recoverable refresh failure throws a ``SessionErrors``
/// when no usable JWT remains. Session hooks should report that error as a recoverable failure.
public struct AuthorizationMiddleware: ClientMiddleware {
    let tokenProvider: AuthTokenProvider

    public init(tokenProvider: AuthTokenProvider) {
        self.tokenProvider = tokenProvider
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard let authToken = try await tokenProvider.resolveAuthToken().get() else {
            return try await next(request, body, baseURL)
        }

        var authenticated = request
        authenticated.headerFields[.authorization] = "Bearer \(authToken)"
        logger.info("Attached authentication credential; credential=jwt; operationID=\(operationID)")

        return try await next(authenticated, body, baseURL)
    }
}
