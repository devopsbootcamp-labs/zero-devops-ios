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
            Task {
                await populateTenantPreflight()
                sessionReady = true
                Task { await ensureTenantContext() }
            }
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

                // Bounded preflight: fetch tenant/profile (≤3 s) before showing the main
                // shell so the x-tenant-id header is set on every first-render API call.
                // Many Keycloak deployments do NOT embed tenantId in the JWT, so without
                // this step views load with no tenant context and receive 403/empty data.
                // onChange(of: tenantId) in each data view handles the slow-preflight path.
                await populateTenantPreflight()

                sessionReady = true

                // Full context enrichment (account discovery etc.) in background.
                Task { await ensureTenantContext() }
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
        // Enterprise default: start in tenant scope and only switch to account scope
        // when the user explicitly selects an account in the UI.
        selectedAccountId = nil
        sessionManager.updateRequestContext(
            tenantId: tenantId,
            accountId: selectedAccountId
        )
    }

    private func ensureTenantContext() async {
        if normalizedValue(tenantId) == nil, let profile = await fetchCurrentProfile() {
            tenantId = normalizedValue(profile.tenantId) ?? normalizedValue(tenantId)
        }

        if normalizedValue(tenantId) == nil,
           let tenants: [TenantIdentity] = try? await api.get("api/v1/tenants") {
            tenantId = normalizedValue(tenants.first?.id)
        }

        tenantId = normalizedValue(tenantId)

        sessionManager.updateRequestContext(
            tenantId: tenantId,
            accountId: selectedAccountId
        )
    }

    /// Populate tenantId before sessionReady so every first-render API call carries
    /// x-tenant-id.  Tries profile endpoints first (fast when backend maps from JWT),
    /// then falls back to the tenant-list endpoint which works on most backends
    /// without an existing x-tenant-id header.  Capped at 5 s so a slow/unreachable
    /// API never re-introduces the login-spinner hang.
    private func populateTenantPreflight() async {
        guard normalizedValue(tenantId) == nil else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                // 1. Profile endpoints — many backends embed tenantId in their /me response.
                let profilePaths = [
                    "api/v1/auth/me",
                    "api/v1/auth/userinfo",
                    "api/v1/users/me",
                    "api/v1/auth/profile",
                    "api/v1/me",
                ]
                for path in profilePaths {
                    if let profile: UserProfile = try? await APIClient.shared.get(path),
                       let tid = profile.tenantId?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !tid.isEmpty {
                        await MainActor.run {
                            self.tenantId = tid
                            self.sessionManager.updateRequestContext(
                                tenantId: tid, accountId: self.selectedAccountId)
                        }
                        return
                    }
                }
                // 2. Tenant-list endpoint — works without x-tenant-id on most backends
                //    because the server resolves the caller's tenant from the JWT sub/email.
                //    This is the common path when Keycloak doesn't embed a tenantId claim.
                if let tenants: [TenantIdentity] = try? await APIClient.shared.get("api/v1/tenants"),
                   let tid = tenants.first?.id.trimmingCharacters(in: .whitespacesAndNewlines),
                   !tid.isEmpty {
                    await MainActor.run {
                        self.tenantId = tid
                        self.sessionManager.updateRequestContext(
                            tenantId: tid, accountId: self.selectedAccountId)
                    }
                }
            }
            group.addTask { try? await Task.sleep(nanoseconds: 5_000_000_000) }
            _ = await group.next()
            group.cancelAll()
        }
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
