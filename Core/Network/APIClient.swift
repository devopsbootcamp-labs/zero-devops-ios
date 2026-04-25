import Foundation

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingFailed(Error)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg): return msg.isEmpty ? "HTTP \(code)" : msg
        case .decodingFailed(let e):        return "Decode error: \(e.localizedDescription)"
        case .invalidResponse:              return "Invalid server response"
        case .notAuthenticated:             return "Not authenticated"
        }
    }
}

// MARK: - Envelope wrappers (mirrors Android response fallback parsing)

private struct Envelope<T: Decodable>: Decodable {
    let data:          T?
    let results:       T?
    let items:         T?
    let accounts:      T?
    let cloudAccounts: T?
    let deployments:   T?
    let resources:     T?
    let providers:     T?
    let trends:        T?
    let activity:      T?
    let insights:      T?
    let failures:      T?
    let blueprints:    T?
    let notifications: T?
    let alerts:        T?
}

// MARK: - APIClient

/// URLSession-based HTTP client — mirrors Android Retrofit + AuthInterceptor.
final class APIClient {

    static let shared = APIClient()

    private let baseURL = URL(string: AppConfig.apiBaseURL)!
    private let sessionManager = AuthSessionManager.shared

    private struct TenantIdentity: Decodable {
        let id: String
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy  = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let raw = try dec.singleValueContainer().decode(String.self)
            let fmts = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
            ]
            let fmt = DateFormatter()
            for f in fmts {
                fmt.dateFormat = f
                if let date = fmt.date(from: raw) { return date }
            }
            return Date()
        }
        return d
    }()

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private let networkDeadlineNanos: UInt64 = 12_000_000_000

    private func dataWithTimeout(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await self.urlSession.data(for: request) }
            group.addTask {
                try await Task.sleep(nanoseconds: self.networkDeadlineNanos)
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else {
                throw URLError(.unknown)
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - HTTP verbs

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await perform(method: "GET", path: path, body: Optional<EmptyBody>.none)
    }

    func getJSON(_ path: String) async throws -> Any {
        let first = try buildRequest(method: "GET", path: path, body: Optional<EmptyBody>.none, useFreshToken: false)
        let (data, response) = try await dataWithTimeout(for: first)

        do {
            try validate(response: response, data: data)
            return try JSONSerialization.jsonObject(with: data)
        } catch APIError.httpError(let statusCode, let message)
            where statusCode == 401 || (statusCode == 403 && isCloudReadDeniedMessage(message)) {
            _ = try await sessionManager.refreshAccessToken()
            let retry = try buildRequest(method: "GET", path: path, body: Optional<EmptyBody>.none, useFreshToken: true)
            let (retryData, retryResponse) = try await dataWithTimeout(for: retry)
            try validate(response: retryResponse, data: retryData)
            return try JSONSerialization.jsonObject(with: retryData)
        }
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        try await perform(method: "POST", path: path, body: body)
    }

    func put<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        try await perform(method: "PUT", path: path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await perform(method: "DELETE", path: path, body: Optional<EmptyBody>.none)
    }

    struct CloudAccountDiscoveryResult {
        let accounts: [CloudAccount]
        let diagnostics: [String]
    }

    func discoverCloudAccounts() async -> [CloudAccount] {
        await discoverCloudAccountsDetailed().accounts
    }

    func discoverCloudAccountsDetailed() async -> CloudAccountDiscoveryResult {
        var diagnostics: [String] = []

        // Preflight: ensure tenant context is populated so x-tenant-id is attached.
        // Without a tenant header the backend may return 403 or an empty list.
        await ensureTenantContextPreflight(diagnostics: &diagnostics)

        // Ordered attempt: wrapped decode → direct array → raw JSON parse.
        // Only use dedicated cloud-account endpoints — never parse deployment/resource
        // payloads as accounts (that creates fake rows with deployment names).
        let accountPaths = [
            "api/v1/cloud/accounts",  // primary — matches Android ZeroDevOpsApi order
            "api/v1/accounts",
            "api/v1/cloud-accounts",
        ]
        var attemptedRefresh = false
        for attempt in 0..<2 {
            for path in accountPaths {
                do {
                    let wrapped: CloudAccountsResponse = try await get(path)
                    let resolved = deduplicateAccounts(wrapped.resolved)
                    diagnostics.append("\(path) wrapped: \(resolved.count)")
                    if !resolved.isEmpty {
                        return CloudAccountDiscoveryResult(accounts: resolved, diagnostics: diagnostics)
                    }
                } catch {
                    diagnostics.append("\(path) wrapped failed: \(error.localizedDescription)")
                    if !attemptedRefresh && isCloudReadDenied(error) {
                        do {
                            _ = try await sessionManager.refreshAccessToken()
                            attemptedRefresh = true
                            diagnostics.append("token refresh: success (retrying account endpoints)")
                            break
                        } catch {
                            attemptedRefresh = true
                            diagnostics.append("token refresh failed: \(error.localizedDescription)")
                        }
                    }
                }

                do {
                    let list: [CloudAccount] = try await get(path)
                    let resolved = deduplicateAccounts(list)
                    diagnostics.append("\(path) direct: \(resolved.count)")
                    if !resolved.isEmpty {
                        return CloudAccountDiscoveryResult(accounts: resolved, diagnostics: diagnostics)
                    }
                } catch {
                    diagnostics.append("\(path) direct failed: \(error.localizedDescription)")
                }

                do {
                    let raw = try await getJSON(path)
                    let parsed = deduplicateAccounts(parseAccounts(from: raw, requireExplicitAccountKey: false))
                    diagnostics.append("\(path) raw: \(parsed.count)")
                    if !parsed.isEmpty {
                        return CloudAccountDiscoveryResult(accounts: parsed, diagnostics: diagnostics)
                    }
                } catch {
                    diagnostics.append("\(path) raw failed: \(error.localizedDescription)")
                }
            }

            // If no refresh was done on attempt 0, the second pass would produce the
            // same failures — skip it and proceed to the profile/inventory fallbacks.
            if attempt == 0 && !attemptedRefresh {
                break
            }
        }

        // Parse profile payloads for explicit account claim objects when account APIs are RBAC denied.
        for path in ["api/v1/auth/me", "api/v1/users/me", "api/v1/me"] {
            if let raw = try? await getJSON(path) {
                let parsed = deduplicateAccounts(parseAccounts(from: raw, requireExplicitAccountKey: true))
                diagnostics.append("\(path) account-claims: \(parsed.count)")
                if !parsed.isEmpty {
                    return CloudAccountDiscoveryResult(accounts: parsed, diagnostics: diagnostics)
                }
            }
        }

        // Inventory/resource/analytics fallbacks can provide account metadata without cloud.read.
        for path in [
            "api/v1/cloud/inventory",
            "api/v1/inventory",
            "api/v1/resources",
            "api/v1/analytics/deployments?limit=200&range=365",
        ] {
            if let raw = try? await getJSON(path) {
                let parsed = deduplicateAccounts(parseAccounts(from: raw, requireExplicitAccountKey: true))
                diagnostics.append("\(path) account-like: \(parsed.count)")
                if !parsed.isEmpty {
                    return CloudAccountDiscoveryResult(accounts: parsed, diagnostics: diagnostics)
                }
            }
        }

        // Final fallback: group tenant-wide deployments by their cloudAccountId to
        // surface accounts that exist but whose account endpoint is unavailable.
        // Use direct tenant deployment endpoints here to avoid recursive fallback loops
        // with fetchDeploymentsScoped(accountId: nil).
        do {
            let tenantPaths = [
                "api/v1/deployments?limit=500",
                "api/v1/deployments",
            ]
            var tenantDeployments: [Deployment] = []
            var tenantError: Error?
            for path in tenantPaths {
                do {
                    tenantDeployments = try await fetchDeploymentList(path: path)
                    if !tenantDeployments.isEmpty {
                        break
                    }
                } catch {
                    tenantError = error
                }
            }

            let derived = deduplicateAccounts(deriveAccounts(from: tenantDeployments))
            diagnostics.append("deployments-derived: \(derived.count)")
            if !derived.isEmpty {
                return CloudAccountDiscoveryResult(accounts: derived, diagnostics: diagnostics)
            }
            if tenantDeployments.isEmpty, let tenantError {
                diagnostics.append("deployments-derived failed: \(tenantError.localizedDescription)")
            }
        }

        return CloudAccountDiscoveryResult(accounts: [], diagnostics: diagnostics)
    }

    private func isCloudReadDenied(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return isCloudReadDeniedMessage(text)
    }

    private func isCloudReadDeniedMessage(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("cloud.read")
            || text.contains("rbac")
            || text.contains("access denied")
            || text.contains("resource_access")
            || text.contains("forbidden")
            || text.contains("http 403")
    }

    private func ensureTenantContextPreflight(diagnostics: inout [String]) async {
        if let currentTenant = sessionManager.currentTenantId()?.trimmingCharacters(in: .whitespacesAndNewlines), !currentTenant.isEmpty {
            diagnostics.append("tenant: already set")
            return
        }
        let profilePaths = ["api/v1/auth/me", "api/v1/auth/userinfo", "api/v1/users/me", "api/v1/auth/profile", "api/v1/me"]
        for path in profilePaths {
            if let profile: UserProfile = try? await get(path) {
                let tid = profile.tenantId?.trimmingCharacters(in: .whitespacesAndNewlines)
                let aid = (profile.cloudAccountId ?? profile.accountId)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let tid, !tid.isEmpty {
                    sessionManager.updateRequestContext(tenantId: tid, accountId: aid?.isEmpty == false ? aid : sessionManager.currentAccountId())
                    diagnostics.append("tenant from \(path): \(tid)")
                    return
                }
            }
        }

        // Fallback: many environments infer tenant from JWT subject/email at this endpoint
        // even when profile payload doesn't include tenantId.
        if let tenants: [TenantIdentity] = try? await get("api/v1/tenants"),
           let tid = tenants.first?.id.trimmingCharacters(in: .whitespacesAndNewlines),
           !tid.isEmpty {
            sessionManager.updateRequestContext(tenantId: tid, accountId: sessionManager.currentAccountId())
            diagnostics.append("tenant from api/v1/tenants: \(tid)")
        }
    }

    /// Mirrors web deployments list behavior: use canonical /api/v1/deployments with
    /// optional cloud_account_id/account_id query filters.
    func fetchDeploymentsScoped(accountId: String?, limit: Int = 500) async throws -> [Deployment] {
        // Self-heal request context before deployment reads in case app-level preflight
        // timed out or resumed from a stale background state.
        var preflightDiagnostics: [String] = []
        await ensureTenantContextPreflight(diagnostics: &preflightDiagnostics)

        let scoped = accountId.flatMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var lastError: Error?
        if let scoped {
            let candidateIds = await resolveAccountScopeCandidates(scoped)
            for candidateId in candidateIds {
                guard let encodedId = Self.percentEncode(candidateId) else { continue }
                let scopedPaths = [
                    "api/v1/deployments?limit=\(limit)&cloud_account_id=\(encodedId)&account_id=\(encodedId)",
                    "api/v1/deployments?cloud_account_id=\(encodedId)&account_id=\(encodedId)&limit=\(limit)",
                    "api/v1/deployments?limit=\(limit)&cloud_account_id=\(encodedId)",
                    "api/v1/deployments?cloud_account_id=\(encodedId)&limit=\(limit)",
                ]
                for path in scopedPaths {
                    do {
                        let list = try await fetchDeploymentList(path: path)
                        if !list.isEmpty {
                            return deduplicateAndSortDeployments(list)
                        }
                    } catch {
                        lastError = error
                    }
                }
            }
            return []
        }

        let tenantPaths = [
            "api/v1/deployments?limit=\(limit)",
            "api/v1/deployments",
        ]
        for path in tenantPaths {
            do {
                let list = try await fetchDeploymentList(path: path)
                if !list.isEmpty {
                    return deduplicateAndSortDeployments(list)
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    private func resolveAccountScopeCandidates(_ scoped: String) async -> [String] {
        let normalizedScoped = scoped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedScoped.isEmpty else { return [] }

        var ordered: [String] = []
        var seen = Set<String>()
        func appendUnique(_ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            let key = value.lowercased()
            guard seen.insert(key).inserted else { return }
            ordered.append(value)
        }

        appendUnique(normalizedScoped)

        let accounts = await discoverCloudAccountsDetailed().accounts
        let scopedKey = normalizedScoped.lowercased()
        for account in accounts {
            let identifiers = [
                account.requestScopeId,
                account.cloudAccountId,
                account.id,
                account.accountIdentifier,
                account.accountId,
                account.externalAccountId,
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            let hasMatch = identifiers.contains { $0.lowercased() == scopedKey }
            if hasMatch {
                appendUnique(account.requestScopeId)
                appendUnique(account.cloudAccountId)
                appendUnique(account.id)
                appendUnique(account.accountIdentifier)
                appendUnique(account.accountId)
                appendUnique(account.externalAccountId)
            }
        }

        return ordered
    }

    private func deduplicateAndSortDeployments(_ list: [Deployment]) -> [Deployment] {
        var byId: [String: Deployment] = [:]
        for deployment in list {
            if let existing = byId[deployment.id] {
                if deploymentSortDate(for: deployment) > deploymentSortDate(for: existing) {
                    byId[deployment.id] = deployment
                }
            } else {
                byId[deployment.id] = deployment
            }
        }

        return byId.values.sorted {
            let lhs = deploymentSortDate(for: $0)
            let rhs = deploymentSortDate(for: $1)
            if lhs == rhs { return $0.id < $1.id }
            return lhs > rhs
        }
    }

    private func deploymentSortDate(for deployment: Deployment) -> Date {
        deployment.createdAt ?? deployment.updatedAt ?? Date.distantPast
    }

    func fetchResourcesList() async throws -> [Resource] {
        if let list: [Resource] = try? await get("api/v1/resources") { return list }
        if let wrapped: ListResponse<Resource> = try? await get("api/v1/resources") { return wrapped.resolved }
        if let list: [Resource] = try? await get("api/v1/inventory") { return list }
        if let wrapped: ListResponse<Resource> = try? await get("api/v1/inventory") { return wrapped.resolved }
        return []
    }

    func fetchResourcesScoped(accountId: String?) async throws -> [Resource] {
        let scoped = accountId.flatMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var lastError: Error?
        if let scoped, let encodedId = Self.percentEncode(scoped) {
            let scopedPaths = [
                "api/v1/cloud-accounts/\(encodedId)/resources",
                "api/v1/resources?cloud_account_id=\(encodedId)",
                "api/v1/inventory?cloud_account_id=\(encodedId)"
            ]
            for path in scopedPaths {
                do {
                    return try await fetchResourceList(path: path)
                } catch {
                    lastError = error
                }
            }
        }

        let tenantPaths = [
            "api/v1/resources",
            "api/v1/inventory"
        ]
        for path in tenantPaths {
            do {
                return try await fetchResourceList(path: path)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? APIError.invalidResponse
    }
    
    /// Percent-encode path component for URL safety (RFC 3986).
    private static func percentEncode(_ component: String) -> String? {
        // Encode all except unreserved characters: A-Z a-z 0-9 - . _ ~
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return component.addingPercentEncoding(withAllowedCharacters: unreserved)
    }
    
    /// Build a query parameter string with proper encoding.
    /// Example: buildQueryString(["cloud_account_id": "acct-123", "limit": "500"])
    /// Returns: "cloud_account_id=acct-123&limit=500" (with unsafe characters encoded)
    static func buildQueryString(_ params: [String: String]) -> String? {
        let encoded = params.compactMap { key, value -> String? in
            guard let k = percentEncode(key), let v = percentEncode(value) else { return nil }
            return "\(k)=\(v)"
        }
        return encoded.isEmpty ? nil : encoded.joined(separator: "&")
    }
    
    /// Build a path segment with proper encoding for a single component.
    /// Example: encodePathComponent("acct-123/special") -> "acct-123%2Fspecial"
    static func encodePathComponent(_ component: String) -> String? {
        return percentEncode(component)
    }

    private func deduplicateAccounts(_ list: [CloudAccount]) -> [CloudAccount] {
        var seen = Set<String>()
        return list.filter {
            let key = $0.resolvedScopeId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    private func parseAccounts(from raw: Any, requireExplicitAccountKey: Bool) -> [CloudAccount] {
        if let array = raw as? [[String: Any]] {
            return array.compactMap { accountFromDictionary($0, requireExplicitAccountKey: requireExplicitAccountKey) }
        }
        if let dict = raw as? [String: Any] {
            let candidateKeys = [
                "accounts", "cloudAccounts", "cloud_accounts", "data", "items", "results",
                "resources", "inventory", "records", "deployments", "rows"
            ]
            for key in candidateKeys {
                if let nested = dict[key] {
                    let parsed = parseAccounts(from: nested, requireExplicitAccountKey: requireExplicitAccountKey)
                    if !parsed.isEmpty { return parsed }
                }
            }
            if let single = accountFromDictionary(dict, requireExplicitAccountKey: requireExplicitAccountKey) {
                return [single]
            }
        }
        return []
    }

    private func deriveAccounts(from deployments: [Deployment]) -> [CloudAccount] {
        var grouped: [String: (provider: String, region: String?, tenantId: String?, name: String?)] = [:]
        for dep in deployments {
            let account = (dep.resolvedAccountId ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
            let accountId = account.isEmpty ? "unknown" : account
            let provider = (dep.cloudProvider ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = dep.params?["cloud_account_name"]
                ?? dep.params?["account_name"]
                ?? dep.params?["cloudAccountName"]
                ?? dep.params?["accountName"]
            let key = "\(provider.lowercased()):\(accountId.lowercased())"
            if grouped[key] == nil {
                grouped[key] = (provider: provider.isEmpty ? "unknown" : provider, region: dep.region, tenantId: dep.tenantId, name: name)
            }
        }

        return grouped.map { item in
            let key = item.key
            let values = item.value
            let accountId = key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).count > 1
                ? String(key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[1])
                : "unknown"
            let normalizedAccountId = accountId == "unknown" ? nil : accountId

            return CloudAccount(
                id: key,
                cloudAccountId: normalizedAccountId,
                accountId: normalizedAccountId,
                accountIdentifier: normalizedAccountId,
                externalAccountId: nil,
                cloudAccountName: values.name ?? normalizedAccountId ?? "\(values.provider.uppercased()) (derived)",
                displayName: values.name ?? normalizedAccountId ?? "\(values.provider.uppercased()) (derived)",
                name: values.name ?? normalizedAccountId,
                provider: values.provider,
                cloudProvider: values.provider,
                region: values.region,
                defaultRegion: values.region,
                regionDefault: values.region,
                status: "derived",
                tenantId: values.tenantId
            )
        }
    }

    private func accountFromDictionary(_ dict: [String: Any], requireExplicitAccountKey: Bool) -> CloudAccount? {
        func stringValue(_ keys: [String]) -> String? {
            for key in keys {
                if let value = dict[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
                if let value = dict[key] as? Int { return String(value) }
                if let value = dict[key] as? Double {
                    return value.rounded(.towardZero) == value ? String(Int(value)) : String(value)
                }
                if let value = dict[key] as? Bool { return value ? "true" : "false" }
            }
            return nil
        }

        let id = stringValue(["id"])
        let cloudAccountId = stringValue(["cloudAccountId", "cloud_account_id"])
        let accountIdentifier = stringValue(["accountIdentifier", "account_identifier"])
        let accountId = stringValue([
            "accountId", "account_id", "x_account_id", "subscriptionId", "subscription_id",
            "projectId", "project_id", "awsAccountId", "aws_account_id", "tenantAccountId", "tenant_account_id"
        ])
        let externalAccountId = stringValue(["externalAccountId", "external_account_id"])
        let cloudAccountName = stringValue(["cloudAccountName", "cloud_account_name"])
        let displayName = stringValue(["displayName", "display_name"])
        let name = stringValue(["name"])
        let provider = stringValue(["provider"])
        let cloudProvider = stringValue(["cloudProvider", "cloud_provider"])
        let region = stringValue(["region"])
        let defaultRegion = stringValue(["defaultRegion", "default_region"])
        let regionDefault = stringValue(["regionDefault", "region_default"])
        let status = stringValue(["status"])
        let tenantId = stringValue(["tenantId", "tenant_id"])

        if requireExplicitAccountKey {
            let explicitKeys = [
                "cloudAccountId", "cloud_account_id", "accountIdentifier", "account_identifier", "accountId", "account_id", "externalAccountId",
                "external_account_id", "x_account_id", "subscriptionId", "subscription_id", "projectId",
                "project_id", "awsAccountId", "aws_account_id", "tenantAccountId", "tenant_account_id"
            ]
            let hasExplicit = explicitKeys.contains { key in
                if let value = dict[key] as? String {
                    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return dict[key] != nil
            }
            if !hasExplicit { return nil }
        }

        let stable = cloudAccountId ?? accountIdentifier ?? accountId ?? externalAccountId ?? id ?? name
        guard stable != nil else { return nil }

        return CloudAccount(
            id: id,
            cloudAccountId: cloudAccountId,
            accountId: accountId,
            accountIdentifier: accountIdentifier,
            externalAccountId: externalAccountId,
            cloudAccountName: cloudAccountName,
            displayName: displayName,
            name: name,
            provider: provider,
            cloudProvider: cloudProvider,
            region: region,
            defaultRegion: defaultRegion,
            regionDefault: regionDefault,
            status: status,
            tenantId: tenantId
        )
    }

    private func fetchDeploymentList(path: String) async throws -> [Deployment] {
        if let list: [Deployment] = try? await get(path) { return list }
        if let wrapped: DeploymentListResponse = try? await get(path) { return wrapped.resolved }
        if let generic: ListResponse<Deployment> = try? await get(path) { return generic.resolved }
        if let raw = try? await getJSON(path) {
            let parsed = parseDeployments(from: raw)
            if !parsed.isEmpty { return parsed }
        }
        throw APIError.invalidResponse
    }

    private func fetchResourceList(path: String) async throws -> [Resource] {
        if let list: [Resource] = try? await get(path) { return list }
        if let wrapped: ListResponse<Resource> = try? await get(path) { return wrapped.resolved }
        throw APIError.invalidResponse
    }

    private func parseDeployments(from raw: Any) -> [Deployment] {
        if let array = raw as? [[String: Any]] {
            return array.compactMap(deploymentFromDictionary)
        }
        if let dict = raw as? [String: Any] {
            for key in ["deployments", "data", "items", "results", "rows"] {
                if let nested = dict[key] {
                    let parsed = parseDeployments(from: nested)
                    if !parsed.isEmpty { return parsed }
                }
            }
            if let one = deploymentFromDictionary(dict) { return [one] }
        }
        return []
    }

    private func deploymentFromDictionary(_ dict: [String: Any]) -> Deployment? {
        func stringValue(_ keys: [String]) -> String? {
            for key in keys {
                if let value = dict[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
                if let value = dict[key] as? Int { return String(value) }
                if let value = dict[key] as? Double {
                    return value.rounded(.towardZero) == value ? String(Int(value)) : String(value)
                }
                if let value = dict[key] as? Bool { return value ? "true" : "false" }
            }
            return nil
        }

        func nestedObject(_ keys: [String]) -> [String: Any]? {
            for key in keys {
                if let object = dict[key] as? [String: Any] {
                    return object
                }
            }
            return nil
        }

        func nestedString(in object: [String: Any]?, keys: [String]) -> String? {
            guard let object else { return nil }
            for key in keys {
                if let value = object[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
                if let value = object[key] as? Int { return String(value) }
                if let value = object[key] as? Double {
                    return value.rounded(.towardZero) == value ? String(Int(value)) : String(value)
                }
            }
            return nil
        }

        let nestedAccount = nestedObject(["cloudAccount", "cloud_account", "account"]) 

        let id = stringValue(["id", "deploymentId", "deployment_id", "name", "displayName"]) ?? UUID().uuidString
        let name = stringValue(["name", "deploymentName", "deployment_name", "displayName", "display_name"])
        let environment = stringValue(["environment"])
        let status = stringValue(["status"])
        let driftStatus = stringValue(["driftStatus", "drift_status"])
        let cloudProvider = stringValue(["cloudProvider", "cloud_provider", "provider"]) 
            ?? nestedString(in: nestedAccount, keys: ["provider", "cloudProvider", "cloud_provider"])
        let region = stringValue(["region"])
        let blueprintId = stringValue(["blueprintId", "blueprint_id"])
        let description = stringValue(["description"])
        let accountId = stringValue(["accountId", "account_id", "x_account_id"]) 
            ?? nestedString(in: nestedAccount, keys: ["accountId", "account_id", "id"])
        let cloudAccountId = stringValue(["cloudAccountId", "cloud_account_id"]) 
            ?? nestedString(in: nestedAccount, keys: ["cloudAccountId", "cloud_account_id", "id"])
        let tenantId = stringValue(["tenantId", "tenant_id"])

        var params: [String: String]? = nil
        if let paramDict = dict["params"] as? [String: Any] {
            params = paramDict.reduce(into: [String: String]()) { partial, item in
                let key = item.key
                let value = String(describing: item.value)
                partial[key] = value
            }
        }
        if let nestedAccount {
            var p = params ?? [:]
            if let value = nestedString(in: nestedAccount, keys: ["id"]) {
                p["cloud_account_id"] = p["cloud_account_id"] ?? value
                p["account_id"] = p["account_id"] ?? value
            }
            if let value = nestedString(in: nestedAccount, keys: ["name", "displayName", "display_name"]) {
                p["cloud_account_name"] = p["cloud_account_name"] ?? value
                p["account_name"] = p["account_name"] ?? value
            }
            if let value = nestedString(in: nestedAccount, keys: ["provider", "cloudProvider", "cloud_provider"]) {
                p["cloud_provider"] = p["cloud_provider"] ?? value
            }
            params = p
        }

        return Deployment(
            id: id,
            name: name,
            displayName: name,
            deploymentName: name,
            environment: environment,
            status: status,
            driftStatus: driftStatus,
            cloudProvider: cloudProvider,
            region: region,
            blueprintId: blueprintId,
            description: description,
            createdAt: nil,
            updatedAt: nil,
            accountId: accountId,
            cloudAccountId: cloudAccountId,
            tenantId: tenantId,
            params: params
        )
    }

    // MARK: - Core

    private func perform<B: Encodable, T: Decodable>(method: String, path: String, body: B?) async throws -> T {
        let first = try buildRequest(method: method, path: path, body: body, useFreshToken: false)
        let (data, response) = try await dataWithTimeout(for: first)

        do {
            try validate(response: response, data: data)
            return try decodeAny(data)
        } catch APIError.httpError(let statusCode, let message)
            where statusCode == 401 || (statusCode == 403 && isCloudReadDeniedMessage(message)) {
            // Mirror Android TokenRefreshAuthenticator behavior: refresh once and retry.
            _ = try await sessionManager.refreshAccessToken()
            let retry = try buildRequest(method: method, path: path, body: body, useFreshToken: true)
            let (retryData, retryResponse) = try await dataWithTimeout(for: retry)
            try validate(response: retryResponse, data: retryData)
            return try decodeAny(retryData)
        }
    }

    private func buildRequest<B: Encodable>(method: String, path: String, body: B?, useFreshToken: Bool) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let token = useFreshToken ? sessionManager.currentBundle()?.accessToken : sessionManager.currentAccessToken()
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let tid = sessionManager.currentTenantId() {
            req.setValue(tid, forHTTPHeaderField: "x-tenant-id")
        }
        // Do NOT attach x-account-id for aggregate/drift/jobs endpoints.
        if let aid = sessionManager.currentAccountId(), shouldAttachAccountHeader(path: path) {
            req.setValue(aid, forHTTPHeaderField: "x-account-id")
        }
        if let body = body, !(body is EmptyBody) {
            req.httpBody = try JSONEncoder().encode(body)
        }
        return req
    }

    private func shouldAttachAccountHeader(path: String) -> Bool {
        let pathOnly = String(path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let normalized = pathOnly.hasPrefix("/") ? pathOnly : "/\(pathOnly)"

        // Keep aggregate/list endpoints tenant-scoped to match web behavior.
        if normalized.hasPrefix("/api/v1/cloud/accounts") { return false }
        if normalized.hasPrefix("/api/v1/cloud-accounts") { return false }
        if normalized.hasPrefix("/api/v1/accounts") { return false }
        if normalized.hasPrefix("/api/v1/auth") { return false }
        if normalized.hasPrefix("/api/v1/users") { return false }
        if normalized == "/api/v1/me" { return false }
        if normalized.hasPrefix("/api/v1/tenants") { return false }
        if normalized.hasPrefix("/api/v1/analytics") { return false }
        if normalized.hasPrefix("/api/v1/chat") { return false }
        if normalized.hasPrefix("/api/v1/dashboard") { return false }
        if normalized.hasPrefix("/api/v1/cost") { return false }
        if normalized.hasPrefix("/api/v1/resources") { return false }
        if normalized.hasPrefix("/api/v1/inventory") { return false }
        if normalized.hasPrefix("/api/v1/drift/posture") { return false }
        if normalized.hasPrefix("/api/v1/drift/deployments") { return false }
        if normalized.hasPrefix("/api/v1/drift/jobs") { return false }
        if normalized.hasPrefix("/api/v1/deployments") { return false }

        // Avoid duplicate account scoping when account is already in path.
        if normalized.range(of: "^/api/v1/cloud-accounts/[^/]+/deployments$", options: .regularExpression) != nil {
            return false
        }
        if normalized.range(of: "^/api/v1/cloud-accounts/[^/]+/cost/.*$", options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = extractErrorMessage(from: data)
            throw APIError.httpError(statusCode: http.statusCode, message: msg)
        }
    }

    private func extractErrorMessage(from data: Data) -> String {
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = ["message", "error", "detail", "reason"]
            for key in keys {
                if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
            if let errors = dict["errors"] as? [String], let first = errors.first, !first.isEmpty {
                return first
            }
        }
        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw.count > 180 ? String(raw.prefix(180)) + "..." : raw
        }
        return ""
    }

    private func decodeAny<T: Decodable>(_ data: Data) throws -> T {
        // Direct decode
        if let value = try? decoder.decode(T.self, from: data) { return value }
        // Try envelope
        if let env = try? decoder.decode(Envelope<T>.self, from: data) {
            if let value = env.data { return value }
            if let value = env.results { return value }
            if let value = env.items { return value }
            if let value = env.accounts { return value }
            if let value = env.cloudAccounts { return value }
            if let value = env.deployments { return value }
            if let value = env.resources { return value }
            if let value = env.providers { return value }
            if let value = env.trends { return value }
            if let value = env.activity { return value }
            if let value = env.insights { return value }
            if let value = env.failures { return value }
            if let value = env.blueprints { return value }
            if let value = env.notifications { return value }
            if let value = env.alerts { return value }
        }
        // Empty body
        if T.self == EmptyResponse.self, let v = EmptyResponse() as? T { return v }
        throw APIError.decodingFailed(DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "No decodable content")
        ))
    }
}

// Sentinel types
private struct EmptyBody: Encodable {}
struct EmptyResponse: Decodable { init?() {} }
