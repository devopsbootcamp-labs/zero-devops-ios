import Foundation

#if canImport(AuthenticationServices) && canImport(UIKit)
import AuthenticationServices
import CryptoKit
import UIKit
#endif

enum AuthError: LocalizedError {
    case invalidTokenResponse
    case tokenEndpointError(statusCode: Int, detail: String)
    case callbackError(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidTokenResponse:
            return "Invalid or empty token response from identity provider."
        case .tokenEndpointError(let code, let detail):
            return "Login failed (\(code)): \(detail)"
        case .callbackError(let detail):
            return "Authorization error: \(detail)"
        case .notAuthenticated:
            return "No valid session — please sign in."
        }
    }
}

/// OIDC / PKCE auth manager using native iOS web authentication.
final class OidcAuthManager {

    static let shared = OidcAuthManager()

#if canImport(AuthenticationServices) && canImport(UIKit)
    private var webSession: ASWebAuthenticationSession?

    @discardableResult
    func resumeExternalUserAgentFlow(with url: URL) -> Bool {
        _ = url
        return false
    }

    private var authorizationEndpoint: URL {
        URL(string: "\(AppConfig.oidcIssuer)/protocol/openid-connect/auth")!
    }

    private var tokenEndpoint: URL {
        URL(string: "\(AppConfig.oidcIssuer)/protocol/openid-connect/token")!
    }

    private func callbackScheme() -> String {
        URL(string: AppConfig.oidcRedirectURI)?.scheme ?? ""
    }

    // MARK: - Authorization

    @MainActor
    func startAuth(from viewController: UIViewController) async throws -> TokenBundle {
        let scheme = callbackScheme().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty else {
            throw AuthError.callbackError("Invalid redirect URI scheme in AppConfig.oidcRedirectURI")
        }

        let state = Self.randomURLSafeString(length: 24)
        let codeVerifier = Self.randomURLSafeString(length: 64)
        let codeChallenge = Self.codeChallenge(from: codeVerifier)

        var comps = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.oidcClientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AppConfig.oidcRedirectURI),
            URLQueryItem(name: "scope", value: AppConfig.oidcScopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        let audience = AppConfig.oidcAudience.trimmingCharacters(in: .whitespacesAndNewlines)
        if !audience.isEmpty {
            queryItems.append(URLQueryItem(name: "audience", value: audience))
        }
        comps?.queryItems = queryItems
        guard let authURL = comps?.url else {
            throw AuthError.invalidTokenResponse
        }

        let callbackURL = try await performWebLogin(
            authURL: authURL,
            callbackScheme: scheme,
            viewController: viewController
        )
        guard let callbackComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.invalidTokenResponse
        }

        // Surface any Keycloak error returned in the callback (e.g., access_denied)
        if let errorCode = callbackComps.queryItems?.first(where: { $0.name == "error" })?.value {
            let desc = callbackComps.queryItems?.first(where: { $0.name == "error_description" })?.value
                ?? errorCode
            throw AuthError.callbackError(normalizeCallbackError(desc))
        }

