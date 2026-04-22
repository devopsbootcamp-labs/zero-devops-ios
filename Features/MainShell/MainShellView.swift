import SwiftUI
import Foundation

/// Main tab shell — mirrors Android MainShell with HorizontalPager-style tabs.
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
        ("Chat",       "bubble.left.and.bubble.right"),
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
                CloudAccountsView(navPath: $navPath)
                    .tabItem { Label(tabs[2].label, systemImage: tabs[2].icon) }.tag(2)
                AnalyticsView()
                    .tabItem { Label(tabs[3].label, systemImage: tabs[3].icon) }.tag(3)
                DriftView()
                    .tabItem { Label(tabs[4].label, systemImage: tabs[4].icon) }.tag(4)
                ChatView()
                    .tabItem { Label(tabs[5].label, systemImage: tabs[5].icon) }.tag(5)
                NotificationsView(navPath: $navPath)
                    .tabItem { Label(tabs[6].label, systemImage: tabs[6].icon) }.tag(6)
                ProfileView()
                    .tabItem { Label(tabs[7].label, systemImage: tabs[7].icon) }.tag(7)
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
                case .chat:
                    ChatView()
                case .drift:
                    DriftView()
                case .analytics:
                    AnalyticsView()
                case .accountWorkspace(let accountId, let accountName):
                    AccountWorkspaceView(accountId: accountId, accountName: accountName, navPath: $navPath)
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
    case chat
    case drift
    case analytics
    case accountWorkspace(accountId: String, accountName: String)
}

// MARK: - Chat

@MainActor
private final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var isSending = false
    @Published var error: String?

    private let api = APIClient.shared

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        draft = ""
        error = nil
        isSending = true
        messages.append(ChatMessage(role: .user, text: text, createdAt: Date()))

        let body = ChatRequest(message: text, context: "zero-devops-ios")
        let result = await requestReply(body)

        if let reply = result.reply, !reply.isEmpty {
            messages.append(ChatMessage(role: .assistant, text: reply, createdAt: Date()))
        } else {
            error = result.error ?? "Chat service is unavailable right now."
            messages.append(ChatMessage(
                role: .assistant,
                text: "I could not reach the chat service. Please try again in a moment.",
                createdAt: Date()
            ))
        }
        isSending = false
    }

    private func requestReply(_ body: ChatRequest) async -> (reply: String?, error: String?) {
        var lastError: Error?

        do {
            let r: ChatResponse = try await api.post("api/v1/chat", body: body)
            if !r.resolvedText.isEmpty { return (r.resolvedText, nil) }
        } catch {
            lastError = error
        }

        do {
            let r: ChatResponse = try await api.post("api/v1/ai/chat", body: body)
            if !r.resolvedText.isEmpty { return (r.resolvedText, nil) }
        } catch {
            lastError = error
        }

        do {
            let r: ChatResponse = try await api.post("api/v1/assistant/chat", body: body)
            if !r.resolvedText.isEmpty { return (r.resolvedText, nil) }
        } catch {
            lastError = error
        }

        // Gateway canonical flow: /api/v1/chat/rooms/{id}/messages
        if let roomId = await resolveRoomId() {
            do {
                let r: ChatRoomMessageResponse = try await api.post(
                    "api/v1/chat/rooms/\(roomId)/messages",
                    body: ChatRoomMessageRequest(message: body.message)
                )
                if !r.resolvedText.isEmpty { return (r.resolvedText, nil) }
            } catch {
                lastError = error
            }

            // Some backends persist message then stream/generate assistant reply asynchronously.
            do {
                let history: ChatRoomMessagesResponse = try await api.get("api/v1/chat/rooms/\(roomId)/messages")
                if let assistant = history.resolved.reversed().first(where: { ($0.role ?? "").lowercased() == "assistant" }),
                   !assistant.resolvedText.isEmpty {
                    return (assistant.resolvedText, nil)
                }
                if let latest = history.resolved.last, !latest.resolvedText.isEmpty {
                    return (latest.resolvedText, nil)
                }
            } catch {
                lastError = error
            }
        }

        return (nil, lastError?.localizedDescription)
    }

    private func resolveRoomId() async -> String? {
        if let rooms: [ChatRoom] = try? await api.get("api/v1/chat/rooms"), let id = rooms.first?.id {
            return id
        }
        if let wrapped: ChatRoomsResponse = try? await api.get("api/v1/chat/rooms"), let id = wrapped.resolved.first?.id {
            return id
        }
        if let created: ChatRoom = try? await api.post(
            "api/v1/chat/rooms",
            body: ChatRoomCreateRequest(name: "iOS Support")
        ) {
            return created.id
        }
        return nil
    }
}

private struct ChatView: View {
    @StateObject private var vm = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if vm.messages.isEmpty {
                ContentUnavailableFallback(
                    title: "Chat",
                    subtitle: "Send a message to the platform chat service when it is available."
                )
                .padding(.top, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.messages) { msg in
                            HStack {
                                if msg.role == .assistant { Spacer(minLength: 28) }
                                Text(msg.text)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(msg.role == .assistant ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.18))
                                    .cornerRadius(10)
                                if msg.role == .user { Spacer(minLength: 28) }
                            }
                        }
                    }
                    .padding()
                }
            }

            if let err = vm.error {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            HStack(spacing: 8) {
                TextField("Message chat service", text: $vm.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button {
                    Task { await vm.send() }
                } label: {
                    if vm.isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isSending)
            }
            .padding()
        }
        .navigationTitle("Chat")
    }
}

private struct ContentUnavailableFallback: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}
