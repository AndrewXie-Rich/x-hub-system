import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyVendorObservedDailyTokensUsed(
        _ consumer: RemoteQuotaCenterClientProjection,
        familyKeys: Set<String>
    ) -> Int64 {
        guard !familyKeys.isEmpty else { return 0 }
        return familyKeys.reduce(Int64(0)) { partial, familyKey in
            partial + max(Int64(0), consumer.observedDailyTokens(for: familyKey))
        }
    }

    func providerKeyVendorObservedDailyTokensUsed(
        _ user: RemoteQuotaCenterUserProjection,
        familyKeys: Set<String>
    ) -> Int64 {
        user.consumers.reduce(Int64(0)) { partial, consumer in
            partial + providerKeyVendorObservedDailyTokensUsed(consumer, familyKeys: familyKeys)
        }
    }

    func providerKeyVendorSpotlightUsers(
        _ users: [RemoteQuotaCenterUserProjection],
        familyKeys: Set<String>
    ) -> [ProviderKeyVendorUserSpotlight] {
        let spotlight = users.map { user in
            ProviderKeyVendorUserSpotlight(
                user: user,
                vendorObservedDailyTokensUsed: providerKeyVendorObservedDailyTokensUsed(
                    user,
                    familyKeys: familyKeys
                )
            )
        }
        let sorted = spotlight.sorted { lhs, rhs in
            let leftRisk = providerKeyUserAtRisk(lhs.user)
            let rightRisk = providerKeyUserAtRisk(rhs.user)
            if leftRisk != rightRisk {
                return leftRisk && !rightRisk
            }
            if lhs.vendorObservedDailyTokensUsed != rhs.vendorObservedDailyTokensUsed {
                return lhs.vendorObservedDailyTokensUsed > rhs.vendorObservedDailyTokensUsed
            }
            if lhs.user.allocatedDailyTokenBudget != rhs.user.allocatedDailyTokenBudget {
                return lhs.user.allocatedDailyTokenBudget > rhs.user.allocatedDailyTokenBudget
            }
            if lhs.user.connectedConsumerCount != rhs.user.connectedConsumerCount {
                return lhs.user.connectedConsumerCount > rhs.user.connectedConsumerCount
            }
            return lhs.user.displayName.localizedCaseInsensitiveCompare(rhs.user.displayName) == .orderedAscending
        }

        let preferred = sorted.filter { spotlight in
            spotlight.vendorObservedDailyTokensUsed > 0
                || spotlight.user.allocatedDailyTokenBudget > 0
                || spotlight.user.hasUnlimitedBudget
                || providerKeyUserAtRisk(spotlight.user)
        }
        return Array((preferred.isEmpty ? sorted : preferred).prefix(3))
    }

    func providerKeyVendorSpotlightConsumers(
        _ consumers: [RemoteQuotaCenterClientProjection],
        familyKeys: Set<String>
    ) -> [ProviderKeyVendorConsumerSpotlight] {
        let spotlight = consumers.map { consumer in
            ProviderKeyVendorConsumerSpotlight(
                consumer: consumer,
                vendorObservedDailyTokensUsed: providerKeyVendorObservedDailyTokensUsed(
                    consumer,
                    familyKeys: familyKeys
                )
            )
        }
        let sorted = spotlight.sorted { lhs, rhs in
            let leftRisk = providerKeyConsumerAtRisk(lhs.consumer)
            let rightRisk = providerKeyConsumerAtRisk(rhs.consumer)
            if leftRisk != rightRisk {
                return leftRisk && !rightRisk
            }
            if lhs.vendorObservedDailyTokensUsed != rhs.vendorObservedDailyTokensUsed {
                return lhs.vendorObservedDailyTokensUsed > rhs.vendorObservedDailyTokensUsed
            }
            if lhs.consumer.dailyTokenLimit != rhs.consumer.dailyTokenLimit {
                return lhs.consumer.dailyTokenLimit > rhs.consumer.dailyTokenLimit
            }
            if lhs.consumer.connected != rhs.consumer.connected {
                return lhs.consumer.connected && !rhs.consumer.connected
            }
            return lhs.consumer.name.localizedCaseInsensitiveCompare(rhs.consumer.name) == .orderedAscending
        }

        let preferred = sorted.filter { spotlight in
            spotlight.vendorObservedDailyTokensUsed > 0
                || spotlight.consumer.dailyTokenLimit > 0
                || spotlight.consumer.allowsAllFamilies
                || providerKeyConsumerAtRisk(spotlight.consumer)
        }
        return Array((preferred.isEmpty ? sorted : preferred).prefix(3))
    }

    func providerKeyVendorInventorySummaries(
        _ pools: [ProviderKeyPoolSnapshot],
        familySummaries: [ProviderKeyFamilyInventorySummary],
        scopedUsers: [RemoteQuotaCenterUserProjection],
        scopedConsumers: [RemoteQuotaCenterClientProjection],
        includeSpotlights: Bool = true
    ) -> [ProviderKeyVendorInventorySummary] {
        let grouped = Dictionary(grouping: pools) { pool in
            providerKeyCanonicalVendorKey(pool.supplierKey)
        }

        return grouped.compactMap { vendorKey, vendorPools in
            guard let firstPool = vendorPools.first else { return nil }
            let sortedVendorPools = vendorPools.sorted(by: providerKeySortVendorPools(_:_:))
            let distinctSupplierKeys = providerKeyDistinctPreviewStrings(vendorPools.map(\.supplierKey))
            let supplierDisplayName = firstPool.supplierDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = distinctSupplierKeys.count > 1
                ? providerKeyVendorDisplayName(vendorKey)
                : (supplierDisplayName.isEmpty ? providerKeyVendorDisplayName(vendorKey) : supplierDisplayName)
            let familyKeys = providerKeyDistinctPreviewStrings(vendorPools.flatMap(\.supportedFamilyKeys))
            let familyKeySet = Set(familyKeys)
            let relatedFamilies = familySummaries.filter { familyKeySet.contains($0.familyKey) }
            let coveredConsumers = scopedConsumers.filter { consumer in
                consumer.allowsAllFamilies || !familyKeySet.isDisjoint(with: Set(consumer.familyKeys))
            }
            let coveredConsumerIDs = Set(coveredConsumers.map(\.id))
            let coveredUsers = scopedUsers.filter { user in
                user.consumers.contains(where: { coveredConsumerIDs.contains($0.id) })
            }
            let spotlightUsers = includeSpotlights
                ? providerKeyVendorSpotlightUsers(coveredUsers, familyKeys: familyKeySet)
                : []
            let spotlightConsumers = includeSpotlights
                ? providerKeyVendorSpotlightConsumers(coveredConsumers, familyKeys: familyKeySet)
                : []
            let assignedDailyTokenBudget = relatedFamilies.reduce(Int64(0)) { partial, family in
                partial + max(Int64(0), family.assignedDailyTokenBudget)
            }
            let observedFamilyTokensUsed = relatedFamilies.reduce(Int64(0)) { partial, family in
                partial + max(Int64(0), family.observedDailyTokensUsed)
            }
            let totalDailyTokenCap = vendorPools.reduce(Int64(0)) { $0 + max(Int64(0), $1.totalDailyTokenCap) }
            return ProviderKeyVendorInventorySummary(
                vendorKey: vendorKey,
                displayName: displayName,
                pools: sortedVendorPools,
                spotlightUsers: spotlightUsers,
                spotlightConsumers: spotlightConsumers,
                providerDisplayNames: providerKeyDistinctPreviewStrings(vendorPools.map(\.providerDisplayName)),
                providerHosts: providerKeyDistinctPreviewStrings(vendorPools.map(\.providerHost)),
                familyKeys: familyKeys,
                familyDisplayNames: providerKeyDistinctPreviewStrings(
                    relatedFamilies.isEmpty
                        ? vendorPools.flatMap(\.supportedFamilyDisplayNames)
                        : relatedFamilies.map(\.displayName)
                ),
                coveredUserCount: coveredUsers.count,
                coveredConsumerCount: coveredConsumers.count,
                coveredUnlimitedConsumerCount: coveredConsumers.filter { $0.dailyTokenLimit <= 0 }.count,
                coveredFamilyCount: relatedFamilies.count,
                poolCount: vendorPools.count,
                totalAccounts: vendorPools.reduce(0) { $0 + $1.totalAccounts },
                readyAccounts: vendorPools.reduce(0) { $0 + $1.readyAccounts },
                cooldownAccounts: vendorPools.reduce(0) { $0 + $1.cooldownAccounts },
                blockedAccounts: vendorPools.reduce(0) { $0 + $1.blockedAccounts },
                disabledAccounts: vendorPools.reduce(0) { $0 + $1.disabledAccounts },
                staleAccounts: vendorPools.reduce(0) { $0 + $1.staleAccounts },
                totalDailyTokenCap: totalDailyTokenCap,
                totalDailyTokensUsed: vendorPools.reduce(Int64(0)) { $0 + max(Int64(0), $1.totalDailyTokensUsed) },
                totalDailyTokensRemaining: vendorPools.reduce(Int64(0)) { $0 + max(Int64(0), $1.totalDailyTokensRemaining) },
                totalTokensUsed: vendorPools.reduce(Int64(0)) { $0 + max(Int64(0), $1.totalTokensUsed) },
                assignedDailyTokenBudget: assignedDailyTokenBudget,
                observedFamilyTokensUsed: observedFamilyTokensUsed,
                allocationHeadroom: totalDailyTokenCap > 0 ? (totalDailyTokenCap - assignedDailyTokenBudget) : 0,
                oversubscribedFamilyCount: relatedFamilies.filter(\.isOversubscribed).count,
                hotPoolCount: vendorPools.filter(providerKeyPoolNeedsAttention(_:)).count
            )
        }
        .sorted { lhs, rhs in
            if lhs.oversubscribedFamilyCount != rhs.oversubscribedFamilyCount {
                return lhs.oversubscribedFamilyCount > rhs.oversubscribedFamilyCount
            }
            if lhs.blockedAccounts != rhs.blockedAccounts {
                return lhs.blockedAccounts > rhs.blockedAccounts
            }
            if lhs.assignedDailyTokenBudget != rhs.assignedDailyTokenBudget {
                return lhs.assignedDailyTokenBudget > rhs.assignedDailyTokenBudget
            }
            if lhs.totalAccounts != rhs.totalAccounts {
                return lhs.totalAccounts > rhs.totalAccounts
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
