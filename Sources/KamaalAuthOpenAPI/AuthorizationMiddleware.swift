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
/// An unauthenticated request is passed through untouched rather than failed, leaving it to the server to answer
/// with a 401. The client has no better answer than the server does.
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
        guard let authToken = await tokenProvider.validAuthToken() else {
            return try await next(request, body, baseURL)
        }

        var authenticated = request
        authenticated.headerFields[.authorization] = "Bearer \(authToken)"
        logger.info("Attached authentication credential; credential=jwt; operationID=\(operationID)")

        return try await next(authenticated, body, baseURL)
    }
}
