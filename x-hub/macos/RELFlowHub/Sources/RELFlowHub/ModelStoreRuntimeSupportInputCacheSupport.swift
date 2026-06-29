import Foundation
import RELFlowHubCore

extension ModelStore {
    func localRuntimeSupportInputs(for model: HubModel) -> LocalRuntimeSupportInputs {
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        if let cached = localRuntimeSupportInputsCache[providerID] {
            return cached
        }

        let cached = LocalRuntimeSupportInputs(
            providerID: providerID,
            probeLaunchConfig: HubStore.shared.localRuntimePythonProbeLaunchConfig(
                preferredProviderID: providerID
            ),
            pythonPath: HubStore.shared.preferredLocalProviderPythonPath(
                preferredProviderID: providerID
            )
        )
        // Probe/config resolution is provider-scoped, so sharing it across models
        // on the same provider avoids repeated Python subprocess probes when the
        // Models drawer renders many rows at once.
        localRuntimeSupportInputsCache[providerID] = cached
        return cached
    }
}
