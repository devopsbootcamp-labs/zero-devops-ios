import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {

    @Published var profile:   UserProfile?
    @Published var isLoading  = false

    private let api     = APIClient.shared
    private let session = AuthSessionManager.shared

    func load() async {
        isLoading = true
        // Cascade through profile endpoints — mirrors Android ProfileViewModel
        let paths = [
            "api/v1/auth/me",
            "api/v1/auth/userinfo",
            "api/v1/users/me",
            "api/v1/auth/profile",
            "api/v1/me",
        ]
        for path in paths {
            if let p: UserProfile = try? await api.get(path) {
                profile   = p
                isLoading = false
                return
            }
        }
        // Fallback: decode from stored ID token
        profile   = localFallback()
        isLoading = false
    }

    private func localFallback() -> UserProfile? {
        guard let bundle = session.currentBundle() else { return nil }
        let token = bundle.idToken ?? bundle.accessToken
        let claims = OidcAuthManager.decodeJwtClaims(token)
        let app = AppContainer.shared
        return UserProfile(
            sub:           claims["sub"] as? String,
            email:         claims["email"] as? String,
            name:          claims["name"] as? String,
            givenName:     claims["given_name"] as? String,
            familyName:    claims["family_name"] as? String,
            tenantId:      (claims["tenant_id"] as? String) ?? bundle.tenantId ?? session.currentTenantId() ?? app.tenantId,
            accountId:     (claims["account_id"] as? String) ?? bundle.accountId ?? session.currentAccountId() ?? app.selectedAccountId,
            cloudAccountId: (claims["cloud_account_id"] as? String) ?? bundle.cloudAccountId ?? session.currentAccountId() ?? app.selectedAccountId
        )
    }
}
