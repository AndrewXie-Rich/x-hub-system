import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyFlowLinkKind(
        _ consumer: RemoteQuotaCenterClientProjection,
        vendorFamilyKeys: Set<String>,
        matchedFamilyCount: Int
    ) -> ProviderKeyFlowLinkKind {
        if consumer.allowsAllFamilies {
            return .elastic
        }
        let consumerFamilyKeys = Set(consumer.familyKeys)
        if matchedFamilyCount > 0 && consumerFamilyKeys.isSubset(of: vendorFamilyKeys) {
            return .dedicated
        }
        return .shared
    }

    func providerKeyFlowChains(
        vendors: [ProviderKeyVendorInventorySummary],
        users: [RemoteQuotaCenterUserProjection],
        consumers: [RemoteQuotaCenterClientProjection],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> [ProviderKeyFlowChainSummary] {
        let userByConsumerID = Dictionary(
            uniqueKeysWithValues: users.flatMap { user in
                user.consumers.map { consumer in
                    (consumer.id, user)
                }
            }
        )

        func makeChains(relaxed: Bool) -> [ProviderKeyFlowChainSummary] {
            var chains: [ProviderKeyFlowChainSummary] = []

            for vendor in vendors {
                let vendorFamilyKeys = Set(vendor.familyKeys)
                guard !vendorFamilyKeys.isEmpty else { continue }

                for consumer in consumers {
                    let matchedFamilyCount: Int = {
                        if consumer.allowsAllFamilies {
                            return vendorFamilyKeys.count
                        }
                        return Set(consumer.familyKeys).intersection(vendorFamilyKeys).count
                    }()

                    guard matchedFamilyCount > 0 else { continue }
                    guard let user = userByConsumerID[consumer.id] else { continue }

                    let linkKind = providerKeyFlowLinkKind(
                        consumer,
                        vendorFamilyKeys: vendorFamilyKeys,
                        matchedFamilyCount: matchedFamilyCount
                    )
                    let vendorObservedDailyTokensUsed = providerKeyVendorObservedDailyTokensUsed(
                        consumer,
                        familyKeys: vendorFamilyKeys
                    )
                    let hasBudgetSignal = consumer.dailyTokenLimit > 0 || user.allocatedDailyTokenBudget > 0
                    let hasRiskSignal = providerKeyConsumerAtRisk(consumer) || providerKeyUserAtRisk(user)
                    let shouldInclude: Bool = {
                        if vendorObservedDailyTokensUsed > 0 { return true }
                        if hasRiskSignal { return true }
                        if linkKind == .dedicated && hasBudgetSignal { return true }
                        if relaxed && hasBudgetSignal { return true }
                        if relaxed && focusedVendor != nil { return true }
                        return false
                    }()

                    guard shouldInclude else { continue }

                    chains.append(
                        ProviderKeyFlowChainSummary(
                            vendor: vendor,
                            user: user,
                            consumer: consumer,
                            linkKind: linkKind,
                            matchedFamilyCount: matchedFamilyCount,
                            vendorObservedDailyTokensUsed: vendorObservedDailyTokensUsed
                        )
                    )
                }
            }

            return chains.sorted { lhs, rhs in
                let leftRisk = providerKeyVendorAtRisk(lhs.vendor)
                    || providerKeyUserAtRisk(lhs.user)
                    || providerKeyConsumerAtRisk(lhs.consumer)
                let rightRisk = providerKeyVendorAtRisk(rhs.vendor)
                    || providerKeyUserAtRisk(rhs.user)
                    || providerKeyConsumerAtRisk(rhs.consumer)
                if leftRisk != rightRisk {
                    return leftRisk && !rightRisk
                }
                if lhs.vendorObservedDailyTokensUsed != rhs.vendorObservedDailyTokensUsed {
                    return lhs.vendorObservedDailyTokensUsed > rhs.vendorObservedDailyTokensUsed
                }
                if lhs.linkKind != rhs.linkKind {
                    return lhs.linkKind < rhs.linkKind
                }
                if lhs.matchedFamilyCount != rhs.matchedFamilyCount {
                    return lhs.matchedFamilyCount > rhs.matchedFamilyCount
                }
                if lhs.vendor.allocationHeadroom != rhs.vendor.allocationHeadroom {
                    return lhs.vendor.allocationHeadroom < rhs.vendor.allocationHeadroom
                }
                if lhs.consumer.dailyTokenLimit != rhs.consumer.dailyTokenLimit {
                    return lhs.consumer.dailyTokenLimit > rhs.consumer.dailyTokenLimit
                }
                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
        }

        let preferred = makeChains(relaxed: false)
        if !preferred.isEmpty {
            return Array(preferred.prefix(6))
        }
        return Array(makeChains(relaxed: true).prefix(6))
    }
}
