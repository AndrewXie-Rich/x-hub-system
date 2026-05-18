import Foundation
import RELFlowHubCore

@MainActor
enum RemoteKeyHealthScanner {
    enum ScanMode: Equatable {
        case quick
        case full
    }

    struct KeyGroup: Equatable {
        let keyReference: String
        let backend: String
        let providerHost: String?
        let models: [RemoteModelEntry]
    }

    struct ModelScanResult: Equatable {
        let modelID: String
        let providerModelID: String
        let state: RemoteKeyHealthState
        let category: ModelTrialCategory
        let detail: String
        let retryAtText: String?

        var isHealthy: Bool {
            state == .healthy
        }
    }

    struct ScanReport: Equatable {
        let record: RemoteKeyHealthRecord
        let modelResults: [ModelScanResult]
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
        previous: RemoteKeyHealthRecord? = nil,
        mode: ScanMode = .quick
    ) async -> RemoteKeyHealthRecord {
        await scanReport(group: group, previous: previous, mode: mode).record
    }

    static func scanReport(
        group: KeyGroup,
        previous: RemoteKeyHealthRecord? = nil,
        mode: ScanMode = .quick
    ) async -> ScanReport {
        let checkedAt = Date().timeIntervalSince1970

        switch mode {
        case .quick:
            return await quickScanReport(
                group: group,
                previous: previous,
                checkedAt: checkedAt
            )
        case .full:
            return await fullScanReport(
                group: group,
                previous: previous,
                checkedAt: checkedAt
            )
        }
    }

    private static func quickScanReport(
        group: KeyGroup,
        previous: RemoteKeyHealthRecord?,
        checkedAt: TimeInterval
    ) async -> ScanReport {
        guard let canary = canaryModel(for: group) else {
            return ScanReport(
                record: RemoteKeyHealthRecord(
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
                ),
                modelResults: []
            )
        }

        let result = await scanModel(
            canary,
            allowDisabledModelLookup: true
        )
        let record: RemoteKeyHealthRecord
        if result.isHealthy {
            record = RemoteKeyHealthRecord(
                keyReference: group.keyReference,
                backend: group.backend,
                providerHost: group.providerHost,
                canaryModelID: result.providerModelID,
                state: .healthy,
                summary: HubUIStrings.Settings.RemoteModels.healthHealthyBadge,
                detail: HubUIStrings.Settings.RemoteModels.healthHealthyDetail(result.providerModelID),
                retryAtText: nil,
                lastCheckedAt: checkedAt,
                lastSuccessAt: checkedAt
            )
        } else {
            record = RemoteKeyHealthRecord(
                keyReference: group.keyReference,
                backend: group.backend,
                providerHost: group.providerHost,
                canaryModelID: result.providerModelID,
                state: result.state,
                summary: summary(for: result.state),
                detail: result.detail,
                retryAtText: result.retryAtText,
                lastCheckedAt: checkedAt,
                lastSuccessAt: previous?.lastSuccessAt
            )
        }

        return ScanReport(
            record: record,
            modelResults: [result]
        )
    }

    private static func fullScanReport(
        group: KeyGroup,
        previous: RemoteKeyHealthRecord?,
        checkedAt: TimeInterval
    ) async -> ScanReport {
        let modelResults = await fullScanModelResults(for: group)

        guard !modelResults.isEmpty else {
            return ScanReport(
                record: RemoteKeyHealthRecord(
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
                ),
                modelResults: []
            )
        }

        let healthyResults = modelResults.filter(\.isHealthy)
        let failedResults = modelResults.filter { !$0.isHealthy }
        let leadSuccess = healthyResults.first
        let leadFailure = preferredFailureResult(from: failedResults)

        let aggregateState: RemoteKeyHealthState
        if failedResults.isEmpty {
            aggregateState = .healthy
        } else if !healthyResults.isEmpty {
            aggregateState = .degraded
        } else {
            aggregateState = leadFailure?.state ?? .blockedProvider
        }

        let canaryModelID = (leadSuccess ?? leadFailure)?.providerModelID
        let retryAtText = leadFailure?.retryAtText ?? firstRetryText(in: failedResults)
        let detail = aggregateDetail(
            aggregateState: aggregateState,
            modelResults: modelResults,
            leadFailure: leadFailure
        )

        return ScanReport(
            record: RemoteKeyHealthRecord(
                keyReference: group.keyReference,
                backend: group.backend,
                providerHost: group.providerHost,
                canaryModelID: canaryModelID,
                state: aggregateState,
                summary: summary(for: aggregateState),
                detail: detail,
                retryAtText: retryAtText,
                lastCheckedAt: checkedAt,
                lastSuccessAt: healthyResults.isEmpty ? previous?.lastSuccessAt : checkedAt
            ),
            modelResults: modelResults
        )
    }

    private static func fullScanModelResults(
        for group: KeyGroup
    ) async -> [ModelScanResult] {
        var results: [ModelScanResult] = []
        for model in group.models {
            results.append(
                await scanModel(
                    model,
                    allowDisabledModelLookup: true
                )
            )
        }
        return results
    }

