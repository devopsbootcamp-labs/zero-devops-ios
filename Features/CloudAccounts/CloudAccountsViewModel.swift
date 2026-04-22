import Foundation

@MainActor
final class CloudAccountsViewModel: ObservableObject {

    private struct AccountProviderKey: Hashable {
        let accountId: String
        let provider: String
    }

    @Published var accounts:         [CloudAccount] = []
    @Published var isLoading         = false
    @Published var error:            String?

    private let api = APIClient.shared
    private let session = AuthSessionManager.shared

    func load() async {
        isLoading = true
        error     = nil

        var lastError: Error?

        if let resp: CloudAccountsResponse = try? await api.get("api/v1/accounts") {
            accounts = deduplicated(resp.resolved)
        } else if let list: [CloudAccount] = try? await api.get("api/v1/accounts") {
            accounts = deduplicated(list)
        } else if let resp: CloudAccountsResponse = try? await api.get("api/v1/cloud/accounts") {
            accounts = deduplicated(resp.resolved)
        } else if let list: [CloudAccount] = try? await api.get("api/v1/cloud/accounts") {
            accounts = deduplicated(list)
        } else if let resp: CloudAccountsResponse = try? await api.get("api/v1/cloud-accounts") {
            accounts = deduplicated(resp.resolved)
        } else if let list: [CloudAccount] = try? await api.get("api/v1/cloud-accounts") {
            accounts = deduplicated(list)
        }

        if accounts.isEmpty {
            do {
                let deps = try await api.fetchDeploymentsScoped(accountId: nil, limit: 500)
                accounts = deduplicated(deriveAccounts(from: deps))
            } catch {
                lastError = error
            }
        }

        if accounts.isEmpty {
            accounts = fallbackAccountsFromSession()
        }

        if accounts.isEmpty {
            if let lastError {
                error = "Unable to load cloud accounts from API: \(lastError.localizedDescription)"
            } else {
                error = "Unable to load cloud accounts from API."
            }
        } else {
            error = nil
        }
        isLoading = false
    }

    private func deduplicated(_ list: [CloudAccount]) -> [CloudAccount] {
        var seen  = Set<String>()
        return list.filter {
            let key = $0.resolvedScopeId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    private func deriveAccounts(from deps: [Deployment]) -> [CloudAccount] {
        let grouped = Dictionary(grouping: deps) { dep in
            let accountKey = (dep.resolvedAccountId ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedAccount = accountKey.isEmpty ? "unknown" : accountKey
            return AccountProviderKey(accountId: normalizedAccount, provider: dep.cloudProvider ?? "unknown")
        }

        return grouped.map { key, deployments in
            let accountId = key.accountId
            let provider = key.provider
            let names = deployments
                .map { $0.resolvedName.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let derivedName = names.isEmpty ? (accountId == "unknown" ? "\(provider.uppercased()) (derived)" : accountId) : names[0]
            return CloudAccount(
                id: "\(provider):\(accountId)",
                cloudAccountId: accountId == "unknown" ? nil : accountId,
                accountId: accountId == "unknown" ? nil : accountId,
                externalAccountId: nil,
                cloudAccountName: derivedName,
                displayName: nil,
                name: derivedName,
                provider: provider,
                cloudProvider: provider,
                region: deployments.first?.region,
                defaultRegion: deployments.first?.region,
                status: "derived",
                tenantId: deployments.first?.tenantId
            )
        }
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
