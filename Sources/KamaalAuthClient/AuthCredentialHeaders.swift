//
//  AuthCredentialHeaders.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore

/// The credentials a successful auth response carries in its headers.
///
/// This is the Swift half of `buildCredentialHeaders` in the `@kamaalio/kamaal-auth` npm package. A hook usually
/// builds one by handing its response headers to ``init(headers:)`` rather than filling the fields in by hand.
public struct AuthCredentialHeaders: Hashable, Sendable {
    public let authToken: String
    public let authTokenExpiresInSeconds: Int
    public let sessionToken: String
    public let sessionUpdateAgeSeconds: Int

    public init(
        authToken: String,
        authTokenExpiresInSeconds: Int,
        sessionToken: String,
        sessionUpdateAgeSeconds: Int
    ) {
        self.authToken = authToken
        self.authTokenExpiresInSeconds = authTokenExpiresInSeconds
        self.sessionToken = sessionToken
        self.sessionUpdateAgeSeconds = sessionUpdateAgeSeconds
    }

    /// Parses the four `set-*` headers. Returns `nil` when any is missing or not a number.
    ///
    /// Lookup is case-insensitive, since HTTP header names are.
    public init?(headers: [String: String]) {
        func value(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        guard let authToken = value(AuthHeaderNames.authToken),
            let sessionToken = value(AuthHeaderNames.sessionToken),
            let expiry = value(AuthHeaderNames.authTokenExpiry).flatMap(Int.init),
            let updateAge = value(AuthHeaderNames.sessionUpdateAge).flatMap(Int.init)
        else { return nil }

        self.init(
            authToken: authToken,
            authTokenExpiresInSeconds: expiry,
            sessionToken: sessionToken,
            sessionUpdateAgeSeconds: updateAge,
        )
    }

    /// Turns the headers into storable credentials, carrying forward a session expiry already learned.
    public func credentials(keepingSessionExpiry sessionExpiryDate: Date? = nil) -> Credentials {
        Credentials(
            authToken: authToken,
            authTokenExpiryDate: Date.now.addingTimeInterval(TimeInterval(authTokenExpiresInSeconds)),
            sessionToken: sessionToken,
            sessionUpdateAge: TimeInterval(sessionUpdateAgeSeconds),
            lastSessionUpdate: .now,
            sessionExpiryDate: sessionExpiryDate,
        )
    }
}
