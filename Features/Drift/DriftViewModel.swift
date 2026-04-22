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
        async let deps = fetchDeployments(accountId: accountId)

        var failures: [String] = []

        do {
            posture = try await p
        } catch {
            posture = nil
            failures.append("posture: \(error.localizedDescription)")
        }
        let driftResult = await Result { try await d }
        let depsResult = await Result { try await deps }

        let deploymentList = (try? depsResult.get()) ?? []
        nameMap = Dictionary(uniqueKeysWithValues: deploymentList.map { ($0.id, $0.resolvedName) })

        if let driftItems = try? driftResult.get(), !driftItems.isEmpty {
            items = driftItems
        } else {
            items = deploymentList.map {
                DriftDeployment(
                    deploymentId: $0.id,
                    drifted: $0.driftStatus?.lowercased() == "drifted",
                    driftedResourcesCount: nil,
                    changesCount: nil,
                    severity: nil,
                    lastCheckedAt: nil,
                    jobStatus: $0.driftStatus
                )
            }
        }

        if case .failure(let e) = driftResult {
            failures.append("drift deployments unavailable, using deployment fallback: \(e.localizedDescription)")
        }
        if case .failure(let e) = depsResult {
            failures.append("deployment name map: \(e.localizedDescription)")
        }

        if !failures.isEmpty {
            error = "Drift fetch failures:\n" + failures.joined(separator: "\n")
        }
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

    private func fetchDeployments(accountId: String?) async throws -> [Deployment] {
        try await api.fetchDeploymentsScoped(accountId: accountId, limit: 500)
    }
}
