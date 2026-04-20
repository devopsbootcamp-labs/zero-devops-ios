import SwiftUI

@main
struct ZeroDevOpsApp: App {

    @StateObject private var container = AppContainer.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
                .onOpenURL { url in
                    // Resume the pending AppAuth browser flow on callback.
                    _ = OidcAuthManager.shared.resumeExternalUserAgentFlow(with: url)
                }
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }
}
