import Foundation

// MARK: - Helpers

extension String {
    /// Returns nil when the string is empty after whitespace trimming.
    func nilIfEmpty() -> String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - CloudAccount

struct CloudAccount: Decodable, Identifiable, Hashable {
    // field name aliases — mirrors Android resolvedScopeId / resolvedAccountId
    let id:               String?
    let cloudAccountId:   String?
    let accountId:        String?
    let accountIdentifier: String?
    let externalAccountId: String?
    let cloudAccountName: String?
    let displayName:      String?
    let name:             String?
    let provider:         String?
    let cloudProvider:    String?
    let region:           String?
    let defaultRegion:    String?
    let regionDefault:    String?
    let status:           String?
    let tenantId:         String?

    enum CodingKeys: String, CodingKey {
        case id, cloudAccountId, accountId, externalAccountId
        case cloudAccountName, displayName, name
        case provider, cloudProvider, region, defaultRegion, status
        case tenantId, accountIdentifier, regionDefault
        case cloud_account_id, account_id, external_account_id
        case cloud_account_name, display_name, cloud_provider, default_region
        case tenant_id, account_identifier, region_default
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLossyString([.id])
        cloudAccountId = c.decodeLossyString([.cloudAccountId, .cloud_account_id])
        accountId = c.decodeLossyString([.accountId, .account_id])
        accountIdentifier = c.decodeLossyString([.accountIdentifier, .account_identifier])
        externalAccountId = c.decodeLossyString([.externalAccountId, .external_account_id])
        cloudAccountName = c.decodeLossyString([.cloudAccountName, .cloud_account_name])
        displayName = c.decodeLossyString([.displayName, .display_name])
        name = c.decodeLossyString([.name])
        provider = c.decodeLossyString([.provider])
        cloudProvider = c.decodeLossyString([.cloudProvider, .cloud_provider])
        region = c.decodeLossyString([.region])
        defaultRegion = c.decodeLossyString([.defaultRegion, .default_region])
        regionDefault = c.decodeLossyString([.regionDefault, .region_default])
        status = c.decodeLossyString([.status])
        tenantId = c.decodeLossyString([.tenantId, .tenant_id])
    }

    init(
        id: String?,
        cloudAccountId: String?,
        accountId: String?,
        accountIdentifier: String?,
        externalAccountId: String?,
        cloudAccountName: String?,
        displayName: String?,
        name: String?,
        provider: String?,
        cloudProvider: String?,
        region: String?,
        defaultRegion: String?,
        regionDefault: String?,
        status: String?,
        tenantId: String?
    ) {
        self.id = id
        self.cloudAccountId = cloudAccountId
        self.accountId = accountId
        self.accountIdentifier = accountIdentifier
        self.externalAccountId = externalAccountId
        self.cloudAccountName = cloudAccountName
        self.displayName = displayName
        self.name = name
        self.provider = provider
        self.cloudProvider = cloudProvider
        self.region = region
        self.defaultRegion = defaultRegion
        self.regionDefault = regionDefault
        self.status = status
        self.tenantId = tenantId
    }

    private func normalizedIdentifier(_ candidates: [String?]) -> String? {
        for candidate in candidates {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }
            if value.caseInsensitiveCompare("unknown") == .orderedSame { continue }
            if value.lowercased().hasSuffix(":unknown") { continue }
            return value
        }
        return nil
    }

    var requestScopeId: String? {
        // Match web routing: v1 uses cloudAccountId, v2 uses UUID id.
        normalizedIdentifier([cloudAccountId, id, accountIdentifier, accountId, externalAccountId])
    }

    var requestAccountId: String? {
        normalizedIdentifier([cloudAccountId, id, accountIdentifier, accountId, externalAccountId])
    }

    var resolvedScopeId: String {
        requestScopeId ?? stableId
    }
    var resolvedAccountId: String {
        requestAccountId ?? stableId
    }
    var resolvedName: String {
        cloudAccountName ?? displayName ?? name ?? requestAccountId ?? stableId
    }
    var resolvedProvider: String {
        provider ?? cloudProvider ?? "Unknown"
    }
    var resolvedRegion: String {
        region ?? regionDefault ?? defaultRegion ?? ""
    }

