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
            if let raw = try? await api.getJSON("api/v1/accounts") {
                accounts = deduplicated(parseAccounts(from: raw))
            } else if let raw = try? await api.getJSON("api/v1/cloud/accounts") {
                accounts = deduplicated(parseAccounts(from: raw))
            } else if let raw = try? await api.getJSON("api/v1/cloud-accounts") {
                accounts = deduplicated(parseAccounts(from: raw))
            }
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

    private func parseAccounts(from raw: Any) -> [CloudAccount] {
        if let array = raw as? [[String: Any]] {
            return array.compactMap(accountFromDictionary)
        }
        if let dict = raw as? [String: Any] {
            let candidateKeys = ["accounts", "cloudAccounts", "cloud_accounts", "data", "items", "results"]
            for key in candidateKeys {
                if let nested = dict[key] {
                    let parsed = parseAccounts(from: nested)
                    if !parsed.isEmpty { return parsed }
                }
            }
            if let single = accountFromDictionary(dict) {
                return [single]
            }
        }
        return []
    }

    private func accountFromDictionary(_ dict: [String: Any]) -> CloudAccount? {
        func stringValue(_ keys: [String]) -> String? {
            for key in keys {
                if let value = dict[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
                if let value = dict[key] as? Int { return String(value) }
                if let value = dict[key] as? Double {
                    return value.rounded(.towardZero) == value ? String(Int(value)) : String(value)
                }
                if let value = dict[key] as? Bool { return value ? "true" : "false" }
            }
            return nil
        }

        let id = stringValue(["id"])
        let cloudAccountId = stringValue(["cloudAccountId", "cloud_account_id"])
        let accountId = stringValue(["accountId", "account_id"])
        let externalAccountId = stringValue(["externalAccountId", "external_account_id"])
        let cloudAccountName = stringValue(["cloudAccountName", "cloud_account_name"])
        let displayName = stringValue(["displayName", "display_name"])
        let name = stringValue(["name"])
        let provider = stringValue(["provider"])
        let cloudProvider = stringValue(["cloudProvider", "cloud_provider"])
        let region = stringValue(["region"])
        let defaultRegion = stringValue(["defaultRegion", "default_region"])
        let status = stringValue(["status"])
        let tenantId = stringValue(["tenantId", "tenant_id"])

        let stable = cloudAccountId ?? accountId ?? externalAccountId ?? id ?? name
        guard stable != nil else { return nil }

        return CloudAccount(
            id: id,
            cloudAccountId: cloudAccountId,
            accountId: accountId,
            externalAccountId: externalAccountId,
            cloudAccountName: cloudAccountName,
            displayName: displayName,
            name: name,
            provider: provider,
            cloudProvider: cloudProvider,
            region: region,
            defaultRegion: defaultRegion,
            status: status,
            tenantId: tenantId
        )
    }

}
