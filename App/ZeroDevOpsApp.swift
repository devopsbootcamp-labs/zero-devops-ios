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
                    // Resume the pending AppAuth browser flow on callback.
                    _ = OidcAuthManager.shared.resumeExternalUserAgentFlow(with: url)
                }
        }
    }
}