    private static func resolvedRetryAtText(
        from detail: String,
        category: ModelTrialCategory? = nil,
        state: RemoteKeyHealthState,
        canary: RemoteModelEntry
    ) async -> String? {
        await RemoteRetryTimeSupport.retryAtText(
            from: detail,
            category: category,
            state: state,
            model: canary
        )
    }

    private static func scanModel(
        _ model: RemoteModelEntry,
        allowDisabledModelLookup: Bool
    ) async -> ModelScanResult {
        let providerModelID = model.effectiveProviderModelID
        var candidate = model
        candidate.enabled = true

        guard RemoteModelStorage.isExecutionReadyRemoteModel(candidate) else {
            let detail = configurationFailureReason(for: model)
            return ModelScanResult(
                modelID: model.id,
                providerModelID: providerModelID,
                state: .blockedConfig,
                category: .config,
                detail: detail,
                retryAtText: nil
            )
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: model.id,
            allowDisabledModelLookup: allowDisabledModelLookup,
            prompt: probePrompt,
            maxTokens: 8,
            temperature: 0.0,
            topP: 1.0,
            timeoutSec: 18.0
        )

        if result.ok {
            return ModelScanResult(
                modelID: model.id,
                providerModelID: providerModelID,
                state: .healthy,
                category: .success,
                detail: HubUIStrings.Settings.RemoteModels.healthHealthyDetail(providerModelID),
                retryAtText: nil
            )
        }

        let detail = humanizedFailureDetail(result)
        let projection = RemoteProviderKeyRuntimeFeedbackSupport.failureProjection(
            accountKey: result.accountKey,
            provider: result.provider,
            modelID: result.modelID.isEmpty ? model.id : result.modelID,
            status: result.status,
            error: result.error,
            detail: detail,
            latencyMs: result.latencyMs,
            occurredAtMs: result.occurredAtMs
        )
        let category = projection.category
        let state = projection.state
        let retryAtText = await resolvedRetryAtText(
            from: detail,
            category: category,
            state: state,
            canary: model
        )
        return ModelScanResult(
            modelID: model.id,
            providerModelID: providerModelID,
            state: state,
            category: category,
            detail: detail,
            retryAtText: retryAtText
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

    private static func configurationFailureReason(for model: RemoteModelEntry) -> String {
        if trimmed(model.apiKey).isEmpty && trimmed(model.apiKeyCiphertext).isEmpty {
            return HubUIStrings.Settings.RemoteModels.healthMissingAPIKeyDetail
        }
        if !hasValidBaseURL(model.baseURL) {
            return HubUIStrings.Settings.RemoteModels.healthInvalidBaseURLDetail
        }
        if trimmed(model.id).isEmpty || trimmed(model.effectiveProviderModelID).isEmpty {
            return HubUIStrings.Settings.RemoteModels.healthNoRunnableModelDetail
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

    private static func preferredFailureResult(
        from results: [ModelScanResult]
    ) -> ModelScanResult? {
        results.sorted { lhs, rhs in
            let lhsPriority = healthPriority(for: lhs.state)
            let rhsPriority = healthPriority(for: rhs.state)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.providerModelID.localizedCaseInsensitiveCompare(rhs.providerModelID) == .orderedAscending
        }
        .first
    }

    private static func healthPriority(for state: RemoteKeyHealthState) -> Int {
        switch state {
        case .healthy:
            return 0
        case .degraded:
            return 1
        case .blockedQuota:
            return 4
        case .blockedNetwork:
            return 5
        case .blockedProvider:
            return 6
        case .blockedAuth:
            return 7
        case .blockedConfig:
            return 8
        case .unknownStale:
            return 9
        }
    }

    private static func firstRetryText(
        in results: [ModelScanResult]
    ) -> String? {
        results
            .compactMap { result in
                let value = (result.retryAtText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            .first
    }

    private static func aggregateDetail(
        aggregateState: RemoteKeyHealthState,
        modelResults: [ModelScanResult],
        leadFailure: ModelScanResult?
    ) -> String {
        let total = modelResults.count
        let healthyCount = modelResults.filter(\.isHealthy).count
        let blockedCount = max(0, total - healthyCount)

        var parts: [String] = [
            "全量扫描：已检测 \(total) 个模型，\(healthyCount) 个可用，\(blockedCount) 个不可用。"
        ]

        if aggregateState == .healthy {
            parts.append("所有模型都通过了执行链路检查。")
            return HubUIStrings.Settings.RemoteModels.detailSummary(parts)
        }

        if aggregateState == .degraded {
            parts.append("这把 key 只有部分模型可执行，Hub 会保留结果到各模型行。")
        }

        if let leadFailure {
            parts.append("主要阻塞：\(leadFailure.providerModelID) · \(leadFailure.detail)")
            let extraFailureCount = max(0, blockedCount - 1)
            if extraFailureCount > 0 {
                parts.append("另有 \(extraFailureCount) 个失败结果已写到各模型行。")
            }
        }

        return HubUIStrings.Settings.RemoteModels.detailSummary(parts)
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
