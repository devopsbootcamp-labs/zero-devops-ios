import Foundation

@MainActor
final class DriftViewModel: ObservableObject {

    @Published var posture:       DriftPosture?
    @Published var items:         [DriftDeployment] = []
    @Published var nameMap:       [String: String]  = [:]
    @Published var isLoading      = false
    @Published var error:         String?
    @Published var triggerResult: String?

    /// Maps deploymentId → cloudAccountId so drift jobs carry the right credential scope.
    private var accountMap: [String: String] = [:]
    private let api = APIClient.shared

    private func isIgnorableDriftError(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("rbac")
            || text.contains("forbidden")
            || text.contains("403")
            || text.contains("missing deployments.read")
            || text.contains("decode error")
            || text.contains("correct format")
            || text.contains("cancelled")
            || text == "cancel"
    }

    func load(accountId: String?) async {
        isLoading = true
        error     = nil

        async let p  = fetchPosture(accountId: accountId)
        async let d  = fetchDriftDeployments(accountId: accountId)
        async let deps = fetchDeployments(accountId: accountId)
        async let accounts = api.discoverCloudAccountsDetailed()

        var failures: [String] = []

        do {
            posture = try await p
        } catch {
            posture = nil
            if !isIgnorableDriftError(error) {
                failures.append("posture: \(error.localizedDescription)")
            }
        }
        let driftResult: Result<[DriftDeployment], Error>
        do { driftResult = .success(try await d) } catch { driftResult = .failure(error) }
        let depsResult: Result<[Deployment], Error>
        do { depsResult = .success(try await deps) } catch { depsResult = .failure(error) }
        let discoveredAccounts = await accounts.accounts

        let deploymentList = (try? depsResult.get()) ?? []
        nameMap    = Dictionary(uniqueKeysWithValues: deploymentList.map { ($0.id, $0.resolvedName) })
        // Build deployment -> canonical account scope map so drift jobs carry the
        // exact cloud account identifier expected by the backend credential resolver.
        accountMap = deploymentList.reduce(into: [:]) { map, dep in
            if let aid = resolveScopeAccountId(for: dep, accounts: discoveredAccounts, scopeAccountId: accountId) {
                map[dep.id] = aid
            }
        }

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

        if case .failure(let e) = driftResult, deploymentList.isEmpty, !isIgnorableDriftError(e) {
            failures.append("drift deployments unavailable: \(e.localizedDescription)")
        }
        if case .failure(let e) = depsResult, !isIgnorableDriftError(e) {
            failures.append("deployment name map: \(e.localizedDescription)")
        }

        if Task.isCancelled {
            isLoading = false
            return
        }

        if !failures.isEmpty {
            error = "Drift fetch failures:\n" + failures.joined(separator: "\n")
        }
        isLoading = false
    }

    /// Trigger a drift check.  Pass `scopeAccountId` from the container's
    /// selectedAccountId so tenant-scope and account-scope runs both work.
    func triggerCheck(deploymentId: String, scopeAccountId: String? = nil) async {
        // Prefer deployment-specific account, fall back to view scope, then omit.
        let cloudAccountId = accountMap[deploymentId]
            ?? scopeAccountId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
        do {
            let _: EmptyResponse = try await api.post(
                "api/v1/drift/jobs",
                body: DriftJobRequest(deploymentId: deploymentId, cloudAccountId: cloudAccountId)
            )
            triggerResult = "Drift check queued for \(nameMap[deploymentId] ?? deploymentId)."
        } catch {
            triggerResult = "Drift check failed: \(error.localizedDescription)"
        }
    }

    func runAllChecks(scopeAccountId: String? = nil) async {
        for item in items {
            await triggerCheck(deploymentId: item.deploymentId, scopeAccountId: scopeAccountId)
        }
    }

    private func fetchPosture(accountId: String?) async throws -> DriftPosture {
        if let aid = accountId, let query = APIClient.buildQueryString(["cloud_account_id": aid]) {
            return try await api.get("api/v1/drift/posture?\(query)")
        }
        return try await api.get("api/v1/drift/posture")
    }

    private func fetchDriftDeployments(accountId: String?) async throws -> [DriftDeployment] {
        let base = "api/v1/drift/deployments?limit=100"
        if let aid = accountId, let query = APIClient.buildQueryString(["cloud_account_id": aid]) {
            let scopedPath = "\(base)&\(query)"
            if let list: [DriftDeployment] = try? await api.get(scopedPath) { return list }
            if let wrapped: DriftDeploymentsResponse = try? await api.get(scopedPath) { return wrapped.resolved }
        }
        if let list: [DriftDeployment] = try? await api.get(base) { return list }
        if let wrapped: DriftDeploymentsResponse = try? await api.get(base) { return wrapped.resolved }
        // Keep Drift UI usable with deployment fallback when this endpoint is unavailable.
        return []
    }

    private func fetchDeployments(accountId: String?) async throws -> [Deployment] {
        try await api.fetchDeploymentsScoped(accountId: accountId, limit: 500)
    }

    private func resolveScopeAccountId(for deployment: Deployment, accounts: [CloudAccount], scopeAccountId: String?) -> String? {
        let deploymentProvider = normalizeIdentifier(deployment.cloudProvider)
        let deploymentCandidates = Set([
            deployment.cloudAccountId,
            deployment.accountId,
            deployment.resolvedAccountId,
            deployment.params?["cloud_account_id"],
            deployment.params?["account_id"],
            deployment.params?["cloudAccountId"],
            deployment.params?["accountId"],
        ].compactMap(normalizeIdentifier).map { $0.lowercased() })

        let matchedAccount = accounts.first { account in
            let accountProvider = normalizeIdentifier(account.provider ?? account.cloudProvider)
            if let deploymentProvider, let accountProvider, deploymentProvider.lowercased() != accountProvider.lowercased() {
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

        return matchedAccount?.requestScopeId
            ?? normalizeIdentifier(deployment.cloudAccountId)
            ?? normalizeIdentifier(deployment.accountId)
            ?? normalizeIdentifier(deployment.resolvedAccountId)
            ?? normalizeIdentifier(scopeAccountId)
    }

    private func normalizeIdentifier(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
    }
}
