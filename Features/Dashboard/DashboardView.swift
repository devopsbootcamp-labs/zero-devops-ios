import SwiftUI

struct DashboardView: View {

    @EnvironmentObject private var container: AppContainer
    @StateObject private var vm = DashboardViewModel()
    @Binding var navPath: NavigationPath

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Scope banner
                HStack {
                    Image(systemName: "scope")
                    if let aid = container.selectedAccountId {
                        Text("Account scope: \(aid)")
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("Tenant-wide scope")
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

                // KPI row
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    KpiCard(label: "Deployments",    value: "\(vm.deployments.count)",                      icon: "server.rack",       color: .blue)
                    KpiCard(label: "Drift Issues",   value: "\(vm.posture?.driftedCount ?? 0)",              icon: "ant",               color: .orange)
                    KpiCard(label: "Monthly Cost",   value: String(format: "$%.0f", vm.costSummary?.totalCostUsd ?? 0), icon: "dollarsign.circle", color: .green)
                    KpiCard(label: "Success Rate",   value: String(format: "%.0f%%", (vm.overview?.successRate ?? 0) * 100), icon: "checkmark.seal", color: .teal)
                }
                .padding(.horizontal)

                // Drift Posture card
                if let posture = vm.posture {
                    GroupBox(label: Label("Drift Posture", systemImage: "ant")) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(posture.healthLabel)
                                    .font(.headline)
                                    .foregroundColor(posture.driftedCount == 0 ? .green : .orange)
                                Spacer()
                                if let last = posture.lastCheckedAt {
                                    Text(last.formatted(.relative(presentation: .named)))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            HStack {
                                StatPill(label: "Checked",  value: "\(posture.totalDeploymentsChecked ?? 0)")
                                StatPill(label: "Drifted",  value: "\(posture.driftedCount ?? 0)")
                                StatPill(label: "Clean",    value: "\(posture.cleanCount ?? 0)")
                                StatPill(label: "Affected", value: "\(posture.totalAffectedResources ?? 0)")
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Quick links
                VStack(spacing: 8) {
                    QuickLinkRow(label: "All Deployments",  icon: "server.rack") {
                        navPath.append(AppRoute.deployments)
                    }
                    QuickLinkRow(label: "Resources",         icon: "cube.box") {
                        navPath.append(AppRoute.resources)
                    }
                    QuickLinkRow(label: "Cost Breakdown",    icon: "dollarsign.circle") {
                        navPath.append(AppRoute.cost)
                    }
                    QuickLinkRow(label: "AI Chat Assistant", icon: "bubble.left.and.bubble.right") {
                        navPath.append(AppRoute.chat)
                    }
                }
                .padding(.horizontal)

                // Recent deployments
                if !vm.deployments.isEmpty {
                    GroupBox(label: Label("Recent Deployments", systemImage: "clock")) {
                        ForEach(vm.deployments.prefix(5)) { dep in
                            Button {
                                navPath.append(AppRoute.deploymentDetail(id: dep.id))
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dep.resolvedName).font(.subheadline.weight(.medium))
                                        Text(dep.environment ?? "—").font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    StatusChip(status: dep.status ?? "unknown")
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Dashboard")
        .refreshable { await vm.load(accountId: container.selectedAccountId) }
        .overlay {
            if vm.isLoading && vm.deployments.isEmpty {
                ProgressView("Loading…")
            }
        }
        .task { await vm.load(accountId: container.selectedAccountId) }
        .onChange(of: container.selectedAccountId) { _ in
            Task { await vm.load(accountId: container.selectedAccountId) }
        }
    }
}

// MARK: - Sub-views

private struct KpiCard: View {
    let label: String
    let value: String
    let icon:  String
    let color: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(value)
                    .font(.title2.bold())
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.bold())
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct QuickLinkRow: View {
    let label:  String
    let icon:   String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 28)
                Text(label)
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

struct StatusChip: View {
    let status: String
    var color: Color {
        switch status.lowercased() {
        case "success", "complete", "applied", "running": return .green
        case "failed",  "error":                          return .red
        case "drifted":                                   return .orange
        case "pending", "planning":                       return .yellow
        default:                                          return .gray
        }
    }
    var body: some View {
        Text(status.capitalized)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}
