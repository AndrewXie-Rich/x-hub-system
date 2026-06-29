import Foundation
import RELFlowHubCore

extension ModelStore {
    func availableLocalRuntimeTargetOptions(for model: HubModel) -> [LocalModelRuntimeTargetOption] {
        guard !isRemoteModel(model) else { return [] }
        if let cached = availableLocalRuntimeTargetOptionsCache[model.id] {
            return cached
        }

        let startedAt = HubPerformanceTrace.now()
        let runtimeStatus = currentRuntimeStatus
        let pairedProfilesSnapshot = currentPairedProfilesSnapshot
        let targetPreference = currentTargetPreferenceByModelId[model.id]
        let inputs = localRuntimeSupportInputs(for: model)

        let autoOption = localRuntimeAutomaticTargetOption(
            for: model,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfilesSnapshot
        )
        var options: [LocalModelRuntimeTargetOption] = [autoOption]
        options.append(
            contentsOf: localRuntimePairedDeviceTargetOptions(
                for: model,
                runtimeStatus: runtimeStatus,
                pairedProfilesSnapshot: pairedProfilesSnapshot
            )
        )
        options.append(
            contentsOf: localRuntimeLoadedInstanceTargetOptions(
                for: model,
                providerID: inputs.providerID,
                runtimeStatus: runtimeStatus,
                pairedProfilesSnapshot: pairedProfilesSnapshot
            )
        )

        var deduped = dedupedLocalRuntimeTargetOptions(options)
        if let targetPreference,
           targetPreference.isValid,
           !containsLocalRuntimeTargetPreference(targetPreference, in: deduped) {
            deduped.insert(autoOption, at: 0)
        }

        availableLocalRuntimeTargetOptionsCache[model.id] = deduped
        HubPerformanceTrace.logSlow(
            "models.projection.runtime_target_options",
            startedAt: startedAt,
            thresholdMs: 10,
            details: "model=\(model.id) provider=\(inputs.providerID) options=\(deduped.count)"
        )
        return deduped
    }
}
