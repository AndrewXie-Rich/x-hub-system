import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated static func reconciledLastCommandResults(
        _ results: [String: ModelCommandResult],
        snapshot: ModelStateSnapshot,
        runtimeStatus: AIRuntimeStatus?
    ) -> [String: ModelCommandResult] {
        guard !results.isEmpty,
              let runtimeStatus,
              runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return results
        }

        let modelByID = Dictionary(uniqueKeysWithValues: snapshot.models.map { ($0.id, $0) })
        return results.filter { modelId, result in
            !shouldClearRecoveredRuntimeFailure(
                result,
                model: modelByID[modelId],
                runtimeStatus: runtimeStatus
            )
        }
    }

    nonisolated static func shouldClearRecoveredRuntimeFailure(
        _ result: ModelCommandResult,
        model: HubModel?,
        runtimeStatus: AIRuntimeStatus
    ) -> Bool {
        guard !result.ok else { return false }

        let action = result.action
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard ["load", "warmup", "unload", "evict", "bench"].contains(action) else {
            return false
        }

        let message = result.msg.trimmingCharacters(in: .whitespacesAndNewlines)
        if message == LocalModelRuntimeActionPlanner.runtimeStartMessage {
            return true
        }

        guard let model else { return false }
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        guard runtimeStatus.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return false
        }

        let providerUnavailablePrefix = "AI 运行时已启动，但 \(providerID) provider 当前不可用"
        return message.hasPrefix(providerUnavailablePrefix)
    }
}
