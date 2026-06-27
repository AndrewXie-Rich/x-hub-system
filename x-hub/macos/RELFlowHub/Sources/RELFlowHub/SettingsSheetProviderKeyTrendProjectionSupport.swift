import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyOverallTrendCard(
        scopeOverview: ProviderKeyScopeOverview,
        consumers: [RemoteQuotaCenterClientProjection],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> ProviderKeyTrendCardSummary? {
        if let focusedVendor {
            guard let aggregate = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
                consumers: consumers,
                familyKeys: Set(focusedVendor.familyKeys)
            ) else {
                return nil
            }

            let title = scopeOverview.focusedUser == nil
                ? "\(focusedVendor.displayName) 下游趋势"
                : "\(scopeOverview.focusedUser?.displayName ?? "") · \(focusedVendor.displayName)"
            let subtitle = scopeOverview.focusedUser == nil
                ? "最近 1 小时命中该厂家家族的下游用量"
                : "当前用户最近 1 小时命中该厂家家族的用量"
            let footnote = aggregate.estimatedConsumerCount > 0
                ? "其中 \(aggregate.estimatedConsumerCount) 个 multi-family consumer 按今日家族命中占比估算，只用于判断 \(focusedVendor.displayName) 的热度变化。"
                : "这张总曲线只看 \(focusedVendor.displayName) 相关家族，便于判断这家现在是否还能继续发额度。"

            return ProviderKeyTrendCardSummary(
                id: "overall.vendor.\(focusedVendor.id)",
                title: title,
                subtitle: subtitle,
                footnote: footnote,
                systemName: scopeOverview.focusedUser == nil ? "building.2.crop.circle.fill" : "person.crop.circle.badge.clock",
                tint: providerKeyVendorAtRisk(focusedVendor) ? .orange : .indigo,
                aggregate: aggregate
            )
        }

        guard let aggregate = RemoteQuotaTrendSupport.aggregateConsumers(consumers) else {
            return nil
        }

        let title = scopeOverview.focusedUser == nil
            ? "全局下游趋势"
            : "\(scopeOverview.focusedUser?.displayName ?? "") 用量趋势"
        let subtitle = scopeOverview.focusedUser == nil
            ? "全部 XT / Terminal 最近 1 小时远端用量"
            : "当前用户相关 XT / Terminal 最近 1 小时远端用量"
        let footnote = scopeOverview.focusedUser == nil
            ? "这张总曲线只看下游消费者的真实 5m usage 桶，便于判断全局发额度的节奏。"
            : "先看这个用户整体是否在放量，再往下看家族和具体 consumer。"

        return ProviderKeyTrendCardSummary(
            id: "overall",
            title: title,
            subtitle: subtitle,
            footnote: footnote,
            systemName: scopeOverview.focusedUser == nil ? "waveform.path.ecg" : "person.crop.circle.badge.clock",
            tint: scopeOverview.focusedUser == nil ? .indigo : .teal,
            aggregate: aggregate
        )
    }

    func providerKeyVendorTrendCards(
        _ vendors: [ProviderKeyVendorInventorySummary],
        scopedConsumers: [RemoteQuotaCenterClientProjection],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> [ProviderKeyTrendCardSummary] {
        guard focusedVendor == nil else { return [] }
        return vendors.compactMap { vendor in
            guard let aggregate = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
                consumers: scopedConsumers,
                familyKeys: Set(vendor.familyKeys)
            ) else {
                return nil
            }

            let budgetSummary = vendor.assignedDailyTokenBudget > 0
                ? "覆盖预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.assignedDailyTokenBudget))"
                : (vendor.coveredUnlimitedConsumerCount > 0 ? "含弹性 consumer \(vendor.coveredUnlimitedConsumerCount)" : "当前无固定预算")
            let footnote = aggregate.estimatedConsumerCount > 0
                ? "其中 \(aggregate.estimatedConsumerCount) 个 multi-family consumer 按今日家族命中占比分摊到厂家，只用于判断热度变化。"
                : "全部来自该厂家相关 consumer 的真实 5m usage 桶。"

            return ProviderKeyTrendCardSummary(
                id: "vendor:\(vendor.id)",
                title: vendor.displayName,
                subtitle: "\(vendor.coveredUserCount) 用户 / \(vendor.coveredConsumerCount) consumer · \(budgetSummary)",
                footnote: footnote,
                systemName: "building.2.crop.circle",
                tint: providerKeyVendorAtRisk(vendor) ? .orange : .indigo,
                aggregate: aggregate
            )
        }
        .sorted(by: providerKeySortTrendCardSummary(_:_:))
    }

    func providerKeyFamilyTrendCards(
        _ families: [ProviderKeyFamilyInventorySummary]
    ) -> [ProviderKeyTrendCardSummary] {
        return families.compactMap { family in
            guard let aggregate = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
                consumers: family.assignedConsumers,
                familyKeys: [family.familyKey]
            ) else {
                return nil
            }

            let budgetSummary = family.assignedDailyTokenBudget > 0
                ? "覆盖预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.assignedDailyTokenBudget))"
                : (family.unlimitedBudgetConsumerCount > 0 ? "含弹性 consumer \(family.unlimitedBudgetConsumerCount)" : "当前无固定预算")
            let footnote = aggregate.estimatedConsumerCount > 0
                ? "其中 \(aggregate.estimatedConsumerCount) 个 multi-family consumer 按今日家族命中占比估算，适合用来看池子升温。"
                : "全部来自这个家族相关 consumer 的真实 5m usage 桶。"

            return ProviderKeyTrendCardSummary(
                id: "family:\(family.id)",
                title: family.displayName,
                subtitle: "\(family.coveredUserCount) 用户 / \(family.assignedClientCount) consumer · \(budgetSummary)",
                footnote: footnote,
                systemName: "square.stack.3d.up.fill",
                tint: providerKeyPoolStateColor(family.quotaPool.state),
                aggregate: aggregate
            )
        }
        .sorted(by: providerKeySortTrendCardSummary(_:_:))
    }

    func providerKeyUserTrendCards(
        _ users: [RemoteQuotaCenterUserProjection],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> [ProviderKeyTrendCardSummary] {
        return users.compactMap { user -> ProviderKeyTrendCardSummary? in
            let focusedVendorName = focusedVendor?.displayName ?? ""
            let aggregate: RemoteQuotaTrendAggregate?
            if let focusedVendor {
                aggregate = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
                    consumers: user.consumers,
                    familyKeys: Set(focusedVendor.familyKeys)
                )
            } else {
                aggregate = RemoteQuotaTrendSupport.aggregateConsumers(user.consumers)
            }

            guard let aggregate else {
                return nil
            }

            let remainingText: String = {
                if user.allocatedDailyTokenBudget > 0 {
                    let base = HubUIStrings.Settings.ProviderKeys.tokenCount(max(Int64(0), user.remainingDailyTokenBudget))
                    return user.hasUnlimitedBudget ? "\(base) +" : base
                }
                return user.hasUnlimitedBudget ? "弹性" : "0"
            }()

            return ProviderKeyTrendCardSummary(
                id: "user:\(user.id)",
                title: user.displayName,
                subtitle: focusedVendor == nil
                    ? "\(user.consumerCount) consumer · 剩余 \(remainingText)"
                    : "\(user.consumerCount) consumer · \(focusedVendorName) 相关剩余 \(remainingText)",
                footnote: focusedVendor == nil
                    ? providerKeyBudgetUserScopeSummary(user)
                    : providerKeyBudgetUserScopeSummary(user) + " · 趋势仅统计 \(focusedVendorName) 相关家族",
                systemName: user.isStandaloneConsumer ? "person.crop.circle.badge.questionmark" : "person.crop.circle",
                tint: providerKeyUserAtRisk(user) ? .orange : providerKeyUserTint(user),
                aggregate: aggregate
            )
        }
        .sorted(by: providerKeySortTrendCardSummary(_:_:))
    }

    func providerKeyConsumerTrendCards(
        _ consumers: [RemoteQuotaCenterClientProjection],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> [ProviderKeyTrendCardSummary] {
        return consumers.compactMap { consumer -> ProviderKeyTrendCardSummary? in
            let focusedVendorName = focusedVendor?.displayName ?? ""
            let aggregate: RemoteQuotaTrendAggregate?
            if let focusedVendor {
                aggregate = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
                    consumers: [consumer],
                    familyKeys: Set(focusedVendor.familyKeys)
                )
            } else {
                aggregate = RemoteQuotaTrendSupport.aggregateConsumers([consumer])
            }

            guard let aggregate else {
                return nil
            }

            let budgetText = consumer.dailyTokenLimit > 0
                ? "预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(consumer.dailyTokenLimit))"
                : "弹性预算"
            let familyText = consumer.familyDisplayNames.isEmpty
                ? "当前未解析到家族"
                : "家族 \(providerKeyPreviewList(consumer.familyDisplayNames))"

            return ProviderKeyTrendCardSummary(
                id: "consumer:\(consumer.id)",
                title: consumer.name,
                subtitle: focusedVendor == nil
                    ? "\(consumer.kindTitle) · \(budgetText)"
                    : "\(consumer.kindTitle) · \(focusedVendorName) 相关 · \(budgetText)",
                footnote: focusedVendor == nil
                    ? "\(familyText) · \(providerKeyBudgetClientReferenceSummary(consumer))"
                    : "\(familyText) · \(providerKeyBudgetClientReferenceSummary(consumer)) · 仅统计 \(focusedVendorName) 命中",
                systemName: consumer.isTerminalAccess ? "terminal.fill" : "display.2",
                tint: providerKeyConsumerAtRisk(consumer) ? .orange : providerKeyConsumerKindColor(consumer.consumerKind),
                aggregate: aggregate
            )
        }
        .sorted(by: providerKeySortTrendCardSummary(_:_:))
    }

    func providerKeySortTrendCardSummary(
        _ lhs: ProviderKeyTrendCardSummary,
        _ rhs: ProviderKeyTrendCardSummary
    ) -> Bool {
        let leftRecent = lhs.aggregate.recentTokens15m
        let rightRecent = rhs.aggregate.recentTokens15m
        if leftRecent != rightRecent {
            return leftRecent > rightRecent
        }
        if lhs.aggregate.totalTokens1h != rhs.aggregate.totalTokens1h {
            return lhs.aggregate.totalTokens1h > rhs.aggregate.totalTokens1h
        }
        if lhs.aggregate.peakBucketTokens != rhs.aggregate.peakBucketTokens {
            return lhs.aggregate.peakBucketTokens > rhs.aggregate.peakBucketTokens
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
