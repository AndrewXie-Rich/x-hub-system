import Foundation
import RELFlowHubCore

extension LocalModelRuntimeActionPlanner {
    static func isRemoteModel(_ model: HubModel) -> Bool {
        isRemoteModel(
            model,
            helperBinaryPath: LocalHelperBridgeDiscovery.discoverHelperBinary()
        )
    }

    static func isRemoteModel(_ model: HubModel, helperBinaryPath: String) -> Bool {
        let modelPath = (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelPath.isEmpty {
            return false
        }
        return providerID(for: model, helperBinaryPath: helperBinaryPath) != "mlx"
    }

    static func providerID(for model: HubModel) -> String {
        providerID(
            for: model,
            helperBinaryPath: LocalHelperBridgeDiscovery.discoverHelperBinary()
        )
    }

    static func providerID(for model: HubModel, helperBinaryPath: String) -> String {
        LocalModelExecutionProviderResolver.preferredRuntimeProviderID(
            for: model,
            helperBinaryPath: helperBinaryPath
        )
    }

    static func localModels(from models: [HubModel]) -> [HubModel] {
        guard !models.isEmpty else { return [] }
        let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()
        return models.filter {
            !isRemoteModel($0, helperBinaryPath: helperBinaryPath)
        }
    }

    static func remoteModels(from models: [HubModel]) -> [HubModel] {
        guard !models.isEmpty else { return [] }
        let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()
        return models.filter {
            isRemoteModel($0, helperBinaryPath: helperBinaryPath)
        }
    }
}
