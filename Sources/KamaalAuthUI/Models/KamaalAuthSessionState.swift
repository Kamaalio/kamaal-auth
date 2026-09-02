import Foundation

/// Represents the lifecycle state of a ``KamaalAuth`` session.
///
/// Subscribe with ``KamaalAuth/sessionStates()`` when an app needs to perform work after authentication completes
/// without observing `KamaalAuth`'s implementation details.
///
/// - Example:
///   ```swift
///   for await state in auth.sessionStates() {
///       if case .authenticated(let session) = state {
///           print(session.email)
///       }
///   }
///   ```
public enum KamaalAuthSessionState: Sendable, Equatable {
    /// Stored credentials are being checked before the app commits to an authentication result.
    case validatingCredentials
    /// No authenticated session is available.
    case unauthenticated
    /// A validated authenticated session is available.
    case authenticated(UserSession)
}
