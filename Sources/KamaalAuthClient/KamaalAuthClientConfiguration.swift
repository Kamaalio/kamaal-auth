//
//  KamaalAuthClientConfiguration.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore

/// How the app's URL scheme reaches the server's trusted-origin check.
public enum OriginScheme: Sendable, Hashable {
    /// Read the first scheme out of the bundle's `CFBundleURLTypes`.
    case fromBundleURLTypes
    /// Use a fixed scheme, e.g. `"kowalski"` for an `Origin: kowalski://` header.
    case explicit(String)
    /// Send no `Origin` header at all.
    case none
}

public struct KamaalAuthClientConfiguration: Sendable {
    public let serverURL: URL
    public let paths: AuthPaths
    public let originScheme: OriginScheme
    public let credentialsKey: String
    public let credentialsStore: any CredentialsStore
    /// Also send the session token as a cookie alongside the bearer JWT.
    public let sendsSessionCookie: Bool

    public init(
        serverURL: URL,
        basePath: String = AuthDefaults.basePath,
        originScheme: OriginScheme = .fromBundleURLTypes,
        credentialsKey: String,
        credentialsStore: any CredentialsStore = KeychainCredentialsStore(),
        sendsSessionCookie: Bool = false
    ) {
        self.serverURL = serverURL
        paths = AuthPaths(basePath: basePath)
        self.originScheme = originScheme
        self.credentialsKey = credentialsKey
        self.credentialsStore = credentialsStore
        self.sendsSessionCookie = sendsSessionCookie
    }

    /// Resolves the scheme to send as `Origin`, or `nil` when no header should be attached.
    public func resolvedOriginScheme(bundle: Bundle = .main) -> String? {
        switch originScheme {
        case .none: nil
        case .explicit(let scheme): scheme
        case .fromBundleURLTypes: Self.firstBundleURLScheme(in: bundle)
        }
    }

    private static func firstBundleURLScheme(in bundle: Bundle) -> String? {
        guard let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return nil
        }

        return urlTypes.lazy
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap(\.self)
            .first
    }
}
