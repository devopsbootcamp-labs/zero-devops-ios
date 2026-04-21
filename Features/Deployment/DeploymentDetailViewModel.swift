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
        do {
            let _: EmptyResponse = try await api.post(
                "api/v1/drift/jobs",
                body: DriftJobRequest(deploymentId: deploymentId)
            )
            actionResult = "Drift check queued."
        } catch {
            actionResult = error.localizedDescription
        }
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

    private func fetchDeployment(id: String) async throws -> Deployment {
        try await api.get("api/v1/deployments/\(id)")
    }
    private func fetchPlan(id: String) async throws -> DeploymentPlan {
        try await api.get("api/v1/deployments/\(id)/plan")
    }
    private func fetchLogs(id: String) async throws -> [DeploymentLog] {
        try await api.get("api/v1/deployments/\(id)/logs")
    }
}

private struct EmptyBody: Encodable {}
