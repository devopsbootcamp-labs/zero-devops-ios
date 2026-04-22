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
        } else if let resp: CloudAccountsResponse = try? await api.get("api/v1/cloud-accounts") {
            accounts = deduplicated(resp.resolved)
        } else if let list: [CloudAccount] = try? await api.get("api/v1/cloud-accounts") {
            accounts = deduplicated(list)
        } else {
            error = "Unable to load cloud accounts from API."
        }
        isLoading = false
    }

    private func deduplicated(_ list: [CloudAccount]) -> [CloudAccount] {
        var seen  = Set<String>()
        return list.filter {
            guard let key = $0.requestScopeId ?? $0.requestAccountId else { return false }
            return seen.insert(key).inserted
        }
    }

}
