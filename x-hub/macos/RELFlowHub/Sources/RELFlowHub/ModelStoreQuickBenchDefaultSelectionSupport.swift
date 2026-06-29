import Foundation
import RELFlowHubCore

extension ModelStore {
    func startDefaultBench(for model: HubModel) {
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let probeLaunchConfig = HubStore.shared.localRuntimePythonProbeLaunchConfig(
            preferredProviderID: providerID
        )
        let pythonPath = probeLaunchConfig?.resolvedPythonPath
            ?? HubStore.shared.preferredLocalProviderPythonPath(preferredProviderID: providerID)
        switch LocalModelTrialSupportResolver.resolveDefaultBenchSelection(
            for: model,
            runtimeStatus: AIRuntimeStatusStorage.load(),
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
        case .success(let selection):
            runBench(
                modelId: model.id,
                taskKind: selection.taskKind,
                fixtureProfile: selection.fixtureProfile
            )
        case .failure(let error):
            recordImmediateFailure(
                action: "bench",
                modelId: model.id,
                msg: error.message
            )
        }
    }
}
