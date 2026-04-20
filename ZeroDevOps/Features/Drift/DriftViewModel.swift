import Foundation

@MainActor
final class DriftViewModel: ObservableObject {

    @Published var posture:     DriftPosture?
    @Published var items:       [DriftDeployment] = []
    @Published var nameMap:     [String: String]  = [:]
    @Published var isLoading    = false
    @Published var error:       String?
    @Published var triggerResult: String?

    private let api = APIClient.shared

    func load(accountId: String?) async {
        isLoading = true
        error     = nil

        async let p  = fetchPosture(accountId: accountId)
        async let d  = fetchDriftDeployments(accountId: accountId)
        async let nm = fetchNameMap(accountId: accountId)

        posture  = try? await p
        items    = (try? await d) ?? []
        nameMap  = (try? await nm) ?? [:]
        isLoading = false
    }

    func triggerCheck(deploymentId: String) async {
        do {
            let _: EmptyResponse = try await api.post(
                "api/v1/drift/jobs",
                body: DriftJobRequest(deploymentId: deploymentId)
            )
            triggerResult = "Drift check queued for \(nameMap[deploymentId] ?? deploymentId)."
        } catch {
            triggerResult = error.localizedDescription
        }
    }

    func runAllChecks() async {
        for item in items {
            await triggerCheck(deploymentId: item.deploymentId)
        }
    }

    private func fetchPosture(accountId: String?) async throws -> DriftPosture {
        let path = accountId.map { "api/v1/drift/posture?cloud_account_id=\($0)" }
                ?? "api/v1/drift/posture"
        return try await api.get(path)
    }

    private func fetchDriftDeployments(accountId: String?) async throws -> [DriftDeployment] {
        let base = "api/v1/drift/deployments?limit=100"
        let path = accountId.map { "\(base)&cloud_account_id=\($0)" } ?? base
        return try await api.get(path)
    }

    private func fetchNameMap(accountId: String?) async throws -> [String: String] {
        var deps: [Deployment] = []
        if let aid = accountId,
           let list: [Deployment] = try? await api.get("api/v1/cloud-accounts/\(aid)/deployments") {
            deps = list
        } else if let list: [Deployment] = try? await api.get("api/v1/deployments") {
            deps = list
        }
        return Dictionary(uniqueKeysWithValues: deps.map { ($0.id, $0.resolvedName) })
    }
}
