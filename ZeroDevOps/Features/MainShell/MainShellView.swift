import SwiftUI

/// Main tab shell — mirrors Android MainShell with HorizontalPager (7 tabs).
struct MainShellView: View {

    @EnvironmentObject private var container: AppContainer
    @State private var selectedTab = 0
    @State private var navPath = NavigationPath()

    private let tabs: [(label: String, icon: String)] = [
        ("Dashboard",  "square.grid.2x2"),
        ("Blueprints", "square.stack.3d.up"),
        ("Cloud",      "cloud"),
        ("Analytics",  "chart.bar"),
        ("Drift",      "ant"),
        ("Alerts",     "bell"),
        ("Profile",    "person.circle"),
    ]

    var body: some View {
        NavigationStack(path: $navPath) {
            TabView(selection: $selectedTab) {
                DashboardView(navPath: $navPath)
                    .tabItem { Label(tabs[0].label, systemImage: tabs[0].icon) }.tag(0)
                BlueprintsView()
                    .tabItem { Label(tabs[1].label, systemImage: tabs[1].icon) }.tag(1)
                CloudAccountsView()
                    .tabItem { Label(tabs[2].label, systemImage: tabs[2].icon) }.tag(2)
                AnalyticsView()
                    .tabItem { Label(tabs[3].label, systemImage: tabs[3].icon) }.tag(3)
                DriftView()
                    .tabItem { Label(tabs[4].label, systemImage: tabs[4].icon) }.tag(4)
                NotificationsView(navPath: $navPath)
                    .tabItem { Label(tabs[5].label, systemImage: tabs[5].icon) }.tag(5)
                ProfileView()
                    .tabItem { Label(tabs[6].label, systemImage: tabs[6].icon) }.tag(6)
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .deploymentDetail(let id):
                    DeploymentDetailView(deploymentId: id)
                case .deployments:
                    DeploymentsView()
                case .resources:
                    ResourcesView()
                case .resourceDetail(let deploymentId, let resourceId):
                    ResourceDetailView(deploymentId: deploymentId, resourceId: resourceId)
                case .cost:
                    CostView()
                }
            }
        }
    }
}

// MARK: - App Routes

enum AppRoute: Hashable {
    case deploymentDetail(id: String)
    case deployments
    case resources
    case resourceDetail(deploymentId: String, resourceId: String)
    case cost
}
