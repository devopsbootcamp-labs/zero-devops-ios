import SwiftUI

struct NotificationsView: View {

    @StateObject private var vm = NotificationsViewModel()
    @Binding var navPath: NavigationPath

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if vm.isDegraded {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Showing derived alerts — notifications API unavailable.")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                }

                List {
                    ForEach(vm.notifications) { n in
                        NotificationRow(notification: n) {
                            if let rid = n.resourceId, !n.id.hasPrefix("derived-") {
                                navPath.append(AppRoute.deploymentDetail(id: rid))
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await vm.delete(id: n.id) }
                            } label: { Label("Delete", systemImage: "trash") }

                            if n.read != true {
                                Button {
                                    Task { await vm.markRead(id: n.id) }
                                } label: { Label("Mark Read", systemImage: "envelope.open") }
                                .tint(.blue)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Alerts")
            .overlay {
                if vm.isLoading && vm.notifications.isEmpty { ProgressView("Loading…") }
                if let err = vm.error { ContentUnavailableView(err, systemImage: "bell.slash") }
                if !vm.isLoading && vm.notifications.isEmpty && vm.error == nil {
                    ContentUnavailableView("No Alerts", systemImage: "bell.badge.checkmark")
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }
}

private struct NotificationRow: View {
    let notification: Notification
    let onTap: () -> Void

    var typeColor: Color {
        switch notification.type?.lowercased() {
        case "error":   return .red
        case "warning": return .orange
        default:        return .blue
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(notification.read == true ? Color.clear : typeColor)
                    .overlay(Circle().strokeBorder(typeColor, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title ?? "Notification")
                        .font(.subheadline.weight(notification.read == true ? .regular : .semibold))
                    if let message = notification.message {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    if let date = notification.createdAt {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                TypeChip(type: notification.type)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct TypeChip: View {
    let type: String?
    var body: some View {
        let t = type?.lowercased() ?? "info"
        let color: Color = t == "error" ? .red : t == "warning" ? .orange : .blue
        Text((type ?? "info").capitalized)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}
