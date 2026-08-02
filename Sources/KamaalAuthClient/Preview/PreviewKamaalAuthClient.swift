//
//  PreviewKamaalAuthClient.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore

/// What a ``PreviewKamaalAuthClient`` should pretend happened.
public enum PreviewAuthOutcome: Sendable {
    case success
    case invalidCredentials
    case emailAlreadyInUse
    case sessionUnavailable
    case serverUnavailable
    case validation(issues: [AuthValidationIssue])
}

/// A client for SwiftUI previews and UI tests that performs no network requests and never touches the Keychain.
public struct PreviewKamaalAuthClient: KamaalAuthClient {
    public let outcome: PreviewAuthOutcome
    public let hasValidCredentials: Bool
    public let previewSession: AuthSession

    public init(
        outcome: PreviewAuthOutcome = .success,
        hasValidCredentials: Bool = false,
        session: AuthSession = PreviewKamaalAuthClient.sampleSession
    ) {
        self.outcome = outcome
        self.hasValidCredentials = hasValidCredentials
        previewSession = session
    }

    public static let sampleSession = AuthSession(
        id: "user_preview",
        name: "John Doe",
        email: "john.doe@example.com",
        emailVerified: true,
        createdAt: .now,
        expiresAt: .distantFuture,
    )

    public func refreshToken() async -> Result<Void, SessionErrors> {
        switch outcome {
        case .success: .success(())
        case .sessionUnavailable, .invalidCredentials: .failure(.unauthorized)
        default: .failure(.unknown(status: 503, payload: nil, cause: nil))
        }
    }

    public func session() async -> Result<AuthSession, SessionErrors> {
        switch outcome {
        case .success: .success(previewSession)
        case .sessionUnavailable, .invalidCredentials: .failure(.unauthorized)
        default: .failure(.unknown(status: 503, payload: nil, cause: nil))
        }
    }

    public func signIn(with payload: SignInPayload) async -> Result<Void, SignInErrors> {
        switch outcome {
        case .success: .success(())
        case .invalidCredentials, .emailAlreadyInUse: .failure(.badRequest(validations: []))
        case .validation(let issues): .failure(.badRequest(validations: issues))
        case .sessionUnavailable: .failure(.sessionUnavailable)
        case .serverUnavailable: .failure(.unknown(status: 503, payload: nil, cause: nil))
        }
    }

    public func signUp(with payload: SignUpPayload) async -> Result<Void, SignUpErrors> {
        switch outcome {
        case .success: .success(())
        case .emailAlreadyInUse: .failure(.conflict)
        case .invalidCredentials: .failure(.badRequest(validations: []))
        case .validation(let issues): .failure(.badRequest(validations: issues))
        case .sessionUnavailable: .failure(.sessionUnavailable)
        case .serverUnavailable: .failure(.unknown(status: 503, payload: nil, cause: nil))
        }
    }

    public func signOut() async -> Result<Void, SignOutErrors> {
        .success(())
    }
}
