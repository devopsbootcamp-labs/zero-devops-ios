import Foundation

#if canImport(AppAuth) && canImport(UIKit)
import AppAuth
import UIKit
#endif

enum AuthError: LocalizedError {
    case invalidTokenResponse
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidTokenResponse: return "Invalid or empty token response from identity provider."
        case .notAuthenticated:     return "No valid session — please sign in."
        }
    }
}

/// OIDC / PKCE auth manager using AppAuth-iOS — mirrors Android OidcAuthManager.
final class OidcAuthManager {

    static let shared = OidcAuthManager()

#if canImport(AppAuth) && canImport(UIKit)
    private var currentFlow: OIDExternalUserAgentSession?

    /// Resume the pending AppAuth browser flow with the callback URL.
    @discardableResult
    func resumeExternalUserAgentFlow(with url: URL) -> Bool {
        guard let flow = currentFlow else { return false }
        let resumed = flow.resumeExternalUserAgentFlow(with: url)
        if resumed {
            currentFlow = nil
        }
        return resumed
    }

    private var serviceConfig: OIDServiceConfiguration {
        OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "\(AppConfig.oidcIssuer)/protocol/openid-connect/auth")!,
            tokenEndpoint:         URL(string: "\(AppConfig.oidcIssuer)/protocol/openid-connect/token")!
        )
    }

    // MARK: - Authorization

    @MainActor
    func startAuth(from viewController: UIViewController) async throws -> TokenBundle {
        let request = OIDAuthorizationRequest(
            configuration:        serviceConfig,
            clientId:             AppConfig.oidcClientId,
            clientSecret:         nil,
            scopes:               AppConfig.oidcScopes,
            redirectURL:          URL(string: AppConfig.oidcRedirectURI)!,
            responseType:         OIDResponseTypeCode,
            additionalParameters: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            self.currentFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting:   viewController
            ) { authState, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard
                    let resp        = authState?.lastTokenResponse,
                    let accessToken = resp.accessToken, !accessToken.isEmpty,
                    let expiryDate  = resp.accessTokenExpirationDate
                else {
                    continuation.resume(throwing: AuthError.invalidTokenResponse)
                    return
                }

                let expiresAt = max(expiryDate, Date().addingTimeInterval(60))
                let claims    = Self.decodeJwtClaims(resp.idToken ?? accessToken)

                let bundle = TokenBundle(
                    accessToken:     accessToken,
                    refreshToken:    resp.refreshToken,
                    idToken:         resp.idToken,
                    expiresAt:       expiresAt,
                    tenantId:        claims["tenant_id"]      as? String,
                    accountId:       claims["account_id"]     as? String,
                    cloudAccountId:  claims["cloud_account_id"] as? String
                )
                continuation.resume(returning: bundle)
            }
        }
    }

    // MARK: - Token Refresh

    func refreshToken(_ refreshToken: String, currentBundle: TokenBundle) async throws -> TokenBundle {
        let request = OIDTokenRequest(
            configuration:      serviceConfig,
            grantType:          OIDGrantTypeRefreshToken,
            authorizationCode:  nil,
            redirectURL:        URL(string: AppConfig.oidcRedirectURI)!,
            clientID:           AppConfig.oidcClientId,
            clientSecret:       nil,
            scope:              AppConfig.oidcScopes.joined(separator: " "),
            refreshToken:       refreshToken,
            codeVerifier:       nil,
            additionalParameters: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(request) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard
                    let resp        = response,
                    let accessToken = resp.accessToken, !accessToken.isEmpty,
                    let expiryDate  = resp.accessTokenExpirationDate
                else {
                    continuation.resume(throwing: AuthError.invalidTokenResponse)
                    return
                }

                let expiresAt = max(expiryDate, Date().addingTimeInterval(60))
                let claims    = Self.decodeJwtClaims(resp.idToken ?? accessToken)

                let bundle = TokenBundle(
                    accessToken:     accessToken,
                    refreshToken:    resp.refreshToken ?? refreshToken,
                    idToken:         resp.idToken ?? currentBundle.idToken,
                    expiresAt:       expiresAt,
                    tenantId:        claims["tenant_id"]       as? String ?? currentBundle.tenantId,
                    accountId:       claims["account_id"]      as? String ?? currentBundle.accountId,
                    cloudAccountId:  claims["cloud_account_id"] as? String ?? currentBundle.cloudAccountId
                )
                continuation.resume(returning: bundle)
            }
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

    // MARK: - JWT Helpers

    static func decodeJwtClaims(_ jwt: String) -> [String: Any] {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count >= 2 else { return [:] }
        var b64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }
}
