import Foundation
import Combine

#if canImport(UIKit)
import UIKit
typealias PlatformViewController = UIViewController
#else
typealias PlatformViewController = AnyObject
#endif

/// Central dependency / session container — mirrors Android AppContainer.
@MainActor
final class AppContainer: ObservableObject {

    static let shared = AppContainer()

    // Published session state drives root navigation
    @Published var sessionReady    = false
    @Published var isLoggingIn     = false
    @Published var loginError:      String?

    // Selected cloud-account scope (nil = tenant-wide)
    @Published var selectedAccountId: String?
    @Published var tenantId:          String?

    private let sessionManager = AuthSessionManager.shared
    private let oidcManager    = OidcAuthManager.shared
    private let api            = APIClient.shared

    private struct TenantIdentity: Decodable {
        let id: String
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private func isUsableAccountId(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else {
            return false
        }
        if normalized.caseInsensitiveCompare("unknown") == .orderedSame { return false }
        if normalized.lowercased().hasSuffix(":unknown") { return false }
        return true
    }

    // MARK: - App Launch

    func onAppear() {
        if sessionManager.resumeIfAvailable() {
            hydrateContextFromStoredBundle()
            Task { await ensureTenantContext() }
            sessionReady = true
        }
    }

    // MARK: - Login

    func login(from viewController: PlatformViewController) {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        loginError  = nil

        Task {
            do {
                let bundle = try await oidcManager.startAuth(from: viewController)
                guard !bundle.accessToken.isEmpty else {
                    loginError  = "Authentication failed — empty token."
                    isLoggingIn = false
                    return
                }
                sessionManager.saveBundle(bundle)
                hydrateContext(from: bundle)
                await ensureTenantContext()
                sessionReady = true
            } catch {
                loginError  = error.localizedDescription
            }
            isLoggingIn = false
        }
    }

    // MARK: - Logout

    func logout() {
        sessionManager.logout()
        selectedAccountId = nil
        tenantId          = nil
        sessionReady      = false
    }

    // MARK: - Context Hydration

    private func hydrateContextFromStoredBundle() {
        guard let bundle = sessionManager.currentBundle() else { return }
        hydrateContext(from: bundle)
    }

    private func hydrateContext(from bundle: TokenBundle) {
        tenantId = normalizedValue(bundle.tenantId) ?? normalizedValue(sessionManager.currentTenantId())
        let scope = normalizedValue(bundle.cloudAccountId)
            ?? normalizedValue(bundle.accountId)
            ?? normalizedValue(sessionManager.currentAccountId())
        selectedAccountId = isUsableAccountId(scope) ? scope : nil
        sessionManager.updateRequestContext(
            tenantId: tenantId,
            accountId: selectedAccountId
        )
    }

    private func ensureTenantContext() async {
        if normalizedValue(tenantId) == nil, let profile = await fetchCurrentProfile() {
            tenantId = normalizedValue(profile.tenantId) ?? normalizedValue(tenantId)
            if !isUsableAccountId(selectedAccountId) {
                let scope = normalizedValue(profile.cloudAccountId) ?? normalizedValue(profile.accountId)
                selectedAccountId = isUsableAccountId(scope) ? scope : nil
            }
        }

        if normalizedValue(tenantId) == nil,
           let tenants: [TenantIdentity] = try? await api.get("api/v1/tenants") {
            tenantId = normalizedValue(tenants.first?.id)
        }

        if !isUsableAccountId(selectedAccountId) {
            let accounts = await api.discoverCloudAccounts()
            if let discovered = accounts.first(where: { isUsableAccountId($0.requestScopeId) })?.requestScopeId {
                selectedAccountId = discovered
            } else if let deployments = try? await api.fetchDeploymentsScoped(accountId: nil, limit: 100) {
                selectedAccountId = deployments.compactMap { dep in
                    let candidate = normalizedValue(dep.resolvedAccountId)
                        ?? normalizedValue(dep.cloudAccountId)
                        ?? normalizedValue(dep.accountId)
                    return isUsableAccountId(candidate) ? candidate : nil
                }.first
            }
        }

        tenantId = normalizedValue(tenantId)

        sessionManager.updateRequestContext(
            tenantId: tenantId,
            accountId: selectedAccountId
        )
    }

    private func fetchCurrentProfile() async -> UserProfile? {
        let paths = [
            "api/v1/auth/me",
            "api/v1/auth/userinfo",
            "api/v1/users/me",
            "api/v1/auth/profile",
            "api/v1/me",
        ]
        for path in paths {
            if let profile: UserProfile = try? await api.get(path) {
                return profile
            }
        }
        return nil
    }

    // MARK: - Account Switching

    func selectAccount(_ id: String?) {
        selectedAccountId = isUsableAccountId(id) ? id : nil
        sessionManager.updateRequestContext(
            tenantId: tenantId,
            accountId: selectedAccountId
        )
    }
}
