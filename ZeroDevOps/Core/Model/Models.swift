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

    var resolvedScopeId: String {
        cloudAccountId ?? id ?? accountId ?? externalAccountId ?? UUID().uuidString
    }
    var resolvedAccountId: String {
        accountId ?? cloudAccountId ?? id ?? externalAccountId ?? UUID().uuidString
    }
    var resolvedName: String {
        cloudAccountName ?? displayName ?? name ?? resolvedScopeId
    }
    var resolvedProvider: String {
        provider ?? cloudProvider ?? "Unknown"
    }
    var resolvedRegion: String {
        region ?? defaultRegion ?? ""
    }

    // Identifiable conformance
    var stableId: String { resolvedScopeId }
    // Hashable / Equatable by scope ID
    func hash(into hasher: inout Hasher) { hasher.combine(resolvedScopeId) }
    static func == (l: Self, r: Self) -> Bool { l.resolvedScopeId == r.resolvedScopeId }
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

    var resolvedName: String { name ?? displayName ?? id }
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
    let totalDeploymentsChecked: Int?
    let driftedCount:            Int?
    let cleanCount:              Int?
    let totalAffectedResources:  Int?
    let lastCheckedAt:           Date?
    let healthStatus:            String?

    var healthLabel: String {
        healthStatus?.capitalized ?? (driftedCount == 0 ? "Clean" : "Drifted")
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
    let succeeded:                 Int?
    let failed:                    Int?
    let driftIssues:               Int?
    let successRate:               Double?
    let avgDuration:               Double?
    let p95Duration:               Double?
    let monthlyCostEstimateSum:    Double?
    let activeResources:           Int?
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

struct ListResponse<T: Codable>: Codable {
    let data:    [T]?
    let items:   [T]?
    let results: [T]?

    var resolved: [T] { data ?? items ?? results ?? [] }
}
