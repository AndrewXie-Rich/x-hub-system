import Foundation
import RELFlowHubCore

extension ModelStore {
    func reconcileSuccessfulLifecycleActionsWithRuntimeStatus(
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        guard !successfulLocalLifecycleActionsByModelId.isEmpty else { return }

        let liveModelIDs = Set(snapshot.models.map(\.id))
        successfulLocalLifecycleActionsByModelId = successfulLocalLifecycleActionsByModelId.filter { modelId, action in
            guard liveModelIDs.contains(modelId) else { return false }
            return Self.activeLifecycleStateHint(
                action,
                runtimeStatus: currentRuntimeStatus,
                now: now
            ) != nil
        }
    }

    func applySuccessfulLocalLifecycleAction(
        action: String,
        modelId: String,
        finishedAt: TimeInterval
    ) {
        let normalizedAction = action
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        successfulLocalLifecycleActionsByModelId[modelId] = SuccessfulLocalLifecycleAction(
            action: normalizedAction,
            finishedAt: finishedAt
        )

        guard let index = snapshot.models.firstIndex(where: { $0.id == modelId }) else { return }
        switch normalizedAction {
        case "warmup", "load":
            snapshot.models[index].state = .loaded
        case "unload", "evict":
            snapshot.models[index].state = .available
            snapshot.models[index].memoryBytes = nil
            snapshot.models[index].tokensPerSec = nil
        default:
            return
        }
        snapshot.updatedAt = finishedAt
        ModelStateStorage.save(snapshot)
    }
}
