import Foundation

@MainActor
final class BlueprintsViewModel: ObservableObject {

    @Published var blueprints:       [Blueprint]  = []
    @Published var isLoading         = false
    @Published var error:            String?
    @Published var deployResult:     String?
    @Published var isDeploying       = false

    private let api = APIClient.shared

    func load() async {
        isLoading = true
        error     = nil
        if let list: [Blueprint] = try? await api.get("api/v1/blueprints") {
            blueprints = list
        } else if let list: [Blueprint] = try? await api.get("api/v1/registry/blueprints") {
            blueprints = list
        } else {
            error = "Unable to load blueprints."
        }
        isLoading = false
    }

    func deploy(blueprintId: String, name: String, cloudProvider: String, region: String) async {
        isDeploying  = true
        deployResult = nil
        let req = DeploymentRequest(
            name:          name,
            cloudProvider: cloudProvider,
            region:        region,
            blueprintId:   blueprintId,
            parameters:    [:]
        )
        do {
            let dep: Deployment = try await api.post("api/v1/deployments", body: req)
            deployResult = "Deployment '\(dep.resolvedName)' created."
        } catch {
            deployResult = error.localizedDescription
        }
        isDeploying = false
    }
}
