import Foundation

/// Central configuration — mirrors Android BuildConfig constants.
enum AppConfig {
    static let apiBaseURL          = "https://api.devopsbootcamp.dev/"
    static let oidcIssuer          = "https://keycloak.devopsbootcamp.dev/realms/zero-devops"
    static let oidcClientId        = "zero-devops-mobile"
    static let oidcRedirectURI     = "com.devopsbootcamp.app://callback"
    static let oidcPostLogoutURI   = "com.devopsbootcamp.app://logout"
    // Include roles scope so Keycloak can include client role claims in access tokens when configured.
    static let oidcScopes          = ["openid", "profile", "email", "offline_access", "roles"]
}
