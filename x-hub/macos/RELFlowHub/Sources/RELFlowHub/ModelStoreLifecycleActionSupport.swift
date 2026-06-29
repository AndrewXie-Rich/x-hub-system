import Foundation
import RELFlowHubCore

extension ModelStore {
    func enqueue(action: String, modelId: String) {
        enqueue(
            action: action,
            modelId: modelId,
            allowRuntimeRecovery: true,
            targetPreferenceOverride: nil
        )
    }

    func enqueueRuntimeLifecycleAction(
        action: String,
        modelId: String,
        targetPreference: LocalModelRuntimeTargetPreference
    ) {
        enqueue(
            action: action,
            modelId: modelId,
            allowRuntimeRecovery: true,
            targetPreferenceOverride: targetPreference
        )
    }

    func enqueue(
        action: String,
        modelId: String,
        allowRuntimeRecovery: Bool,
        targetPreferenceOverride: LocalModelRuntimeTargetPreference?
    ) {
        guard let model = snapshot.models.first(where: { $0.id == modelId }) else { return }
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lastResultByModelId.removeValue(forKey: modelId)
        if ["load", "warmup", "unload", "evict"].contains(normalizedAction) {
            successfulLocalLifecycleActionsByModelId.removeValue(forKey: modelId)
        }
        if shouldPrepareManagedLocalModel(
            action: normalizedAction,
            model: model
        ) {
            prepareManagedLocalModelAndRetry(
                action: normalizedAction,
                model: model,
                allowRuntimeRecovery: allowRuntimeRecovery,
                targetPreferenceOverride: targetPreferenceOverride
            )
            return
        }
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let probeLaunchConfig = HubStore.shared.localRuntimePythonProbeLaunchConfig(
            preferredProviderID: providerID
        )
        let pythonPath = HubStore.shared.preferredLocalProviderPythonPath(
            preferredProviderID: providerID
        )
        if normalizedAction == "bench" {
            startDefaultBench(for: model)
            return
        }
        let runtimeStatus = AIRuntimeStatusStorage.load()
        if allowRuntimeRecovery,
           shouldAttemptRuntimeRecovery(
                action: normalizedAction,
                model: model,
                providerID: providerID,
                runtimeStatus: runtimeStatus
           ) {
            recoverRuntimeAndRetry(action: normalizedAction, model: model, providerID: providerID)
            return
        }
        if let blockedMessage = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: action,
            model: model,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
            recordImmediateFailure(action: action, modelId: modelId, msg: blockedMessage)
            return
        }
        switch LocalModelRuntimeActionPlanner.plan(action: action, model: model, runtimeStatus: runtimeStatus) {
        case .immediateFailure(let message):
            recordImmediateFailure(action: action, modelId: modelId, msg: message)
            return
        case .legacyModelCommand(let routedAction):
            enqueueLegacyModelCommand(
                action: routedAction,
                model: model,
                runtimeStatus: runtimeStatus,
                targetPreferenceOverride: targetPreferenceOverride
            )
        case .providerLifecycleCommand(let routedAction):
            enqueueProviderLifecycleCommand(
                action: routedAction,
                model: model,
                targetPreferenceOverride: targetPreferenceOverride
            )
        }
    }
}
