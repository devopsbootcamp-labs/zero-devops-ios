import Foundation

@MainActor
final class NotificationsViewModel: ObservableObject {

    @Published var notifications:  [Notification] = []
    @Published var isDegraded      = false
    @Published var isLoading       = false
    @Published var error:          String?

    private let api = APIClient.shared

    func load() async {
        isLoading = true
        error     = nil
        isDegraded = false

        if let list: [Notification] = try? await api.get("api/v1/notifications") {
            notifications = list
        } else if let list: [Notification] = try? await api.get("api/v1/alerts") {
            notifications = list
        } else {
            await loadDerived()
        }
        isLoading = false
    }

    func markRead(id: String) async {
        let _: EmptyResponse? = try? await api.put("api/v1/notifications/\(id)/read", body: EmptyBody())
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx] = Notification(
                id: id, title: notifications[idx].title, message: notifications[idx].message,
                type: notifications[idx].type, read: true,
                createdAt: notifications[idx].createdAt, resourceId: notifications[idx].resourceId
            )
        }
    }

    func delete(id: String) async {
        try? await api.delete("api/v1/notifications/\(id)")
        notifications.removeAll { $0.id == id }
    }

    private func loadDerived() async {
        isDegraded = true
        var derived = [Notification]()
        if let deps: [Deployment] = try? await api.get("api/v1/deployments") {
            derived += deps.filter { $0.status?.lowercased() == "failed" || $0.driftStatus?.lowercased() == "drifted" }
                .map { dep in
                    Notification(
                        id:         "derived-\(dep.id)",
                        title:      dep.status?.lowercased() == "failed" ? "Deployment Failed" : "Drift Detected",
                        message:    "\(dep.resolvedName) — \(dep.environment ?? "")",
                        type:       dep.status?.lowercased() == "failed" ? "error" : "warning",
                        read:       false,
                        createdAt:  dep.updatedAt,
                        resourceId: dep.id
                    )
                }
        }
        notifications = derived
    }
}

private struct EmptyBody: Encodable {}
