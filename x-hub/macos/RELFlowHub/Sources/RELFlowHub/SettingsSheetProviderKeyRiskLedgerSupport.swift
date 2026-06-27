import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeySortFamilyInventorySummary(
        _ lhs: ProviderKeyFamilyInventorySummary,
        _ rhs: ProviderKeyFamilyInventorySummary
    ) -> Bool {
        if lhs.isOversubscribed != rhs.isOversubscribed {
            return lhs.isOversubscribed && !rhs.isOversubscribed
        }
        if lhs.quotaPool.blockedAccounts != rhs.quotaPool.blockedAccounts {
            return lhs.quotaPool.blockedAccounts > rhs.quotaPool.blockedAccounts
        }
        if lhs.assignedDailyTokenBudget != rhs.assignedDailyTokenBudget {
            return lhs.assignedDailyTokenBudget > rhs.assignedDailyTokenBudget
        }
        if lhs.observedDailyTokensUsed != rhs.observedDailyTokensUsed {
            return lhs.observedDailyTokensUsed > rhs.observedDailyTokensUsed
        }
        if lhs.combinedDailyTokenCap != rhs.combinedDailyTokenCap {
            return lhs.combinedDailyTokenCap > rhs.combinedDailyTokenCap
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    func providerKeyVendorAtRisk(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> Bool {
        if vendor.oversubscribedFamilyCount > 0 || vendor.blockedAccounts > 0 {
            return true
        }
        if vendor.allocationHeadroom < 0 {
            return true
        }
        if vendor.cooldownAccounts > 0 && vendor.totalAccounts <= max(1, vendor.readyAccounts) {
            return true
        }
        guard vendor.totalDailyTokenCap > 0 else { return vendor.hotPoolCount > 0 }
        return vendor.totalDailyTokensRemaining <= max(Int64(50_000), vendor.totalDailyTokenCap / 10)
    }

    func providerKeyFamilyAtRisk(
        _ family: ProviderKeyFamilyInventorySummary
    ) -> Bool {
        if family.isOversubscribed || family.quotaPool.blockedAccounts > 0 {
            return true
        }
        if family.quotaPool.cooldownAccounts > 0 && family.quotaPool.readyAccounts <= 1 {
            return true
        }
        guard family.combinedDailyTokenCap > 0 else { return false }
        return family.combinedDailyTokensRemaining <= max(Int64(50_000), family.combinedDailyTokenCap / 10)
    }

    func providerKeyScopeSummary(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?,
        vendors: [ProviderKeyVendorInventorySummary],
        families: [ProviderKeyFamilyInventorySummary],
        users: [RemoteQuotaCenterUserProjection],
        consumers: [RemoteQuotaCenterClientProjection]
    ) -> String {
        let allocatedBudget = consumers.reduce(Int64(0)) { $0 + max(Int64(0), $1.dailyTokenLimit) }
        let observedUsage = consumers.reduce(Int64(0)) { $0 + max(Int64(0), $1.dailyTokenUsed) }
        let unlimitedCount = consumers.filter { $0.dailyTokenLimit <= 0 }.count
        var parts: [String] = []
        if let focusedUser {
            parts.append("当前按 \(focusedUser.displayName) 视角查看")
        } else {
            parts.append("当前是全局视角")
        }
        if let focusedVendor {
            parts.append("已锁定 \(focusedVendor.displayName) 厂家")
        } else if providerKeyHasFocusedVendor {
            parts.append("已锁定 \(providerKeyVendorDisplayName(providerKeyNormalizedFocusedVendorKey)) 厂家")
        }
        parts.append("厂家 \(vendors.count)")
        parts.append("家族 \(families.count)")
        parts.append("用户 \(users.count)")
        parts.append("消费者 \(consumers.count)")
        if allocatedBudget > 0 {
            parts.append("覆盖预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(allocatedBudget))")
            let remainingBudget = HubUIStrings.Settings.ProviderKeys.tokenCount(max(Int64(0), allocatedBudget - observedUsage))
            parts.append(unlimitedCount > 0 ? "剩余 \(remainingBudget) +" : "剩余 \(remainingBudget)")
        } else if unlimitedCount > 0 {
            parts.append("弹性 consumer \(unlimitedCount)")
        }
        if observedUsage > 0 {
            parts.append("今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(observedUsage))")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyVendorFilterSummary(
        _ vendors: [ProviderKeyVendorInventorySummary],
        totalVendors: Int,
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> String {
        if let focusedVendor {
            if let focusedUser {
                return "当前已锁定 \(focusedVendor.displayName) 厂家，并叠加 \(focusedUser.displayName) 视角。这里只看这位用户实际命中的 \(vendors.count)/\(totalVendors) 家厂家。"
            }
            return "当前已锁定 \(focusedVendor.displayName) 厂家。这里保留该厂家全局库存与覆盖预算，便于继续往下看家族与热点用户。"
        } else if providerKeyHasFocusedVendor {
            return "当前已锁定 \(providerKeyVendorDisplayName(providerKeyNormalizedFocusedVendorKey)) 厂家，但 Hub 账本里还没有这家可展示的库存。先同步后再看。"
        }
        switch remoteQuotaVendorFilter {
        case .all:
            if let focusedUser {
                return "当前只显示与 \(focusedUser.displayName) 相关的 \(vendors.count)/\(totalVendors) 家厂家。上游库存与 key 健康仍是厂家全局账，覆盖预算和今日用量已按当前用户重算。"
            }
            return "显示全部 \(vendors.count) 家厂家，覆盖库存、预算缓冲和健康态势。"
        case .risk:
            return vendors.isEmpty
                ? "当前视角下没有库存缓冲偏低、超配或阻塞明显的厂家。"
                : "风险视图共 \(vendors.count)/\(totalVendors) 家，按超配、缓冲不足或 key 阻塞筛出。"
        }
    }

    func providerKeyUserFilterSummary(
        _ users: [RemoteQuotaCenterUserProjection],
        totalUsers: Int,
        focusedUser: RemoteQuotaCenterUserProjection?
    ) -> String {
        switch remoteQuotaUserFilter {
        case .all:
            if let focusedUser {
                return "当前只显示 \(focusedUser.displayName) 这一位用户主体。"
            }
            return providerKeyUserLedgerSummary(users)
        case .risk:
            return users.isEmpty
                ? "当前视角下没有逼近上限、已触顶或出现阻断记录的用户主体。"
                : "风险用户共 \(users.count)/\(totalUsers) 个，按 consumer 风险和剩余额度偏低筛出。"
        }
    }
}
