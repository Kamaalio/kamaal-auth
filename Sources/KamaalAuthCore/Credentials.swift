//
//  Credentials.swift
//  KamaalAuth
//

import Foundation

/// The credentials persisted between launches.
///
/// Two tokens are kept: a short-lived `authToken` (a JWT) that signs ordinary API calls, and a long-lived
/// `sessionToken` used only to mint a fresh `authToken`.
public struct Credentials: Codable, Hashable, Sendable {
    public let authToken: String
    public let authTokenExpiryDate: Date
    public let sessionToken: String
    public let sessionUpdateAge: TimeInterval
    public let lastSessionUpdate: Date
    /// Filled in from a session lookup. `nil` means "not yet known", which is treated as not expired.
    public let sessionExpiryDate: Date?

    public init(
        authToken: String,
        authTokenExpiryDate: Date,
        sessionToken: String,
        sessionUpdateAge: TimeInterval,
        lastSessionUpdate: Date,
        sessionExpiryDate: Date? = nil
    ) {
        self.authToken = authToken
        self.authTokenExpiryDate = authTokenExpiryDate
        self.sessionToken = sessionToken
        self.sessionUpdateAge = sessionUpdateAge
        self.lastSessionUpdate = lastSessionUpdate
        self.sessionExpiryDate = sessionExpiryDate
    }

    public var authTokenHasExpired: Bool {
        authTokenExpiryDate <= .now
    }

    public var sessionHasExpired: Bool {
        guard let sessionExpiryDate else { return false }

        return sessionExpiryDate <= .now
    }

    public func authTokenWillExpireSoon(within interval: TimeInterval = 3600) -> Bool {
        authTokenExpiryDate <= .now.addingTimeInterval(interval)
    }

    public var shouldUpdateSession: Bool {
        Date.now.timeIntervalSince(lastSessionUpdate) >= sessionUpdateAge
    }

    public func settingSessionExpiryDate(_ date: Date) -> Credentials {
        Credentials(
            authToken: authToken,
            authTokenExpiryDate: authTokenExpiryDate,
            sessionToken: sessionToken,
            sessionUpdateAge: sessionUpdateAge,
            lastSessionUpdate: lastSessionUpdate,
            sessionExpiryDate: date,
        )
    }

    public func updatingLastSessionUpdate(to date: Date = .now) -> Credentials {
        Credentials(
            authToken: authToken,
            authTokenExpiryDate: authTokenExpiryDate,
            sessionToken: sessionToken,
            sessionUpdateAge: sessionUpdateAge,
            lastSessionUpdate: date,
            sessionExpiryDate: sessionExpiryDate,
        )
    }

    private enum CodingKeys: String, CodingKey {
        case authToken
        case authTokenExpiryDate
        case sessionToken
        case sessionUpdateAge
        case lastSessionUpdate
        case sessionExpiryDate
    }

    /// Legacy key from an app that stored the JWT expiry as `expiryDate`.
    private enum LegacyCodingKeys: String, CodingKey {
        case expiryDate
    }

    /// Decodes both the current shape and the older one that named the JWT expiry `expiryDate`.
    ///
    /// Without this, upgrading an app that used the old shape would fail to decode every stored credential and
    /// silently sign the user out.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authToken = try container.decode(String.self, forKey: .authToken)
        sessionToken = try container.decode(String.self, forKey: .sessionToken)
        sessionUpdateAge = try container.decode(TimeInterval.self, forKey: .sessionUpdateAge)
        lastSessionUpdate = try container.decode(Date.self, forKey: .lastSessionUpdate)
        sessionExpiryDate = try container.decodeIfPresent(Date.self, forKey: .sessionExpiryDate)

        if let expiryDate = try container.decodeIfPresent(Date.self, forKey: .authTokenExpiryDate) {
            authTokenExpiryDate = expiryDate
            return
        }

        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        authTokenExpiryDate = try legacyContainer.decode(Date.self, forKey: .expiryDate)
    }
}
