import Foundation

/// Central configuration — mirrors Android BuildConfig constants.
enum AppConfig {
    static let apiBaseURL          = "https://api.devopsbootcamp.dev/"
    static let oidcIssuer          = "https://keycloak.devopsbootcamp.dev/realms/zero-devops"
    static let oidcClientId        = "zero-devops-mobile"
    static let oidcAudience        = "cloudblueprints-api"
    static let oidcRedirectURI     = "com.devopsbootcamp.app://callback"
    static let oidcPostLogoutURI   = "com.devopsbootcamp.app://logout"
    // Match Android scope set; server default scopes still supply role mappings.
    static let oidcScopes          = ["openid", "profile", "email", "offline_access"]
}
