//
//  AuthHTTPClient.swift
//  KamaalAuth
//

import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A minimal HTTP client over a `ClientTransport`, used for the auth endpoints this package defines.
///
/// Deliberately not generated: the package owns both ends of this contract, and shipping a code-generation plugin
/// inside a library dependency would force every consumer through plugin-trust prompts and generator-version lockstep.
/// Building on `ClientTransport` rather than `URLSession` keeps the same test doubles usable.
struct AuthHTTPClient: Sendable {
    let serverURL: URL
    let transport: any ClientTransport
    let middlewares: [any ClientMiddleware]

    struct Response: Sendable {
        let status: Int
        let headerFields: HTTPFields
        let body: Data

        func header(_ name: String) -> String? {
            guard let field = HTTPField.Name(name) else { return nil }

            return headerFields[field]
        }
    }

    func send(
        method: HTTPRequest.Method,
        path: String,
        body: (any Encodable)? = nil,
        operationID: String
    ) async throws -> Response {
        var request = HTTPRequest(method: method, scheme: nil, authority: nil, path: path)
        var httpBody: HTTPBody?
        if let body {
            let data = try JSONEncoder().encode(body)
            request.headerFields[.contentType] = "application/json"
            httpBody = HTTPBody(data)
        }
        request.headerFields[.accept] = "application/json"

        let (response, responseBody) = try await sendThroughMiddlewares(
            request: request,
            body: httpBody,
            operationID: operationID
        )

        let data: Data
        if let responseBody {
            data = try await Data(collecting: responseBody, upTo: Self.maximumResponseBytes)
        } else {
            data = Data()
        }

        return Response(status: response.status.code, headerFields: response.headerFields, body: data)
    }

    private func sendThroughMiddlewares(
        request: HTTPRequest,
        body: HTTPBody?,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let transport = transport
        var next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?) = {
            try await transport.send($0, body: $1, baseURL: $2, operationID: operationID)
        }

        for middleware in middlewares.reversed() {
            let tail = next
            next = { request, body, baseURL in
                try await middleware.intercept(
                    request,
                    body: body,
                    baseURL: baseURL,
                    operationID: operationID,
                    next: tail
                )
            }
        }

        return try await next(request, body, serverURL)
    }

    private static let maximumResponseBytes = 1024 * 1024 * 4
}
