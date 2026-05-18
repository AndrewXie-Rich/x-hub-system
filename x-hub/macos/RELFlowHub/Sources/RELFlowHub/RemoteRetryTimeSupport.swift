import Foundation
import RELFlowHubCore

@MainActor
enum RemoteRetryTimeSupport {
    static func retryAtText(
        from detail: String,
        category: ModelTrialCategory? = nil,
        state: RemoteKeyHealthState? = nil,
        model: RemoteModelEntry
    ) async -> String? {
        if let providerRetryAtText = RemoteProviderClient.usageLimitNotice(from: detail)?.retryAtText,
           !providerRetryAtText.isEmpty {
            return providerRetryAtText
        }

        let apiKey = trimmed(model.apiKey)
        guard !apiKey.isEmpty,
              let credential = ProviderKeyStorage.loadResolvedCredential(
                apiKey: apiKey,
                provider: model.backend,
                baseURL: model.baseURL
              ) else {
            return nil
        }

        return await ProviderKeyRefreshCoordinator.retryDecision(
            from: detail,
            category: category,
            state: state,
            credential: credential
        )?.retryAtText
    }

    static func enrichedDetail(
        _ detail: String,
        category: ModelTrialCategory,
        model: RemoteModelEntry
    ) async -> String {
        let normalized = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return detail }
        guard !normalized.contains("预计下次可用："),
              let retryAtText = await retryAtText(
                from: normalized,
                category: category,
                model: model
              ),
              !retryAtText.isEmpty else {
            return detail
        }

        return HubUIStrings.Settings.RemoteModels.detailSummary([
            normalized,
            "预计下次可用：\(retryAtText)",
        ])
    }

    private static func trimmed(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
