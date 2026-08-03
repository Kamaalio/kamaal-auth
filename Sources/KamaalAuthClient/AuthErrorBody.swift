//
//  AuthErrorBody.swift
//  KamaalAuth
//

import Foundation

/// The error envelope the `@kamaalio/kamaal-auth` router returns.
///
/// Hooks use this to turn an error response body into an ``AuthRequestFailure`` without each app re-deriving the
/// shape. Apps whose generated client already decodes the body can build ``AuthRequestFailure`` directly instead.
public struct AuthErrorBody: Decodable, Sendable {
    public let message: String?
    public let code: String?
    public let context: Context?

    public struct Context: Decodable, Sendable {
        public let validations: [Issue]?
    }

    public struct Issue: Decodable, Sendable {
        public let code: String
        public let path: [AuthJSONValue]
        public let message: String
    }

    public var validationIssues: [AuthValidationIssue] {
        (context?.validations ?? []).map { issue in
            AuthValidationIssue(
                code: issue.code,
                path: issue.path.compactMap(Self.pathComponent(from:)),
                message: issue.message,
            )
        }
    }

    /// Decodes an error body, returning `nil` when it is not this envelope.
    public static func decode(from data: Data) -> AuthErrorBody? {
        try? JSONDecoder().decode(AuthErrorBody.self, from: data)
    }

    /// Builds a failure from a status and an error body, defaulting sensibly when the body is absent or unexpected.
    public static func failure(status: Int, body: Data?) -> AuthRequestFailure {
        guard let body, let decoded = decode(from: body) else { return AuthRequestFailure(status: status) }

        return AuthRequestFailure(status: status, code: decoded.code, validations: decoded.validationIssues)
    }

    private static func pathComponent(from value: AuthJSONValue) -> String? {
        switch value {
        case .string(let string): string
        case .number(let number): String(Int(number))
        default: nil
        }
    }
}
