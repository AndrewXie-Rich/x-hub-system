import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyFamilyQuotaSummary(_ family: ProviderKeyFamilyInventorySummary) -> String {
        var parts: [String] = []
        if family.combinedDailyTokenCap > 0 {
            parts.append(
                "上游今日 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokensUsed)) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokenCap)) tokens"
            )
            parts.append("剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokensRemaining))")
        } else if family.combinedDailyTokensUsed > 0 {
            parts.append("上游今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokensUsed)) tokens")
        }
        if family.quotaPool.sharedSources > 0 {
            parts.append(
                HubUIStrings.Settings.ProviderKeys.sharedSourceSummary(
                    count: family.quotaPool.sharedSources,
                    sharedFamilies: family.quotaPool.sharedWithFamilyDisplayNames.joined(separator: ", ")
                )
            )
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyFamilyBudgetSummary(_ family: ProviderKeyFamilyInventorySummary) -> String {
        var parts: [String] = []
        if family.assignedClientCount > 0 {
            parts.append("覆盖 \(family.coveredUserCount) 个用户 / \(family.assignedClientCount) 个消费者")
        }
        if family.connectedAssignedConsumerCount > 0 {
            parts.append("在线 \(family.connectedAssignedConsumerCount)")
        }
        if family.assignedDailyTokenBudget > 0 {
            parts.append("覆盖预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.assignedDailyTokenBudget))")
        }
        if family.unlimitedBudgetConsumerCount > 0 {
            parts.append("\(family.unlimitedBudgetConsumerCount) 个未设硬预算")
        }
        if family.observedDailyTokensUsed > 0 {
            parts.append("今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.observedDailyTokensUsed))")
        }
        if parts.isEmpty {
            parts.append("当前还没有消费者显式使用这个家族")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyFamilyClientPreview(_ family: ProviderKeyFamilyInventorySummary) -> String {
        let previewNames = family.assignedClients.prefix(3).map(\.name)
        guard !previewNames.isEmpty else { return "" }
        let suffix = family.assignedClients.count > previewNames.count
            ? " 等另外 \(family.assignedClients.count - previewNames.count) 个"
            : ""
        return "消费者：\(previewNames.joined(separator: "、"))\(suffix)"
    }

    func providerKeyFamilyRetrySummary(_ family: ProviderKeyFamilyInventorySummary) -> String {
        if let retryText = family.quotaPool.sources
            .flatMap(\.members)
            .map({ $0.account.errorState.retryAtText.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return HubUIStrings.Settings.ProviderKeys.nextRetry(retryText)
        }
        guard family.quotaPool.earliestRetryAtMs > 0 else {
            return HubUIStrings.Settings.ProviderKeys.nextRetryUnknown
        }
        return HubUIStrings.Settings.ProviderKeys.nextRetry(
            formattedProviderKeyImportSourceTime(family.quotaPool.earliestRetryAtMs)
        )
    }

    func providerKeyBudgetClientScopeSummary(_ clientProjection: RemoteQuotaCenterClientProjection) -> String {
        var parts: [String] = []
        if clientProjection.allowsAllFamilies {
            parts.append("允许所有已知付费家族")
        } else if !clientProjection.familyDisplayNames.isEmpty {
            parts.append("家族 \(clientProjection.familyDisplayNames.joined(separator: " / "))")
        } else {
            parts.append("当前还没有解析到模型家族")
        }
        if clientProjection.paidModelCount > 0 {
            parts.append("模型白名单 \(clientProjection.paidModelCount) 个")
        }
        if !clientProjection.appId.isEmpty {
            parts.append("app \(clientProjection.appId)")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyBudgetClientActivitySummary(_ clientProjection: RemoteQuotaCenterClientProjection) -> String {
        var parts: [String] = []
        if !clientProjection.topModel.isEmpty {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.topModel(clientProjection.topModel))
        }
        if let status = clientProjection.deviceStatus {
            if status.requestsToday > 0 {
                parts.append(HubUIStrings.Settings.GRPC.DeviceList.requests(status.requestsToday))
            }
            if status.blockedToday > 0 {
                parts.append(HubUIStrings.Settings.GRPC.DeviceList.blocked(status.blockedToday))
            }
            if let lastUsed = providerKeyTimestampSummary(
                status.modelBreakdown.map(\.lastUsedAtMs).max() ?? 0,
                prefix: "最近命中"
            ) {
                parts.append(lastUsed)
            }
        } else if let accessKey = clientProjection.terminalAccessKey {
            if let lastUsed = providerKeyTimestampSummary(accessKey.lastUsedAtMs, prefix: "最近使用") {
                parts.append(lastUsed)
            }
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }
}
