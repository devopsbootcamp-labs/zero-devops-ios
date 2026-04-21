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

    func load() async {
        isLoading = true
        error     = nil

        async let ov   = tryGet(AnalyticsOverview.self,    path: "api/v1/analytics/overview?range=\(range)")
        async let perf = tryGet(AnalyticsPerformance.self, path: "api/v1/analytics/performance?range=\(range)")
        async let tr   = tryGetList(AnalyticsTrend.self,   path: "api/v1/analytics/trends?range=\(range)")
        async let prov = tryGetList(AnalyticsProvider.self, path: "api/v1/analytics/providers?range=\(range)")
        async let bp   = tryGetList(AnalyticsBlueprint.self, path: "api/v1/analytics/blueprints?range=\(range)")
        async let fail = tryGetList(AnalyticsFailure.self,  path: "api/v1/analytics/failures?range=\(range)")
        async let act  = tryGetList(AnalyticsActivity.self, path: "api/v1/analytics/activity?limit=15")
        async let ins  = tryGetList(AnalyticsInsight.self,  path: "api/v1/analytics/insights")
        async let intl = tryGet(AnalyticsIntelligence.self, path: "api/v1/analytics/intelligence?range=\(range)")
        async let acc  = loadAccounts()

        overview     = await ov
        performance  = await perf
        trends       = await tr
        providers    = await prov
        self.blueprints = await bp
        failures     = await fail
        activity     = await act
        insights     = await ins
        intelligence = await intl
        accounts     = await acc
        isLoading    = false
    }

    private func tryGet<T: Decodable>(_ type: T.Type, path: String) async -> T? {
        try? await api.get(path)
    }
    private func tryGetList<T: Decodable & Identifiable>(_ type: T.Type, path: String) async -> [T] {
        (try? await api.get(path)) ?? []
    }
    private func loadAccounts() async -> [CloudAccount] {
        if let list: [CloudAccount] = try? await api.get("api/v1/accounts") { return list }
        if let resp: CloudAccountsResponse = try? await api.get("api/v1/cloud/accounts") { return resp.resolved }
        return []
    }
}
