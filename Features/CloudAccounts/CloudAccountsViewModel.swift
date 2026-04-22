import Foundation

@MainActor
final class CloudAccountsViewModel: ObservableObject {

    @Published var accounts:         [CloudAccount] = []
    @Published var isLoading         = false
    @Published var error:            String?
    @Published var diagnostics:      [String] = []

    private let api = APIClient.shared

    func load() async {
        isLoading = true
        error     = nil

        let discovery = await api.discoverCloudAccountsDetailed()
        accounts = discovery.accounts
        diagnostics = discovery.diagnostics

        if accounts.isEmpty {
            // Build a user-readable error that surfaces exactly which endpoints were
            // tried and why they failed, so the root cause can be identified quickly.
            let failures = diagnostics.filter { $0.contains("failed") }
            let successes = diagnostics.filter { !$0.contains("failed") }
            var lines: [String] = ["Unable to load cloud accounts from API."]
            if let tenantLine = diagnostics.first(where: { $0 == "tenant: already set" || $0.hasPrefix("tenant from ") }) {
                lines.append(tenantLine)
            }
            if let firstFailure = failures.first {
                lines.append(firstFailure)
            }
            if let successLine = successes.first(where: { $0.contains("0") && !$0.contains("tenant") }) {
                lines.append(successLine)
            }
            error = lines.joined(separator: "\n")
        } else {
            error = nil
        }
        isLoading = false
    }

}

