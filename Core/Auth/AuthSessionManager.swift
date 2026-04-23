import Foundation
import Combine

/// Mirrors Android DefaultAuthSessionManager — validates expiry with 30-second skew.
final class AuthSessionManager: ObservableObject {

    static let shared = AuthSessionManager()

    private let tokenStore = TokenStore.shared
    private let expirySkew: TimeInterval = 30
    private let refreshSkew: TimeInterval = 60
    private let refreshLock = NSLock()
    private let contextLock = NSLock()
    private var inFlightRefresh: Task<TokenBundle, Error>?
    private var requestTenantId: String?
    private var requestAccountId: String?

    @Published private(set) var isAuthenticated = false

    private func normalizeContextValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

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

    func currentTenantId() -> String? {
        contextLock.lock()
        defer { contextLock.unlock() }
        return requestTenantId
    }

    func currentAccountId() -> String? {
        contextLock.lock()
        defer { contextLock.unlock() }
        return requestAccountId
    }

    func updateRequestContext(tenantId: String?, accountId: String?) {
        contextLock.lock()
        requestTenantId = normalizeContextValue(tenantId)
        requestAccountId = normalizeContextValue(accountId)
        contextLock.unlock()
    }

    /// Returns a currently valid access token or refreshes it if possible.
    func validAccessToken() async throws -> String {
        if let token = currentAccessToken() {
            return token
        }
        let refreshed = try await refreshAccessToken()
        return refreshed.accessToken
    }

    /// Refresh token, deduplicating concurrent refreshes.
    func refreshAccessToken() async throws -> TokenBundle {
        let existingTask: Task<TokenBundle, Error>? = {
            refreshLock.lock()
            defer { refreshLock.unlock() }
            return inFlightRefresh
        }()
        if let task = existingTask {
            return try await task.value
        }

        guard let bundle = tokenStore.load(),
              let refreshToken = bundle.refreshToken,
              !refreshToken.isEmpty
        else {
            logout()
            throw AuthError.notAuthenticated
        }

        let task = Task<TokenBundle, Error> {
            let refreshed = try await OidcAuthManager.shared.refreshToken(refreshToken, currentBundle: bundle)
            guard !refreshed.accessToken.isEmpty,
                  refreshed.expiresAt > Date().addingTimeInterval(expirySkew)
            else {
                self.logout()
                throw AuthError.invalidTokenResponse
            }
            self.saveBundle(refreshed)
            return refreshed
        }

        refreshLock.lock()
        inFlightRefresh = task
        refreshLock.unlock()

        defer {
            refreshLock.lock()
            inFlightRefresh = nil
            refreshLock.unlock()
        }

        return try await task.value
    }

    // MARK: - Session Lifecycle

    func saveBundle(_ bundle: TokenBundle) {
        guard !bundle.accessToken.isEmpty else { return }
        tokenStore.save(bundle)
        updateRequestContext(
            tenantId: bundle.tenantId,
            accountId: bundle.cloudAccountId ?? bundle.accountId
        )
        DispatchQueue.main.async { self.isAuthenticated = true }
    }

    func logout() {
        // Best-effort revoke refresh token at identity provider
        if let bundle = tokenStore.load(), let refreshToken = bundle.refreshToken, !refreshToken.isEmpty {
            Task {
                await OidcAuthManager.shared.revokeRefreshToken(refreshToken)
            }
        }
        
        tokenStore.clear()
        updateRequestContext(tenantId: nil, accountId: nil)
        DispatchQueue.main.async { self.isAuthenticated = false }
    }

    /// Validate and resume a stored session — mirrors AppContainer.resumeSessionIfAvailable().
    func resumeIfAvailable() -> Bool {
        guard let bundle = currentBundle(), !bundle.accessToken.isEmpty else {
            logout()
            return false
        }
        // If token is near expiry, caller can still refresh asynchronously before API usage.
        if bundle.expiresAt <= Date().addingTimeInterval(refreshSkew), bundle.refreshToken == nil {
            logout()
            return false
        }
        updateRequestContext(
            tenantId: bundle.tenantId,
            accountId: bundle.cloudAccountId ?? bundle.accountId
        )
        DispatchQueue.main.async { self.isAuthenticated = true }
        return true
    }
}
