//
//  AuthSession.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore

/// The signed-in user, as far as this package is concerned.
///
/// Fields the package does not model are preserved verbatim in ``extras``, so an app can carry its own per-user state
/// (a preferred currency, a feature flag) through the shared session without this package knowing about it.
public struct AuthSession: Hashable, Codable, Sendable, Expirable {
    public let id: String
    public let name: String
    public let email: String
    public let emailVerified: Bool
    public let createdAt: Date
    public let expiresAt: Date
    public let extras: [String: AuthJSONValue]

    public init(
        id: String,
        name: String,
        email: String,
        emailVerified: Bool,
        createdAt: Date,
        expiresAt: Date,
        extras: [String: AuthJSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.emailVerified = emailVerified
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.extras = extras
    }

    /// Decodes the app-specific user fields into a type of the app's choosing.
    public func decodeExtras<T: Decodable>(as type: T.Type = T.self) throws -> T {
        let data = try JSONEncoder().encode(extras)

        return try JSONDecoder().decode(T.self, from: data)
    }

    public func extra(_ key: String) -> AuthJSONValue? {
        extras[key]
    }
}
