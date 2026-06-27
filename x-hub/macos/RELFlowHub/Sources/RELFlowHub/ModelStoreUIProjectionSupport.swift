import Foundation
import RELFlowHubCore

struct OptionalRuntimePresentationCacheEntry {
    let value: LocalModelRuntimePresentation?
}

struct OptionalStringCacheEntry {
    let value: String?
}

struct LocalRuntimeSupportInputs {
    let providerID: String
    let probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?
    let pythonPath: String?
}

extension ModelStore {
    private func localRuntimeSupportInputs(for model: HubModel) -> LocalRuntimeSupportInputs {
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


    func localModelRuntimePresentation(for model: HubModel) -> LocalModelRuntimePresentation? {
        guard !isRemoteModel(model) else { return nil }
        if let cached = localRuntimePresentationCache[model.id] {
            return cached.value
        }

        let runtimeStatus = currentRuntimeStatus
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let providerStatus = runtimeStatus?.providerStatus(providerID)
        let controlMode = LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: providerStatus
        )
        let providerReady = runtimeStatus?.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false
        let supportsWarmup = controlMode == .warmable
            && (providerStatus?.supportsWarmup(forModelTaskKinds: model.taskKinds) ?? false)
        let supportsUnload = LocalRuntimeProviderPolicy.supportsUnload(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: providerStatus
        )
        let supportsBench = !(
            availableBenchTaskDescriptorsCache[model.id]
            ?? LocalModelBenchCapabilityPolicy.benchableDescriptors(
                for: model,
                runtimeStatus: runtimeStatus
            )
        ).isEmpty
        let presentation = LocalModelRuntimePresentation(
            providerID: providerID,
            controlMode: controlMode,
            lifecycleMode: providerStatus?.lifecycleMode ?? "",
            residencyScope: providerStatus?.residencyScope ?? "",
            providerReady: providerReady,
            supportsWarmup: supportsWarmup,
            supportsUnload: supportsUnload,
            supportsBench: supportsBench
        )
        localRuntimePresentationCache[model.id] = OptionalRuntimePresentationCacheEntry(value: presentation)
        return presentation
    }

