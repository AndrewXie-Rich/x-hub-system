import Foundation
import RELFlowHubCore

@MainActor
enum RemoteKeyHealthScanner {
    struct KeyGroup: Equatable {
        let keyReference: String
        let backend: String
        let providerHost: String?
        let models: [RemoteModelEntry]
    }

    private static let probePrompt = "Reply with OK only."

    static func groups(
        from models: [RemoteModelEntry],
        limitingTo keyReferences: Set<String>? = nil
    ) -> [KeyGroup] {
        let grouped = Dictionary(grouping: models) { entry in
            RemoteModelStorage.keyReference(for: entry)
        }

        return grouped.compactMap { keyReference, entries in
            let normalizedKey = keyReference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else { return nil }
            if let keyReferences, !keyReferences.contains(normalizedKey) {
                return nil
            }
            guard let first = entries.first else { return nil }
            return KeyGroup(
                keyReference: normalizedKey,
                backend: RemoteProviderEndpoints.canonicalBackend(first.backend),
                providerHost: RemoteModelPresentationSupport.endpointHost(for: first),
                models: RemoteModelPresentationSupport.sorted(entries)
            )
        }
        .sorted { lhs, rhs in
            if lhs.backend != rhs.backend {
                return lhs.backend < rhs.backend
            }
            return lhs.keyReference.localizedCaseInsensitiveCompare(rhs.keyReference) == .orderedAscending
        }
    }

    static func scan(
        group: KeyGroup,
        previous: RemoteKeyHealthRecord? = nil
    ) async -> RemoteKeyHealthRecord {
        let checkedAt = Date().timeIntervalSince1970

        guard let canary = canaryModel(for: group) else {
            return RemoteKeyHealthRecord(
                keyReference: group.keyReference,
                backend: group.backend,
                providerHost: group.providerHost,
                canaryModelID: group.models.first?.effectiveProviderModelID,
                state: .blockedConfig,
                summary: HubUIStrings.Settings.RemoteModels.healthConfigBadge,
                detail: configurationFailureReason(for: group),
                retryAtText: nil,
                lastCheckedAt: checkedAt,
                lastSuccessAt: previous?.lastSuccessAt
            )
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: canary.id,
            allowDisabledModelLookup: true,
            prompt: probePrompt,
            maxTokens: 8,
            temperature: 0.0,
            topP: 1.0,
            timeoutSec: 18.0
        )

        if result.ok {
            return RemoteKeyHealthRecord(
                keyReference: group.keyReference,
                backend: group.backend,
                providerHost: group.providerHost,
                canaryModelID: canary.effectiveProviderModelID,
                state: .healthy,
                summary: HubUIStrings.Settings.RemoteModels.healthHealthyBadge,
                detail: HubUIStrings.Settings.RemoteModels.healthHealthyDetail(canary.effectiveProviderModelID),
                retryAtText: nil,
                lastCheckedAt: checkedAt,
                lastSuccessAt: checkedAt
            )
        }

        let detail = humanizedFailureDetail(result)
        let category = hubClassifyModelTrialFailure(detail)
        let state = healthState(for: category)
        let retryAtText = RemoteProviderClient.usageLimitNotice(from: detail)?.retryAtText
        return RemoteKeyHealthRecord(
            keyReference: group.keyReference,
            backend: group.backend,
            providerHost: group.providerHost,
            canaryModelID: canary.effectiveProviderModelID,
            state: state,
            summary: summary(for: state),
            detail: detail,
            retryAtText: retryAtText,
            lastCheckedAt: checkedAt,
            lastSuccessAt: previous?.lastSuccessAt
        )
    }

    private static func canaryModel(for group: KeyGroup) -> RemoteModelEntry? {
        for entry in group.models {
            var candidate = entry
            candidate.enabled = true
            if RemoteModelStorage.isExecutionReadyRemoteModel(candidate) {
                return entry
            }
        }
        return nil
    }

    private static func configurationFailureReason(for group: KeyGroup) -> String {
        if group.models.allSatisfy({ trimmed($0.apiKey).isEmpty && trimmed($0.apiKeyCiphertext).isEmpty }) {
            return HubUIStrings.Settings.RemoteModels.healthMissingAPIKeyDetail
        }
        if group.models.allSatisfy({ !hasValidBaseURL($0.baseURL) }) {
            return HubUIStrings.Settings.RemoteModels.healthInvalidBaseURLDetail
        }
        return HubUIStrings.Settings.RemoteModels.healthNoRunnableModelDetail
    }

    private static func humanizedFailureDetail(_ result: RemoteModelTrialRunner.TrialResult) -> String {
        let normalizedError = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status > 0 {
            return RemoteProviderClient.userFacingHTTPError(status: result.status, body: normalizedError)
        }
        return RemoteProviderClient.humanizedBridgeFailureReason(normalizedError)
    }

    private static func healthState(for category: ModelTrialCategory) -> RemoteKeyHealthState {
        switch category {
        case .success:
            return .healthy
        case .quota:
            return .blockedQuota
        case .auth:
            return .blockedAuth
        case .network, .timeout:
            return .blockedNetwork
        case .rateLimit:
            return .degraded
        case .config, .unsupported:
            return .blockedConfig
        case .runtime, .failed:
            return .blockedProvider
        case .running:
            return .unknownStale
        }
    }

    private static func summary(for state: RemoteKeyHealthState) -> String {
        switch state {
        case .healthy:
            return HubUIStrings.Settings.RemoteModels.healthHealthyBadge
        case .degraded:
            return HubUIStrings.Settings.RemoteModels.healthDegradedBadge
        case .blockedQuota:
            return HubUIStrings.Settings.RemoteModels.healthQuotaBadge
        case .blockedAuth:
            return HubUIStrings.Settings.RemoteModels.healthAuthBadge
        case .blockedNetwork:
            return HubUIStrings.Settings.RemoteModels.healthNetworkBadge
        case .blockedProvider:
            return HubUIStrings.Settings.RemoteModels.healthProviderBadge
        case .blockedConfig:
            return HubUIStrings.Settings.RemoteModels.healthConfigBadge
        case .unknownStale:
            return HubUIStrings.Settings.RemoteModels.healthStaleBadge
        }
    }

    private static func trimmed(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasValidBaseURL(_ raw: String?) -> Bool {
        let value = trimmed(raw)
        guard !value.isEmpty else { return true }
        guard let components = URLComponents(string: value) else { return false }
        return !(components.scheme ?? "").isEmpty && !(components.host ?? "").isEmpty
    }
}
