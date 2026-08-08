import Foundation
import KamaalAuthCore

/// The minimal authenticated user data displayed by the auth UI.
///
/// - Example:
///   ```swift
///   let session = UserSession(name: "Jane Doe", email: "jane@example.com", expiresAt: .distantFuture)
///   ```
public struct UserSession: Hashable, Codable, Expirable {
    /// The authenticated person's display name.
    public let name: String
    /// The authenticated person's email address.
    public let email: String
    /// The date when the authenticated session expires.
    public let expiresAt: Date

    /// Creates session data for the authenticated person.
    ///
    /// - Example:
    ///   ```swift
    ///   let session = UserSession(name: "Jane Doe", email: "jane@example.com", expiresAt: .distantFuture)
    ///   ```
    public init(name: String, email: String, expiresAt: Date) {
        self.name = name
        self.email = email
        self.expiresAt = expiresAt
    }
}
