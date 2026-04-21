import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published var deployments:   [Deployment]       = []
    @Published var posture:       DriftPosture?
    @Published var overview:      AnalyticsOverview?
    @Published var costSummary:   CostSummary?
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

        deployments  = (try? await deps)    ?? []
        self.posture = try? await posture
        overview     = try? await ov
        costSummary  = try? await cost
        isLoading    = false
    }

    private func fetchDeployments(accountId: String?) async throws -> [Deployment] {
        if let aid = accountId {
            if let list: [Deployment] = try? await api.get("api/v1/cloud-accounts/\(aid)/deployments") {
                return list
            }
        }
        return try await api.get("api/v1/deployments")
    }

    private func fetchPosture(accountId: String?) async throws -> DriftPosture {
        let path = accountId.map { "api/v1/drift/posture?cloud_account_id=\($0)" }
                ?? "api/v1/drift/posture"
        return try await api.get(path)
    }

    private func fetchOverview() async throws -> AnalyticsOverview {
        try await api.get("api/v1/analytics/overview?range=30d")
    }

    private func fetchCost(accountId: String?) async throws -> CostSummary {
        if let aid = accountId {
            if let s: CostSummary = try? await api.get("api/v1/cloud-accounts/\(aid)/cost/summary") {
                return s
            }
        }
        if let s: CostSummary = try? await api.get("api/v1/cost/summary") { return s }
        return try await api.get("api/v1/dashboard/cost")
    }
}
