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
    private var driftAfterSeq = 0

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

        // If a drift check is already in-flight, stream its execution logs when the
        // user opens this deployment (matches click-through behavior from Drift list).
        if let active = await fetchLatestDriftJob(deploymentId: deploymentId),
           let status = active.status?.lowercased(),
           status == "queued" || status == "running" || status == "pending" {
            actionResult = "Streaming drift logs for active check..."
            await streamDriftLogs(deploymentId: deploymentId, jobId: active.id)
        }
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
                let response: DriftJobQueuedResponse = try await api.post(
                    "api/v1/drift/jobs",
                    body: DriftJobRequest(deploymentId: deploymentId, cloudAccountId: candidate, accountId: candidate)
                )
                actionResult = "Drift check queued. Streaming logs..."
                isActionRunning = false
                await refreshDeploymentState(deploymentId: deploymentId)
                await streamDriftLogs(deploymentId: deploymentId, jobId: response.jobId)
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

    private func streamDriftLogs(deploymentId: String, jobId: String?) async {
        isStreaming = true
        pollCount   = 0
        driftAfterSeq = 0
        var activeJobId = jobId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
        while pollCount < 60 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if activeJobId == nil {
                activeJobId = await resolveLatestDriftJobId(deploymentId: deploymentId)
            }
            if let normalizedJobId = activeJobId,
               let chunk = try? await fetchDriftJobLogChunk(jobId: normalizedJobId, afterSeq: driftAfterSeq) {
                if !chunk.logs.isEmpty {
                    logs.append(contentsOf: chunk.logs)
                    if let next = chunk.nextAfterSeq {
                        driftAfterSeq = max(driftAfterSeq, next)
                    } else {
                        driftAfterSeq += chunk.logs.count
                    }
                }
            } else if let newLogs: [DeploymentLog] = try? await api.get("api/v1/deployments/\(deploymentId)/logs") {
                // Fallback for environments without drift job log streaming endpoint.
                logs = newLogs
            }
            await refreshDeploymentState(deploymentId: deploymentId)
            pollCount += 1
        }
        isStreaming = false
    }

    private func resolveLatestDriftJobId(deploymentId: String) async -> String? {
        guard let jobs: DriftJobsResponse = try? await api.get("api/v1/drift/jobs?deployment_id=\(deploymentId)&limit=1") else {
            return nil
        }
        return jobs.items.first?.id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
    }

    private func fetchLatestDriftJob(deploymentId: String) async -> DriftJobItem? {
        guard let jobs: DriftJobsResponse = try? await api.get("api/v1/drift/jobs?deployment_id=\(deploymentId)&limit=1") else {
            return nil
        }
        return jobs.items.first
    }

    private func fetchDriftJobLogChunk(jobId: String, afterSeq: Int) async throws -> (logs: [DeploymentLog], nextAfterSeq: Int?) {
        let path = "api/v1/drift/jobs/\(jobId)/logs?after_seq=\(afterSeq)&limit=200"
        let raw = try await api.getJSON(path)
        guard let root = raw as? [String: Any] else {
            return ([], nil)
        }

        let next = root["next_after_seq"] as? Int
        let rows = (root["logs"] as? [[String: Any]]) ?? []
        let mapped: [DeploymentLog] = rows.compactMap { row in
            guard let message = row["message"] as? String else { return nil }
            let level = (row["level"] as? String) ?? (row["stream"] as? String)
            let timestamp = Self.parseDriftLogDate(row["ts"] as? String)
            return DeploymentLog(timestamp: timestamp, level: level, message: message)
        }
        return (mapped, next)
    }

    private static func parseDriftLogDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFractional.date(from: value) {
            return parsed
        }
        let plain = ISO8601DateFormatter()
        return plain.date(from: value)
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

private struct DriftJobsResponse: Decodable {
    let items: [DriftJobItem]
}

private struct DriftJobItem: Decodable {
    let id: String?
    let status: String?
}
