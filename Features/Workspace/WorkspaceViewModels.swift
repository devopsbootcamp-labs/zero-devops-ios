import Foundation

// MARK: - Deployments

@MainActor
final class DeploymentsViewModel: ObservableObject {
    @Published var deployments: [Deployment] = []
    @Published var isLoading   = false
    @Published var error:       String?

    private let api = APIClient.shared

    func load(accountId: String?) async {
        isLoading = true
        error     = nil
        if let aid = accountId,
           let list: [Deployment] = try? await api.get("api/v1/cloud-accounts/\(aid)/deployments?limit=500") {
            deployments = list
        } else if let aid = accountId,
                  let list: [Deployment] = try? await api.get("api/v1/deployments?cloud_account_id=\(aid)&limit=500") {
            deployments = list
        } else if let list: [Deployment] = try? await api.get("api/v1/deployments?limit=500") {
            deployments = list
        } else {
            error = "Unable to load deployments."
        }
        isLoading = false
    }
}

// MARK: - Resources

@MainActor
final class ResourcesViewModel: ObservableObject {
    @Published var resources: [Resource] = []
    @Published var isLoading  = false
    @Published var error:      String?

    private let api = APIClient.shared

    func load(accountId: String?) async {
        isLoading = true
        error     = nil
        if let list: [Resource] = try? await api.get("api/v1/resources") {
            resources = list
        } else if let list: [Resource] = try? await api.get("api/v1/inventory") {
            resources = list
        } else if let aid = accountId,
                  let deps: [Deployment] = try? await api.get("api/v1/cloud-accounts/\(aid)/deployments?limit=500") {
            resources = deps.map {
                Resource(
                    id: $0.id,
                    resourceId: nil,
                    name: $0.resolvedName,
                    type: "deployment",
                    provider: $0.cloudProvider,
                    region: $0.region,
                    status: $0.status,
                    driftStatus: $0.driftStatus,
                    deploymentId: $0.id,
                    deploymentName: $0.resolvedName,
                    tags: nil
                )
            }
        } else {
            error = "Unable to load resources."
        }
        isLoading = false
    }
}

// MARK: - Resource Detail

@MainActor
final class ResourceDetailViewModel: ObservableObject {
    @Published var resource: Resource?
    @Published var isLoading = false

    private let api = APIClient.shared

    func load(deploymentId: String, resourceId: String) async {
        isLoading = true
        if let list: [Resource] = try? await api.get("api/v1/resources?deployment_id=\(deploymentId)") {
            resource = list.first { ($0.id ?? $0.resourceId) == resourceId }
        } else if let list: [Resource] = try? await api.get("api/v1/deployments/\(deploymentId)/resources") {
            resource = list.first { ($0.id ?? $0.resourceId) == resourceId }
        }
        isLoading = false
    }
}

// MARK: - Cost

@MainActor
final class CostViewModel: ObservableObject {
    @Published var summary:     CostSummary?
    @Published var resources:   [CostResource]   = []
    @Published var deployments: [CostDeployment] = []
    @Published var isLoading    = false
    @Published var error:        String?

    private let api = APIClient.shared

    func load(accountId: String?) async {
        isLoading = true
        error     = nil
        async let s  = fetchSummary(accountId: accountId)
        async let r  = fetchResources(accountId: accountId)
        async let d  = fetchDeployments(accountId: accountId)
        summary     = try? await s
        resources   = (try? await r) ?? []
        deployments = (try? await d) ?? []
        isLoading   = false
    }

    private func fetchSummary(accountId: String?) async throws -> CostSummary {
        if let aid = accountId,
           let s: CostSummary = try? await api.get("api/v1/cloud-accounts/\(aid)/cost/summary") { return s }
        if let s: CostSummary = try? await api.get("api/v1/cost/summary") { return s }
        return try await api.get("api/v1/dashboard/cost")
    }
    private func fetchResources(accountId: String?) async throws -> [CostResource] {
        if let aid = accountId,
           let r: [CostResource] = try? await api.get("api/v1/cloud-accounts/\(aid)/cost/resources") { return r }
        return (try? await api.get("api/v1/cost/resources")) ?? []
    }
    private func fetchDeployments(accountId: String?) async throws -> [CostDeployment] {
        if let aid = accountId,
           let d: [CostDeployment] = try? await api.get("api/v1/cloud-accounts/\(aid)/cost/deployments") { return d }
        return (try? await api.get("api/v1/cost/deployments")) ?? []
    }
}
