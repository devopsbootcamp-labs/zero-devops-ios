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
        tenantId          = bundle.tenantId
        let scope = bundle.cloudAccountId ?? bundle.accountId
        selectedAccountId = isUsableAccountId(scope) ? scope : nil
        sessionManager.updateRequestContext(
            tenantId: tenantId,
            accountId: selectedAccountId
        )
    }

    private func ensureTenantContext() async {
        if tenantId == nil, let profile = await fetchCurrentProfile() {
            tenantId = profile.tenantId ?? tenantId
            if selectedAccountId == nil {
                let scope = profile.cloudAccountId ?? profile.accountId
                selectedAccountId = isUsableAccountId(scope) ? scope : nil
            }
        }

        if tenantId == nil,
           let tenants: [TenantIdentity] = try? await api.get("api/v1/tenants") {
            tenantId = tenants.first?.id
        }

        if selectedAccountId == nil {
            if let accounts: [CloudAccount] = try? await api.get("api/v1/accounts") {
                selectedAccountId = accounts.first(where: { isUsableAccountId($0.requestScopeId) })?.requestScopeId
            } else if let response: CloudAccountsResponse = try? await api.get("api/v1/cloud/accounts") {
                selectedAccountId = response.resolved.first(where: { isUsableAccountId($0.requestScopeId) })?.requestScopeId
            } else if let response: CloudAccountsResponse = try? await api.get("api/v1/cloud-accounts") {
                selectedAccountId = response.resolved.first(where: { isUsableAccountId($0.requestScopeId) })?.requestScopeId
            } else if let accounts: [CloudAccount] = try? await api.get("api/v1/cloud-accounts") {
                selectedAccountId = accounts.first(where: { isUsableAccountId($0.requestScopeId) })?.requestScopeId
            }
        }

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