    // Identifiable conformance
    var stableId: String {
        requestScopeId
            ?? requestAccountId
            ?? normalizedIdentifier([name, displayName, cloudAccountName])
            ?? "unscoped-account"
    }
    // Hashable / Equatable by scope ID
    func hash(into hasher: inout Hasher) { hasher.combine(stableId) }
    static func == (l: Self, r: Self) -> Bool { l.stableId == r.stableId }
}

private extension KeyedDecodingContainer where Key: CodingKey {
    func decodeLossyString(_ keys: [Key]) -> String? {
        for key in keys {
            if let s = (try? decodeIfPresent(String.self, forKey: key)) ?? nil, !s.isEmpty {
                return s
            }
            if let i = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil {
                return String(i)
            }
            if let d = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil {
                return d.rounded(.towardZero) == d ? String(Int(d)) : String(d)
            }
            if let b = (try? decodeIfPresent(Bool.self, forKey: key)) ?? nil {
                return b ? "true" : "false"
            }
        }
        return nil
    }
}

struct CloudAccountsResponse: Decodable {
    let accounts:      [CloudAccount]?
    let cloudAccounts: [CloudAccount]?
    let data:          [CloudAccount]?
    let items:         [CloudAccount]?
    let results:       [CloudAccount]?

    var resolved: [CloudAccount] {
        accounts ?? cloudAccounts ?? data ?? items ?? results ?? []
    }
}

// MARK: - Deployment

struct Deployment: Codable, Identifiable {
    let id:            String
    let name:          String?
    let displayName:   String?
    let deploymentName: String?
    let environment:   String?
    let status:        String?
    let driftStatus:   String?
    let cloudProvider: String?
    let region:        String?
    let blueprintId:   String?
    let description:   String?
    let createdAt:     Date?
    let updatedAt:     Date?
    let accountId:     String?
    let cloudAccountId: String?
    let tenantId:      String?
    let params:        [String: String]?

    var resolvedAccountId: String? {
        accountId
            ?? cloudAccountId
            ?? params?["cloud_account_id"]
            ?? params?["account_id"]
    }

    var resolvedName: String {
        name
            ?? deploymentName
            ?? displayName
            ?? params?["name"]
            ?? params?["deployment_name"]
            ?? blueprintId
            ?? id
    }
}

struct DeploymentListResponse: Decodable {
    let deployments: [Deployment]?
    let data: [Deployment]?
    let items: [Deployment]?
    let results: [Deployment]?

    var resolved: [Deployment] {
        deployments ?? data ?? items ?? results ?? []
    }
}

struct DeploymentPlan: Codable {
    let status:        String?
    let summary:       String?
    let toAdd:         Int?
    let toChange:      Int?
    let toDestroy:     Int?
    let estimatedCost: Double?
}

struct DeploymentLog: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date?
    let level:     String?
    let message:   String

    enum CodingKeys: String, CodingKey {
        case timestamp, level, message
    }
}

// MARK: - Drift

struct DriftPosture: Codable {
    let health:                  String?
    let totalDeploymentsChecked: Int?
    let driftedCount:            Int?
    let cleanCount:              Int?
    let totalAffectedResources:  Int?
    let lastCheckedAt:           Date?
    let healthStatus:            String?

    var healthLabel: String {
        health?.capitalized ?? healthStatus?.capitalized ?? (driftedCount == 0 ? "Clean" : "Drifted")
    }
}

struct DriftDeployment: Codable, Identifiable {
    let deploymentId:         String
    let drifted:              Bool?
    let driftedResourcesCount: Int?
    let changesCount:         Int?
    let severity:             String?
    let lastCheckedAt:        Date?
    let jobStatus:            String?

    var id: String { deploymentId }

    var driftDisplayStatus: String {
        if let s = jobStatus { return s.capitalized }
        return (drifted == true) ? "Drifted" : "Clean"
    }
}

struct DriftJobRequest: Encodable {
    let deploymentId:    String
    let cloudAccountId:  String?
    let accountId:       String?

    /// Backend requires cloud_account_id to resolve the correct cloud-connect
    /// credentials for drift detection.  Include it in the request body whenever
    /// it is known so both account-scope and tenant-scope runs succeed.
    enum CodingKeys: String, CodingKey {
        case deploymentId   = "deployment_id"
        case cloudAccountId = "cloud_account_id"
        case accountId      = "account_id"
    }
}

struct DriftJobQueuedResponse: Decodable {
    let queued:  Bool?
    let jobId:   String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case queued
        case jobId = "job_id"
        case message
    }
}

