//
//  AuthValidationIssue.swift
//  KamaalAuth
//

import Foundation

/// A single field-level validation failure returned by the server.
public struct AuthValidationIssue: Hashable, Codable, Sendable {
    public let code: String
    public let path: [String]
    public let message: String

    public init(code: String, path: [String], message: String) {
        self.code = code
        self.path = path
        self.message = message
    }

    /// The field this issue points at, i.e. the last path component.
    public var field: String? {
        path.last
    }
}
