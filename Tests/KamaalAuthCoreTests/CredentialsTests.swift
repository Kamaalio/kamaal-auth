//
//  CredentialsTests.swift
//  KamaalAuth
//

import Foundation
import Testing

@testable import KamaalAuthCore

@Suite("Credentials")
struct CredentialsTests {
    @Test("Round trips through JSON")
    func roundTrips() throws {
        let credentials = makeCredentials()

        let data = try JSONEncoder().encode(credentials)
        let decoded = try JSONDecoder().decode(Credentials.self, from: data)

        #expect(decoded == credentials)
    }

    @Test("Rejects credentials stored in an older shape, so the app re-authenticates once")
    func rejectsOlderShape() {
        let older = """
            {
              "authToken": "token",
              "expiryDate": 800000000,
              "sessionToken": "session",
              "sessionUpdateAge": 86400,
              "lastSessionUpdate": 700000000
            }
            """

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Credentials.self, from: Data(older.utf8))
        }
    }

    @Test("Treats an unknown session expiry as not expired")
    func unknownSessionExpiryIsNotExpired() {
        #expect(makeCredentials(sessionExpiryDate: nil).sessionHasExpired == false)
    }

    @Test("Reports an elapsed session expiry as expired")
    func elapsedSessionExpiryIsExpired() {
        #expect(makeCredentials(sessionExpiryDate: .distantPast).sessionHasExpired)
    }

    @Test("Flags a session that is due for an update")
    func flagsStaleSession() {
        let stale = makeCredentials(lastSessionUpdate: Date.now.addingTimeInterval(-90_000))

        #expect(stale.shouldUpdateSession)
        #expect(makeCredentials().shouldUpdateSession == false)
    }

    @Test("Flags an auth token that is about to expire")
    func flagsImminentExpiry() {
        let soon = makeCredentials(authTokenExpiryDate: Date.now.addingTimeInterval(60))

        #expect(soon.authTokenWillExpireSoon())
        #expect(soon.authTokenWillExpireSoon(within: 10) == false)
        #expect(soon.authTokenHasExpired == false)
    }

    private func makeCredentials(
        authTokenExpiryDate: Date = Date.now.addingTimeInterval(604_800),
        lastSessionUpdate: Date = .now,
        sessionExpiryDate: Date? = Date.now.addingTimeInterval(2_592_000)
    ) -> Credentials {
        Credentials(
            authToken: "token",
            authTokenExpiryDate: authTokenExpiryDate,
            sessionToken: "session",
            sessionUpdateAge: 86_400,
            lastSessionUpdate: lastSessionUpdate,
            sessionExpiryDate: sessionExpiryDate,
        )
    }
}

@Suite("Expirable")
struct ExpirableTests {
    private struct Thing: Expirable {
        let expiresAt: Date
    }

    @Test("Reports expiry relative to now")
    func reportsExpiry() {
        #expect(Thing(expiresAt: .distantPast).hasExpired)
        #expect(Thing(expiresAt: .distantFuture).hasExpired == false)
    }

    @Test("Reports imminent expiry within the given window")
    func reportsImminentExpiry() {
        let thing = Thing(expiresAt: Date.now.addingTimeInterval(300))

        #expect(thing.willExpireSoon())
        #expect(thing.willExpireSoon(within: 60) == false)
    }
}

@Suite("InMemoryCredentialsStore")
struct InMemoryCredentialsStoreTests {
    @Test("Stores, reads back and deletes credentials")
    func storesAndDeletes() throws {
        let store = InMemoryCredentialsStore()
        let credentials = Credentials(
            authToken: "token",
            authTokenExpiryDate: .distantFuture,
            sessionToken: "session",
            sessionUpdateAge: 86_400,
            lastSessionUpdate: .now,
        )

        try store.store(credentials, forKey: "key")
        #expect(try store.credentials(forKey: "key") == credentials)

        try store.delete(forKey: "key")
        #expect(try store.credentials(forKey: "key") == nil)
    }

    @Test("Returns nil for an unknown key")
    func returnsNilForUnknownKey() throws {
        #expect(try InMemoryCredentialsStore().credentials(forKey: "missing") == nil)
    }
}
