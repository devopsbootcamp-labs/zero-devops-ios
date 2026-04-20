import Foundation
import Combine

/// Mirrors Android DefaultAuthSessionManager — validates expiry with 30-second skew.
final class AuthSessionManager: ObservableObject {

    static let shared = AuthSessionManager()

    private let tokenStore = TokenStore.shared
    private let expirySkew: TimeInterval = 30

    @Published private(set) var isAuthenticated = false

    // MARK: - Token Access

    func currentAccessToken() -> String? {
        guard let bundle = tokenStore.load() else { return nil }
        guard !bundle.accessToken.isEmpty else { return nil }
        guard bundle.expiresAt > Date().addingTimeInterval(expirySkew) else { return nil }
        return bundle.accessToken
    }

    func currentBundle() -> TokenBundle? {
        tokenStore.load()
    }

    // MARK: - Session Lifecycle

    func saveBundle(_ bundle: TokenBundle) {
        guard !bundle.accessToken.isEmpty else { return }
        tokenStore.save(bundle)
        DispatchQueue.main.async { self.isAuthenticated = true }
    }

    func logout() {
        tokenStore.clear()
        DispatchQueue.main.async { self.isAuthenticated = false }
    }

    /// Validate and resume a stored session — mirrors AppContainer.resumeSessionIfAvailable().
    func resumeIfAvailable() -> Bool {
        guard let token = currentAccessToken(), !token.isEmpty else {
            logout()
            return false
        }
        DispatchQueue.main.async { self.isAuthenticated = true }
        return true
    }
}