struct DriftDeploymentsResponse: Decodable {
    let deployments: [DriftDeployment]?
    let data: [DriftDeployment]?
    let items: [DriftDeployment]?
    let results: [DriftDeployment]?

    var resolved: [DriftDeployment] {
        deployments ?? data ?? items ?? results ?? []
    }
}

// MARK: - Analytics

struct AnalyticsOverview: Codable {
    let totalDeployments:          Int?
    let deploymentsTotal:          Int?
    let deploymentCount:           Int?
    let succeeded:                 Int?
    let deploymentsSucceeded:      Int?
    let failed:                    Int?
    let deploymentsFailed:         Int?
    let driftIssues:               Int?
    let successRate:               Double?
    let deployFrequency:           Double?
    let currentActiveResources:    Int?
    let avgDuration:               Double?
    let avgDurationSeconds:        Double?
    let p95Duration:               Double?
    let p95DurationSeconds:        Double?
    let monthlyCostEstimateSum:    Double?
    let activeResources:           Int?

    struct DailyTrendPoint: Codable, Identifiable {
        let id = UUID()
        let day: String?
        let date: String?
        let total: Int?
        let succeeded: Int?
        let failed: Int?
        let avgDuration: Double?

        enum CodingKeys: String, CodingKey {
            case day, date, total, succeeded, failed, avgDuration
        }

        var resolvedDay: String { day ?? date ?? "" }
    }

    struct PeriodValue: Codable {
        let current: Double?
        let previous: Double?
        let delta: Double?
        let deltaPct: Double?
    }

    struct PeriodComparison: Codable {
        let successRate: PeriodValue?
        let deploymentFreq: PeriodValue?
    }

    let dailyTrend:                [DailyTrendPoint]?
    let periodComparison:          PeriodComparison?

    func resolvedTotalDeployments() -> Int {
        totalDeployments ?? deploymentsTotal ?? deploymentCount ?? 0
    }

    func resolvedSucceeded() -> Int {
        succeeded ?? deploymentsSucceeded ?? 0
    }

    func resolvedFailed() -> Int {
        failed ?? deploymentsFailed ?? 0
    }

    func resolvedAvgDuration() -> Double {
        avgDurationSeconds ?? avgDuration ?? 0
    }

    func resolvedP95Duration() -> Double {
        p95DurationSeconds ?? p95Duration ?? 0
    }

    func resolvedActiveResources() -> Int {
        activeResources ?? currentActiveResources ?? 0
    }
}

struct AnalyticsPerformance: Codable {
    let deploymentFrequency: Double?
    let leadTimeSeconds:     Double?
    let mttrSeconds:         Double?
    let changeFailureRate:   Double?
    let successRate:         Double?
}

struct AnalyticsTrend: Codable, Identifiable {
    let id   = UUID()
    let date:        String
    let deployments: Int?
    let successes:   Int?
    let failures:    Int?
    enum CodingKeys: String, CodingKey { case date, deployments, successes, failures }
}

struct AnalyticsProvider: Codable, Identifiable {
    let id = UUID()
    let provider:        String
    let deploymentCount: Int?
    let resourceCount:   Int?
    let monthlyCost:     Double?
    enum CodingKeys: String, CodingKey { case provider, deploymentCount, resourceCount, monthlyCost }
}

struct AnalyticsBlueprint: Codable, Identifiable {
    let id = UUID()
    let blueprintName:   String
    let deploymentCount: Int?
    let successCount:    Int?
    let failureCount:    Int?
    let cloudProvider:   String?
    enum CodingKeys: String, CodingKey { case blueprintName, deploymentCount, successCount, failureCount, cloudProvider }
}

struct AnalyticsFailure: Codable, Identifiable {
    let id = UUID()
    let name:             String?
    let failureReason:    String?
    let blueprintId:      String?
    let region:           String?
    let createdAt:        Date?
    let durationSeconds:  Double?
    enum CodingKeys: String, CodingKey { case name, failureReason, blueprintId, region, createdAt, durationSeconds }
}

struct AnalyticsActivity: Codable, Identifiable {
    let id            = UUID()
    let type:         String?
    let message:      String?
    let deploymentId: String?
    let createdAt:    Date?
    enum CodingKeys: String, CodingKey { case type, message, deploymentId, createdAt }
}

struct AnalyticsInsight: Codable, Identifiable {
    let id       = UUID()
    let type:     String?
    let title:    String?
    let message:  String?
    let severity: String?
    enum CodingKeys: String, CodingKey { case type, title, message, severity }
}

