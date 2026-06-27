import Foundation
import RELFlowHubCore

enum LocalModelRuntimeActionPlanner {
    static let runtimeStartMessage = HubUIStrings.Models.Runtime.ActionPlanner.runtimeStartMessage

    static func isRemoteModel(_ model: HubModel) -> Bool {
        isRemoteModel(
            model,
            helperBinaryPath: LocalHelperBridgeDiscovery.discoverHelperBinary()
        )
    }

    static func isRemoteModel(_ model: HubModel, helperBinaryPath: String) -> Bool {
        let modelPath = (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelPath.isEmpty {
            return false
        }
        return providerID(for: model, helperBinaryPath: helperBinaryPath) != "mlx"
    }

    static func providerID(for model: HubModel) -> String {
        providerID(
            for: model,
            helperBinaryPath: LocalHelperBridgeDiscovery.discoverHelperBinary()
        )
    }

    static func providerID(for model: HubModel, helperBinaryPath: String) -> String {
        LocalModelExecutionProviderResolver.preferredRuntimeProviderID(
            for: model,
            helperBinaryPath: helperBinaryPath
        )
    }

    static func localModels(from models: [HubModel]) -> [HubModel] {
        guard !models.isEmpty else { return [] }
        let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()
        return models.filter {
            !isRemoteModel($0, helperBinaryPath: helperBinaryPath)
        }
    }

    static func remoteModels(from models: [HubModel]) -> [HubModel] {
        guard !models.isEmpty else { return [] }
        let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()
        return models.filter {
            isRemoteModel($0, helperBinaryPath: helperBinaryPath)
        }
    }

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

    private static func legacyCommandAction(for action: String) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "warmup" {
            return "load"
        }
        return normalized
    }

    private static func providerLifecycleAction(for action: String) -> String? {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "load", "warmup":
            return "warmup_local_model"
        case "unload":
            return "unload_local_model"
        case "evict":
            return "evict_local_instance"
        default:
            return nil
        }
    }

    private static func actionDisplayName(
        _ action: String,
        controlMode: AIRuntimeProviderHubControlMode
    ) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "load":
            return controlMode == .mlxLegacy
                ? HubUIStrings.Models.Runtime.ActionPlanner.load
                : HubUIStrings.Models.Runtime.ActionPlanner.warmup
        case "warmup":
            return HubUIStrings.Models.Runtime.ActionPlanner.warmup
        case "sleep":
            return HubUIStrings.Models.Runtime.ActionPlanner.sleep
        case "unload":
            return HubUIStrings.Models.Runtime.ActionPlanner.unload
        case "bench":
            return HubUIStrings.Models.Runtime.ActionPlanner.bench
        case "evict":
            return HubUIStrings.Models.Runtime.ActionPlanner.evict
        default:
            return normalized.isEmpty ? HubUIStrings.Models.Runtime.ActionPlanner.defaultAction : normalized
        }
    }

    private static func providerUnavailableMessage(
        providerID: String,
        runtimeStatus: AIRuntimeStatus
    ) -> String {
        let providerStatus = runtimeStatus.providerStatus(providerID)
        let reason = (providerStatus?.reasonCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let importError = (providerStatus?.importError ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = LocalModelRuntimeErrorPresentation.humanized(
            !importError.isEmpty ? importError : reason
        )
        let extra = detail.isEmpty ? "" : " (\(detail))"
        return HubUIStrings.Models.Runtime.ActionPlanner.providerUnavailable(
            providerID: providerID,
            extra: extra
        )
    }

    private static func warmableActionUnsupportedMessage(
        action: String,
        providerID: String,
        controlMode: AIRuntimeProviderHubControlMode
    ) -> String {
        let displayAction = actionDisplayName(action, controlMode: controlMode)
        return HubUIStrings.Models.Runtime.ActionPlanner.warmableActionUnsupported(
            providerID: providerID,
            actionTitle: displayAction
        )
    }

    private static func onDemandActionBlockedMessage(
        action: String,
        providerID: String,
        residencyScope: String,
        lifecycleMode: String,
        controlMode: AIRuntimeProviderHubControlMode
    ) -> String {
        let displayAction = actionDisplayName(action, controlMode: controlMode)
        let scope = residencyScope.isEmpty ? "process_local" : residencyScope
        let lifecycle = lifecycleMode.isEmpty ? "ephemeral_on_demand" : lifecycleMode
        return HubUIStrings.Models.Runtime.ActionPlanner.onDemandActionBlocked(
            providerID: providerID,
            lifecycle: lifecycle,
            scope: scope,
            actionTitle: displayAction
        )
    }
}
