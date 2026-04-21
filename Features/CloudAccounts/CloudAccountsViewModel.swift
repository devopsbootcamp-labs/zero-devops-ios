import Foundation

@MainActor
final class CloudAccountsViewModel: ObservableObject {

    @Published var accounts:         [CloudAccount] = []
    @Published var isLoading         = false
    @Published var error:            String?

    private let api = APIClient.shared

    func load() async {
        isLoading = true
        error     = nil

        if let list: [CloudAccount] = try? await api.get("api/v1/accounts") {
            accounts = deduplicated(list)
        } else if let resp: CloudAccountsResponse = try? await api.get("api/v1/cloud/accounts") {
            accounts = deduplicated(resp.resolved)
        } else if let list: [CloudAccount] = try? await api.get("api/v1/cloud-accounts") {
            accounts = deduplicated(list)
        } else {
            // Derive virtual accounts from deployments
            if let deps: [Deployment] = try? await api.get("api/v1/deployments") {
                accounts = derivedAccounts(from: deps)
            } else {
                error = "Unable to load cloud accounts."
            }
        }
        isLoading = false
    }

    private func deduplicated(_ list: [CloudAccount]) -> [CloudAccount] {
        var seen  = Set<String>()
        return list.filter { seen.insert($0.resolvedScopeId).inserted }
    }

    private func derivedAccounts(from deployments: [Deployment]) -> [CloudAccount] {
        var seen  = Set<String>()
        var result = [CloudAccount]()
        for dep in deployments {
            guard let scopeId = dep.cloudAccountId ?? dep.accountId else {
                continue
            }
            if seen.insert(scopeId).inserted {
                result.append(CloudAccount(
                    id:               scopeId,
                    cloudAccountId:   dep.cloudAccountId,
                    accountId:        dep.accountId,
                    externalAccountId: nil,
                    cloudAccountName:  nil,
                    displayName:       nil,
                    name:              scopeId,
                    provider:          dep.cloudProvider,
                    cloudProvider:     dep.cloudProvider,
                    region:            dep.region,
                    defaultRegion:     nil,
                    status:            "active",
                    tenantId:          nil
                ))
            }
        }
        return result
    }
}
