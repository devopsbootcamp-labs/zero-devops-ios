import Foundation
import Combine

@MainActor
final class DeploymentDetailViewModel: ObservableObject {

    @Published var deployment:   Deployment?
    @Published var plan:         DeploymentPlan?
    @Published var logs:         [DeploymentLog] = []
    @Published var isLoading     = false
    @Published var isActionRunning = false
    @Published var actionResult: String?
    @Published var error:        String?
    @Published var isStreaming   = false

    private let api = APIClient.shared
    private var pollCount = 0

    func load(deploymentId: String) async {
        isLoading = true
        error     = nil
        async let dep  = fetchDeployment(id: deploymentId)
        async let plan = fetchPlan(id: deploymentId)
        async let logs = fetchLogs(id: deploymentId)
        deployment   = try? await dep
        self.plan    = try? await plan
        self.logs    = (try? await logs) ?? []
        isLoading    = false
    }

    func runPlan(deploymentId: String) async {
        await runAction(path: "api/v1/deployments/\(deploymentId)/plan", label: "Plan")
        await streamLogs(deploymentId: deploymentId)
    }

    func runApply(deploymentId: String) async {
        await runAction(path: "api/v1/deployments/\(deploymentId)/apply", label: "Apply")
        await streamLogs(deploymentId: deploymentId)
    }

    func runApprove(deploymentId: String) async {
        await runAction(path: "api/v1/deployments/\(deploymentId)/approve", label: "Approve")
    }

    func runDriftCheck(deploymentId: String) async {
        isActionRunning = true
        actionResult    = nil
        // Resolve canonical cloud-account scope id so backend credential lookup works
        // across providers (notably GCP project/account aliases).
        let cloudAccountId = await resolveDriftCloudAccountId()
        do {
            let _: EmptyResponse = try await api.post(
                "api/v1/drift/jobs",
                body: DriftJobRequest(deploymentId: deploymentId, cloudAccountId: cloudAccountId)
            )
            actionResult = "Drift check queued. Streaming logs..."
        } catch {
            actionResult = error.localizedDescription
            isActionRunning = false
            return
        }
        isActionRunning = false
        await refreshDeploymentState(deploymentId: deploymentId)
        await streamDriftLogs(deploymentId: deploymentId)
    }

    func runDestroy(deploymentId: String) async -> Bool {
        await runAction(path: "api/v1/deployments/\(deploymentId)/destroy", label: "Destroy")
        return actionResult?.hasPrefix("Destroy") == true
    }

    // MARK: - Private

    private func runAction(path: String, label: String) async {
        isActionRunning = true
        actionResult    = nil
        do {
            let _: EmptyResponse = try await api.post(path, body: EmptyBody())
            actionResult = "\(label) started."
        } catch {
            actionResult = error.localizedDescription
        }
        isActionRunning = false
    }

    private func streamLogs(deploymentId: String) async {
        isStreaming = true
        pollCount   = 0
        while pollCount < 40 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if let newLogs: [DeploymentLog] = try? await api.get("api/v1/deployments/\(deploymentId)/logs") {
                logs = newLogs
            }
            pollCount += 1
        }
        isStreaming = false
    }

    private func streamDriftLogs(deploymentId: String) async {
        isStreaming = true
        pollCount   = 0
        while pollCount < 40 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if let newLogs = try? await fetchDriftLogs(deploymentId: deploymentId), !newLogs.isEmpty {
                logs = newLogs
            }
            await refreshDeploymentState(deploymentId: deploymentId)
            pollCount += 1
        }
        isStreaming = false
    }

    private func fetchDriftLogs(deploymentId: String) async throws -> [DeploymentLog] {
        let paths = [
            "api/v1/deployments/\(deploymentId)/drift/logs",
            "api/v1/drift/deployments/\(deploymentId)/logs",
            "api/v1/drift/jobs/\(deploymentId)/logs",
            "api/v1/deployments/\(deploymentId)/logs?source=drift",
            "api/v1/deployments/\(deploymentId)/logs",
        ]
        for path in paths {
            if let list: [DeploymentLog] = try? await api.get(path), !list.isEmpty {
                return list
            }
        }
        return []
    }

    private func fetchDeployment(id: String) async throws -> Deployment {
        try await api.get("api/v1/deployments/\(id)")
    }
    private func fetchPlan(id: String) async throws -> DeploymentPlan {
        try await api.get("api/v1/deployments/\(id)/plan")
    }
    private func fetchLogs(id: String) async throws -> [DeploymentLog] {
        try await api.get("api/v1/deployments/\(id)/logs")
    }

    private func refreshDeploymentState(deploymentId: String) async {
        if let updated: Deployment = try? await api.get("api/v1/deployments/\(deploymentId)") {
            deployment = updated
        }
    }

    private func resolveDriftCloudAccountId() async -> String? {
        guard let dep = deployment else { return nil }

        let deploymentProvider = normalizeIdentifier(dep.cloudProvider)
        let deploymentCandidates = Set([
            dep.cloudAccountId,
            dep.accountId,
            dep.resolvedAccountId,
            dep.params?["cloud_account_id"],
            dep.params?["account_id"],
            dep.params?["cloudAccountId"],
            dep.params?["accountId"],
        ].compactMap(normalizeIdentifier).map { $0.lowercased() })

        let accounts = await api.discoverCloudAccountsDetailed().accounts
        let matched = accounts.first { account in
            let accountProvider = normalizeIdentifier(account.provider ?? account.cloudProvider)
            if let deploymentProvider, let accountProvider,
               deploymentProvider.lowercased() != accountProvider.lowercased() {
                return false
            }
            let accountCandidates = [
                account.requestScopeId,
                account.cloudAccountId,
                account.id,
                account.accountIdentifier,
                account.accountId,
                account.externalAccountId,
            ].compactMap(normalizeIdentifier).map { $0.lowercased() }
            return !deploymentCandidates.isDisjoint(with: Set(accountCandidates))
        }

        return matched?.requestScopeId
            ?? normalizeIdentifier(dep.cloudAccountId)
            ?? normalizeIdentifier(dep.accountId)
            ?? normalizeIdentifier(dep.resolvedAccountId)
    }

    private func normalizeIdentifier(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
    }
}

private struct EmptyBody: Encodable {}
