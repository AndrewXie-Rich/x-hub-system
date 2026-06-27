import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func maybeRebuildProviderKeySectionSnapshot() {
        guard selectedSettingsPage == .models, providerQuotaOperationsExpanded else { return }
        rebuildProviderKeySectionSnapshot()
    }

    private func rebuildProviderKeySectionSnapshot() {
        providerKeySectionSnapshot = makeProviderKeySectionSnapshot()
    }

    private func makeProviderKeySectionSnapshot() -> ProviderKeySectionSnapshot {
        let keyPools = providerKeyDerivedSnapshot.keyPools
        let quotaProjection = remoteQuotaProjection
        let users = quotaProjection.users
        let focusedUser = providerKeyFocusedUser(users)
        let focusedVendorFamilyKeys = providerKeyFocusedVendorFamilyKeys(quotaProjection)
        let scopedUsers = providerKeyVendorScopedUsers(
            providerKeyScopedUsers(users),
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        let scopedConsumers = providerKeyVendorScopedConsumers(
            providerKeyScopedConsumers(quotaProjection),
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        let filteredFamilies = providerKeyFamilyInventorySummaries(
            quotaProjection,
            scopedUsers: scopedUsers,
            scopedConsumers: scopedConsumers,
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        let vendorSummaries = providerKeyVendorInventorySummaries(
            keyPools,
            familySummaries: filteredFamilies,
            scopedUsers: scopedUsers,
            scopedConsumers: scopedConsumers,
            includeSpotlights: providerVendorLedgerExpanded
        )
        let focusedVendor = providerKeyFocusedVendor(vendorSummaries)
        let filteredVendors = providerKeyFilteredVendors(
            vendorSummaries,
            focusedVendor: focusedVendor
        )
        let filteredUsers = providerKeyFilteredUsers(
            users,
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        let filteredConsumers = providerKeyFilteredConsumers(
            quotaProjection,
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        let scopeOverview = providerKeyScopeOverview(
            focusedUser: focusedUser,
            focusedVendorDisplayName: focusedVendor?.displayName,
            scopedUsers: scopedUsers,
            scopedConsumers: scopedConsumers,
            families: filteredFamilies
        )
        let riskVendorCount = filteredVendors.filter(providerKeyVendorAtRisk(_:)).count
        let riskFamilyCount = filteredFamilies.filter(providerKeyFamilyAtRisk(_:)).count

        let flowChains: [ProviderKeyFlowChainSummary] = {
            guard providerFlowExpanded else { return [] }
            let flowChainVendors = focusedVendor == nil ? vendorSummaries : filteredVendors
            return providerKeyFlowChains(
                vendors: flowChainVendors,
                users: scopedUsers,
                consumers: scopedConsumers,
                focusedVendor: focusedVendor
            )
        }()

        let overallTrendCard: ProviderKeyTrendCardSummary?
        let vendorTrendCards: [ProviderKeyTrendCardSummary]
        let familyTrendCards: [ProviderKeyTrendCardSummary]
        let userTrendCards: [ProviderKeyTrendCardSummary]
        let consumerTrendCards: [ProviderKeyTrendCardSummary]
        let trendCardCount: Int

        if providerTrendExpanded {
            overallTrendCard = providerKeyOverallTrendCard(
                scopeOverview: scopeOverview,
                consumers: scopedConsumers,
                focusedVendor: focusedVendor
            )
            vendorTrendCards = providerKeyVendorTrendCards(
                vendorSummaries,
                scopedConsumers: scopedConsumers,
                focusedVendor: focusedVendor
            )
            familyTrendCards = providerKeyFamilyTrendCards(filteredFamilies)
            userTrendCards = providerKeyUserTrendCards(
                filteredUsers,
                focusedVendor: focusedVendor
            )
            consumerTrendCards = providerKeyConsumerTrendCards(
                filteredConsumers,
                focusedVendor: focusedVendor
            )
            trendCardCount = providerKeyTrendCardCount(
                overallTrendCard: overallTrendCard,
                vendorTrendCards: vendorTrendCards,
                familyTrendCards: familyTrendCards,
                userTrendCards: userTrendCards,
                consumerTrendCards: consumerTrendCards
            )
        } else {
            overallTrendCard = nil
            vendorTrendCards = []
            familyTrendCards = []
            userTrendCards = []
            consumerTrendCards = []
            trendCardCount = 0
        }

        return ProviderKeySectionSnapshot(
            keyPools: keyPools,
            overview: quotaProjection.overview,
            totalFamilyCount: quotaProjection.families.count,
            totalConsumerCount: quotaProjection.consumers.count,
            consumerLedgerTotalCount: focusedUser == nil ? quotaProjection.consumers.count : scopedConsumers.count,
            users: users,
            focusedUser: focusedUser,
            scopedUsers: scopedUsers,
            scopedConsumers: scopedConsumers,
            vendorSummaries: vendorSummaries,
            filteredVendors: filteredVendors,
            filteredFamilies: filteredFamilies,
            filteredUsers: filteredUsers,
            filteredConsumers: filteredConsumers,
            focusedVendor: focusedVendor,
            flowChains: flowChains,
            scopeOverview: scopeOverview,
            riskVendorCount: riskVendorCount,
            riskFamilyCount: riskFamilyCount,
            overallTrendCard: overallTrendCard,
            vendorTrendCards: vendorTrendCards,
            familyTrendCards: familyTrendCards,
            userTrendCards: userTrendCards,
            consumerTrendCards: consumerTrendCards,
            trendCardCount: trendCardCount,
            operationalTint: providerKeyOperationalTint(
                focusedUser: focusedUser,
                focusedVendor: focusedVendor,
                riskVendorCount: riskVendorCount,
                riskFamilyCount: riskFamilyCount
            )
        )
    }
}
