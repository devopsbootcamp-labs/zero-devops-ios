import Foundation

// MARK: - CloudAccount

struct CloudAccount: Codable, Identifiable, Hashable {
    // field name aliases — mirrors Android resolvedScopeId / resolvedAccountId
    let id:               String?
    let cloudAccountId:   String?
    let accountId:        String?
    let externalAccountId: String?
    let cloudAccountName: String?
    let displayName:      String?
    let name:             String?
    let provider:         String?
    let cloudProvider:    String?
    let region:           String?
    let defaultRegion:    String?
    let status:           String?
    let tenantId:         String?

    private func normalizedIdentifier(_ candidates: [String?]) -> String? {
        candidates.first { candidate in
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return false
            }
            if value.caseInsensitiveCompare("unknown") == .orderedSame { return false }
            if value.lowercased().hasSuffix(":unknown") { return false }
            return true
        }?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var requestScopeId: String? {
        normalizedIdentifier([cloudAccountId, id, accountId, externalAccountId])
    }

    var requestAccountId: String? {
        normalizedIdentifier([accountId, externalAccountId, cloudAccountId, id])
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
        region ?? defaultRegion ?? ""
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
    let deploymentId: String
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
