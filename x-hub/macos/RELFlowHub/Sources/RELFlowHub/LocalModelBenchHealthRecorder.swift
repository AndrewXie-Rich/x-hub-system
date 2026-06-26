import Foundation
import RELFlowHubCore

enum LocalModelBenchHealthRecorder {
    static func updatedSnapshot(
        after result: ModelBenchResult,
        previous snapshot: LocalModelHealthSnapshot,
        model: HubModel?,
        detail: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> LocalModelHealthSnapshot {
        guard let record = healthRecord(
            after: result,
            previous: snapshot.records.first(where: { $0.modelId == result.modelId }),
            model: model,
            detail: detail,
            now: now
        ) else {
            return snapshot
        }

        var records = snapshot.records.filter { $0.modelId != record.modelId }
        records.append(record)
        records.sort { lhs, rhs in
            let lhsPriority = LocalModelHealthSupport.sortPriority(for: lhs, now: now)
            let rhsPriority = LocalModelHealthSupport.sortPriority(for: rhs, now: now)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            let lhsRecency = LocalModelHealthSupport.recency(for: lhs)
            let rhsRecency = LocalModelHealthSupport.recency(for: rhs)
            if lhsRecency != rhsRecency {
                return lhsRecency > rhsRecency
            }
            return lhs.modelId.localizedCaseInsensitiveCompare(rhs.modelId) == .orderedAscending
        }
        return LocalModelHealthSnapshot(records: records, updatedAt: now)
    }

    static func healthRecord(
        after result: ModelBenchResult,
        previous: LocalModelHealthRecord?,
        model: HubModel?,
        detail: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> LocalModelHealthRecord? {
        let modelID = result.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else { return nil }

        let checkedAt = result.measuredAt > 0 ? result.measuredAt : now
        if let previous, previous.lastCheckedAt > checkedAt + 1 {
            return nil
        }

        let providerID = normalizedProviderID(result: result, model: model, previous: previous)
        let state = healthState(for: result, detail: detail)
        let recordDetail = normalizedDetail(for: result, detail: detail)
        return LocalModelHealthRecord(
            modelId: modelID,
            providerID: providerID,
            state: state,
            summary: summary(for: state),
            detail: recordDetail,
            lastCheckedAt: checkedAt,
            lastSuccessAt: result.ok ? checkedAt : previous?.lastSuccessAt
        )
    }

    private static func normalizedProviderID(
        result: ModelBenchResult,
        model: HubModel?,
        previous: LocalModelHealthRecord?
    ) -> String {
        let candidates = [
            model.map { LocalModelRuntimeActionPlanner.providerID(for: $0) } ?? "",
            result.providerID,
            previous?.providerID ?? "",
        ]
        let providerID = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first { !$0.isEmpty } ?? ""
        return providerID.isEmpty ? "local" : providerID
    }

    private static func healthState(for result: ModelBenchResult, detail: String) -> LocalModelHealthState {
        guard !result.ok else { return .healthy }
        switch hubClassifyModelTrialFailure(failureText(for: result, detail: detail)) {
        case .success:
            return .healthy
        case .config, .unsupported:
            return .blockedReadiness
        case .running:
            return .unknownStale
        case .runtime, .failed, .network, .timeout, .auth, .quota, .rateLimit:
            return .blockedRuntime
        }
    }

    private static func normalizedDetail(for result: ModelBenchResult, detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.ok {
            let rawDetail = trimmed.isEmpty ? HubUIStrings.Models.LocalHealth.smokePassedFallback : trimmed
            return HubUIStrings.Models.LocalHealth.smokePassedDetail(rawDetail)
        }
        if !trimmed.isEmpty {
            return trimmed
        }
        let fallback = failureText(for: result, detail: detail).trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? HubUIStrings.Models.LocalHealth.runtimeBlockedFallback : fallback
    }

    private static func failureText(for result: ModelBenchResult, detail: String) -> String {
        let parts = [
            detail,
            result.reasonCode,
            result.runtimeReasonCode,
            result.runtimeHint,
            result.runtimeMissingRequirements.joined(separator: " "),
            result.notes.joined(separator: " "),
        ]
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func summary(for state: LocalModelHealthState) -> String {
        switch state {
        case .healthy:
            return HubUIStrings.Models.LocalHealth.recommendedBadge
        case .degraded, .unknownStale:
            return HubUIStrings.Models.LocalHealth.reviewBadge
        case .blockedReadiness, .blockedRuntime:
            return HubUIStrings.Models.LocalHealth.discouragedBadge
        }
    }
}
