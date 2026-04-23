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
            error = buildErrorMessage(diagnostics: discovery.diagnostics)
        } else {
            error = nil
        }
        isLoading = false
    }

    private func buildErrorMessage(diagnostics: [String]) -> String {
        let allFailures = diagnostics.filter { $0.contains("failed") }
        let diagnosticText = allFailures.joined(separator: " ").lowercased()

        // RBAC / permission denial
        if diagnosticText.contains("cloud.read")
            || diagnosticText.contains("rbac")
            || diagnosticText.contains("access denied")
            || diagnosticText.contains("403")
            || diagnosticText.contains("forbidden") {
            return "Permission denied: your account does not have the cloud.read permission.\n" +
                   "Contact your administrator to grant you access to cloud accounts."
        }

        // Authentication failure
        if diagnosticText.contains("401")
            || diagnosticText.contains("unauthorized")
            || diagnosticText.contains("unauthenticated") {
            return "Session expired. Please sign out and sign in again to refresh your credentials."
        }

        // Network / connectivity
        if diagnosticText.contains("network")
            || diagnosticText.contains("offline")
            || diagnosticText.contains("timed out")
            || diagnosticText.contains("connection") {
            return "Cannot reach the server. Check your internet connection and try again."
        }

        // All endpoints returned empty (no error, but no accounts found)
        let hasOnlyEmpty = !allFailures.isEmpty && diagnostics.allSatisfy {
            !$0.contains("failed") || $0.hasSuffix("0")
        }
        if hasOnlyEmpty || allFailures.isEmpty {
            return "No cloud accounts found for your tenant.\n" +
                   "Ask your administrator to connect a cloud account in the web console."
        }

        // Generic: surface first actionable failure line
        if let first = allFailures.first {
            return "Unable to load cloud accounts.\n\(first)"
        }
        return "Unable to load cloud accounts from the API. Pull to retry."
    }

}

