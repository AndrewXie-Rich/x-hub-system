import Foundation
import RELFlowHubCore

extension ModelStore {
    func recordImmediateFailure(action: String, modelId: String, msg: String) {
        let reqId = UUID().uuidString
        successfulLocalLifecycleActionsByModelId.removeValue(forKey: modelId)
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: reqId,
            action: action,
            modelId: modelId,
            ok: false,
            msg: msg,
            finishedAt: Date().timeIntervalSince1970
        )
        pendingByModelId.removeValue(forKey: modelId)
    }

    func localRuntimeRequestContext(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot? = nil,
        targetPreference: LocalModelRuntimeTargetPreference? = nil
    ) -> LocalModelRuntimeRequestContext {
        LocalModelRuntimeRequestContextResolver.resolve(
            model: model,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfilesSnapshot ?? currentPairedProfilesSnapshot,
            targetPreference: targetPreference ?? currentTargetPreferenceByModelId[model.id]
        )
    }

    nonisolated static func isNewerBenchResult(_ lhs: ModelBenchResult, _ rhs: ModelBenchResult) -> Bool {
        if lhs.measuredAt == rhs.measuredAt {
            return lhs.id < rhs.id
        }
        return lhs.measuredAt > rhs.measuredAt
    }
}
