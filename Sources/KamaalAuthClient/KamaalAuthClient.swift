//
//  KamaalAuthClient.swift
//  KamaalAuth
//

import Foundation
import KamaalAuthCore
import KamaalLogger
import OpenAPIRuntime

private let logger = KamaalLogger(from: KamaalAuthClientImpl.self)

public struct SignInPayload: Hashable, Sendable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct SignUpPayload: Hashable, Sendable {
    public let email: String
    public let password: String
    public let name: String

    public init(email: String, password: String, name: String) {
        self.email = email
        self.password = password
        self.name = name
    }
}

public protocol KamaalAuthClient: Sendable {
    /// Whether stored credentials exist and their session has not expired.
    var hasValidCredentials: Bool { get }

    func refreshToken() async -> Result<Void, SessionErrors>
    func session() async -> Result<AuthSession, SessionErrors>
    func signIn(with payload: SignInPayload) async -> Result<Void, SignInErrors>
    func signUp(with payload: SignUpPayload) async -> Result<Void, SignUpErrors>
    func signOut() async -> Result<Void, SignOutErrors>
}

extension KamaalAuthClient where Self == KamaalAuthClientImpl {
    /// Builds a client over the given transport, wiring the package's middlewares.
    public static func live(
        configuration: KamaalAuthClientConfiguration,
        transport: any ClientTransport,
        extraMiddlewares: [any ClientMiddleware] = []
    ) -> KamaalAuthClientImpl {
        KamaalAuthClientImpl(configuration: configuration, transport: transport, extraMiddlewares: extraMiddlewares)
    }
}

public struct KamaalAuthClientImpl: KamaalAuthClient {
    let configuration: KamaalAuthClientConfiguration
    private let http: AuthHTTPClient
    private let tokenRefresher: TokenRefresher

    public init(
        configuration: KamaalAuthClientConfiguration,
        transport: any ClientTransport,
        extraMiddlewares: [any ClientMiddleware] = []
    ) {
        self.configuration = configuration

        let originMiddleware = OriginHeaderMiddleware(configuration: configuration)

        // The token endpoint gets its own client, authorized with the session token rather than the JWT. Reusing the
        // main client here would recurse: refreshing a token would itself trigger a refresh.
        let tokenHTTP = AuthHTTPClient(
            serverURL: configuration.serverURL,
            transport: transport,
            middlewares: [SessionTokenMiddleware(configuration: configuration), originMiddleware] + extraMiddlewares,
        )
        tokenRefresher = TokenRefresher(http: tokenHTTP, configuration: configuration)
        http = AuthHTTPClient(
            serverURL: configuration.serverURL,
            transport: transport,
            middlewares: [
                AuthorizationMiddleware(configuration: configuration, tokenRefresher: tokenRefresher),
                originMiddleware,
            ] + extraMiddlewares,
        )
    }

    public var hasValidCredentials: Bool {
        let credentials: Credentials?
        do {
            credentials = try tokenRefresher.credentials()
        } catch {
            logger.error("Couldn't decode stored credentials; treating as signed out; reason=\(error)")

            return false
        }
        guard let credentials else {
            logger.info("No stored credentials found; treating as signed out.")

            return false
        }

        return !credentials.sessionHasExpired
    }

    public func refreshToken() async -> Result<Void, SessionErrors> {
        await tokenRefresher.refreshToken()
    }

    public func session() async -> Result<AuthSession, SessionErrors> {
        do {
            guard try tokenRefresher.credentials() != nil else { return .failure(.unauthorized) }
        } catch {
            return .failure(.unknown(status: 500, payload: nil, cause: error))
        }

        let response: AuthHTTPClient.Response
        do {
            response = try await http.send(method: .get, path: configuration.paths.session, operationID: "authSession")
        } catch {
            if let sessionError = error as? SessionErrors {
                logger.warning("Session request failed; reason=\(sessionError)")

                return .failure(sessionError)
            }
            logger.warning("Session request failed; status=503")

            return .failure(.unknown(status: 503, payload: nil, cause: error))
        }

        switch response.status {
        case 200: break
        case 401, 404: return tokenRefresher.deleteCredentials(then: .unauthorized)
        default:
            return .failure(
                .unknown(status: response.status, payload: String(data: response.body, encoding: .utf8), cause: nil)
            )
        }

        let payload: Wire.SessionResponse
        do {
            payload = try Wire.makeDecoder().decode(Wire.SessionResponse.self, from: response.body)
        } catch {
            return .failure(.unknown(status: 503, payload: nil, cause: error))
        }

        cacheSessionExpiry(payload.session.expiresAt)

        return .success(makeSession(user: payload.user, expiresAt: payload.session.expiresAt))
    }

