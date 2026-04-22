import Foundation

/// Central configuration — mirrors Android BuildConfig constants.
enum AppConfig {
    static let apiBaseURL          = "https://api.devopsbootcamp.dev/"
    static let oidcIssuer          = "https://keycloak.devopsbootcamp.dev/realms/zero-devops"
    static let oidcClientId        = "zero-devops-mobile"
    static let oidcRedirectURI     = "com.devopsbootcamp.app://callback"
    static let oidcPostLogoutURI   = "com.devopsbootcamp.app://logout"
    // "roles" scope tells Keycloak to include resource_access (client role claims) in the JWT.
    // Without it, RBAC checks like deployments.read in cloudeprints-api.roles will 403.
    static let oidcScopes          = ["openid", "profile", "email", "offline_access", "roles"]
}