    func localRuntimeActionBlockedMessage(for model: HubModel, action: String) -> String? {
        guard !isRemoteModel(model) else { return nil }
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheKey = "\(model.id)|\(normalizedAction)"
        if let cached = localRuntimeActionBlockedMessageCache[cacheKey] {
            return cached.value
        }
        let inputs = localRuntimeSupportInputs(for: model)
        let blockedMessage = LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: action,
            model: model,
            probeLaunchConfig: inputs.probeLaunchConfig,
            pythonPath: inputs.pythonPath
        )
        localRuntimeActionBlockedMessageCache[cacheKey] = OptionalStringCacheEntry(value: blockedMessage)
        return blockedMessage
    }

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

    func availableLocalRuntimeTargetOptions(for model: HubModel) -> [LocalModelRuntimeTargetOption] {
        guard !isRemoteModel(model) else { return [] }
        if let cached = availableLocalRuntimeTargetOptionsCache[model.id] {
            return cached
        }
        let runtimeStatus = currentRuntimeStatus
        let pairedProfilesSnapshot = currentPairedProfilesSnapshot
        let targetPreference = currentTargetPreferenceByModelId[model.id]
        let inputs = localRuntimeSupportInputs(for: model)

        var options: [LocalModelRuntimeTargetOption] = []
        let autoContext = localRuntimeRequestContext(
            for: model,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreference: nil
        )
        options.append(
            LocalModelRuntimeTargetOption(
                kind: .auto,
                deviceID: "",
                instanceKey: "",
                title: HubUIStrings.Models.Runtime.ActionPlanner.automaticTarget,
                detail: autoContext.uiSummary
            )
        )

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
        for profile in pairedProfiles {
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
            options.append(
                LocalModelRuntimeTargetOption(
                    kind: .pairedDevice,
                    deviceID: profile.deviceId,
                    instanceKey: "",
                    title: profile.deviceId == LocalModelRuntimeRequestContextResolver.defaultPairedDeviceID
                        ? HubUIStrings.Models.Runtime.ActionPlanner.pairedTerminalTarget
                        : profile.deviceId,
                    detail: context.uiSummary
                )
            )
        }

        let loadedInstances = runtimeStatus?
            .providerStatus(inputs.providerID)?
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
        for loaded in loadedInstances {
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
            options.append(
                LocalModelRuntimeTargetOption(
                    kind: .loadedInstance,
                    deviceID: "",
                    instanceKey: loaded.instanceKey,
                    title: HubUIStrings.Models.Runtime.Operations.instanceTitle(shortInstance),
                    detail: context.technicalSummary
                )
            )
        }

        var deduped: [LocalModelRuntimeTargetOption] = []
        var seen = Set<String>()
        for option in options {
            guard seen.insert(option.id).inserted else { continue }
            deduped.append(option)
        }

        if let targetPreference,
           targetPreference.isValid,
           !deduped.contains(where: { option in
               switch option.kind {
               case .auto:
                   return false
               case .pairedDevice:
                   return targetPreference.kind == .pairedDevice && option.deviceID == targetPreference.deviceId
               case .loadedInstance:
                   return targetPreference.kind == .loadedInstance && option.instanceKey == targetPreference.instanceKey
               }
           }) {
            deduped.insert(
                LocalModelRuntimeTargetOption(
                    kind: .auto,
                    deviceID: "",
                    instanceKey: "",
                    title: HubUIStrings.Models.Runtime.ActionPlanner.automaticTarget,
                    detail: autoContext.uiSummary
                ),
                at: 0
            )
        }

        availableLocalRuntimeTargetOptionsCache[model.id] = deduped
        return deduped
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

    func preferredBenchResult(for model: HubModel) -> ModelBenchResult? {
        currentTargetBenchResults(for: model).first
    }

    func currentTargetBenchResult(for model: HubModel, taskKind: String) -> ModelBenchResult? {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return currentTargetBenchResults(for: model).first {
            normalizedTaskKind.isEmpty || $0.taskKind == normalizedTaskKind
        }
    }

    func currentTargetBenchResults(for model: HubModel) -> [ModelBenchResult] {
        let rows = benchResults(for: model.id)
        guard let requestContext = currentLocalRuntimeRequestContext(for: model) else {
            return rows
        }
        let matching = rows.filter { requestContext.matchesBenchResult($0) }
        return matching.isEmpty ? rows : matching
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

    func quickBenchMonitorExplanation(for model: HubModel, taskKind: String) -> LocalModelBenchMonitorExplanation? {
        guard !isRemoteModel(model) else { return nil }
        return LocalModelBenchMonitorExplanationBuilder.build(
            model: model,
            taskKind: taskKind,
            requestContext: currentLocalRuntimeRequestContext(for: model),
            benchResult: currentTargetBenchResult(for: model, taskKind: taskKind),
            runtimeStatus: currentRuntimeStatus
        )
    }

    func availableBenchTaskDescriptors(for model: HubModel) -> [LocalTaskRoutingDescriptor] {
        guard !isRemoteModel(model) else { return [] }
        if let cached = availableBenchTaskDescriptorsCache[model.id] {
            return cached
        }
        let inputs = localRuntimeSupportInputs(for: model)
        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: currentRuntimeStatus,
            probeLaunchConfig: inputs.probeLaunchConfig,
            pythonPath: inputs.pythonPath
        )
        availableBenchTaskDescriptorsCache[model.id] = descriptors
        return descriptors
    }

    func availableBenchFixtures(for model: HubModel, taskKind: String) -> [LocalBenchFixtureDescriptor] {
        guard !isRemoteModel(model) else { return [] }
        return LocalBenchFixtureCatalog.fixtures(
            for: taskKind,
            providerID: LocalModelRuntimeActionPlanner.providerID(for: model)
        )
    }

    func benchResults(for modelId: String) -> [ModelBenchResult] {
        benchSnapshot.results.filter { $0.modelId == modelId }.sorted {
            if $0.measuredAt == $1.measuredAt {
                return $0.id < $1.id
            }
            return $0.measuredAt > $1.measuredAt
        }
    }

}
