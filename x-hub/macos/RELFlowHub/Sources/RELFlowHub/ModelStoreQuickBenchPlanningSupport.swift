import Foundation
import RELFlowHubCore

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
