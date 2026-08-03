//
//  MockAuthRequestHooks.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthClient
import KamaalAuthCore

/// A scriptable ``AuthRequestHooks`` for tests: queue outcomes per operation, then assert on what was called.
public final class MockAuthRequestHooks: AuthRequestHooks, @unchecked Sendable {
    public enum Operation: String, Sendable, Hashable {
        case signUp
        case signIn
        case signOut
        case session
        case issueToken
    }

    public struct Call: Sendable {
        public let operation: Operation
        /// The session token `issueToken` was called with, if any.
        public let sessionToken: String?
    }

    private let lock = NSLock()
    private var credentialOutcomes: [Operation: [AuthRequestOutcome<AuthCredentialHeaders>]] = [:]
    private var sessionOutcomes: [AuthRequestOutcome<AuthSession>] = []
    private var signOutOutcomes: [AuthRequestOutcome<Void>] = []
    private var recorded: [Call] = []

    public init() {}

    public var calls: [Call] {
        lock.withLock { recorded }
    }

    public func callCount(_ operation: Operation) -> Int {
        calls.filter { $0.operation == operation }.count
    }

    public func lastCall(_ operation: Operation) -> Call? {
        calls.last { $0.operation == operation }
    }

    @discardableResult
    public func stub(
        _ operation: Operation,
        with outcome: AuthRequestOutcome<AuthCredentialHeaders>
    ) -> MockAuthRequestHooks {
        lock.withLock { credentialOutcomes[operation, default: []].append(outcome) }

        return self
    }

    @discardableResult
    public func stubSession(_ outcome: AuthRequestOutcome<AuthSession>) -> MockAuthRequestHooks {
        lock.withLock { sessionOutcomes.append(outcome) }

        return self
    }

    @discardableResult
    public func stubSignOut(_ outcome: AuthRequestOutcome<Void>) -> MockAuthRequestHooks {
        lock.withLock { signOutOutcomes.append(outcome) }

        return self
    }

    /// Credentials good enough for a test that does not care about the exact values.
    public static func credentials(
        authToken: String = "header.payload.signature",
        sessionToken: String = "session-token",
        expiresInSeconds: Int = 604_800,
        sessionUpdateAgeSeconds: Int = 86_400
    ) -> AuthCredentialHeaders {
        AuthCredentialHeaders(
            authToken: authToken,
            authTokenExpiresInSeconds: expiresInSeconds,
            sessionToken: sessionToken,
            sessionUpdateAgeSeconds: sessionUpdateAgeSeconds,
        )
    }

    public func signUp(_ payload: SignUpPayload) async -> AuthRequestOutcome<AuthCredentialHeaders> {
        record(.signUp)

        return nextCredentialOutcome(.signUp)
    }

    public func signIn(_ payload: SignInPayload) async -> AuthRequestOutcome<AuthCredentialHeaders> {
        record(.signIn)

        return nextCredentialOutcome(.signIn)
    }

    public func issueToken(sessionToken: String) async -> AuthRequestOutcome<AuthCredentialHeaders> {
        record(.issueToken, sessionToken: sessionToken)

        return nextCredentialOutcome(.issueToken)
    }

    public func session() async -> AuthRequestOutcome<AuthSession> {
        record(.session)

        return lock.withLock {
            guard !sessionOutcomes.isEmpty else { return .failure(AuthRequestFailure(status: 404)) }
            // Keep the last outcome so repeated calls keep behaving the same way.
            return sessionOutcomes.count == 1 ? sessionOutcomes[0] : sessionOutcomes.removeFirst()
        }
    }

    public func signOut() async -> AuthRequestOutcome<Void> {
        record(.signOut)

        return lock.withLock {
            guard !signOutOutcomes.isEmpty else { return .success(()) }
            return signOutOutcomes.count == 1 ? signOutOutcomes[0] : signOutOutcomes.removeFirst()
        }
    }

    private func record(_ operation: Operation, sessionToken: String? = nil) {
        lock.withLock { recorded.append(Call(operation: operation, sessionToken: sessionToken)) }
    }

    private func nextCredentialOutcome(_ operation: Operation) -> AuthRequestOutcome<AuthCredentialHeaders> {
        lock.withLock {
            guard var queued = credentialOutcomes[operation], !queued.isEmpty else {
                return .failure(AuthRequestFailure(status: 404))
            }
            guard queued.count > 1 else { return queued[0] }

            let next = queued.removeFirst()
            credentialOutcomes[operation] = queued

            return next
        }
    }
}
