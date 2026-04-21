import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@main
struct ZeroDevOpsApp: App {

    @StateObject private var container = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
                .onOpenURL { url in
                    // Keep callback hook for auth redirects.
                    _ = OidcAuthManager.shared.resumeExternalUserAgentFlow(with: url)
                }
        }
    }
}
