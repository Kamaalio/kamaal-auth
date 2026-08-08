import Foundation

public enum KamaalAuthOperationError: LocalizedError, Equatable {
    case validation([KamaalAuthValidationIssue])
    case invalidCredentials
    case emailAlreadyInUse
    case credentialsUnavailable
    case serverUnavailable
    case sessionUnavailable

    public var errorDescription: String? {
        message
    }

    var message: String {
        switch self {
        case .validation: String(localized: "Please correct the highlighted fields.")
        case .invalidCredentials: String(localized: "The email or password is incorrect.")
        case .emailAlreadyInUse: String(localized: "An account already exists for this email address.")
        case .credentialsUnavailable: String(localized: "Your sign-in details could not be saved. Please try again.")
        case .serverUnavailable: String(localized: "The server is unavailable. Please try again.")
        case .sessionUnavailable:
            String(localized: "Your account was authenticated, but the session could not be loaded. Please try again.")
        }
    }
}
