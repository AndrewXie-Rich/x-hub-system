import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func providerKeyPoolMemberDisclosureSummary(_ pool: ProviderKeyPoolSnapshot) -> String {
        let totalMembers = pool.members.count
        let riskCount = pool.members.filter { member in
            let state = member.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return state == "blocked" || state == "cooldown" || state == "stale"
        }.count

        var parts: [String] = ["\(totalMembers) 个成员"]
        if riskCount > 0 {
            parts.append("\(riskCount) 个需关注")
        } else {
            parts.append("当前成员整体稳定")
        }
        return parts.joined(separator: " · ")
    }

    func remoteModelGroupDisclosureSummary(_ group: RemoteModelKeyGroup) -> String {
        var parts: [String] = ["\(group.models.count) 个模型"]
        if group.loadedCount > 0 {
            parts.append("\(group.loadedCount) 已加载")
        }
        if group.availableCount > 0 {
            parts.append("\(group.availableCount) 可执行")
        }
        if group.needsSetupCount > 0 {
            parts.append("\(group.needsSetupCount) 待补齐")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyImportSourcesSummaryText(
        _ sources: [ProviderKeyImportSourceStatus]
    ) -> String {
        let readyCount = sources.filter { $0.state == "ready" }.count
        let issueCount = sources.filter { $0.state != "ready" || $0.lastErrorCount > 0 }.count
        let importedCount = sources.reduce(0) { $0 + max(0, $1.lastImportedCount) }
        var parts: [String] = ["\(sources.count) 个来源"]
        if readyCount > 0 {
            parts.append("\(readyCount) 已同步")
        }
        if importedCount > 0 {
            parts.append("导入 \(importedCount)")
        }
        if issueCount > 0 {
            parts.append("\(issueCount) 需处理")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyVendorLedgerSummaryText(
        _ vendors: [ProviderKeyVendorInventorySummary],
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> String {
        let readyAccounts = vendors.reduce(0) { $0 + max(0, $1.readyAccounts) }
        let totalAccounts = vendors.reduce(0) { $0 + max(0, $1.totalAccounts) }
        let riskCount = vendors.filter(providerKeyVendorAtRisk(_:)).count
        var parts: [String] = ["\(vendors.count) 家厂家"]
        if totalAccounts > 0 {
            parts.append("\(readyAccounts)/\(totalAccounts) Ready")
        }
        if riskCount > 0 {
            parts.append("\(riskCount) 家需关注")
        }
        if let focusedVendor {
            parts.append("已锁定 \(focusedVendor.displayName)")
        } else if let focusedUser {
            parts.append("按 \(focusedUser.displayName) 视角重算")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyFamilyLedgerSummaryText(
        _ families: [ProviderKeyFamilyInventorySummary],
        focusedUser: RemoteQuotaCenterUserProjection?
    ) -> String {
        let oversubscribedCount = families.filter(\.isOversubscribed).count
        let readyCount = families.filter { family in
            family.quotaPool.state == "ready" || family.quotaPool.state == "mixed"
        }.count
        var parts: [String] = ["\(families.count) 个家族"]
        if readyCount > 0 {
            parts.append("\(readyCount) 个可供路由")
        }
        if oversubscribedCount > 0 {
            parts.append("\(oversubscribedCount) 个超配")
        }
        if let focusedUser {
            parts.append("按 \(focusedUser.displayName) 视角重算")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyPhysicalPoolsSummaryText(
        _ keyPools: [ProviderKeyPoolSnapshot]
    ) -> String {
        let readyAccounts = keyPools.reduce(0) { $0 + max(0, $1.readyAccounts) }
        let blockedAccounts = keyPools.reduce(0) { $0 + max(0, $1.blockedAccounts) }
        let cooldownAccounts = keyPools.reduce(0) { $0 + max(0, $1.cooldownAccounts) }
        var parts: [String] = ["\(keyPools.count) 个物理池"]
        if readyAccounts > 0 {
            parts.append("\(readyAccounts) 个就绪")
        }
        if blockedAccounts > 0 {
            parts.append("\(blockedAccounts) 个阻塞")
        }
        if cooldownAccounts > 0 {
            parts.append("\(cooldownAccounts) 个冷却")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyUserLedgerDisclosureSummary(
        _ users: [RemoteQuotaCenterUserProjection],
        totalUsers: Int,
        focusedUser: RemoteQuotaCenterUserProjection?
    ) -> String {
        let riskCount = users.filter(providerKeyUserAtRisk(_:)).count
        let connectedCount = users.filter { $0.connectedConsumerCount > 0 }.count
        var parts: [String] = ["\(users.count)/\(max(totalUsers, users.count)) 个用户"]
        if riskCount > 0 {
            parts.append("\(riskCount) 个风险")
        }
        if connectedCount > 0 {
            parts.append("\(connectedCount) 个在线")
        }
        if let focusedUser {
            parts.append("已锁定 \(focusedUser.displayName)")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyFlowSummaryText(
        flowChains: [ProviderKeyFlowChainSummary],
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> String {
        guard !flowChains.isEmpty else {
            if let focusedVendor, let focusedUser {
                return "当前还没有 \(focusedVendor.displayName) -> \(focusedUser.displayName) 的清晰配额链路。"
            }
            if let focusedVendor {
                return "当前还没有 \(focusedVendor.displayName) 的清晰配额链路。"
            }
            if let focusedUser {
                return "当前还没有 \(focusedUser.displayName) 的清晰配额链路。"
            }
            return "当前还没有足够清晰的厂家 -> 用户 -> consumer 配额链路。"
        }

        let riskCount = flowChains.filter { chain in
            providerKeyVendorAtRisk(chain.vendor)
                || providerKeyUserAtRisk(chain.user)
                || providerKeyConsumerAtRisk(chain.consumer)
        }.count

        var parts: [String] = ["\(flowChains.count) 条链路"]
        if riskCount > 0 {
            parts.append("\(riskCount) 条需关注")
        }
        if let focusedVendor {
            parts.append("锁定 \(focusedVendor.displayName)")
        }
        if let focusedUser {
            parts.append("锁定 \(focusedUser.displayName)")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyTrendCardCount(
        overallTrendCard: ProviderKeyTrendCardSummary?,
        vendorTrendCards: [ProviderKeyTrendCardSummary],
        familyTrendCards: [ProviderKeyTrendCardSummary],
        userTrendCards: [ProviderKeyTrendCardSummary],
        consumerTrendCards: [ProviderKeyTrendCardSummary]
    ) -> Int {
        (overallTrendCard == nil ? 0 : 1)
            + vendorTrendCards.count
            + familyTrendCards.count
            + userTrendCards.count
            + consumerTrendCards.count
    }

    func providerKeyTrendSummaryText(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?,
        overallTrendCard: ProviderKeyTrendCardSummary?,
        vendorTrendCards: [ProviderKeyTrendCardSummary],
        familyTrendCards: [ProviderKeyTrendCardSummary],
        userTrendCards: [ProviderKeyTrendCardSummary],
        consumerTrendCards: [ProviderKeyTrendCardSummary]
    ) -> String {
        let totalCardCount = providerKeyTrendCardCount(
            overallTrendCard: overallTrendCard,
            vendorTrendCards: vendorTrendCards,
            familyTrendCards: familyTrendCards,
            userTrendCards: userTrendCards,
            consumerTrendCards: consumerTrendCards
        )

        guard totalCardCount > 0 else {
            if let focusedVendor, let focusedUser {
                return "当前还没有 \(focusedUser.displayName) 在 \(focusedVendor.displayName) 视角下的 5m 趋势数据。"
            }
            if let focusedVendor {
                return "当前还没有 \(focusedVendor.displayName) 的 5m 趋势数据。"
            }
            if let focusedUser {
                return "当前还没有 \(focusedUser.displayName) 的 5m 趋势数据。"
            }
            return "当前还没有足够的 5m token series 数据。"
        }

        var parts: [String] = ["\(totalCardCount) 张趋势图"]
        if overallTrendCard != nil {
            parts.append("含总曲线")
        }
        if let focusedVendor {
            parts.append("围绕 \(focusedVendor.displayName)")
        }
        if let focusedUser {
            parts.append("围绕 \(focusedUser.displayName)")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyOperationalBadgeText(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> String {
        if focusedUser != nil && focusedVendor != nil {
            return "叠加视角"
        }
        if focusedVendor != nil {
            return "厂家视角"
        }
        if focusedUser != nil {
            return "用户视角"
        }
        return "全局视角"
    }

    func providerKeyOperationalSummaryText(
        scopeOverview: ProviderKeyScopeOverview,
        overview: RemoteQuotaCenterOverview,
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> String {
        var parts: [String] = [
            "\(scopeOverview.userCount) 用户 / \(scopeOverview.consumerCount) 消费者",
            "\(overview.quotaPoolCount) 个额度池 / \(overview.keyPoolCount) 个物理池",
            "Ready key \(overview.readyKeys)/\(overview.totalKeys)"
        ]
        if let focusedVendor {
            parts.append("锁定 \(focusedVendor.displayName)")
        }
        if let focusedUser {
            parts.append("锁定 \(focusedUser.displayName)")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyOperationalTint(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?,
        riskVendorCount: Int,
        riskFamilyCount: Int
    ) -> Color {
        if riskVendorCount > 0 || riskFamilyCount > 0 {
            return riskFamilyCount > 0 ? .red : .orange
        }
        if focusedVendor != nil {
            return .indigo
        }
        if focusedUser != nil {
            return .teal
        }
        return .blue
    }

    func providerKeyConsumerLedgerDisclosureSummary(
        _ consumers: [RemoteQuotaCenterClientProjection],
        totalConsumers: Int,
        focusedUser: RemoteQuotaCenterUserProjection?
    ) -> String {
        let xtCount = consumers.filter { $0.consumerKind == .pairedXT }.count
        let terminalCount = consumers.filter { $0.consumerKind == .terminalAccess }.count
        let riskCount = consumers.filter(providerKeyConsumerAtRisk(_:)).count
        var parts: [String] = ["\(consumers.count)/\(max(totalConsumers, consumers.count)) 个消费者"]
        if xtCount > 0 {
            parts.append("XT \(xtCount)")
        }
        if terminalCount > 0 {
            parts.append("Terminal \(terminalCount)")
        }
        if riskCount > 0 {
            parts.append("\(riskCount) 个风险")
        }
        if let focusedUser {
            parts.append("已锁定 \(focusedUser.displayName)")
        }
        return parts.joined(separator: " · ")
    }
}
