//
//  RedactingLoggingMiddleware.swift
//  KamaalAuth
//

import Foundation
import HTTPTypes
import KamaalLogger
import OpenAPIRuntime

private let logger = KamaalLogger(from: RedactingLoggingMiddleware.self)

/// Logs requests and responses, redacting token values so credentials never reach the log.
public struct RedactingLoggingMiddleware: ClientMiddleware {
    let redactedKeys: Set<String>

    public init(redactedKeys: Set<String> = ["token"]) {
        self.redactedKeys = redactedKeys
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        logger.info("Request; operationID=\(operationID); path=\(request.path ?? "")")

        let (response, responseBody) = try await next(request, body, baseURL)
        logger.info("Response; operationID=\(operationID); status=\(response.status.code)")

        return (response, responseBody)
    }

    /// Replaces the value of every redacted key in a JSON string. Exposed for testing the redaction rule itself.
    public func redact(json: String) -> String {
        redactedKeys.reduce(json) { partial, key in
            partial.replacingOccurrences(
                of: "\"\(key)\"\\s*:\\s*\"[^\"]*\"",
                with: "\"\(key)\":\"<redacted>\"",
                options: .regularExpression,
            )
        }
    }
}
