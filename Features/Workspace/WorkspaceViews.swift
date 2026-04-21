import SwiftUI

// MARK: - Deployments

struct DeploymentsView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var vm = DeploymentsViewModel()
    @State private var navPath  = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            List(vm.deployments) { dep in
                NavigationLink(value: dep.id) {
                    DeploymentListRow(deployment: dep)
                }
            }
            .navigationTitle("Deployments")
            .navigationDestination(for: String.self) { id in
                DeploymentDetailView(deploymentId: id)
            }
            .overlay {
                if vm.isLoading { ProgressView("Loading…") }
                if let err = vm.error { ContentUnavailableView(err, systemImage: "server.rack") }
                if !vm.isLoading && vm.deployments.isEmpty && vm.error == nil {
                    ContentUnavailableView("No Deployments", systemImage: "server.rack")
                }
            }
            .task { await vm.load(accountId: container.selectedAccountId) }
            .refreshable { await vm.load(accountId: container.selectedAccountId) }
        }
    }
}

private struct DeploymentListRow: View {
    let deployment: Deployment
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(deployment.resolvedName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                StatusChip(status: deployment.status ?? "unknown")
            }
            HStack(spacing: 10) {
                if let env = deployment.environment {
                    Label(env, systemImage: "tag").font(.caption2).foregroundColor(.secondary)
                }
                if let provider = deployment.cloudProvider {
                    Label(provider, systemImage: "cloud").font(.caption2).foregroundColor(.secondary)
                }
                if let drift = deployment.driftStatus, drift.lowercased() != "clean" {
                    Label(drift, systemImage: "ant").font(.caption2).foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Resources

struct ResourcesView: View {
    @StateObject private var vm = ResourcesViewModel()

    var body: some View {
        List(vm.resources, id: \.stableId) { res in
            ResourceListRow(resource: res)
        }
        .navigationTitle("Resources")
        .overlay {
            if vm.isLoading { ProgressView("Loading…") }
            if let err = vm.error { ContentUnavailableView(err, systemImage: "cube.box") }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}

private struct ResourceListRow: View {
    let resource: Resource
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(resource.name ?? resource.stableId)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let status = resource.status { StatusChip(status: status) }
            }
            HStack(spacing: 10) {
                if let type_ = resource.type {
                    Label(type_, systemImage: "cube.box").font(.caption2).foregroundColor(.secondary)
                }
                if let prov = resource.provider {
                    Label(prov, systemImage: "cloud").font(.caption2).foregroundColor(.secondary)
                }
                if let region = resource.region {
                    Label(region, systemImage: "location").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Resource Detail

struct ResourceDetailView: View {
    let deploymentId: String
    let resourceId:   String
    @StateObject private var vm = ResourceDetailViewModel()

    var body: some View {
        Group {
            if let res = vm.resource {
                List {
                    Section("Identity") {
                        LabeledContent("ID",       value: res.stableId)
                        LabeledContent("Name",     value: res.name      ?? "—")
                        LabeledContent("Type",     value: res.type      ?? "—")
                        LabeledContent("Provider", value: res.provider  ?? "—")
                        LabeledContent("Region",   value: res.region    ?? "—")
                    }
                    Section("Status") {
                        LabeledContent("Status",      value: res.status     ?? "—")
                        LabeledContent("Drift Status",value: res.driftStatus ?? "—")
                    }
                    if let tags = res.tags, !tags.isEmpty {
                        Section("Tags") {
                            ForEach(Array(tags.keys.sorted()), id: \.self) { key in
                                LabeledContent(key, value: tags[key] ?? "")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Resource Detail")
        .overlay { if vm.isLoading { ProgressView("Loading…") } }
        .task { await vm.load(deploymentId: deploymentId, resourceId: resourceId) }
    }
}

// MARK: - Cost

struct CostView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var vm = CostViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let summary = vm.summary {
                    GroupBox(label: Label("Summary", systemImage: "dollarsign.circle")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "$%.2f", summary.totalCostUsd ?? 0))
                                    .font(.largeTitle.bold())
                                Text("\(summary.currency ?? "USD") · \(summary.period ?? "Monthly")")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal)
                }

                if !vm.resources.isEmpty {
                    GroupBox(label: Label("By Resource Type", systemImage: "cube.box")) {
                        ForEach(vm.resources) { r in
                            HStack {
                                Text(r.resourceType).font(.subheadline)
                                Spacer()
                                Text(String(format: "$%.2f", r.monthlyCost ?? 0))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.green)
                            }
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }

                if !vm.deployments.isEmpty {
                    GroupBox(label: Label("By Deployment", systemImage: "server.rack")) {
                        ForEach(vm.deployments) { d in
                            HStack {
                                Text(d.deploymentName ?? d.deploymentId ?? "—").font(.subheadline)
                                Spacer()
                                Text(String(format: "$%.2f", d.monthlyCost ?? 0))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.green)
                            }
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Cost")
        .overlay { if vm.isLoading { ProgressView("Loading…") } }
        .task { await vm.load(accountId: container.selectedAccountId) }
        .refreshable { await vm.load(accountId: container.selectedAccountId) }
    }
}
