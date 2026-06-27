import Foundation
import RELFlowHubCore

enum LocalModelRuntimeActionRoute: Equatable {
    case legacyModelCommand(action: String)
    case providerLifecycleCommand(action: String)
    case immediateFailure(message: String)
}

struct LocalModelRuntimePresentation: Equatable {
    var providerID: String
    var controlMode: AIRuntimeProviderHubControlMode
    var lifecycleMode: String
    var residencyScope: String
    var providerReady: Bool
    var supportsWarmup: Bool
    var supportsUnload: Bool
    var supportsBench: Bool

    var badgeTitle: String {
        switch controlMode {
        case .mlxLegacy:
            return HubUIStrings.Models.Runtime.ActionPlanner.mlxLegacyBadge
        case .warmable:
            return HubUIStrings.Models.Runtime.ActionPlanner.warmableBadge
        case .ephemeralOnDemand:
            return HubUIStrings.Models.Runtime.ActionPlanner.onDemandBadge
        }
    }

    var badgeSystemName: String {
        switch controlMode {
        case .mlxLegacy:
            return "cpu"
        case .warmable:
            return "flame"
        case .ephemeralOnDemand:
            return "bolt.horizontal"
        }
    }
}

struct LocalModelRuntimeTargetOption: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case auto
        case pairedDevice = "paired_device"
        case loadedInstance = "loaded_instance"
    }

    var kind: Kind
    var deviceID: String
    var instanceKey: String
    var title: String
    var detail: String

    var id: String {
        "\(kind.rawValue)::\(deviceID)::\(instanceKey)"
    }

    var isAuto: Bool {
        kind == .auto
    }
}

struct ModelCapacitySnapshot: Equatable {
    var usedMemoryBytes: Int64
    var budgetMemoryBytes: Int64

    static let empty = ModelCapacitySnapshot(
        usedMemoryBytes: 0,
        budgetMemoryBytes: 1
    )

    var percent: Double {
        let used = Double(max(0, usedMemoryBytes))
        let budget = Double(max(1, budgetMemoryBytes))
        return max(0.0, min(1.0, used / budget))
    }
}

struct LocalModelQuickBenchPreparationPlan: Equatable {
    var requestContext: LocalModelRuntimeRequestContext
    var requiresWarmup: Bool
}

enum LocalModelQuickBenchPlanner {
    static func prepare(
        model: HubModel,
        taskKind: String,
        runtimeStatus: AIRuntimeStatus?,
        requestContext: LocalModelRuntimeRequestContext
    ) -> LocalModelQuickBenchPreparationPlan {
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let providerStatus = runtimeStatus?.providerStatus(providerID)
        let controlMode = LocalRuntimeProviderPolicy.resolvedControlMode(
            providerID: providerID,
            taskKinds: model.taskKinds,
            providerStatus: providerStatus
        )
        guard controlMode == .warmable,
              let providerStatus,
              providerStatus.supportsWarmup(forModelTaskKinds: model.taskKinds),
              !matchesResidentTarget(
                modelID: model.id,
                taskKind: taskKind,
                requestContext: requestContext,
                loadedInstances: providerStatus.loadedInstances
              ) else {
            return LocalModelQuickBenchPreparationPlan(
                requestContext: requestContext,
                requiresWarmup: false
            )
        }

        return LocalModelQuickBenchPreparationPlan(
            requestContext: requestContext,
            requiresWarmup: true
        )
    }

    static func updatedRequestContext(
        fromWarmupPayload payload: [String: Any],
        fallback: LocalModelRuntimeRequestContext
    ) -> LocalModelRuntimeRequestContext {
        let resolvedInstanceKey = (payload["instanceKey"] as? String ?? payload["instance_key"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLoadProfileHash = (payload["loadProfileHash"] as? String ?? payload["load_profile_hash"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedContextLength = max(
            0,
            payload["effectiveContextLength"] as? Int
                ?? payload["effective_context_length"] as? Int
                ?? fallback.effectiveContextLength
        )
        return LocalModelRuntimeRequestContext(
            providerID: fallback.providerID,
            modelID: fallback.modelID,
            deviceID: fallback.deviceID,
            instanceKey: resolvedInstanceKey,
            loadProfileHash: resolvedLoadProfileHash,
            predictedLoadProfileHash: !resolvedLoadProfileHash.isEmpty
                ? resolvedLoadProfileHash
                : fallback.predictedLoadProfileHash,
            effectiveContextLength: resolvedContextLength,
            loadProfileOverride: fallback.loadProfileOverride,
            effectiveLoadProfile: updatedEffectiveLoadProfile(
                fallback.effectiveLoadProfile,
                contextLength: resolvedContextLength
            ),
            source: "bench_auto_warmup"
        )
    }

    private static func updatedEffectiveLoadProfile(
        _ profile: LocalModelLoadProfile?,
        contextLength: Int
    ) -> LocalModelLoadProfile? {
        guard let profile else {
            guard contextLength > 0 else { return nil }
            return LocalModelLoadProfile(contextLength: contextLength)
        }
        let resolvedContextLength = contextLength > 0 ? contextLength : profile.contextLength
        return LocalModelLoadProfile(
            contextLength: resolvedContextLength,
            gpuOffloadRatio: profile.gpuOffloadRatio,
            ropeFrequencyBase: profile.ropeFrequencyBase,
            ropeFrequencyScale: profile.ropeFrequencyScale,
            evalBatchSize: profile.evalBatchSize,
            ttl: profile.ttl,
            parallel: profile.parallel,
            identifier: profile.identifier,
            vision: profile.vision
        )
    }

    private static func matchesResidentTarget(
        modelID: String,
        taskKind: String,
        requestContext: LocalModelRuntimeRequestContext,
        loadedInstances: [AIRuntimeLoadedInstance]
    ) -> Bool {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return loadedInstances.contains { loaded in
            guard loaded.modelId == modelID else { return false }
            if !normalizedTaskKind.isEmpty,
               !loaded.taskKinds.isEmpty,
               !loaded.taskKinds.contains(normalizedTaskKind) {
                return false
            }
            if !requestContext.instanceKey.isEmpty {
                return loaded.instanceKey == requestContext.instanceKey
            }
            if !requestContext.preferredBenchHash.isEmpty,
               !loaded.loadProfileHash.isEmpty {
                return loaded.loadProfileHash == requestContext.preferredBenchHash
            }
            if requestContext.effectiveContextLength > 0,
               loaded.effectiveContextLength > 0 {
                return loaded.effectiveContextLength == requestContext.effectiveContextLength
            }
            return true
        }
    }
}

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
