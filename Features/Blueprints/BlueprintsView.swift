import SwiftUI

struct BlueprintsView: View {

    @StateObject private var vm = BlueprintsViewModel()
    @State private var deployingBlueprint: Blueprint?
    @State private var deployName          = ""
    @State private var deployProvider      = ""
    @State private var deployRegion        = ""

    var body: some View {
        NavigationView {
            List(vm.blueprints) { bp in
                BlueprintRow(blueprint: bp) {
                    deployingBlueprint = bp
                    deployName         = ""
                    deployProvider     = bp.provider ?? ""
                    deployRegion       = ""
                }
            }
            .navigationTitle("Blueprints")
            .overlay {
                if vm.isLoading { ProgressView("Loading…") }
                if let err = vm.error {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up.slash")
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
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .sheet(item: $deployingBlueprint) { bp in
                DeploySheet(
                    blueprint:    bp,
                    name:         $deployName,
                    provider:     $deployProvider,
                    region:       $deployRegion,
                    isDeploying:  vm.isDeploying,
                    result:       vm.deployResult
                ) {
                    Task {
                        await vm.deploy(
                            blueprintId:   bp.id,
                            name:          deployName,
                            cloudProvider: deployProvider,
                            region:        deployRegion
                        )
                        if vm.deployResult?.hasPrefix("Deployment") == true {
                            deployingBlueprint = nil
                        }
                    }
                } onCancel: {
                    deployingBlueprint = nil
                }
            }
        }
    }
}

private struct BlueprintRow: View {
    let blueprint: Blueprint
    let onDeploy:  () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(blueprint.resolvedName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let version = blueprint.version {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            if let description = blueprint.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                if let provider = blueprint.provider {
                    Chip(text: provider, color: .blue)
                }
                if let category = blueprint.category {
                    Chip(text: category, color: .purple)
                }
                if let tags = blueprint.tags {
                    ForEach(tags.prefix(2), id: \.self) { Chip(text: $0, color: .gray) }
                }
                Spacer()
                Button("Deploy", action: onDeploy)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct Chip: View {
    let text:  String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

private struct DeploySheet: View {
    let blueprint:   Blueprint
    @Binding var name:     String
    @Binding var provider: String
    @Binding var region:   String
    let isDeploying: Bool
    let result:      String?
    let onDeploy:    () -> Void
    let onCancel:    () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Blueprint") {
                    Text(blueprint.resolvedName).font(.headline)
                    if let desc = blueprint.description {
                        Text(desc).font(.caption).foregroundColor(.secondary)
                    }
                }
                Section("Deployment Details") {
                    TextField("Deployment Name", text: $name)
                    TextField("Cloud Provider", text: $provider)
                    TextField("Region", text: $region)
                }
                if let result = result {
                    Section("Result") {
                        Text(result)
                            .foregroundColor(result.hasPrefix("Deployment") ? .green : .red)
                    }
                }
                Section {
                    Button {
                        onDeploy()
                    } label: {
                        if isDeploying {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("Deploy").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(name.isEmpty || provider.isEmpty || region.isEmpty || isDeploying)
                }
            }
            .navigationTitle("Deploy Blueprint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
