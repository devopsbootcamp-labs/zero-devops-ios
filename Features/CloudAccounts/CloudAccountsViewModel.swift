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

        var lastError: Error?

        // Try each endpoint in order — surface the real error if all fail.
        do {
            let list: [CloudAccount] = try await api.get("api/v1/accounts")
            accounts = deduplicated(list)
            isLoading = false
            return
        } catch { lastError = error }

        do {
            let resp: CloudAccountsResponse = try await api.get("api/v1/cloud/accounts")
            accounts = deduplicated(resp.resolved)
            isLoading = false
            return
        } catch { lastError = error }

        do {
            let resp: CloudAccountsResponse = try await api.get("api/v1/cloud-accounts")
            accounts = deduplicated(resp.resolved)
            isLoading = false
            return
        } catch { lastError = error }

        do {
            let list: [CloudAccount] = try await api.get("api/v1/cloud-accounts")
            accounts = deduplicated(list)
            isLoading = false
            return
        } catch { lastError = error }

        // All endpoints failed — show the real error (e.g. RBAC 403) rather than a generic message.
        accounts = []
        error = lastError.map { "Unable to load cloud accounts: \($0.localizedDescription)" }
               ?? "Unable to load cloud accounts from API."
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
