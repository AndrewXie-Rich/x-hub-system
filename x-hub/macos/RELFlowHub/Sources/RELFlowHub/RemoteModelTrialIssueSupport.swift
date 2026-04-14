import Foundation

struct RemoteKeyUsageLimitNotice: Equatable {
    let retryAtText: String?
    let suggestsPlusUpgrade: Bool

    var badgeText: String {
        HubUIStrings.Settings.RemoteModels.usageLimitBadge
    }

    var detailText: String {
        if let retryAtText, !retryAtText.isEmpty {
            if suggestsPlusUpgrade {
                return HubUIStrings.Settings.RemoteModels.usageLimitUpgradeRetryDetail(retryAtText)
            }
            return HubUIStrings.Settings.RemoteModels.usageLimitRetryDetail(retryAtText)
        }
        if suggestsPlusUpgrade {
            return HubUIStrings.Settings.RemoteModels.usageLimitUpgradeDetail
        }
        return HubUIStrings.Settings.RemoteModels.usageLimitDetail
    }
}

enum RemoteModelTrialIssueSupport {
    static func latestUsageLimitNotice(in statuses: [ModelTrialStatus]) -> RemoteKeyUsageLimitNotice? {
        statuses
            .filter { !$0.isRunning }
            .sorted { $0.updatedAt > $1.updatedAt }
            .compactMap(usageLimitNotice(from:))
            .first
    }

    static func usageLimitNotice(from status: ModelTrialStatus) -> RemoteKeyUsageLimitNotice? {
        let detail = status.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty,
              let usageLimit = RemoteProviderClient.usageLimitNotice(from: detail) else {
            return nil
        }
        return RemoteKeyUsageLimitNotice(
            retryAtText: usageLimit.retryAtText,
            suggestsPlusUpgrade: usageLimit.suggestsPlusUpgrade
        )
    }
}
