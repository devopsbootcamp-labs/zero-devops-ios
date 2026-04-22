import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published var deployments:   [Deployment]       = []
    @Published var posture:       DriftPosture?
    @Published var overview:      AnalyticsOverview?
    @Published var costSummary:   CostSummary?
    @Published var activeResources = 0
    @Published var isLoading      = false
    @Published var error:         String?

    private let api     = APIClient.shared
    private let session = AuthSessionManager.shared

    func load(accountId: String?) async {
        isLoading = true
        error     = nil

        async let deps    = fetchDeployments(accountId: accountId)
        async let posture = fetchPosture(accountId: accountId)
        async let ov      = fetchOverview()
        async let cost    = fetchCost(accountId: accountId)
        async let resources = fetchActiveResources()

        var failures: [String] = []

        do {
            deployments = try await deps
        } catch {
            deployments = []
            failures.append("deployments: \(error.localizedDescription)")
        }
        do {
            self.posture = try await posture
        } catch {
            self.posture = nil
            failures.append("drift posture: \(error.localizedDescription)")
        }
        do {
            overview = try await ov
        } catch {
            overview = nil
            failures.append("analytics overview: \(error.localizedDescription)")
        }
        do {
            costSummary = try await cost
        } catch {
            costSummary = nil
            failures.append("cost summary: \(error.localizedDescription)")
        }
        do {
            activeResources = try await resources
        } catch {
            activeResources = overview?.resolvedActiveResources() ?? 0
            failures.append("active resources: \(error.localizedDescription)")
        }

        if activeResources == 0 {
            activeResources = overview?.resolvedActiveResources() ?? 0
        }

        if !failures.isEmpty {
            error = "Dashboard fetch failures:\n" + failures.joined(separator: "\n")
        }
        isLoading    = false
    }

    private func fetchDeployments(accountId: String?) async throws -> [Deployment] {
        try await api.fetchDeploymentsScoped(accountId: accountId, limit: 500)
    }

    private func fetchPosture(accountId: String?) async throws -> DriftPosture {
        if let aid = accountId,
           let query = APIClient.buildQueryString(["cloud_account_id": aid]),
           let scoped: DriftPosture = try? await api.get("api/v1/drift/posture?\(query)") {
            return scoped
        }
        return try await api.get("api/v1/drift/posture")
    }

    private func fetchOverview() async throws -> AnalyticsOverview {
        try await api.get("api/v1/analytics/overview?range=30d")
    }

    private func fetchCost(accountId: String?) async throws -> CostSummary {
        if let aid = accountId, let encoded = APIClient.encodePathComponent(aid),
           let s: CostSummary = try? await api.get("api/v1/cloud-accounts/\(encoded)/cost/summary") {
            return s
        }
        if let s: CostSummary = try? await api.get("api/v1/cost/summary") { return s }
        return try await api.get("api/v1/dashboard/cost")
    }

    private func fetchActiveResources() async throws -> Int {
        if let resources: [Resource] = try? await api.get("api/v1/resources") {
            return resources.count
        }
        let inventory: [Resource] = try await api.get("api/v1/inventory")
        return inventory.count
    }
}
