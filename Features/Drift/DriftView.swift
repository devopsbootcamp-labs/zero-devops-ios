import SwiftUI

struct DriftView: View {

    @EnvironmentObject private var container: AppContainer
    @StateObject private var vm = DriftViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Posture banner
            if let posture = vm.posture {
                PostureBanner(posture: posture)
            }

            if let result = vm.triggerResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(8)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }

            List(vm.items) { item in
                DriftItemRow(
                    item:         item,
                    name:         vm.nameMap[item.deploymentId] ?? item.deploymentId,
                    onTrigger:    { Task { await vm.triggerCheck(deploymentId: item.deploymentId) } }
                )
            }
            .listStyle(.plain)
        }
        .navigationTitle("Drift")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { Task { await vm.runAllChecks() } } label: {
                    Label("Run All", systemImage: "play.fill")
                        .font(.caption)
                }
                Button { Task { await vm.load(accountId: container.selectedAccountId) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .overlay {
            if vm.isLoading && vm.items.isEmpty { ProgressView("Loading…") }
            if let err = vm.error {
                VStack(spacing: 8) {
                    Image(systemName: "ant")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(err)
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
    }
}

private struct PostureBanner: View {
    let posture: DriftPosture

    var bannerColor: Color { posture.driftedCount == 0 ? .green : .orange }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(posture.healthLabel)
                    .font(.headline)
                    .foregroundColor(bannerColor)
                Spacer()
                if let last = posture.lastCheckedAt {
                    Text(last.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 12) {
                StatPill(label: "Checked",  value: "\(posture.totalDeploymentsChecked ?? 0)")
                StatPill(label: "Drifted",  value: "\(posture.driftedCount ?? 0)")
                StatPill(label: "Clean",    value: "\(posture.cleanCount ?? 0)")
                StatPill(label: "Affected", value: "\(posture.totalAffectedResources ?? 0)")
            }
        }
        .padding()
        .background(bannerColor.opacity(0.08))
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
    }
}

private struct DriftItemRow: View {
    let item:      DriftDeployment
    let name:      String
    let onTrigger: () -> Void

    var body: some View {
        HStack {
            NavigationLink(value: AppRoute.deploymentDetail(id: item.deploymentId)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        StatusChip(status: item.driftDisplayStatus)
                        if let severity = item.severity {
                            Text(severity.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                        }
                    }
                    if let last = item.lastCheckedAt {
                        Text("Checked \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button(action: onTrigger) {
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
