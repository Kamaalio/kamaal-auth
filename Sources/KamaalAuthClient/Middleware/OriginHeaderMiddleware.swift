//
//  OriginHeaderMiddleware.swift
//  KamaalAuth
//

import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Sends the app's URL scheme as `Origin`, satisfying the server's trusted-origin check.
public struct OriginHeaderMiddleware: ClientMiddleware {
    let configuration: KamaalAuthClientConfiguration
    let bundle: Bundle

    public init(configuration: KamaalAuthClientConfiguration, bundle: Bundle = .main) {
        self.configuration = configuration
        self.bundle = bundle
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard let scheme = configuration.resolvedOriginScheme(bundle: bundle) else {
            return try await next(request, body, baseURL)
        }

        var withOrigin = request
        withOrigin.headerFields[.origin] = "\(scheme)://"

        return try await next(withOrigin, body, baseURL)
    }
}