        guard callbackComps.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = callbackComps.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw AuthError.invalidTokenResponse
        }

        let token = try await exchangeAuthorizationCode(code: code, codeVerifier: codeVerifier)
        let expiresAt = Date().addingTimeInterval(TimeInterval(max(token.expiresIn ?? 60, 60)))
        // Access token carries API authorization claims (tenant/roles/resource_access).
        let claims = Self.decodeJwtClaims(token.accessToken)

        return TokenBundle(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            idToken: token.idToken,
            expiresAt: expiresAt,
            tenantId: Self.extractTenantId(from: claims),
            accountId: Self.extractAccountId(from: claims),
            cloudAccountId: Self.extractCloudAccountId(from: claims)
        )
    }

    private func performWebLogin(
        authURL: URL,
        callbackScheme: String,
        viewController: UIViewController
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                self.webSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AuthError.invalidTokenResponse)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            let provider = PresentationProvider(viewController: viewController)
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            let started = session.start()
            if !started {
                self.webSession = nil
                continuation.resume(throwing: AuthError.callbackError("Unable to start iOS web authentication session"))
            }
        }
    }

    private func exchangeAuthorizationCode(code: String, codeVerifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": AppConfig.oidcRedirectURI,
            "client_id": AppConfig.oidcClientId,
            "code_verifier": codeVerifier
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidTokenResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.tokenEndpointError(
                statusCode: http.statusCode,
                detail: extractErrorDetail(from: data)
            )
        }
        guard let parsed = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !parsed.accessToken.isEmpty else {
            throw AuthError.tokenEndpointError(
                statusCode: http.statusCode,
                detail: extractErrorDetail(from: data)
            )
        }
        return parsed
    }

    // MARK: - Token Refresh

    func refreshToken(_ refreshToken: String, currentBundle: TokenBundle) async throws -> TokenBundle {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": AppConfig.oidcClientId
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidTokenResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.tokenEndpointError(
                statusCode: http.statusCode,
                detail: extractErrorDetail(from: data)
            )
        }
        guard let parsed = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !parsed.accessToken.isEmpty else {
            throw AuthError.tokenEndpointError(
                statusCode: http.statusCode,
                detail: extractErrorDetail(from: data)
            )
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(max(parsed.expiresIn ?? 60, 60)))
        // Keep tenant/account context aligned with API token claims after refresh.
        let claims = Self.decodeJwtClaims(parsed.accessToken)
        return TokenBundle(
            accessToken: parsed.accessToken,
            refreshToken: parsed.refreshToken ?? refreshToken,
            idToken: parsed.idToken ?? currentBundle.idToken,
            expiresAt: expiresAt,
            tenantId: Self.extractTenantId(from: claims) ?? currentBundle.tenantId,
            accountId: Self.extractAccountId(from: claims) ?? currentBundle.accountId,
            cloudAccountId: Self.extractCloudAccountId(from: claims) ?? currentBundle.cloudAccountId
        )
    }

    private func formBody(_ params: [String: String]) -> Data {
        // RFC 3986 unreserved chars only — prevents + / = & from corrupting values
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = params
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: unreserved) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
                return "\(k)=\(v)"
            }
            .sorted()   // deterministic order
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private func extractErrorDetail(from data: Data) -> String {
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let desc = dict["error_description"] as? String
            let err  = dict["error"] as? String
            if let detail = desc ?? err, !detail.isEmpty { return detail }
        }
        return String(data: data, encoding: .utf8)?.prefix(200).description ?? "Unknown error"
    }

    private func normalizeCallbackError(_ value: String) -> String {
        let plusNormalized = value.replacingOccurrences(of: "+", with: " ")
        return plusNormalized.removingPercentEncoding ?? plusNormalized
    }

    private static func randomURLSafeString(length: Int) -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).compactMap { _ in charset.randomElement() })
    }

    private static func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case expiresIn = "expires_in"
        }
    }

    private final class PresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        private weak var viewController: UIViewController?

        init(viewController: UIViewController) {
            self.viewController = viewController
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            _ = session
            if let window = viewController?.view.window {
                return window
            }
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
#else
    @discardableResult
    func resumeExternalUserAgentFlow(with url: URL) -> Bool {
        _ = url
        return false
    }

    @MainActor
    func startAuth(from viewController: AnyObject) async throws -> TokenBundle {
        _ = viewController
        throw AuthError.notAuthenticated
    }

    func refreshToken(_ refreshToken: String, currentBundle: TokenBundle) async throws -> TokenBundle {
        _ = refreshToken
        _ = currentBundle
        throw AuthError.notAuthenticated
    }
#endif

    /// Revoke the refresh token at the identity provider to invalidate outstanding sessions.
    func revokeRefreshToken(_ refreshToken: String) async {
        let revokeEndpoint = URL(string: "\(AppConfig.oidcIssuer)/protocol/openid-connect/revoke")!
        var request = URLRequest(url: revokeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": AppConfig.oidcClientId,
            "token": refreshToken,
            "token_type_hint": "refresh_token"
        ])
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            // Best-effort: any response (including 204 No Content) means revocation was accepted
        } catch {
            // Best-effort: if network fails, token is still invalidated server-side by TTL
            _ = error
        }
    }

    // MARK: - JWT Helpers

    /// Decode JWT claims without signature validation (for app use).
    /// In production, validate signature using issuer's JWKS.
    static func decodeJwtClaims(_ jwt: String) -> [String: Any] {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count >= 3 else { return [:] }  // Valid JWT must have 3 parts (header.payload.signature)
        
        var b64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }

    private static func firstNonBlank(in claims: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = claims[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func extractTenantId(from claims: [String: Any]) -> String? {
        firstNonBlank(in: claims, keys: ["tenant_id", "tenantId", "tenant_uuid", "tenantUUID", "tid", "org_id", "tenant"])
    }

    private static func extractAccountId(from claims: [String: Any]) -> String? {
        firstNonBlank(in: claims, keys: ["account_id", "accountId", "x_account_id", "cloud_account_id", "cloudAccountId"])
    }

    private static func extractCloudAccountId(from claims: [String: Any]) -> String? {
        firstNonBlank(in: claims, keys: ["cloud_account_id", "cloudAccountId", "account_id", "accountId", "x_account_id"])
    }
}
