//
//  WirePayloads.swift
//  KamaalAuth
//

import Foundation

/// The JSON shapes the `@kamaalio/kamaal-auth` router emits.
///
/// Hand-written rather than generated: this package defines the server routes too, so these are its own contract
/// rather than a description of somebody else's API.
enum Wire {
    struct AuthResponse: Decodable {
        let token: String
        let user: User
    }

    struct SessionResponse: Decodable {
        let session: Session
        let user: User
    }

    struct TokenResponse: Decodable {
        let token: String
    }

    struct Session: Decodable {
        let expiresAt: Date
        let createdAt: Date
        let updatedAt: Date

        private enum CodingKeys: String, CodingKey {
            case expiresAt = "expires_at"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    /// Decoded as a loose dictionary so unknown app-specific fields survive as extras.
    struct User: Decodable {
        let id: String
        let name: String
        let email: String
        let emailVerified: Bool
        let createdAt: Date
        let extras: [String: AuthJSONValue]

        private static let knownKeys: Set<String> = ["id", "name", "email", "email_verified", "created_at"]

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode([String: AuthJSONValue].self)

            guard let id = raw["id"]?.stringValue else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Missing user id")
            }
            guard let name = raw["name"]?.stringValue else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Missing user name")
            }
            guard let email = raw["email"]?.stringValue else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Missing user email")
            }

            self.id = id
            self.name = name
            self.email = email
            emailVerified = raw["email_verified"]?.boolValue ?? false
            createdAt =
                raw["created_at"]?.stringValue.flatMap(Wire.date(fromISO8601:)) ?? Date(timeIntervalSince1970: 0)
            extras = raw.filter { !Self.knownKeys.contains($0.key) }
        }
    }

    struct ErrorResponse: Decodable {
        let message: String?
        let code: String?
        let context: ErrorContext?
    }

    struct ErrorContext: Decodable {
        let validations: [Issue]?
    }

    struct Issue: Decodable {
        let code: String
        let path: [AuthJSONValue]
        let message: String
    }

    struct SignInRequest: Encodable {
        let email: String
        let password: String
    }

    struct SignUpRequest: Encodable {
        let email: String
        let password: String
        let name: String
    }

    /// The server emits fractional seconds, but tolerate their absence rather than failing a whole session decode.
    ///
    /// Formatters are built per call because `ISO8601DateFormatter` is not `Sendable`, and these run only when a
    /// session or auth response is decoded.
    static func date(fromISO8601 string: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        return plain.date(from: string)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = Wire.date(fromISO8601: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
            }

            return date
        }

        return decoder
    }
}
