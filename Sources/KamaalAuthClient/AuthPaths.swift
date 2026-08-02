//
//  AuthPaths.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore

/// The endpoints served by the `@kamaalio/kamaal-auth` router, relative to a configured base path.
///
/// Middlewares match on these paths rather than on a generated operation identifier, so they work against any app's
/// generated OpenAPI client without being coupled to its codegen output.
public struct AuthPaths: Sendable, Hashable {
    public let basePath: String

    public init(basePath: String) {
        self.basePath = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
    }

    public var signUp: String { "\(basePath)/sign-up/email" }
    public var signIn: String { "\(basePath)/sign-in/email" }
    public var signOut: String { "\(basePath)/sign-out" }
    public var session: String { "\(basePath)/session" }
    public var token: String { "\(basePath)/token" }
    public var jwks: String { "\(basePath)/jwks" }

    /// Whether a request path targets the token endpoint, ignoring any query string.
    public func isTokenPath(_ path: String?) -> Bool {
        guard let path else { return false }

        return path.split(separator: "?", maxSplits: 1).first.map(String.init) == token
    }
}

public enum AuthDefaults {
    public static let basePath = "/app-api/auth"
    public static let sessionCookieName = "better-auth.session_token"
}
