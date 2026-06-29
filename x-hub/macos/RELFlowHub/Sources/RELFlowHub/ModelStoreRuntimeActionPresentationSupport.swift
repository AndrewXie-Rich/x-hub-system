import Foundation
import RELFlowHubCore

extension LocalModelRuntimeActionPlanner {
    static func presentation(
        for model: HubModel,
        runtimeStatus: AIRuntimeStatus? = nil
    ) -> LocalModelRuntimePresentation? {
        let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()
        guard !isRemoteModel(model, helperBinaryPath: helperBinaryPath) else { return nil }
        let providerID = providerID(for: model, helperBinaryPath: helperBinaryPath)
        let providerStatus = runtimeStatus?.providerStatus(providerID)
        let controlMode = LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: providerStatus
        )
        let providerReady = runtimeStatus?.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false
        let supportsWarmup = controlMode == .warmable && (providerStatus?.supportsWarmup(forModelTaskKinds: model.taskKinds) ?? false)
        let supportsUnload = LocalRuntimeProviderPolicy.supportsUnload(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: providerStatus
        )
        let supportsBench = !LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: runtimeStatus
        ).isEmpty
        return LocalModelRuntimePresentation(
            providerID: providerID,
            controlMode: controlMode,
            lifecycleMode: providerStatus?.lifecycleMode ?? "",
            residencyScope: providerStatus?.residencyScope ?? "",
            providerReady: providerReady,
            supportsWarmup: supportsWarmup,
            supportsUnload: supportsUnload,
            supportsBench: supportsBench
        )
    }
}
