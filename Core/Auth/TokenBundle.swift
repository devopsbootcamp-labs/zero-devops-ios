import Foundation

/// Mirrors Android TokenBundle — stored in Keychain via TokenStore.
struct TokenBundle: Codable {
    let accessToken:  String
    let refreshToken: String?
    let idToken:      String?
    let expiresAt:    Date
    var tenantId:     String?
    var accountId:    String?
    var cloudAccountId: String?
}
