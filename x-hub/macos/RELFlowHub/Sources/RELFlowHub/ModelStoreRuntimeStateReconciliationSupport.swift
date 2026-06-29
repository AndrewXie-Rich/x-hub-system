import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated static func reconciledLocalRuntimeState(
        _ snapshot: ModelStateSnapshot,
        runtimeStatus: AIRuntimeStatus?,
        pendingByModelId: [String: PendingCommand],
        successfulLocalLifecycleActionsByModelId: [String: SuccessfulLocalLifecycleAction] = [:],
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> ModelStateSnapshot {
        guard !snapshot.models.isEmpty else { return snapshot }

        let loadedByProvider = loadedLocalModelIDsByProvider(runtimeStatus)
        var models = snapshot.models
        var changed = false

        for index in models.indices {
            let model = models[index]
            guard !LocalModelRuntimeActionPlanner.isRemoteModel(model) else { continue }

            let providerID = LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model)
            let runtimeLoaded = loadedByProvider[providerID]?.contains(model.id) ?? false
            let pendingAction = pendingByModelId[model.id]?.action
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            let shouldHoldLoadedState = ["load", "warmup", "bench", "prepare_local_model"].contains(pendingAction)
            let lifecycleHint = activeLifecycleStateHint(
                successfulLocalLifecycleActionsByModelId[model.id],
                runtimeStatus: runtimeStatus,
                now: now
            )
            let shouldPreferLoadedState = lifecycleHint == "load" || lifecycleHint == "warmup"
            let shouldPreferAvailableState = lifecycleHint == "unload" || lifecycleHint == "evict"

            if runtimeLoaded, !shouldPreferAvailableState {
                if models[index].state != .loaded {
                    models[index].state = .loaded
                    changed = true
                }
                continue
            }

            if shouldPreferLoadedState {
                if models[index].state != .loaded {
                    models[index].state = .loaded
                    changed = true
                }
                continue
            }

            guard models[index].state == .loaded, !shouldHoldLoadedState else { continue }
            models[index].state = .available
            models[index].memoryBytes = nil
            models[index].tokensPerSec = nil
            changed = true
        }

        guard changed else { return snapshot }
        return ModelStateSnapshot(
            models: models,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    nonisolated static func activeLifecycleStateHint(
        _ action: SuccessfulLocalLifecycleAction?,
        runtimeStatus: AIRuntimeStatus?,
        now: TimeInterval
    ) -> String? {
        guard let action else { return nil }
        let normalizedAction = action.action
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard ["load", "warmup", "unload", "evict"].contains(normalizedAction) else { return nil }
        guard (now - action.finishedAt) <= successfulLifecycleActionGraceSec else { return nil }
        if let runtimeStatus, runtimeStatus.updatedAt >= action.finishedAt {
            return nil
        }
        return normalizedAction
    }

    nonisolated private static func loadedLocalModelIDsByProvider(
        _ runtimeStatus: AIRuntimeStatus?
    ) -> [String: Set<String>] {
        guard let runtimeStatus, runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else { return [:] }

        var loadedByProvider: [String: Set<String>] = [:]
        for providerStatus in runtimeStatus.providers.values {
            let providerID = providerStatus.provider
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !providerID.isEmpty else { continue }

            var loaded = Set(
                providerStatus.loadedModels
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            for instance in providerStatus.loadedInstances {
                let modelID = instance.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !modelID.isEmpty {
                    loaded.insert(modelID)
                }
            }
            loadedByProvider[providerID] = loaded
        }
        return loadedByProvider
    }

}
