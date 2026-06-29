import Foundation
import RELFlowHubCore

extension ModelStore {
    func dispatchLegacyQuickBenchRoute(
        modelId: String,
        model: HubModel,
        runtimeStatus: AIRuntimeStatus?
    ) {
        switch LocalModelRuntimeActionPlanner.plan(action: "bench", model: model, runtimeStatus: runtimeStatus) {
        case .legacyModelCommand(let routedAction):
            enqueueLegacyModelCommand(
                action: routedAction,
                model: model,
                runtimeStatus: runtimeStatus,
                targetPreferenceOverride: nil
            )
        case .providerLifecycleCommand:
            recordImmediateFailure(
                action: "bench",
                modelId: modelId,
                msg: HubUIStrings.Models.Review.QuickBenchRunner.lifecycleNotImplemented
            )
        case .immediateFailure(let message):
            recordImmediateFailure(action: "bench", modelId: modelId, msg: message)
        }
    }
}
