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

        let candidates = buildDriftAccountCandidates()
        var lastError: Error?

        for candidate in candidates {
            do {
                let _: EmptyResponse = try await api.post(
                    "api/v1/drift/jobs",
                    body: DriftJobRequest(deploymentId: deploymentId, cloudAccountId: candidate)
                )
                actionResult = "Drift check queued. Streaming logs..."
                isActionRunning = false
                await refreshDeploymentState(deploymentId: deploymentId)
                await streamDriftLogs(deploymentId: deploymentId)
                return
            } catch {
                lastError = error
            }
        }

        actionResult = (lastError ?? APIError.invalidResponse).localizedDescription
        isActionRunning = false
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

    private func buildDriftAccountCandidates() -> [String?] {
        var result: [String?] = []
        var seen = Set<String>()

        func appendUnique(_ value: String?) {
            guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty() else { return }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { return }
            result.append(normalized)
        }

        appendUnique(deployment?.params?["cloud_account_id"])
        appendUnique(deployment?.params?["account_id"])
        appendUnique(deployment?.cloudAccountId)
        appendUnique(deployment?.accountId)
        appendUnique(deployment?.resolvedAccountId)
        // Final fallback: backend resolves account from deployment + tenant context.
        result.append(nil)
        return result
    }
}

private struct EmptyBody: Encodable {}
