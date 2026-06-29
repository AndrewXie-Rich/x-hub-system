import Foundation
import RELFlowHubCore

extension LocalModelRuntimeActionPlanner {
    static func plan(
        action: String,
        model: HubModel,
        runtimeStatus: AIRuntimeStatus?
    ) -> LocalModelRuntimeActionRoute {
        let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()
        guard !isRemoteModel(model, helperBinaryPath: helperBinaryPath) else {
            return .immediateFailure(message: HubUIStrings.Models.Runtime.ActionPlanner.remoteModelControlUnsupported)
        }
        guard let runtimeStatus else {
            return .immediateFailure(message: runtimeStartMessage)
        }
        guard runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return .immediateFailure(message: runtimeStartMessage)
        }

        let providerID = providerID(for: model, helperBinaryPath: helperBinaryPath)
        let resolvedControlMode = LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: runtimeStatus.providerStatus(providerID)
        )
        let presentation = presentation(for: model, runtimeStatus: runtimeStatus)
            ?? LocalModelRuntimePresentation(
                providerID: providerID,
                controlMode: resolvedControlMode,
                lifecycleMode: "",
                residencyScope: "",
                providerReady: false,
                supportsWarmup: false,
                supportsUnload: LocalRuntimeProviderPolicy.supportsUnload(
                    providerID: providerID,
                    taskKinds: model.taskKinds,
                    providerStatus: runtimeStatus.providerStatus(providerID)
                ),
                supportsBench: !LocalModelBenchCapabilityPolicy.benchableDescriptors(for: model).isEmpty
            )

        guard runtimeStatus.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return .immediateFailure(message: providerUnavailableMessage(providerID: providerID, runtimeStatus: runtimeStatus))
        }

        switch presentation.controlMode {
        case .mlxLegacy:
            return .legacyModelCommand(action: legacyCommandAction(for: action))
        case .warmable:
            guard let lifecycleAction = providerLifecycleAction(for: action) else {
                return .immediateFailure(
                    message: warmableActionUnsupportedMessage(
                        action: action,
                        providerID: providerID,
                        controlMode: presentation.controlMode
                    )
                )
            }
            return .providerLifecycleCommand(action: lifecycleAction)
        case .ephemeralOnDemand:
            if action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "unload",
               presentation.supportsUnload,
               let lifecycleAction = providerLifecycleAction(for: action) {
                return .providerLifecycleCommand(action: lifecycleAction)
            }
            return .immediateFailure(
                message: onDemandActionBlockedMessage(
                    action: action,
                    providerID: providerID,
                    residencyScope: presentation.residencyScope,
                    lifecycleMode: presentation.lifecycleMode,
                    controlMode: presentation.controlMode
                )
            )
        }
    }
}
