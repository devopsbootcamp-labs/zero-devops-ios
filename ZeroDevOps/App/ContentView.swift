import SwiftUI

/// Root navigation — mirrors Android NavHost: "login" → "main".
struct ContentView: View {

    @EnvironmentObject private var container: AppContainer

    var body: some View {
        Group {
            if container.sessionReady {
                MainShellView()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: container.sessionReady)
        .onAppear {
            container.onAppear()
        }
    }
}
