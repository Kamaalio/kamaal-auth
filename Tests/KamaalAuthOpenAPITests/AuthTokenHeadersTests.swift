//
//  AuthTokenHeadersTests.swift
//  KamaalAuth
//

import KamaalAuthClient
import Testing

@testable import KamaalAuthOpenAPI

/// Mirrors the shape swift-openapi-generator emits for a `Headers` struct, exactly as a consumer's empty
/// `extension Operations.X.Headers: AuthTokenHeaders {}` would rely on.
private struct GeneratedHeaders: AuthTokenHeaders {
    let setAuthToken: String
    let setAuthTokenExpiry: String
    let setSessionToken: String
    let setSessionUpdateAge: String
}

@Suite("AuthCredentialHeaders from generated headers")
struct AuthCredentialHeadersFromGeneratedTests {
    @Test("Maps every field from the generated header names")
    func mapsFields() throws {
        let generated = GeneratedHeaders(
            setAuthToken: "header.payload.signature",
            setAuthTokenExpiry: "604800",
            setSessionToken: "session-token",
            setSessionUpdateAge: "86400",
        )

        let credentials = try #require(AuthCredentialHeaders(generated))

        #expect(credentials.authToken == "header.payload.signature")
        #expect(credentials.authTokenExpiresInSeconds == 604_800)
        #expect(credentials.sessionToken == "session-token")
        #expect(credentials.sessionUpdateAgeSeconds == 86_400)
    }

    @Test("Fails when a numeric field is not a number")
    func failsForNonNumeric() {
        let generated = GeneratedHeaders(
            setAuthToken: "token",
            setAuthTokenExpiry: "soon",
            setSessionToken: "session",
            setSessionUpdateAge: "86400",
        )

        #expect(AuthCredentialHeaders(generated) == nil)
    }
}

@Suite("AuthTokenHeadersMapper")
struct AuthTokenHeadersMapperTests {
    @Test("Succeeds with valid headers")
    func succeedsWithValidHeaders() throws {
        let generated = GeneratedHeaders(
            setAuthToken: "header.payload.signature",
            setAuthTokenExpiry: "604800",
            setSessionToken: "session-token",
            setSessionUpdateAge: "86400",
        )

        let outcome = AuthTokenHeadersMapper.credentials(from: generated)

        guard case .success(let credentials) = outcome else {
            Issue.record("Expected success, got \(outcome)")
            return
        }
        #expect(credentials.sessionToken == "session-token")
    }

    @Test("Fails with MISSING_CREDENTIAL_HEADERS when a numeric field cannot be parsed")
    func failsWithMissingCredentialHeadersCode() {
        let generated = GeneratedHeaders(
            setAuthToken: "token",
            setAuthTokenExpiry: "not-a-number",
            setSessionToken: "session",
            setSessionUpdateAge: "86400",
        )

        let outcome = AuthTokenHeadersMapper.credentials(from: generated)

        guard case .failure(let failure) = outcome else {
            Issue.record("Expected failure, got \(outcome)")
            return
        }
        #expect(failure.status == 500)
        #expect(failure.code == "MISSING_CREDENTIAL_HEADERS")
    }
}
