import Foundation

@MainActor
final class CloudAccountsViewModel: ObservableObject {

    @Published var accounts:         [CloudAccount] = []
    @Published var isLoading         = false
    @Published var error:            String?
    @Published var diagnostics:      [String] = []

    private let api = APIClient.shared
    private let session = AuthSessionManager.shared

    func load() async {
        isLoading = true
        error     = nil

        let discovery = await api.discoverCloudAccountsDetailed()
        accounts = discovery.accounts
        diagnostics = discovery.diagnostics

        if accounts.isEmpty {
            accounts = fallbackAccountsFromSession()
            if !accounts.isEmpty {
                diagnostics.append("session fallback: \(accounts.count)")
            }
        }

        if accounts.isEmpty {
            let hint = diagnostics.prefix(3).joined(separator: " | ")
            error = hint.isEmpty ? "Unable to load cloud accounts from API." : "Unable to load cloud accounts from API. \(hint)"
        } else {
            error = nil
        }
        isLoading = false
    }

    private func fallbackAccountsFromSession() -> [CloudAccount] {
        let bundle = session.currentBundle()
        let rawAccount = session.currentAccountId() ?? bundle?.cloudAccountId ?? bundle?.accountId
        guard let accountId = rawAccount?.trimmingCharacters(in: .whitespacesAndNewlines), !accountId.isEmpty else {
            return []
        }

        let providerGuess: String
        if accountId.lowercased().contains("aws") { providerGuess = "aws" }
        else if accountId.lowercased().contains("gcp") { providerGuess = "gcp" }
        else if accountId.lowercased().contains("azure") { providerGuess = "azure" }
        else { providerGuess = "unknown" }

        return [
            CloudAccount(
                id: accountId,
                cloudAccountId: bundle?.cloudAccountId ?? accountId,
                accountId: bundle?.accountId ?? accountId,
                externalAccountId: nil,
                cloudAccountName: "Current Account",
                displayName: "Current Account",
                name: accountId,
                provider: providerGuess,
                cloudProvider: providerGuess,
                region: nil,
                defaultRegion: nil,
                status: "session",
                tenantId: bundle?.tenantId
            )
        ]
    }

}
