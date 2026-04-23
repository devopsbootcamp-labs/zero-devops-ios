import Foundation

@MainActor
final class AnalyticsViewModel: ObservableObject {

    @Published var overview:      AnalyticsOverview?
    @Published var performance:   AnalyticsPerformance?
    @Published var trends:        [AnalyticsTrend]     = []
    @Published var providers:     [AnalyticsProvider]  = []
    @Published var blueprints:    [AnalyticsBlueprint] = []
    @Published var failures:      [AnalyticsFailure]   = []
    @Published var activity:      [AnalyticsActivity]  = []
    @Published var insights:      [AnalyticsInsight]   = []
    @Published var intelligence:  AnalyticsIntelligence?
    @Published var accounts:      [CloudAccount]       = []
    @Published var range          = "30d"
    @Published var isLoading      = false
    @Published var error:         String?

    private let api = APIClient.shared

    func load(accountId: String? = nil) async {
        isLoading = true
        error     = nil

        // Build optional account scope suffix for query strings.
        let scopeParam: String = {
            guard let id = accountId,
                  let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            else { return "" }
            return "&account_id=\(enc)"
        }()
        let insightsQuery = scopeParam.isEmpty ? "" : "?account_id=\(accountId!.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? accountId!)"

        async let ov   = tryGet(AnalyticsOverview.self,    path: "api/v1/analytics/overview?range=\(range)\(scopeParam)")
        async let perf = tryGet(AnalyticsPerformance.self, path: "api/v1/analytics/performance?range=\(range)\(scopeParam)")
        async let tr   = tryGetList(AnalyticsTrend.self,   path: "api/v1/analytics/trends?range=\(range)\(scopeParam)")
        async let prov = tryGetList(AnalyticsProvider.self, path: "api/v1/analytics/providers?range=\(range)\(scopeParam)")
        async let bp   = tryGetList(AnalyticsBlueprint.self, path: "api/v1/analytics/blueprints?range=\(range)\(scopeParam)")
        async let fail = tryGetList(AnalyticsFailure.self,  path: "api/v1/analytics/failures?range=\(range)\(scopeParam)")
        async let act  = tryGetList(AnalyticsActivity.self, path: "api/v1/analytics/activity?limit=15\(scopeParam)")
        async let ins  = tryGetList(AnalyticsInsight.self,  path: "api/v1/analytics/insights\(insightsQuery)")
        async let intl = tryGet(AnalyticsIntelligence.self, path: "api/v1/analytics/intelligence?range=\(range)\(scopeParam)")
        async let acc  = loadAccounts()

        let overviewValue = await ov
        let performanceValue = await perf
        let trendValues = await tr
        let providerValues = await prov
        let blueprintValues = await bp
        let failureValues = await fail
        let activityValues = await act
        let insightValues = await ins
        let intelligenceValue = await intl
        let accountValues = await acc

        overview     = overviewValue
        performance  = performanceValue ?? derivePerformance(overviewValue)
        trends       = trendValues.isEmpty ? deriveTrends(overviewValue) : trendValues
        providers    = providerValues
        self.blueprints = blueprintValues
        failures     = failureValues
        activity     = activityValues
        insights     = insightValues
        intelligence = intelligenceValue
        accounts     = accountValues

        if overviewValue == nil && providerValues.isEmpty && trendValues.isEmpty {
            error = "Unable to load analytics from API endpoints."
        }
        isLoading    = false
    }

    private func tryGet<T: Decodable>(_ type: T.Type, path: String) async -> T? {
        try? await api.get(path)
    }
    private func tryGetList<T: Decodable & Identifiable>(_ type: T.Type, path: String) async -> [T] {
        if let list: [T] = try? await api.get(path) { return list }
        if let wrapped: ListResponse<T> = try? await api.get(path) { return wrapped.resolved }
        return []
    }
    private func loadAccounts() async -> [CloudAccount] {
        await api.discoverCloudAccounts()
    }

    private func deriveTrends(_ overview: AnalyticsOverview?) -> [AnalyticsTrend] {
        guard let dailyTrend = overview?.dailyTrend, !dailyTrend.isEmpty else { return [] }
        return dailyTrend.compactMap { point in
            let date = point.resolvedDay
            guard !date.isEmpty else { return nil }
            return AnalyticsTrend(
                date: date,
                deployments: point.total,
                successes: point.succeeded,
                failures: point.failed
            )
        }
    }

    private func derivePerformance(_ overview: AnalyticsOverview?) -> AnalyticsPerformance? {
        guard let overview else { return nil }
        let frequency = overview.deployFrequency ?? overview.periodComparison?.deploymentFreq?.current
        let success = overview.successRate ?? overview.periodComparison?.successRate?.current
        return AnalyticsPerformance(
            deploymentFrequency: frequency,
            leadTimeSeconds: overview.resolvedAvgDuration(),
            mttrSeconds: nil,
            changeFailureRate: success.map { 1.0 - min(max($0, 0.0), 1.0) },
            successRate: success
        )
    }
}
