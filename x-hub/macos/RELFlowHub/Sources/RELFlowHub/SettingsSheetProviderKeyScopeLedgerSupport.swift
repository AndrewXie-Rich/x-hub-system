import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyFocusUserTitle(
        _ user: RemoteQuotaCenterUserProjection
    ) -> String {
        if user.isStandaloneConsumer {
            return "\(user.displayName) · 单 consumer"
        }
        return "\(user.displayName) · \(user.consumerCount) consumer"
    }

    func providerKeyFocusVendorTitle(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> String {
        "\(vendor.displayName) · \(vendor.readyAccounts)/\(vendor.totalAccounts) Ready"
    }

    func providerKeyFocusedUser(
        _ users: [RemoteQuotaCenterUserProjection]
    ) -> RemoteQuotaCenterUserProjection? {
        let focusKey = remoteQuotaFocusedUserGroupingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !focusKey.isEmpty else { return nil }
        return users.first(where: { $0.groupingKey == focusKey })
    }

    var providerKeyNormalizedFocusedVendorKey: String {
        let focusKey = remoteQuotaFocusedVendorKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !focusKey.isEmpty else { return "" }
        return providerKeyCanonicalVendorKey(focusKey)
    }

    var providerKeyHasFocusedVendor: Bool {
        !providerKeyNormalizedFocusedVendorKey.isEmpty
    }

    func providerKeyFocusedVendor(
        _ vendors: [ProviderKeyVendorInventorySummary]
    ) -> ProviderKeyVendorInventorySummary? {
        let focusKey = providerKeyNormalizedFocusedVendorKey
        guard !focusKey.isEmpty else { return nil }
        return vendors.first { vendor in
            providerKeyCanonicalVendorKey(vendor.vendorKey) == focusKey
        }
    }

    func providerKeyFocusedVendorFamilyKeys(
        _ projection: RemoteQuotaCenterProjection
    ) -> Set<String> {
        let focusKey = providerKeyNormalizedFocusedVendorKey
        guard !focusKey.isEmpty else { return [] }

        let familyKeysFromProjection = projection.families.compactMap { family -> String? in
            let supplierKeys = Set(family.quotaPool.supplierKeys.map(providerKeyCanonicalVendorKey(_:)))
            return supplierKeys.contains(focusKey) ? family.familyKey : nil
        }

        if !familyKeysFromProjection.isEmpty {
            return Set(familyKeysFromProjection)
        }

        let fallbackFamilyKeys = providerKeyDerivedSnapshot.keyPools
            .filter { pool in
                providerKeyCanonicalVendorKey(pool.supplierKey) == focusKey
            }
            .flatMap(\.supportedFamilyKeys)
        return Set(fallbackFamilyKeys)
    }

    func providerKeyConsumerMatchesFocusedVendor(
        _ consumer: RemoteQuotaCenterClientProjection,
        focusedVendorFamilyKeys: Set<String>
    ) -> Bool {
        guard providerKeyHasFocusedVendor else { return true }
        guard !focusedVendorFamilyKeys.isEmpty else { return false }
        if consumer.allowsAllFamilies {
            return true
        }
        return !focusedVendorFamilyKeys.isDisjoint(with: Set(consumer.familyKeys))
    }

    func providerKeyUserMatchesFocusedVendor(
        _ user: RemoteQuotaCenterUserProjection,
        focusedVendorFamilyKeys: Set<String>
    ) -> Bool {
        guard providerKeyHasFocusedVendor else { return true }
        guard !focusedVendorFamilyKeys.isEmpty else { return false }
        if !focusedVendorFamilyKeys.isDisjoint(with: Set(user.familyKeys)) {
            return true
        }
        return user.consumers.contains { consumer in
            providerKeyConsumerMatchesFocusedVendor(
                consumer,
                focusedVendorFamilyKeys: focusedVendorFamilyKeys
            )
        }
    }

    func providerKeyVendorScopedUsers(
        _ users: [RemoteQuotaCenterUserProjection],
        focusedVendorFamilyKeys: Set<String>
    ) -> [RemoteQuotaCenterUserProjection] {
        guard providerKeyHasFocusedVendor else { return users }
        return users.filter { user in
            providerKeyUserMatchesFocusedVendor(
                user,
                focusedVendorFamilyKeys: focusedVendorFamilyKeys
            )
        }
    }

    func providerKeyVendorScopedConsumers(
        _ consumers: [RemoteQuotaCenterClientProjection],
        focusedVendorFamilyKeys: Set<String>
    ) -> [RemoteQuotaCenterClientProjection] {
        guard providerKeyHasFocusedVendor else { return consumers }
        return consumers.filter { consumer in
            providerKeyConsumerMatchesFocusedVendor(
                consumer,
                focusedVendorFamilyKeys: focusedVendorFamilyKeys
            )
        }
    }

    func providerKeyScopedUsers(
        _ users: [RemoteQuotaCenterUserProjection]
    ) -> [RemoteQuotaCenterUserProjection] {
        if let focused = providerKeyFocusedUser(users) {
            return [focused]
        }
        return users
    }

    func providerKeyScopedConsumers(
        _ projection: RemoteQuotaCenterProjection
    ) -> [RemoteQuotaCenterClientProjection] {
        let scopedUsers = providerKeyScopedUsers(projection.users)
        let scopedConsumerIDs = Set(scopedUsers.flatMap { $0.consumers.map(\.id) })
        guard providerKeyFocusedUser(projection.users) != nil, !scopedConsumerIDs.isEmpty else {
            return projection.consumers
        }
        return projection.consumers.filter { scopedConsumerIDs.contains($0.id) }
    }

    func providerKeyFilteredUsers(
        _ users: [RemoteQuotaCenterUserProjection],
        focusedVendorFamilyKeys: Set<String>
    ) -> [RemoteQuotaCenterUserProjection] {
        let scoped = providerKeyVendorScopedUsers(
            providerKeyScopedUsers(users),
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        switch remoteQuotaUserFilter {
        case .all:
            return scoped
        case .risk:
            return scoped.filter(providerKeyUserAtRisk(_:))
        }
    }

    func providerKeyFilteredFamilies(
        _ families: [ProviderKeyFamilyInventorySummary],
        focusedVendorFamilyKeys: Set<String>
    ) -> [ProviderKeyFamilyInventorySummary] {
        guard providerKeyHasFocusedVendor else { return families }
        guard !focusedVendorFamilyKeys.isEmpty else { return [] }
        return families.filter { family in
            focusedVendorFamilyKeys.contains(family.familyKey)
        }
    }

    func providerKeyFilteredVendors(
        _ vendors: [ProviderKeyVendorInventorySummary],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> [ProviderKeyVendorInventorySummary] {
        if providerKeyHasFocusedVendor, focusedVendor == nil {
            return []
        }
        if let focusedVendor {
            return [focusedVendor]
        }
        switch remoteQuotaVendorFilter {
        case .all:
            return vendors
        case .risk:
            return vendors.filter(providerKeyVendorAtRisk(_:))
        }
    }
}
