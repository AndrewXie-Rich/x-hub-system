import Foundation
import RELFlowHubCore

enum LocalModelHealthScanMode: Equatable, Sendable {
    case preflightOnly
    case full
}

@MainActor
enum LocalModelHealthScanner {
    typealias ReadinessResolver = (HubModel) -> LocalLibraryRuntimeReadiness
    typealias TrialRunner = (HubModel) async throws -> String

    static func scan(
        model: HubModel,
        mode: LocalModelHealthScanMode = .full,
        previous: LocalModelHealthRecord? = nil,
        readinessResolver: ReadinessResolver,
        trialRunner: @escaping TrialRunner
    ) async -> LocalModelHealthRecord {
        let checkedAt = Date().timeIntervalSince1970
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let readiness = readinessResolver(model)

        guard readiness.state == .ready else {
            let detail = normalizedDetail(
                readiness.detail,
                fallback: HubUIStrings.Models.LocalHealth.readinessBlockedFallback
            )
            return LocalModelHealthRecord(
                modelId: model.id,
                providerID: providerID,
                state: .blockedReadiness,
                summary: HubUIStrings.Models.LocalHealth.discouragedBadge,
                detail: detail,
                lastCheckedAt: checkedAt,
                lastSuccessAt: previous?.lastSuccessAt
            )
        }

        if mode == .preflightOnly {
            let priorState = previous?.state
            let state: LocalModelHealthState = priorState == .healthy ? .healthy : .degraded
            return LocalModelHealthRecord(
                modelId: model.id,
                providerID: providerID,
                state: state,
                summary: summary(for: state),
                detail: HubUIStrings.Models.LocalHealth.preflightPassedDetail,
                lastCheckedAt: checkedAt,
                lastSuccessAt: previous?.lastSuccessAt
            )
        }

        do {
            let trialDetail = normalizedDetail(
                try await trialRunner(model),
                fallback: HubUIStrings.Models.LocalHealth.smokePassedFallback
            )
            return LocalModelHealthRecord(
                modelId: model.id,
                providerID: providerID,
                state: .healthy,
                summary: HubUIStrings.Models.LocalHealth.recommendedBadge,
                detail: HubUIStrings.Models.LocalHealth.smokePassedDetail(trialDetail),
                lastCheckedAt: checkedAt,
                lastSuccessAt: checkedAt
            )
        } catch {
            let failureDetail = normalizedDetail(
                LocalLibraryRuntimeReadinessResolver.collapsedDetail(error.localizedDescription),
                fallback: HubUIStrings.Models.LocalHealth.runtimeBlockedFallback
            )
            let category = hubClassifyModelTrialFailure(failureDetail)
            let state = healthState(for: category)
            return LocalModelHealthRecord(
                modelId: model.id,
                providerID: providerID,
                state: state,
                summary: summary(for: state),
                detail: failureDetail,
                lastCheckedAt: checkedAt,
                lastSuccessAt: previous?.lastSuccessAt
            )
        }
    }

    private static func healthState(for category: ModelTrialCategory) -> LocalModelHealthState {
        switch category {
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

    private static func normalizedDetail(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
