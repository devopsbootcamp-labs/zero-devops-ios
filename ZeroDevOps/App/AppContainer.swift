import Foundation
import Combine
import UIKit

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

    // MARK: - App Launch

    func onAppear() {
        if sessionManager.resumeIfAvailable() {
            hydrateContextFromStoredBundle()
            sessionReady = true
        }
    }

    // MARK: - Login

    func login(from viewController: UIViewController) {
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
        selectedAccountId = bundle.cloudAccountId ?? bundle.accountId
    }

    private func ensureTenantContext() async {
        guard selectedAccountId == nil else { return }
        // Fetch cloud accounts and use the first one as default scope
        if let accounts: [CloudAccount] = try? await api.get("api/v1/accounts") {
            selectedAccountId = accounts.first?.resolvedScopeId
        } else if let response: CloudAccountsResponse = try? await api.get("api/v1/cloud/accounts") {
            selectedAccountId = response.resolved.first?.resolvedScopeId
        }
    }

    // MARK: - Account Switching

    func selectAccount(_ id: String?) {
        selectedAccountId = id
    }
}
