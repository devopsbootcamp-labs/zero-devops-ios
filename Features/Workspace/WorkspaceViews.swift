import SwiftUI

// MARK: - Deployments

struct DeploymentsView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var vm = DeploymentsViewModel()

    var body: some View {
        List(vm.deployments) { dep in
            NavigationLink(value: AppRoute.deploymentDetail(id: dep.id)) {
                DeploymentListRow(deployment: dep)
            }
        }
        .navigationTitle("Deployments")
        .overlay {
            if vm.isLoading { ProgressView("Loading…") }
            if let err = vm.error {
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(err)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
            if !vm.isLoading && vm.deployments.isEmpty && vm.error == nil {
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No Deployments")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
    @EnvironmentObject private var container: AppContainer
    @StateObject private var vm = ResourcesViewModel()
    let resourceTypeFilter: String?

    init(resourceTypeFilter: String? = nil) {
        self.resourceTypeFilter = resourceTypeFilter
    }

    private var filteredResources: [Resource] {
        guard let filter = resourceTypeFilter?.trimmingCharacters(in: .whitespacesAndNewlines), !filter.isEmpty else {
            return vm.resources
        }
        return vm.resources.filter { ($0.type ?? "").localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        List(filteredResources, id: \.stableId) { res in
            if let destination = resourceRoute(for: res) {
                NavigationLink(value: destination) {
                    ResourceListRow(resource: res)
                }
            } else {
                ResourceListRow(resource: res)
            }
        }
        .navigationTitle(resourceTypeFilter?.isEmpty == false ? resourceTypeFilter! : "Resources")
        .overlay {
            if vm.isLoading { ProgressView("Loading…") }
            if let err = vm.error {
                VStack(spacing: 8) {
                    Image(systemName: "cube.box")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(err)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
            if !vm.isLoading && filteredResources.isEmpty && vm.error == nil {
                VStack(spacing: 8) {
                    Image(systemName: "cube.box")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(resourceTypeFilter?.isEmpty == false ? "No matching resources" : "No Resources")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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

    private func resourceRoute(for resource: Resource) -> AppRoute? {
        let deploymentId = resource.deploymentId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resourceId = (resource.id ?? resource.resourceId)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let deploymentId, !deploymentId.isEmpty, let resourceId, !resourceId.isEmpty {
            return .resourceDetail(deploymentId: deploymentId, resourceId: resourceId)
        }
        if let deploymentId, !deploymentId.isEmpty {
            return .deploymentDetail(id: deploymentId)
        }
        return nil
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
                            NavigationLink(value: AppRoute.resourcesByType(type: r.resourceType)) {
                                HStack {
                                    Text(r.resourceType).font(.subheadline)
                                    Spacer()
                                    Text(String(format: "$%.2f", r.monthlyCost ?? 0))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.green)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }

                if !vm.deployments.isEmpty {
                    GroupBox(label: Label("By Deployment", systemImage: "server.rack")) {
                        ForEach(vm.deployments) { d in
                            if let deploymentId = d.deploymentId?.trimmingCharacters(in: .whitespacesAndNewlines), !deploymentId.isEmpty {
                                NavigationLink(value: AppRoute.deploymentDetail(id: deploymentId)) {
                                    HStack {
                                        Text(d.deploymentName ?? d.deploymentId ?? "—").font(.subheadline)
                                        Spacer()
                                        Text(String(format: "$%.2f", d.monthlyCost ?? 0))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.green)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                HStack {
                                    Text(d.deploymentName ?? d.deploymentId ?? "—").font(.subheadline)
                                    Spacer()
                                    Text(String(format: "$%.2f", d.monthlyCost ?? 0))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.green)
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
        .navigationTitle("Cost")
        .overlay { if vm.isLoading { ProgressView("Loading…") } }
        .task { await vm.load(accountId: container.selectedAccountId) }
        .refreshable { await vm.load(accountId: container.selectedAccountId) }
        .onChange(of: container.selectedAccountId) { _ in
            Task { await vm.load(accountId: container.selectedAccountId) }
        }
    }
}
