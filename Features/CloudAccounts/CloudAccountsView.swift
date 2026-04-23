import SwiftUI

struct CloudAccountsView: View {

    @EnvironmentObject private var container: AppContainer
    @StateObject private var vm = CloudAccountsViewModel()
    @Binding var navPath: NavigationPath

    var body: some View {
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

            ForEach(vm.accounts, id: \.stableId) { account in
                NavigationLink(value: AppRoute.accountWorkspace(accountId: account.resolvedScopeId, accountName: account.resolvedName)) {
                    AccountRow(
                        account: account,
                        isSelected: container.selectedAccountId == account.resolvedScopeId
                    )
                }
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
                VStack(spacing: 10) {
                    Image(systemName: "cloud.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    ForEach(err.components(separatedBy: "\n"), id: \.self) { line in
                        Text(line)
                            .font(line.contains("Unable to load") ? .subheadline : .caption2)
                            .foregroundColor(line.contains("Unable to load") ? .secondary : .orange)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                    Button("Retry") { Task { await vm.load() } }
                        .font(.caption.bold())
                        .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: 340)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}

struct AccountWorkspaceView: View {
    @EnvironmentObject private var container: AppContainer
    let accountId: String
    let accountName: String
    @Binding var navPath: NavigationPath
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(accountName)
                            .font(.title2.bold())
                        Text(accountId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    KpiBlock(label: "Deployments", value: "\(vm.overview?.resolvedTotalDeployments() ?? vm.deployments.count)", icon: "server.rack")
                    KpiBlock(label: "Drift", value: "\(vm.posture?.driftedCount ?? 0)", icon: "ant")
                    KpiBlock(label: "Resources", value: "\(vm.overview?.resolvedActiveResources() ?? 0)", icon: "cube.box")
                    KpiBlock(label: "Cost", value: String(format: "$%.2f", vm.costSummary?.totalCostUsd ?? 0), icon: "dollarsign.circle")
                }
                .padding(.horizontal)

                VStack(spacing: 8) {
                    ScopedAction(label: "Deployments", icon: "server.rack") {
                        navPath.append(AppRoute.deployments)
                    }
                    ScopedAction(label: "Resources", icon: "cube.box") {
                        navPath.append(AppRoute.resources)
                    }
                    ScopedAction(label: "Drift", icon: "ant") {
                        navPath.append(AppRoute.drift)
                    }
                    ScopedAction(label: "Cost", icon: "dollarsign.circle") {
                        navPath.append(AppRoute.cost)
                    }
                    ScopedAction(label: "Analytics", icon: "chart.line.uptrend.xyaxis") {
                        navPath.append(AppRoute.analytics)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Account Workspace")
        .overlay {
            if vm.isLoading { ProgressView("Loading…") }
            if let err = vm.error {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(12)
            }
        }
        .onAppear {
            container.selectAccount(accountId)
        }
        .task {
            await vm.load(accountId: accountId)
        }
        .refreshable {
            await vm.load(accountId: accountId)
        }
    }
}

private struct KpiBlock: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).foregroundColor(.teal)
                Text(value).font(.headline)
                Text(label).font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScopedAction: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
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
                Text(account.requestScopeId ?? account.resolvedAccountId)
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
        let p = provider.lowercased()
        if p.contains("aws") || p.contains("azure") || p.contains("gcp") || p.contains("google") {
            return "cloud.fill"
        }
        return "server.rack"
    }
    var color: Color {
        let p = provider.lowercased()
        if p.contains("aws") { return .orange }
        if p.contains("azure") { return .blue }
        if p.contains("gcp") || p.contains("google") { return .red }
        return .gray
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
