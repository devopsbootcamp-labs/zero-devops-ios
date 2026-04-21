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
        guard let bundle = session.currentBundle(),
              let idToken = bundle.idToken ?? bundle.accessToken as String?
        else { return nil }
        let claims = OidcAuthManager.decodeJwtClaims(idToken)
        return UserProfile(
            sub:           claims["sub"]           as? String,
            email:         claims["email"]         as? String,
            name:          claims["name"]          as? String,
            givenName:     claims["given_name"]    as? String,
            familyName:    claims["family_name"]   as? String,
            tenantId:      claims["tenant_id"]     as? String,
            accountId:     claims["account_id"]    as? String,
            cloudAccountId: claims["cloud_account_id"] as? String
        )
    }
}
