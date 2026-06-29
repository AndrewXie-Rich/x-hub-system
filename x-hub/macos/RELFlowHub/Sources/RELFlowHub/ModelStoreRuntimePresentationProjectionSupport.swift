import Foundation
import RELFlowHubCore

extension ModelStore {
    func localModelRuntimePresentation(for model: HubModel) -> LocalModelRuntimePresentation? {
        guard !isRemoteModel(model) else { return nil }
        if let cached = localRuntimePresentationCache[model.id] {
            return cached.value
        }

        let startedAt = HubPerformanceTrace.now()
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
        HubPerformanceTrace.logSlow(
            "models.projection.runtime_presentation",
            startedAt: startedAt,
            thresholdMs: 8,
            details: "model=\(model.id) provider=\(providerID) control=\(controlMode.rawValue)"
        )
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
}
