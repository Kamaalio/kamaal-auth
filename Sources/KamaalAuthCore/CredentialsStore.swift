//
//  CredentialsStore.swift
//  KamaalAuth
//

import Foundation
import KamaalLogger
import KamaalUtils

private let logger = KamaalLogger(from: KeychainCredentialsStore.self)

public protocol CredentialsStore: Sendable {
    func delete(forKey key: String) throws
    func get(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
}

extension CredentialsStore {
    public func credentials(forKey key: String) throws -> Credentials? {
        let data: Data?
        do {
            data = try get(forKey: key)
        } catch {
            logger.error("Couldn't read credentials from the store; key=\(key); reason=\(error)")
            throw error
        }
        guard let data else {
            logger.info("No credentials data found in the store; key=\(key)")
            return nil
        }

        do {
            return try JSONDecoder().decode(Credentials.self, from: data)
        } catch {
            logger.error("Couldn't decode credentials from the store; key=\(key); reason=\(error)")
            throw error
        }
    }

    public func store(_ credentials: Credentials, forKey key: String) throws {
        try set(JSONEncoder().encode(credentials), forKey: key)
    }
}

public struct KeychainCredentialsStore: CredentialsStore {
    public init() {}

    public func delete(forKey key: String) throws {
        guard try get(forKey: key) != nil else { return }

        try Keychain.delete(forKey: key).get()
    }

    public func get(forKey key: String) throws -> Data? {
        try Keychain.get(forKey: key).get()
    }

    public func set(_ data: Data, forKey key: String) throws {
        try Keychain.set(data, forKey: key).get()
    }
}

/// A store that never touches the Keychain, for previews and tests.
public final class InMemoryCredentialsStore: CredentialsStore, @unchecked Sendable {
    private var storage: [String: Data]
    private let lock = NSLock()

    public init(seed: Data? = nil, key: String = InMemoryCredentialsStore.defaultKey) {
        storage = seed.map { [key: $0] } ?? [:]
    }

    public static let defaultKey = "KamaalAuth.previewCredentials"

    public func delete(forKey key: String) throws {
        lock.withLock { _ = storage.removeValue(forKey: key) }
    }

    public func get(forKey key: String) throws -> Data? {
        lock.withLock { storage[key] }
    }

    public func set(_ data: Data, forKey key: String) throws {
        lock.withLock { storage[key] = data }
    }
}
