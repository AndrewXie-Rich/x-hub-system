import Foundation
import RELFlowHubCore

enum LocalModelHealthRuntimeInvalidationPolicy {
    static func revalidatedSnapshot(
        _ snapshot: LocalModelHealthSnapshot,
        models: [HubModel],
        runtimeStatus: AIRuntimeStatus?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> LocalModelHealthSnapshot {
        let modelsByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        var changed = false
        let records = snapshot.records.map { record -> LocalModelHealthRecord in
            guard let revalidated = revalidatedRecord(
                record,
                model: modelsByID[record.modelId],
                runtimeStatus: runtimeStatus,
                now: now
            ) else {
                return record
            }
            changed = true
            return revalidated
        }
        guard changed else { return snapshot }
        return LocalModelHealthSnapshot(records: records, updatedAt: now)
    }

    static func revalidatedRecord(
        _ record: LocalModelHealthRecord,
        model: HubModel?,
        runtimeStatus: AIRuntimeStatus?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> LocalModelHealthRecord? {
        guard shouldInvalidate(record, model: model, runtimeStatus: runtimeStatus) else {
            return nil
        }
        let providerID = normalizedProviderID(record: record, model: model)
        return LocalModelHealthRecord(
            modelId: record.modelId,
            providerID: providerID,
            state: .degraded,
            summary: HubUIStrings.Models.LocalHealth.reviewBadge,
            detail: HubUIStrings.Models.LocalHealth.runtimeRevalidatedDetail,
            lastCheckedAt: now,
            lastSuccessAt: record.lastSuccessAt
        )
    }

    private static func shouldInvalidate(
        _ record: LocalModelHealthRecord,
        model: HubModel?,
        runtimeStatus: AIRuntimeStatus?
    ) -> Bool {
        switch record.state {
        case .blockedReadiness, .blockedRuntime:
            break
        case .healthy, .degraded, .unknownStale:
            return false
        }

        guard let runtimeStatus,
              runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return false
        }

        let providerID = normalizedProviderID(record: record, model: model)
        guard runtimeStatus.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
              let providerStatus = runtimeStatus.providerStatus(providerID) else {
            return false
        }

        let statusUpdatedAt = max(providerStatus.updatedAt, runtimeStatus.updatedAt)
        guard statusUpdatedAt > record.lastCheckedAt + 1 else {
            return false
        }

        if let model,
           LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(action: "load", model: model) != nil {
            return false
        }

        if normalized(record.providerID) != providerID {
            return true
        }
        return detailLooksRuntimeScoped(record.detail)
    }

    private static func normalizedProviderID(record: LocalModelHealthRecord, model: HubModel?) -> String {
        let providerID = model.map { LocalModelRuntimeActionPlanner.providerID(for: $0) } ?? record.providerID
        return normalized(providerID)
    }

    private static func detailLooksRuntimeScoped(_ detail: String) -> Bool {
        let text = detail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        let needles = [
            "provider 当前不可用",
            "provider runtime unavailable",
            "runtime unavailable",
            "runtime_missing",
            "helper_probe_failed",
            "helper_service",
            "lms_daemon",
            "缺少 torch",
            "missing torch",
            "python 运行时",
            "transformers provider",
            "mlx provider",
            "llama.cpp provider",
        ]
        return needles.contains { text.contains($0.lowercased()) }
    }

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