struct AnalyticsIntelligence: Codable {
    let platformHealthScore:  Double?
    let riskLevel:            String?
    let driftIntelligence:    String?
    let blueprintIntelligence: String?
    let failureIntelligence:  String?
    let costIntelligence:     String?
}

// MARK: - Blueprint

struct Blueprint: Codable, Identifiable {
    let id:          String
    let name:        String?
    let description: String?
    let provider:    String?
    let version:     String?
    let category:    String?
    let tags:        [String]?

    var resolvedName: String { name ?? id }
}

struct DeploymentRequest: Encodable {
    let name:          String
    let cloudProvider: String
    let region:        String
    let blueprintId:   String
    let parameters:    [String: String]
}

// MARK: - Notifications

struct Notification: Codable, Identifiable {
    let id:         String
    let title:      String?
    let message:    String?
    let type:       String?
    let read:       Bool?
    let createdAt:  Date?
    let resourceId: String?
}

// MARK: - Resource

struct Resource: Codable, Identifiable {
    let id:           String?
    let resourceId:   String?
    let name:         String?
    let type:         String?
    let provider:     String?
    let region:       String?
    let status:       String?
    let driftStatus:  String?
    let deploymentId: String?
    let deploymentName: String?
    let tags:         [String: String]?

    var stableId: String { id ?? resourceId ?? UUID().uuidString }
}

// MARK: - Cost

struct CostSummary: Codable {
    let totalCostUsd: Double?
    let currency:     String?
    let period:       String?
}

struct CostResource: Codable, Identifiable {
    let id           = UUID()
    let resourceType: String
    let monthlyCost:  Double?
    enum CodingKeys: String, CodingKey { case resourceType, monthlyCost }
}

struct CostDeployment: Codable, Identifiable {
    let id         = UUID()
    let deploymentId:   String?
    let deploymentName: String?
    let monthlyCost:    Double?
    enum CodingKeys: String, CodingKey { case deploymentId, deploymentName, monthlyCost }
}

// MARK: - Dashboard

struct DashboardKpis: Codable {
    let deployments:  Int?
    let driftIssues:  Int?
    let monthlyCost:  Double?
    let successRate:  Double?
    let resources:    Int?
}

// MARK: - Chat

enum ChatMessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Codable, Identifiable {
    let id = UUID()
    let role: ChatMessageRole
    let text: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case role, text, createdAt
    }
}

struct ChatRequest: Encodable {
    let message: String
    let context: String?
}

struct ChatResponse: Decodable {
    let reply: String?
    let message: String?
    let content: String?

    var resolvedText: String {
        reply ?? message ?? content ?? ""
    }
}

struct ChatRoom: Decodable, Identifiable {
    let id: String
    let name: String?
}

struct ChatRoomsResponse: Decodable {
    let data: [ChatRoom]?
    let items: [ChatRoom]?
    let results: [ChatRoom]?
    let rooms: [ChatRoom]?

    var resolved: [ChatRoom] {
        rooms ?? data ?? items ?? results ?? []
    }
}

struct ChatRoomCreateRequest: Encodable {
    let name: String
}

struct ChatRoomMessageRequest: Encodable {
    let message: String
}

struct ChatRoomMessageResponse: Decodable {
    let message: String?
    let text: String?
    let content: String?
    let reply: String?
    let role: String?

    var resolvedText: String {
        reply ?? content ?? text ?? message ?? ""
    }
}

struct ChatRoomMessagesResponse: Decodable {
    let data: [ChatRoomMessageResponse]?
    let items: [ChatRoomMessageResponse]?
    let results: [ChatRoomMessageResponse]?
    let messages: [ChatRoomMessageResponse]?

    var resolved: [ChatRoomMessageResponse] {
        messages ?? data ?? items ?? results ?? []
    }
}

// MARK: - Profile / User

struct UserProfile: Codable {
    let sub:           String?
    let email:         String?
    let name:          String?
    let givenName:     String?
    let familyName:    String?
    let tenantId:      String?
    let accountId:     String?
    let cloudAccountId: String?
}

// MARK: - Generic list wrappers

struct ListResponse<T: Decodable>: Decodable {
    let data:    [T]?
    let items:   [T]?
    let results: [T]?

    var resolved: [T] { data ?? items ?? results ?? [] }
}
