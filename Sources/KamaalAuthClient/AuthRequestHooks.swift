//
//  AuthRequestHooks.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore

public struct SignInPayload: Hashable, Sendable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct SignUpPayload: Hashable, Sendable {
    public let email: String
    public let password: String
    public let name: String

    public init(email: String, password: String, name: String) {
        self.email = email
        self.password = password
        self.name = name
    }
}

/// Why a request did not succeed, in the vocabulary the server speaks.
///
/// `code` is the verbatim upstream code (`INVALID_EMAIL_OR_PASSWORD`, …) rather than an enum, so a hook never has to
/// import anything of this package's to describe a failure.
public struct AuthRequestFailure: Sendable {
    public let status: Int
    public let code: String?
    public let validations: [AuthValidationIssue]
    public let cause: (any Error)?

    public init(
        status: Int,
        code: String? = nil,
        validations: [AuthValidationIssue] = [],
        cause: (any Error)? = nil
    ) {
        self.status = status
        self.code = code
        self.validations = validations
        self.cause = cause
    }

    /// The request never reached the server.
    public static func unreachable(_ error: any Error) -> AuthRequestFailure {
        AuthRequestFailure(status: 503, cause: error)
    }
}

public enum AuthRequestOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(AuthRequestFailure)
}

/// The requests a consumer performs on this package's behalf.
///
/// The app already has a generated client for its API; this is where it plugs that in. Keeping the requests on the
/// app's side means this package needs no HTTP stack, no transport, and no knowledge of the app's code generation,
/// which mirrors how the server package takes hooks rather than an auth library.
///
/// What stays here is everything worth sharing: credential storage, the refresh policy, expiry rules, session
/// modelling, and error semantics.
public protocol AuthRequestHooks: Sendable {
    func signUp(_ payload: SignUpPayload) async -> AuthRequestOutcome<AuthCredentialHeaders>

    func signIn(_ payload: SignInPayload) async -> AuthRequestOutcome<AuthCredentialHeaders>

    func signOut() async -> AuthRequestOutcome<Void>

    /// Looks the session up using the stored JWT.
    func session() async -> AuthRequestOutcome<AuthSession>

    /// Mints a fresh JWT. Must authorize with the session token, not the JWT this call replaces, or it will recurse.
    func issueToken() async -> AuthRequestOutcome<AuthCredentialHeaders>
}
