//
//  AuthErrors.swift
//  KamaalAuth
//

import Foundation

/// Errors are `Equatable` so tests can assert on them directly.
///
/// `cause` and `payload` are deliberately excluded from equality: two failures that reached the same outcome for the
/// same reason are the same failure, regardless of which underlying error carried them there.
public enum SessionErrors: LocalizedError, Equatable, Sendable {
    case unauthorized
    case unknown(status: Int, payload: String?, cause: (any Error)?)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: String(localized: "Your session has expired. Please sign in again.")
        case .unknown: String(localized: "Your session could not be retrieved.")
        }
    }

    public static func == (lhs: SessionErrors, rhs: SessionErrors) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): true
        case (.unknown(let lhsStatus, _, _), .unknown(let rhsStatus, _, _)): lhsStatus == rhsStatus
        default: false
        }
    }
}

public enum SignInErrors: LocalizedError, Equatable, Sendable {
    /// Either the payload failed validation or the credentials were rejected. `validations` is empty in the latter
    /// case, which is what lets the UI show a generic "wrong email or password" rather than a per-field error.
    case badRequest(validations: [AuthValidationIssue])
    case sessionUnavailable
    case credentialsUnavailable(cause: any Error)
    case unknown(status: Int, payload: String?, cause: (any Error)?)

    public var errorDescription: String? {
        switch self {
        case .badRequest: String(localized: "Please check the details you entered and try again.")
        case .sessionUnavailable: String(localized: "Signing in succeeded but the session could not be started.")
        case .credentialsUnavailable: String(localized: "Your sign-in details could not be saved.")
        case .unknown: String(localized: "Signing in failed. Please try again.")
        }
    }

    public static func == (lhs: SignInErrors, rhs: SignInErrors) -> Bool {
        switch (lhs, rhs) {
        case (.badRequest(let lhsValidations), .badRequest(let rhsValidations)): lhsValidations == rhsValidations
        case (.sessionUnavailable, .sessionUnavailable): true
        case (.credentialsUnavailable, .credentialsUnavailable): true
        case (.unknown(let lhsStatus, _, _), .unknown(let rhsStatus, _, _)): lhsStatus == rhsStatus
        default: false
        }
    }
}

public enum SignUpErrors: LocalizedError, Equatable, Sendable {
    case badRequest(validations: [AuthValidationIssue])
    case conflict
    case sessionUnavailable
    case credentialsUnavailable(cause: any Error)
    case unknown(status: Int, payload: String?, cause: (any Error)?)

    public var errorDescription: String? {
        switch self {
        case .badRequest: String(localized: "Please check the details you entered and try again.")
        case .conflict: String(localized: "An account with that email address already exists.")
        case .sessionUnavailable: String(localized: "The account was created but the session could not be started.")
        case .credentialsUnavailable: String(localized: "Your sign-in details could not be saved.")
        case .unknown: String(localized: "Creating your account failed. Please try again.")
        }
    }

    public static func == (lhs: SignUpErrors, rhs: SignUpErrors) -> Bool {
        switch (lhs, rhs) {
        case (.badRequest(let lhsValidations), .badRequest(let rhsValidations)): lhsValidations == rhsValidations
        case (.conflict, .conflict): true
        case (.sessionUnavailable, .sessionUnavailable): true
        case (.credentialsUnavailable, .credentialsUnavailable): true
        case (.unknown(let lhsStatus, _, _), .unknown(let rhsStatus, _, _)): lhsStatus == rhsStatus
        default: false
        }
    }
}

public enum SignOutErrors: LocalizedError, Equatable, Sendable {
    case unknown(status: Int, payload: String?, cause: (any Error)?)

    public var errorDescription: String? {
        String(localized: "Signing out failed. Please try again.")
    }

    public static func == (lhs: SignOutErrors, rhs: SignOutErrors) -> Bool {
        switch (lhs, rhs) {
        case (.unknown(let lhsStatus, _, _), .unknown(let rhsStatus, _, _)): lhsStatus == rhsStatus
        }
    }
}

enum AuthErrorCode: String {
    case invalidEmailOrPassword = "INVALID_EMAIL_OR_PASSWORD"
    case userAlreadyExists = "USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL"
    case sessionNotFound = "SESSION_NOT_FOUND"
    case invalidPayload = "INVALID_PAYLOAD"
}
