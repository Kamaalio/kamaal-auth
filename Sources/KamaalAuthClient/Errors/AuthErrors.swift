//
//  AuthErrors.swift
//  KamaalAuth
//

import Foundation

public enum SessionErrors: Error, Sendable {
    case unauthorized
    case unknown(status: Int, payload: String?, cause: (any Error)?)
}

public enum SignInErrors: Error, Sendable {
    /// Either the payload failed validation or the credentials were rejected. `validations` is empty in the latter
    /// case, which is what lets the UI show a generic "wrong email or password" rather than a per-field error.
    case badRequest(validations: [AuthValidationIssue])
    case sessionUnavailable
    case credentialsUnavailable(cause: any Error)
    case unknown(status: Int, payload: String?, cause: (any Error)?)
}

public enum SignUpErrors: Error, Sendable {
    case badRequest(validations: [AuthValidationIssue])
    case conflict
    case sessionUnavailable
    case credentialsUnavailable(cause: any Error)
    case unknown(status: Int, payload: String?, cause: (any Error)?)
}

public enum SignOutErrors: Error, Sendable {
    case unknown(status: Int, payload: String?, cause: (any Error)?)
}

enum CredentialsStorageError: Error {
    case invalidResponseHeaders
}

enum AuthErrorCode: String {
    case invalidEmailOrPassword = "INVALID_EMAIL_OR_PASSWORD"
    case userAlreadyExists = "USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL"
    case sessionNotFound = "SESSION_NOT_FOUND"
    case invalidPayload = "INVALID_PAYLOAD"
}
