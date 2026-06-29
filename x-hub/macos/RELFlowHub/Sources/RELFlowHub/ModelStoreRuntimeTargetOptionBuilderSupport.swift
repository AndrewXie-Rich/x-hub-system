import Foundation
import RELFlowHubCore

extension ModelStore {
    func localRuntimeAutomaticTargetOption(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot
    ) -> LocalModelRuntimeTargetOption {
        let autoContext = localRuntimeRequestContext(
            for: model,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreference: nil
        )
        return LocalModelRuntimeTargetOption(
            kind: .auto,
            deviceID: "",
            instanceKey: "",
            title: HubUIStrings.Models.Runtime.ActionPlanner.automaticTarget,
            detail: autoContext.uiSummary
        )
    }

    func localRuntimePairedDeviceTargetOptions(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot
    ) -> [LocalModelRuntimeTargetOption] {
        let pairedProfiles = pairedProfilesSnapshot.profiles
            .filter { $0.modelId == model.id && !$0.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.deviceId == rhs.deviceId {
                    return lhs.updatedAtMs > rhs.updatedAtMs
                }
                if lhs.deviceId == LocalModelRuntimeRequestContextResolver.defaultPairedDeviceID {
                    return true
                }
                if rhs.deviceId == LocalModelRuntimeRequestContextResolver.defaultPairedDeviceID {
                    return false
                }
                return lhs.deviceId.localizedCaseInsensitiveCompare(rhs.deviceId) == .orderedAscending
            }
        return pairedProfiles.map { profile in
            let context = localRuntimeRequestContext(
                for: model,
                runtimeStatus: runtimeStatus,
                pairedProfilesSnapshot: pairedProfilesSnapshot,
                targetPreference: LocalModelRuntimeTargetPreference(
                    modelId: model.id,
                    targetKind: .pairedDevice,
                    deviceId: profile.deviceId
                )
            )
            return LocalModelRuntimeTargetOption(
                kind: .pairedDevice,
                deviceID: profile.deviceId,
                instanceKey: "",
                title: profile.deviceId == LocalModelRuntimeRequestContextResolver.defaultPairedDeviceID
                    ? HubUIStrings.Models.Runtime.ActionPlanner.pairedTerminalTarget
                    : profile.deviceId,
                detail: context.uiSummary
            )
        }
    }

    func localRuntimeLoadedInstanceTargetOptions(
        for model: HubModel,
        providerID: String,
        runtimeStatus: AIRuntimeStatus?,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot
    ) -> [LocalModelRuntimeTargetOption] {
        let loadedInstances = runtimeStatus?
            .providerStatus(providerID)?
            .loadedInstances
            .filter { $0.modelId == model.id }
            .sorted {
                if $0.lastUsedAt == $1.lastUsedAt {
                    if $0.loadedAt == $1.loadedAt {
                        return $0.instanceKey < $1.instanceKey
                    }
                    return $0.loadedAt > $1.loadedAt
                }
                return $0.lastUsedAt > $1.lastUsedAt
            } ?? []

        return loadedInstances.map { loaded in
            let context = localRuntimeRequestContext(
                for: model,
                runtimeStatus: runtimeStatus,
                pairedProfilesSnapshot: pairedProfilesSnapshot,
                targetPreference: LocalModelRuntimeTargetPreference(
                    modelId: model.id,
                    targetKind: .loadedInstance,
                    instanceKey: loaded.instanceKey
                )
            )
            let shortInstance = String(
                String(loaded.instanceKey.split(separator: ":").last ?? Substring("")).prefix(8)
            )
            return LocalModelRuntimeTargetOption(
                kind: .loadedInstance,
                deviceID: "",
                instanceKey: loaded.instanceKey,
                title: HubUIStrings.Models.Runtime.Operations.instanceTitle(shortInstance),
                detail: context.technicalSummary
            )
        }
    }

    func dedupedLocalRuntimeTargetOptions(
        _ options: [LocalModelRuntimeTargetOption]
    ) -> [LocalModelRuntimeTargetOption] {
        var deduped: [LocalModelRuntimeTargetOption] = []
        var seen = Set<String>()
        for option in options {
            guard seen.insert(option.id).inserted else { continue }
            deduped.append(option)
        }
        return deduped
    }

    func containsLocalRuntimeTargetPreference(
        _ targetPreference: LocalModelRuntimeTargetPreference,
        in options: [LocalModelRuntimeTargetOption]
    ) -> Bool {
        options.contains { option in
            switch option.kind {
            case .auto:
                return false
            case .pairedDevice:
                return targetPreference.kind == .pairedDevice && option.deviceID == targetPreference.deviceId
            case .loadedInstance:
                return targetPreference.kind == .loadedInstance && option.instanceKey == targetPreference.instanceKey
            }
        }
    }
}
