import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyScopeOverview(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendorDisplayName: String?,
        scopedUsers: [RemoteQuotaCenterUserProjection],
        scopedConsumers: [RemoteQuotaCenterClientProjection],
        families: [ProviderKeyFamilyInventorySummary]
    ) -> ProviderKeyScopeOverview {
        ProviderKeyScopeOverview(
            focusedUser: focusedUser,
            focusedVendorDisplayName: focusedVendorDisplayName,
            userCount: scopedUsers.count,
            consumerCount: scopedConsumers.count,
            connectedConsumerCount: scopedConsumers.filter(\.connected).count,
            xtConsumerCount: scopedConsumers.filter { $0.consumerKind == .pairedXT }.count,
            terminalConsumerCount: scopedConsumers.filter { $0.consumerKind == .terminalAccess }.count,
            allocatedDailyTokenBudget: scopedConsumers.reduce(Int64(0)) { $0 + max(Int64(0), $1.dailyTokenLimit) },
            unlimitedBudgetConsumerCount: scopedConsumers.filter { $0.dailyTokenLimit <= 0 }.count,
            observedConsumerTokensUsed: scopedConsumers.reduce(Int64(0)) { $0 + max(Int64(0), $1.dailyTokenUsed) },
            oversubscribedFamilyCount: families.filter(\.isOversubscribed).count
        )
    }

    func providerKeyFamilyInventorySummaries(
        _ projection: RemoteQuotaCenterProjection,
        scopedUsers: [RemoteQuotaCenterUserProjection],
        scopedConsumers: [RemoteQuotaCenterClientProjection],
        focusedVendorFamilyKeys: Set<String>
    ) -> [ProviderKeyFamilyInventorySummary] {
        let scopedConsumerIDs = Set(scopedConsumers.map(\.id))
        let focusedUser = providerKeyFocusedUser(projection.users)
        let summaries = projection.families.map { family in
            let assignedConsumers = focusedUser == nil
                ? family.assignedConsumers
                : family.assignedConsumers.filter { scopedConsumerIDs.contains($0.id) }
            let assignedConsumerIDs = Set(assignedConsumers.map(\.id))
            let coveredUserCount = scopedUsers.filter { user in
                user.consumers.contains(where: { assignedConsumerIDs.contains($0.id) })
            }.count
            let observedDailyTokensUsed = scopedConsumers.reduce(Int64(0)) { partial, consumer in
                partial + consumer.observedDailyTokens(for: family.familyKey)
            }
            return ProviderKeyFamilyInventorySummary(
                familyProjection: family,
                coveredUserCount: coveredUserCount,
                assignedConsumers: assignedConsumers,
                assignedDailyTokenBudget: assignedConsumers.reduce(Int64(0)) { partial, consumer in
                    partial + max(Int64(0), consumer.dailyTokenLimit)
                },
                unlimitedBudgetConsumerCount: assignedConsumers.filter { $0.dailyTokenLimit <= 0 }.count,
                connectedAssignedConsumerCount: assignedConsumers.filter(\.connected).count,
                observedDailyTokensUsed: observedDailyTokensUsed
            )
        }

        let visibleSummaries: [ProviderKeyFamilyInventorySummary]
        if providerKeyHasFocusedVendor {
            visibleSummaries = summaries.filter { summary in
                focusedVendorFamilyKeys.contains(summary.familyKey)
                    && (!summary.assignedConsumers.isEmpty || summary.observedDailyTokensUsed > 0 || focusedUser == nil)
            }
        } else if focusedUser != nil {
            visibleSummaries = summaries.filter { !$0.assignedConsumers.isEmpty || $0.observedDailyTokensUsed > 0 }
        } else {
            visibleSummaries = summaries
        }

        return visibleSummaries.sorted(by: providerKeySortFamilyInventorySummary(_:_:))
    }
}