    public func signIn(with payload: SignInPayload) async -> Result<Void, SignInErrors> {
        do {
            try configuration.credentialsStore.delete(forKey: configuration.credentialsKey)
        } catch {
            logger.warning("Couldn't remove old saved sign-in details before signing in: \(error)")
        }

        logger.info("Starting sign in request.")

        let response: AuthHTTPClient.Response
        do {
            response = try await http.send(
                method: .post,
                path: configuration.paths.signIn,
                body: Wire.SignInRequest(email: payload.email, password: payload.password),
                operationID: "authSignIn",
            )
        } catch {
            logger.error("Sign in request failed before receiving a server response.")

            return .failure(.unknown(status: 503, payload: nil, cause: error))
        }

        switch response.status {
        case 200: break
        case 400:
            return .failure(.badRequest(validations: AuthValidationErrorParser.parseIssues(from: response.body)))
        case 401:
            let code = AuthValidationErrorParser.errorCode(from: response.body)
            guard code == AuthErrorCode.invalidEmailOrPassword.rawValue else {
                logger.warning("Sign in was authorized but the session could not be established afterward.")

                return .failure(.sessionUnavailable)
            }

            return .failure(.badRequest(validations: []))
        default:
            logger.warning("Sign in received an unexpected response from the server (status \(response.status)).")

            return .failure(
                .unknown(status: response.status, payload: String(data: response.body, encoding: .utf8), cause: nil)
            )
        }

        return persistCredentials(from: response, operation: "Sign in")
            .mapError(SignInErrors.credentialsUnavailable(cause:))
    }

    public func signUp(with payload: SignUpPayload) async -> Result<Void, SignUpErrors> {
        logger.info("Starting account creation request.")

        let response: AuthHTTPClient.Response
        do {
            response = try await http.send(
                method: .post,
                path: configuration.paths.signUp,
                body: Wire.SignUpRequest(email: payload.email, password: payload.password, name: payload.name),
                operationID: "authSignUp",
            )
        } catch {
            logger.error("Account creation request failed before receiving a server response.")

            return .failure(.unknown(status: 503, payload: nil, cause: error))
        }

        switch response.status {
        case 201: break
        case 400:
            return .failure(.badRequest(validations: AuthValidationErrorParser.parseIssues(from: response.body)))
        case 409: return .failure(.conflict)
        case 401:
            logger.warning("Account creation was authorized but the session could not be established afterward.")

            return .failure(.sessionUnavailable)
        default:
            logger.warning("Account creation received an unexpected response (status \(response.status)).")

            return .failure(
                .unknown(status: response.status, payload: String(data: response.body, encoding: .utf8), cause: nil)
            )
        }

        return persistCredentials(from: response, operation: "Account creation")
            .mapError(SignUpErrors.credentialsUnavailable(cause:))
    }

    public func signOut() async -> Result<Void, SignOutErrors> {
        let response: AuthHTTPClient.Response?
        do {
            response = try await http.send(method: .post, path: configuration.paths.signOut, operationID: "authSignOut")
        } catch {
            // The local credentials still get dropped below: a user asking to sign out should end up signed out even
            // when the server is unreachable.
            logger.warning("Sign out request failed; clearing local credentials anyway; reason=\(error)")
            response = nil
        }

        do {
            try configuration.credentialsStore.delete(forKey: configuration.credentialsKey)
        } catch {
            logger.error("Couldn't clear credentials during sign out; reason=\(error)")

            return .failure(.unknown(status: 500, payload: nil, cause: error))
        }

        guard let response, response.status != 200 else { return .success(()) }

        return .failure(
            .unknown(status: response.status, payload: String(data: response.body, encoding: .utf8), cause: nil)
        )
    }

    private func persistCredentials(
        from response: AuthHTTPClient.Response,
        operation: String
    ) -> Result<Void, any Error> {
        do {
            guard try tokenRefresher.storeCredentials(from: response) else {
                logger.error("The \(operation.lowercased()) response did not include valid session details to save.")

                return .failure(CredentialsStorageError.invalidResponseHeaders)
            }
        } catch {
            logger.error(label: "Couldn't save details after \(operation.lowercased())", error: error)

            return .failure(error)
        }

        logger.info("\(operation) completed and the session details were saved.")

        return .success(())
    }

    /// Records the session expiry so `hasValidCredentials` can answer without a network round trip on next launch.
    private func cacheSessionExpiry(_ expiresAt: Date) {
        do {
            guard let credentials = try tokenRefresher.credentials() else { return }

            try configuration.credentialsStore.store(
                credentials.settingSessionExpiryDate(expiresAt),
                forKey: configuration.credentialsKey,
            )
        } catch {
            logger.warning("Couldn't cache the session expiry date; reason=\(error)")
        }
    }

    private func makeSession(user: Wire.User, expiresAt: Date) -> AuthSession {
        AuthSession(
            id: user.id,
            name: user.name,
            email: user.email,
            emailVerified: user.emailVerified,
            createdAt: user.createdAt,
            expiresAt: expiresAt,
            extras: user.extras,
        )
    }
}
