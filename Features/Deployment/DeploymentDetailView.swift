import SwiftUI

struct DeploymentDetailView: View {

    let deploymentId: String
    @StateObject private var vm = DeploymentDetailViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Header
                if let dep = vm.deployment {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(dep.resolvedName)
                                    .font(.title3.bold())
                                Spacer()
                                StatusChip(status: dep.status ?? "unknown")
                            }
                            HStack(spacing: 16) {
                                if let env = dep.environment {
                                    Label(env, systemImage: "tag")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let provider = dep.cloudProvider {
                                    Label(provider, systemImage: "cloud")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let region = dep.region {
                                    Label(region, systemImage: "location")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if let drift = dep.driftStatus {
                                HStack {
                                    Text("Drift: ")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    StatusChip(status: drift)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Plan card
                if let plan = vm.plan {
                    GroupBox(label: Label("Plan", systemImage: "doc.text")) {
                        if let summary = plan.summary {
                            Text(summary).font(.caption)
                        }
                        HStack(spacing: 16) {
                            PlanStat(label: "Add",     value: plan.toAdd     ?? 0, color: .green)
                            PlanStat(label: "Change",  value: plan.toChange  ?? 0, color: .orange)
                            PlanStat(label: "Destroy", value: plan.toDestroy ?? 0, color: .red)
                            if let cost = plan.estimatedCost {
                                PlanStat(label: "$Cost", value: Int(cost), color: .blue)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Action buttons
                if let dep = vm.deployment {
                    ActionButtonRow(
                        deployment:     dep,
                        isRunning:      vm.isActionRunning,
                        result:         vm.actionResult,
                        onPlan:         { Task { await vm.runPlan(deploymentId: dep.id) } },
                        onApply:        { Task { await vm.runApply(deploymentId: dep.id) } },
                        onApprove:      { Task { await vm.runApprove(deploymentId: dep.id) } },
                        onDrift:        { Task { await vm.runDriftCheck(deploymentId: dep.id) } },
                        onDestroy:      { Task {
                            let ok = await vm.runDestroy(deploymentId: dep.id)
                            if ok { dismiss() }
                        }}
                    )
                    .padding(.horizontal)
                }

                // Logs
                if vm.isStreaming || !vm.logs.isEmpty {
                    GroupBox(label: Label("Logs" + (vm.isStreaming ? "  ●" : ""), systemImage: "terminal")) {
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 2) {
                                if vm.logs.isEmpty {
                                    Text("No logs yet. Streaming will show new lines as they arrive.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                ForEach(vm.logs) { log in
                                    HStack(alignment: .top, spacing: 6) {
                                        if let ts = log.timestamp {
                                            Text(ts.formatted(date: .omitted, time: .standard))
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .frame(width: 80)
                                        }
                                        Text(log.message)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(logColor(log.level))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 280)
                        .background(Color.black.opacity(0.04))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Deployment")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if vm.isLoading { ProgressView("Loading…") } }
        .task { await vm.load(deploymentId: deploymentId) }
    }

    private func logColor(_ level: String?) -> Color {
        switch level?.lowercased() {
        case "error":   return .red
        case "warning": return .orange
        case "debug":   return .secondary
        default:        return .primary
        }
    }
}

private struct PlanStat: View {
    let label: String
    let value: Int
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.subheadline.bold()).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}

private struct ActionButtonRow: View {
    let deployment:  Deployment
    let isRunning:   Bool
    let result:      String?
    let onPlan:      () -> Void
    let onApply:     () -> Void
    let onApprove:   () -> Void
    let onDrift:     () -> Void
    let onDestroy:   () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let result = result {
                Text(result)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                ActionBtn(label: "Plan",    icon: "doc.badge.arrow.up",         color: .blue,   disabled: isRunning, action: onPlan)
                ActionBtn(label: "Drift",   icon: "ant",                         color: .orange, disabled: isRunning, action: onDrift)
                ActionBtn(label: "Approve", icon: "checkmark.shield",            color: .green,  disabled: isRunning, action: onApprove)
                ActionBtn(label: "Apply",   icon: "play.fill",                   color: .teal,   disabled: isRunning, action: onApply)
                ActionBtn(label: "Destroy", icon: "trash",                       color: .red,    disabled: isRunning, action: onDestroy)
            }
        }
    }
}

private struct ActionBtn: View {
    let label:    String
    let icon:     String
    let color:    Color
    let disabled: Bool
    let action:   () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.callout)
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(disabled ? Color.gray.opacity(0.15) : color.opacity(0.12))
            .foregroundColor(disabled ? .gray : color)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
