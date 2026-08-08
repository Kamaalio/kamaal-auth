//
//  AuthTokenHeaders.swift
//  KamaalAuth
//

import KamaalAuthClient
import KamaalAuthCore
import KamaalLogger

private let logger = KamaalLogger(from: AuthTokenHeadersMapper.self)

/// The four `set-*` credential headers, as swift-openapi-generator's idiomatic naming strategy emits them on a
/// generated operation's response.
///
/// The generator turns `set-auth-token` into `setAuthToken` and produces a distinct nominal `Headers` type per
/// operation, so this is a structural protocol rather than a shared base type: any generated `Headers` struct that
/// already has these four members satisfies it with an empty conformance declaration.
///
/// ```swift
/// extension Operations.PostAppApiAuthSignInEmail.Output.Ok.Headers: AuthTokenHeaders {}
/// ```
public protocol AuthTokenHeaders: Sendable {
    var setAuthToken: String { get }
    var setAuthTokenExpiry: String { get }
    var setSessionToken: String { get }
    var setSessionUpdateAge: String { get }
}

extension AuthCredentialHeaders {
    /// Builds credentials from a generated operation's response headers.
    ///
    /// The wire names (`set-auth-token`, …) are this package's own contract, so the mapping belongs here rather than
    /// in every consumer.
    public init?(_ headers: some AuthTokenHeaders) {
        self.init(headers: [
            AuthHeaderNames.authToken: headers.setAuthToken,
            AuthHeaderNames.authTokenExpiry: headers.setAuthTokenExpiry,
            AuthHeaderNames.sessionToken: headers.setSessionToken,
            AuthHeaderNames.sessionUpdateAge: headers.setSessionUpdateAge,
        ])
    }
}

/// Builds a hook outcome from a generated operation's response headers, for use directly inside an
/// ``AuthRequestHooks`` conformance.
public enum AuthTokenHeadersMapper {
    public static func credentials(from headers: some AuthTokenHeaders) -> AuthRequestOutcome<AuthCredentialHeaders> {
        guard let parsed = AuthCredentialHeaders(headers) else {
            logger.error("The authentication response did not include valid session details to save.")

            return .failure(AuthRequestFailure(status: 500, code: "MISSING_CREDENTIAL_HEADERS"))
        }

        return .success(parsed)
    }
}
