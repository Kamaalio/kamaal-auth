//
//  Expirable.swift
//  KamaalAuth
//

import Foundation

public protocol Expirable {
    var expiresAt: Date { get }
}

extension Expirable {
    public var hasExpired: Bool {
        Date.now >= expiresAt
    }

    /// Whether this will expire within the given interval.
    /// - Parameter within: Seconds of headroom before expiry. Defaults to an hour.
    public func willExpireSoon(within: TimeInterval = 3600) -> Bool {
        expiresAt <= Date.now.addingTimeInterval(within)
    }
}
