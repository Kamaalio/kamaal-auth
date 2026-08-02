//
//  MockAuthTransport.swift
//  KamaalAuth
//

import Foundation
import HTTPTypes
import KamaalAuthCore
import OpenAPIRuntime

/// A canned response for ``MockAuthTransport`` to return.
public struct MockAuthResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public init(status: Int, headers: [String: String] = [:], json: String) {
        self.init(status: status, headers: headers, body: Data(json.utf8))
    }

    /// A response carrying the four credential headers the client persists.
    public static func authenticated(
        status: Int,
        json: String,
        authToken: String = "header.payload.signature",
        sessionToken: String = "session-token",
        expiresInSeconds: Int = 604_800,
        sessionUpdateAge: Int = 86_400
    ) -> MockAuthResponse {
        MockAuthResponse(
            status: status,
            headers: [
                AuthHeaderNames.authToken: authToken,
                AuthHeaderNames.authTokenExpiry: String(expiresInSeconds),
                AuthHeaderNames.sessionToken: sessionToken,
                AuthHeaderNames.sessionUpdateAge: String(sessionUpdateAge),
            ],
            json: json,
        )
    }
}

/// A record of one request the client made.
public struct MockAuthRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data?

    /// Looks a header up without regard to case, since HTTP header names are case-insensitive.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public var bodyString: String? {
        body.flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// A `ClientTransport` that answers from a queue of canned responses and records what it was asked.
public final class MockAuthTransport: ClientTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: [MockAuthResponse]]
    private var fallback: MockAuthResponse
    private var recorded: [MockAuthRequest] = []

    /// - Parameters:
    ///   - responses: Keyed by request path. Each call pops the next response for that path; the last one repeats.
    ///   - fallback: Returned when a path has no queued response.
    public init(responses: [String: [MockAuthResponse]] = [:], fallback: MockAuthResponse = .init(status: 404)) {
        self.responses = responses
        self.fallback = fallback
    }

    public var requests: [MockAuthRequest] {
        lock.withLock { recorded }
    }

    public func requests(forPath path: String) -> [MockAuthRequest] {
        requests.filter { $0.path == path }
    }

    public func enqueue(_ response: MockAuthResponse, forPath path: String) {
        lock.withLock { responses[path, default: []].append(response) }
    }

    public func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let bodyData: Data? = if let body { try await Data(collecting: body, upTo: 1024 * 1024) } else { nil }
        let path = request.path ?? ""

        let response: MockAuthResponse = lock.withLock {
            recorded.append(
                MockAuthRequest(
                    method: request.method.rawValue,
                    path: path,
                    headers: Dictionary(
                        request.headerFields.map { ($0.name.canonicalName, $0.value) },
                        uniquingKeysWith: { first, _ in first },
                    ),
                    body: bodyData,
                )
            )

            guard var queued = responses[path], !queued.isEmpty else { return fallback }
            let next = queued.removeFirst()
            // Keep the last response so repeated calls to the same path keep succeeding.
            responses[path] = queued.isEmpty ? [next] : queued

            return next
        }

        var fields = HTTPFields()
        for (name, value) in response.headers {
            guard let fieldName = HTTPField.Name(name) else { continue }
            fields[fieldName] = value
        }

        return (HTTPResponse(status: .init(code: response.status), headerFields: fields), HTTPBody(response.body))
    }
}
