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
        var lastError: Error?
        do {
            deployments = try await api.fetchDeploymentsScoped(accountId: accountId, limit: 500)
        } catch {
            lastError = error
            deployments = []
        }
        if deployments.isEmpty, let lastError {
            self.error = "Unable to load deployments: \(lastError.localizedDescription)"
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
        var lastError: Error?
        do {
            resources = try await api.fetchResourcesScoped(accountId: accountId)
            isLoading = false
            return
        } catch {
            lastError = error
        }
        resources = []
        if resources.isEmpty, let lastError {
            self.error = "Unable to load resources: \(lastError.localizedDescription)"
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
        if let encoded = APIClient.encodePathComponent(deploymentId),
           let query = APIClient.buildQueryString(["deployment_id": deploymentId]),
           let list: [Resource] = try? await api.get("api/v1/resources?\(query)") {
            resource = list.first { ($0.id ?? $0.resourceId) == resourceId }
        } else if let encoded = APIClient.encodePathComponent(deploymentId),
                  let list: [Resource] = try? await api.get("api/v1/deployments/\(encoded)/resources") {
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
        do {
            summary     = try await s
        } catch {
            summary = nil
            self.error = "Cost summary unavailable: \(error.localizedDescription)"
        }
        do {
            resources = try await r
        } catch {
            resources = []
            self.error = (self.error ?? "") + (self.error == nil ? "" : "\n") + "Cost resources unavailable: \(error.localizedDescription)"
        }
        do {
            deployments = try await d
        } catch {
            deployments = []
            self.error = (self.error ?? "") + (self.error == nil ? "" : "\n") + "Cost deployments unavailable: \(error.localizedDescription)"
        }
        isLoading   = false
    }

    private func fetchSummary(accountId: String?) async throws -> CostSummary {
        if let aid = accountId,
           let s: CostSummary = try? await api.get("api/v1/cloud-accounts/\(aid)/cost/summary") { return s }
        if let s: CostSummary = try? await api.get("api/v1/cost/summary") { return s }
        return try await api.get("api/v1/dashboard/cost")
    }
    private func fetchResources(accountId: String?) async throws -> [CostResource] {
        if let aid = accountId, let encoded = APIClient.encodePathComponent(aid),
           let r: [CostResource] = try? await api.get("api/v1/cloud-accounts/\(encoded)/cost/resources") { return r }
        return (try? await api.get("api/v1/cost/resources")) ?? []
    }
    
    private func fetchDeployments(accountId: String?) async throws -> [CostDeployment] {
        if let aid = accountId, let encoded = APIClient.encodePathComponent(aid),
           let d: [CostDeployment] = try? await api.get("api/v1/cloud-accounts/\(encoded)/cost/deployments") { return d }
        return (try? await api.get("api/v1/cost/deployments")) ?? []
    }
}
