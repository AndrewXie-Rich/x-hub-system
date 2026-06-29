import Foundation
import RELFlowHubCore

extension ModelStore {
    func currentLocalRuntimeRequestContext(for model: HubModel) -> LocalModelRuntimeRequestContext? {
        guard !isRemoteModel(model) else { return nil }
        if let cached = currentLocalRuntimeRequestContextByModelId[model.id] {
            return cached
        }
        return localRuntimeRequestContext(
            for: model,
            runtimeStatus: currentRuntimeStatus,
            pairedProfilesSnapshot: currentPairedProfilesSnapshot,
            targetPreference: currentTargetPreferenceByModelId[model.id]
        )
    }

    func currentLocalRuntimeTargetPreference(for model: HubModel) -> LocalModelRuntimeTargetPreference? {
        guard !isRemoteModel(model) else { return nil }
        return currentTargetPreferenceByModelId[model.id]
    }

    func setLocalRuntimeTargetOption(_ option: LocalModelRuntimeTargetOption, for model: HubModel) {
        guard !isRemoteModel(model) else { return }
        switch option.kind {
        case .auto:
            LocalModelRuntimeTargetPreferencesStorage.remove(modelId: model.id)
        case .pairedDevice:
            LocalModelRuntimeTargetPreferencesStorage.upsert(
                LocalModelRuntimeTargetPreference(
                    modelId: model.id,
                    targetKind: .pairedDevice,
                    deviceId: option.deviceID
                )
            )
        case .loadedInstance:
            LocalModelRuntimeTargetPreferencesStorage.upsert(
                LocalModelRuntimeTargetPreference(
                    modelId: model.id,
                    targetKind: .loadedInstance,
                    instanceKey: option.instanceKey
                )
            )
        }
        refresh()
    }

    func canEvictCurrentLocalRuntimeInstance(for model: HubModel) -> Bool {
        guard !isRemoteModel(model) else { return false }
        guard let requestContext = currentLocalRuntimeRequestContext(for: model) else {
            return false
        }
        guard !requestContext.instanceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        return currentRuntimeStatus?
            .providerStatus(providerID)?
            .supportsLifecycleAction(.evictLocalInstance) == true
    }
}
