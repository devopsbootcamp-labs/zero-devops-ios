import SwiftUI

struct LoginView: View {

    @EnvironmentObject private var container: AppContainer
    @State private var showingAuthVC = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.1, blue: 0.2),
                         Color(red: 0.1,  green: 0.2, blue: 0.4)],
                startPoint: .topLeading,
                endPoint:   .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Logo mark
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 100, height: 100)
                    Text("ZD")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text("Zero DevOps")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Text("Enterprise Infrastructure Platform")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                // SSO Card
                VStack(spacing: 16) {
                    if let error = container.loginError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal)
                    }

                    Button {
                        showingAuthVC = true
                    } label: {
                        HStack {
                            if container.isLoggingIn {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 4)
                            }
                            Text(container.isLoggingIn ? "Signing in…" : "Sign in with SSO")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(container.isLoggingIn ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(container.isLoggingIn)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)
            }
        }
        .sheet(isPresented: $showingAuthVC) {
            AuthViewController { viewController in
                container.login(from: viewController)
                showingAuthVC = false
            }
        }
    }
}

// MARK: - UIViewControllerRepresentable bridge for AppAuth

struct AuthViewController: UIViewControllerRepresentable {
    let onPresent: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Trigger once when the sheet is shown
        if !context.coordinator.didTrigger {
            context.coordinator.didTrigger = true
            DispatchQueue.main.async {
                onPresent(uiViewController)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var didTrigger = false
    }
}
