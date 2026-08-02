//
//  AuthHeaderNames.swift
//  KamaalAuth
//

/// The response headers the server writes credentials into.
///
/// These mirror `AUTH_HEADER_NAMES` in the `@kamaalio/kamaal-auth` npm package. The two are halves of one wire
/// contract, so a name may only change in both places at once.
public enum AuthHeaderNames {
    public static let authToken = "set-auth-token"
    public static let authTokenExpiry = "set-auth-token-expiry"
    public static let sessionToken = "set-session-token"
    public static let sessionUpdateAge = "set-session-update-age"
}
