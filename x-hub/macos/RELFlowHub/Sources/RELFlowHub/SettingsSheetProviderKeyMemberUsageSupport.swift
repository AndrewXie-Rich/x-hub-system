import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyMemberQuotaText(_ account: ProviderKeyAccount) -> String {
        var parts: [String] = []
        if account.quota.usageWindows.isEmpty,
           account.quota.dailyTokensUsed > 0 || account.quota.dailyTokenCap > 0 {
            parts.append(
                HubUIStrings.Settings.ProviderKeys.dailyUsageText(
                    used: account.quota.dailyTokensUsed,
                    cap: account.quota.dailyTokenCap
                )
            )
        }
        if account.quota.totalTokensUsed > 0 {
            parts.append("累计 \(HubUIStrings.Settings.ProviderKeys.tokenCount(account.quota.totalTokensUsed))")
        }
        if !account.quota.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(account.quota.reason)
        }
        if let nextRecover = providerKeyTimestampSummary(
            max(account.quota.nextRecoverAtMs, account.quota.cooldownUntilMs),
            prefix: "恢复"
        ) {
            parts.append(nextRecover)
        }
        if let nextRefresh = providerKeyTimestampSummary(
            account.refreshState.nextRefreshAtMs,
            prefix: "下次刷新"
        ) {
            parts.append(nextRefresh)
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyMemberHeatLabel(_ account: ProviderKeyAccount) -> String {
        let fraction = providerKeyUsageFraction(
            used: account.quota.dailyTokensUsed,
            cap: account.quota.dailyTokenCap
        )
        switch fraction {
        case let value where value >= 0.95:
            return "热度 见底"
        case let value where value >= 0.8:
            return "热度 高"
        case let value where value >= 0.45:
            return "热度 中"
        case let value where value > 0:
            return "热度 低"
        default:
            return "热度 空闲"
        }
    }

    func providerKeyPoolRemainingSummary(_ pool: ProviderKeyPoolSnapshot) -> String {
        var parts: [String] = []
        if pool.totalDailyTokenCap > 0 {
            parts.append(
                "剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(max(Int64(0), pool.totalDailyTokensRemaining))) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(pool.totalDailyTokenCap)) tokens"
            )
        } else if pool.totalDailyTokensRemaining > 0 {
            parts.append("剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(pool.totalDailyTokensRemaining)) tokens")
        }
        if let lastUsed = providerKeyTimestampSummary(
            pool.members.map(\.account.quota.lastUsedAtMs).max() ?? 0,
            prefix: "最近使用"
        ) {
            parts.append(lastUsed)
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyMemberUsageMetaText(_ account: ProviderKeyAccount) -> String {
        var parts: [String] = []
        if account.quota.usageWindows.isEmpty {
            if account.quota.dailyTokenCap > 0 {
                parts.append(
                    "剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(max(Int64(0), account.quota.dailyTokensRemaining))) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(account.quota.dailyTokenCap)) tokens"
                )
            } else if account.quota.dailyTokensRemaining > 0 {
                parts.append("剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(account.quota.dailyTokensRemaining)) tokens")
            }
        }
        if let lastUsed = providerKeyTimestampSummary(account.quota.lastUsedAtMs, prefix: "最近使用") {
            parts.append(lastUsed)
        }
        if let lastRefresh = providerKeyTimestampSummary(
            max(account.lastRefreshAtMs, account.refreshState.lastSuccessAtMs),
            prefix: "上次刷新"
        ) {
            parts.append(lastRefresh)
        }
        if account.refreshState.failureCount > 0 {
            parts.append("刷新失败 \(account.refreshState.failureCount) 次")
        }
        if !account.refreshState.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           account.refreshState.status != "idle" {
            parts.append("刷新状态 \(account.refreshState.status)")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }
}
