import SwiftUI

struct CloudAccountsView: View {

    @EnvironmentObject private var container: AppContainer
    @StateObject private var vm = CloudAccountsViewModel()

    var body: some View {
        NavigationView {
            List {
                // Show-all row
                Button {
                    container.selectAccount(nil)
                } label: {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Accounts")
                                .font(.subheadline.weight(.medium))
                            Text("Tenant-wide scope")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if container.selectedAccountId == nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(vm.accounts, id: \.resolvedScopeId) { account in
                    Button {
                        container.selectAccount(account.resolvedScopeId)
                    } label: {
                        AccountRow(
                            account:    account,
                            isSelected: container.selectedAccountId == account.resolvedScopeId
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Cloud Accounts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await vm.load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .overlay {
                if vm.isLoading { ProgressView("Loading…") }
                if let err = vm.error {
                    ContentUnavailableView(err, systemImage: "cloud.slash")
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }
}

private struct AccountRow: View {
    let account:    CloudAccount
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProviderIcon(provider: account.resolvedProvider)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.resolvedName)
                    .font(.subheadline.weight(.medium))
                Text(account.resolvedProvider + (account.resolvedRegion.isEmpty ? "" : "  ·  \(account.resolvedRegion)"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(account.resolvedScopeId)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
                if let status = account.status {
                    StatusChip(status: status)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProviderIcon: View {
    let provider: String
    var icon: String {
        switch provider.lowercased() {
        case _ where provider.lowercased().contains("aws"):   return "cloud.fill"
        case _ where provider.lowercased().contains("azure"): return "cloud.fill"
        case _ where provider.lowercased().contains("gcp"),
             _ where provider.lowercased().contains("google"): return "cloud.fill"
        default: return "server.rack"
        }
    }
    var color: Color {
        switch provider.lowercased() {
        case _ where provider.lowercased().contains("aws"):    return .orange
        case _ where provider.lowercased().contains("azure"):  return .blue
        case _ where provider.lowercased().contains("gcp"),
             _ where provider.lowercased().contains("google"): return .red
        default: return .gray
        }
    }
    var body: some View {
        Image(systemName: icon)
            .font(.title2)
            .foregroundColor(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.12))
            .cornerRadius(8)
    }
}
