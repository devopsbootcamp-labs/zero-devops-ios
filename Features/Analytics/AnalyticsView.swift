import SwiftUI

struct AnalyticsView: View {

    @EnvironmentObject private var container: AppContainer
    @StateObject private var vm = AnalyticsViewModel()

    private let ranges = ["7d", "30d", "90d"]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Range picker
                Picker("Range", selection: $vm.range) {
                    ForEach(ranges, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: vm.range) { _ in Task { await vm.load(accountId: container.selectedAccountId) } }

                    // Overview KPIs
                    if let ov = vm.overview {
                        OverviewSection(ov: ov)
                    }

                    // DORA Performance
                    if let perf = vm.performance {
                        DoraSection(perf: perf)
                    }

                    if !vm.trends.isEmpty {
                        GroupBox(label: Label("Deployment Trends", systemImage: "chart.line.uptrend.xyaxis")) {
                            ForEach(vm.trends.prefix(7)) { trend in
                                HStack {
                                    Text(trend.date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(trend.deployments ?? 0) deploys")
                                        .font(.caption.weight(.medium))
                                }
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Providers
                    if !vm.providers.isEmpty {
                        GroupBox(label: Label("By Provider", systemImage: "cloud")) {
                            ForEach(vm.providers) { p in
                                HStack {
                                    Text(p.provider).font(.subheadline)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(p.deploymentCount ?? 0) deployments").font(.caption)
                                        Text(String(format: "$%.0f/mo", p.monthlyCost ?? 0)).font(.caption).foregroundColor(.green)
                                    }
                                }
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }

                    if !vm.accounts.isEmpty {
                        GroupBox(label: Label("Accounts", systemImage: "building.2")) {
                            ForEach(vm.accounts.prefix(8), id: \.stableId) { account in
                                NavigationLink(value: AppRoute.accountWorkspace(accountId: account.resolvedScopeId, accountName: account.resolvedName)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(account.resolvedName).font(.subheadline.weight(.medium))
                                            Text(account.resolvedProvider + (account.resolvedRegion.isEmpty ? "" : "  ·  \(account.resolvedRegion)"))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(account.requestScopeId ?? account.stableId)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }

                    if !vm.blueprints.isEmpty {
                        GroupBox(label: Label("Blueprint Usage", systemImage: "square.stack.3d.up")) {
                            ForEach(vm.blueprints.prefix(6)) { blueprint in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(blueprint.blueprintName).font(.subheadline.weight(.medium))
                                        Text(blueprint.cloudProvider ?? "Unknown provider")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("\(blueprint.deploymentCount ?? 0)")
                                        .font(.subheadline.bold())
                                }
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Failures
                    if !vm.failures.isEmpty {
                        GroupBox(label: Label("Recent Failures", systemImage: "xmark.circle")) {
                            ForEach(vm.failures.prefix(5)) { f in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name ?? "Unknown").font(.subheadline.weight(.medium))
                                    if let reason = f.failureReason {
                                        Text(reason).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Insights
                    if !vm.insights.isEmpty {
                        GroupBox(label: Label("AI Insights", systemImage: "brain")) {
                            ForEach(vm.insights.prefix(5)) { i in
                                HStack(alignment: .top) {
                                    Image(systemName: severityIcon(i.severity))
                                        .foregroundColor(severityColor(i.severity))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(i.title ?? "").font(.subheadline.weight(.medium))
                                        Text(i.message ?? "").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }

                    if !vm.activity.isEmpty {
                        GroupBox(label: Label("Recent Activity", systemImage: "clock.arrow.circlepath")) {
                            ForEach(vm.activity.prefix(8)) { event in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.message ?? event.type ?? "Activity")
                                        .font(.subheadline.weight(.medium))
                                    HStack(spacing: 8) {
                                        if let type = event.type {
                                            Text(type)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        if let deploymentId = event.deploymentId {
                                            Text(deploymentId)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Analytics")
            .overlay {
                if vm.isLoading && vm.overview == nil { ProgressView("Loading…") }
                if !vm.isLoading,
                   vm.overview == nil,
                   vm.providers.isEmpty,
                   vm.trends.isEmpty,
                   let error = vm.error {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                }
            }
            .task { await vm.load(accountId: container.selectedAccountId) }
            .refreshable { await vm.load(accountId: container.selectedAccountId) }
            .onChange(of: container.selectedAccountId) { _ in
                Task { await vm.load(accountId: container.selectedAccountId) }
            }
            .onChange(of: container.tenantId) { _ in
                Task { await vm.load(accountId: container.selectedAccountId) }
            }
    }

    private func severityIcon(_ s: String?) -> String {
        switch s?.lowercased() {
        case "error", "critical": return "xmark.circle.fill"
        case "warning":           return "exclamationmark.triangle.fill"
        default:                  return "info.circle.fill"
        }
    }
    private func severityColor(_ s: String?) -> Color {
        switch s?.lowercased() {
        case "error", "critical": return .red
        case "warning":           return .orange
        default:                  return .blue
        }
    }
}

private struct OverviewSection: View {
    let ov: AnalyticsOverview
    var body: some View {
        GroupBox(label: Label("Overview", systemImage: "chart.bar")) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                MetricCell(label: "Total Deployments", value: "\(ov.resolvedTotalDeployments())")
                MetricCell(label: "Success Rate",      value: String(format: "%.0f%%", (ov.successRate ?? 0) * 100))
                MetricCell(label: "Failed",            value: "\(ov.resolvedFailed())")
                MetricCell(label: "Drift Issues",      value: "\(ov.driftIssues ?? 0)")
                MetricCell(label: "Monthly Cost",      value: String(format: "$%.0f", ov.monthlyCostEstimateSum ?? 0))
                MetricCell(label: "Active Resources",  value: "\(ov.resolvedActiveResources())")
            }
        }
        .padding(.horizontal)
    }
}

private struct DoraSection: View {
    let perf: AnalyticsPerformance
    var body: some View {
        GroupBox(label: Label("DORA Metrics", systemImage: "speedometer")) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                MetricCell(label: "Deploy Frequency", value: String(format: "%.1f/wk", perf.deploymentFrequency ?? 0))
                MetricCell(label: "Lead Time",        value: durationString(perf.leadTimeSeconds))
                MetricCell(label: "MTTR",             value: durationString(perf.mttrSeconds))
                MetricCell(label: "Change Failure",   value: String(format: "%.1f%%", (perf.changeFailureRate ?? 0) * 100))
            }
        }
        .padding(.horizontal)
    }
    func durationString(_ seconds: Double?) -> String {
        guard let s = seconds, s > 0 else { return "—" }
        if s < 3600  { return String(format: "%.0fm", s / 60) }
        return String(format: "%.1fh", s / 3600)
    }
}

private struct MetricCell: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }
}
