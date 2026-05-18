import Foundation
import RELFlowHubCore

enum RemoteQuotaCenterConsumerKind: String, Codable, Equatable, Sendable {
    case pairedXT = "paired_xt"
    case terminalAccess = "terminal_access"

    var title: String {
        switch self {
        case .pairedXT:
            return "XT"
        case .terminalAccess:
            return "Terminal"
        }
    }
}

enum RemoteQuotaCenterUserGroupingKind: String, Codable, Equatable, Sendable {
    case userID = "user_id"
    case standaloneConsumer = "standalone_consumer"

    var title: String {
        switch self {
        case .userID:
            return "User"
        case .standaloneConsumer:
            return "未绑定 User"
        }
    }
}

struct RemoteQuotaCenterOverview: Equatable {
    var quotaPoolCount: Int
    var keyPoolCount: Int
    var totalKeys: Int
    var readyKeys: Int
    var cooldownKeys: Int
    var blockedKeys: Int
    var knownQuotaKeys: Int
    var totalDailyTokenCap: Int64
    var totalDailyTokensUsed: Int64
    var totalDailyTokensRemaining: Int64
    var userCount: Int
    var consumerCount: Int
    var connectedConsumerCount: Int
    var xtConsumerCount: Int
    var terminalConsumerCount: Int
    var allocatedDailyTokenBudget: Int64
    var unlimitedBudgetConsumerCount: Int
    var observedConsumerTokensUsed: Int64
    var oversubscribedFamilyCount: Int

    var paidClientCount: Int { consumerCount }
    var connectedPaidClientCount: Int { connectedConsumerCount }
    var unlimitedBudgetClientCount: Int { unlimitedBudgetConsumerCount }
    var observedClientTokensUsed: Int64 { observedConsumerTokensUsed }
}

struct RemoteQuotaCenterClientProjection: Identifiable, Equatable {
    let consumerKind: RemoteQuotaCenterConsumerKind
    let grpcClient: HubGRPCClientEntry?
    let terminalAccessKey: HubTerminalAccessKey?
    let deviceStatus: GRPCDeviceStatusEntry?
    let referenceID: String
    let deviceId: String
    let name: String
    let userId: String
    let appId: String
    let paidPolicyMode: String
    let paidPolicyTitle: String
    let paidModelCount: Int
    let allowsAllFamilies: Bool
    let familyKeys: [String]
    let familyDisplayNames: [String]
    let defaultWebFetchEnabled: Bool
    let dailyTokenLimit: Int64
    let dailyTokenUsed: Int64
    let remainingDailyTokenBudget: Int64
    let observedDailyTokensByFamily: [String: Int64]
    let topModel: String

    var id: String { "\(consumerKind.rawValue):\(referenceID)" }
    var connected: Bool { deviceStatus?.connected == true }
    var kindTitle: String { consumerKind.title }
    var managementTitle: String { consumerKind == .terminalAccess ? "管理 Key" : "编辑预算" }
    var isTerminalAccess: Bool { consumerKind == .terminalAccess }

    func observedDailyTokens(for familyKey: String) -> Int64 {
        max(Int64(0), observedDailyTokensByFamily[familyKey] ?? 0)
    }
}

struct RemoteQuotaCenterUserProjection: Identifiable, Equatable {
    let groupingKind: RemoteQuotaCenterUserGroupingKind
    let groupingKey: String
    let groupingValue: String
    let displayName: String
    let consumers: [RemoteQuotaCenterClientProjection]
    let appIds: [String]
    let familyKeys: [String]
    let familyDisplayNames: [String]
    let consumerCount: Int
    let xtConsumerCount: Int
    let terminalConsumerCount: Int
    let connectedConsumerCount: Int
    let allocatedDailyTokenBudget: Int64
    let unlimitedBudgetConsumerCount: Int
    let observedDailyTokensUsed: Int64
    let remainingDailyTokenBudget: Int64

    var id: String { groupingKey }
    var hasUnlimitedBudget: Bool { unlimitedBudgetConsumerCount > 0 }
    var isStandaloneConsumer: Bool { groupingKind == .standaloneConsumer }
}

struct RemoteQuotaCenterFamilyProjection: Identifiable, Equatable {
    let quotaPool: ProviderQuotaPoolSnapshot
    let assignedConsumers: [RemoteQuotaCenterClientProjection]
    let assignedDailyTokenBudget: Int64
    let unlimitedBudgetClientCount: Int
    let connectedAssignedClientCount: Int
    let observedDailyTokensUsed: Int64

    var id: String { quotaPool.familyKey }
    var familyKey: String { quotaPool.familyKey }
    var displayName: String { quotaPool.displayName }
    var combinedDailyTokenCap: Int64 { max(Int64(0), quotaPool.exclusiveDailyTokenCap) + max(Int64(0), quotaPool.sharedDailyTokenCap) }
    var combinedDailyTokensUsed: Int64 { max(Int64(0), quotaPool.exclusiveDailyTokensUsed) + max(Int64(0), quotaPool.sharedDailyTokensUsed) }
    var combinedDailyTokensRemaining: Int64 {
        max(Int64(0), quotaPool.exclusiveDailyTokensRemaining) + max(Int64(0), quotaPool.sharedDailyTokensRemaining)
    }
    var assignedClientCount: Int { assignedConsumers.count }
    var assignedClients: [RemoteQuotaCenterClientProjection] { assignedConsumers }
    var isOversubscribed: Bool {
        combinedDailyTokenCap > 0 && assignedDailyTokenBudget > combinedDailyTokenCap
    }
}

struct RemoteQuotaCenterProjection: Equatable {
    var overview: RemoteQuotaCenterOverview
    var users: [RemoteQuotaCenterUserProjection]
    var families: [RemoteQuotaCenterFamilyProjection]
    var consumers: [RemoteQuotaCenterClientProjection]

    var paidClients: [RemoteQuotaCenterClientProjection] { consumers }
}

enum RemoteQuotaCenterSupport {
    static func projection(
        providerKeySnapshot: ProviderKeyStoreSnapshot,
        remoteModels: [RemoteModelEntry],
        clients: [HubGRPCClientEntry],
        terminalAccessKeys: [HubTerminalAccessKey] = [],
        deviceStatusSnapshot: GRPCDevicesStatusSnapshot
    ) -> RemoteQuotaCenterProjection {
        let quotaPools = providerKeySnapshot.quotaPools
        let allFamilyDescriptors = uniqueOrderedFamilyDescriptors(
            quotaPools.map {
                SupplierDescriptor(
                    key: $0.familyKey,
                    displayName: $0.displayName
                )
            }
        )
        let allFamilyKeys = allFamilyDescriptors.map(\.key)
        let familyDisplayNameByKey = Dictionary(
            uniqueKeysWithValues: allFamilyDescriptors.map { ($0.key, $0.displayName) }
        )

        let deviceStatusById = Dictionary(
            uniqueKeysWithValues: deviceStatusSnapshot.devices.map { ($0.deviceId, $0) }
        )
        let remoteModelFamilyByLookupToken = remoteModelFamilyLookup(remoteModels)

        let xtConsumers = clients.compactMap { client in
            grpcConsumerProjection(
                client: client,
                deviceStatus: deviceStatusById[client.deviceId],
                allFamilyKeys: allFamilyKeys,
                familyDisplayNameByKey: familyDisplayNameByKey,
                remoteModelFamilyByLookupToken: remoteModelFamilyByLookupToken
            )
        }
        let terminalConsumers = terminalAccessKeys.compactMap { accessKey in
            terminalAccessConsumerProjection(
                accessKey: accessKey,
                deviceStatus: deviceStatusById[accessKey.deviceID],
                allFamilyKeys: allFamilyKeys,
                familyDisplayNameByKey: familyDisplayNameByKey,
                remoteModelFamilyByLookupToken: remoteModelFamilyByLookupToken
            )
        }
        let consumers = (xtConsumers + terminalConsumers)
            .sorted(by: sortPaidClientProjection(_:_:))
        let users = userProjections(consumers)

        let observedTokensByFamily = observedDailyTokensByFamily(consumers)

        let families = quotaPools.map { pool in
            let assignedConsumers = consumers.filter {
                $0.allowsAllFamilies || $0.familyKeys.contains(pool.familyKey)
            }
            let assignedBudget = assignedConsumers.reduce(Int64(0)) { partial, consumer in
                partial + max(Int64(0), consumer.dailyTokenLimit)
            }
            let unlimitedCount = assignedConsumers.filter { $0.dailyTokenLimit <= 0 }.count
            let connectedCount = assignedConsumers.filter(\.connected).count
            return RemoteQuotaCenterFamilyProjection(
                quotaPool: pool,
                assignedConsumers: assignedConsumers,
                assignedDailyTokenBudget: assignedBudget,
                unlimitedBudgetClientCount: unlimitedCount,
                connectedAssignedClientCount: connectedCount,
                observedDailyTokensUsed: observedTokensByFamily[pool.familyKey] ?? 0
            )
        }
        .sorted(by: sortFamilyProjection(_:_:))

        let allAccounts = providerKeySnapshot.allAccounts
        let knownQuotaKeys = allAccounts.filter(hasKnownQuotaData(_:)).count
        let overview = RemoteQuotaCenterOverview(
            quotaPoolCount: quotaPools.count,
            keyPoolCount: providerKeySnapshot.keyPools.count,
            totalKeys: providerKeySnapshot.totalAccounts,
            readyKeys: providerKeySnapshot.readyAccounts,
            cooldownKeys: providerKeySnapshot.cooldownAccounts,
            blockedKeys: providerKeySnapshot.blockedAccounts,
            knownQuotaKeys: knownQuotaKeys,
            totalDailyTokenCap: allAccounts.reduce(Int64(0)) { $0 + max(Int64(0), $1.quota.dailyTokenCap) },
            totalDailyTokensUsed: allAccounts.reduce(Int64(0)) { $0 + max(Int64(0), $1.quota.dailyTokensUsed) },
            totalDailyTokensRemaining: allAccounts.reduce(Int64(0)) { $0 + max(Int64(0), $1.quota.dailyTokensRemaining) },
            userCount: users.count,
            consumerCount: consumers.count,
            connectedConsumerCount: consumers.filter(\.connected).count,
            xtConsumerCount: consumers.filter { $0.consumerKind == .pairedXT }.count,
            terminalConsumerCount: consumers.filter { $0.consumerKind == .terminalAccess }.count,
            allocatedDailyTokenBudget: consumers.reduce(Int64(0)) { $0 + max(Int64(0), $1.dailyTokenLimit) },
            unlimitedBudgetConsumerCount: consumers.filter { $0.dailyTokenLimit <= 0 }.count,
            observedConsumerTokensUsed: consumers.reduce(Int64(0)) { $0 + max(Int64(0), $1.dailyTokenUsed) },
            oversubscribedFamilyCount: families.filter(\.isOversubscribed).count
        )

        return RemoteQuotaCenterProjection(
            overview: overview,
            users: users,
            families: families,
            consumers: consumers
        )
    }

    private static func userProjections(
        _ consumers: [RemoteQuotaCenterClientProjection]
    ) -> [RemoteQuotaCenterUserProjection] {
        var grouped: [String: (descriptor: ConsumerOwnerDescriptor, consumers: [RemoteQuotaCenterClientProjection])] = [:]

        for consumer in consumers {
            let descriptor = consumerOwnerDescriptor(for: consumer)
            if grouped[descriptor.key] == nil {
                grouped[descriptor.key] = (descriptor: descriptor, consumers: [])
            }
            grouped[descriptor.key]?.consumers.append(consumer)
        }

        return grouped.values
            .map { entry in
                let groupedConsumers = entry.consumers.sorted(by: sortPaidClientProjection(_:_:))
                let familyDescriptors = uniqueOrderedFamilyDescriptors(
                    groupedConsumers.flatMap { consumer in
                        zip(consumer.familyKeys, consumer.familyDisplayNames).map {
                            SupplierDescriptor(key: $0.0, displayName: $0.1)
                        }
                    }
                )

                return RemoteQuotaCenterUserProjection(
                    groupingKind: entry.descriptor.groupingKind,
                    groupingKey: entry.descriptor.key,
                    groupingValue: entry.descriptor.groupingValue,
                    displayName: entry.descriptor.displayName,
                    consumers: groupedConsumers,
                    appIds: uniqueOrderedStrings(groupedConsumers.map(\.appId)),
                    familyKeys: familyDescriptors.map(\.key),
                    familyDisplayNames: familyDescriptors.map(\.displayName),
                    consumerCount: groupedConsumers.count,
                    xtConsumerCount: groupedConsumers.filter { $0.consumerKind == .pairedXT }.count,
                    terminalConsumerCount: groupedConsumers.filter { $0.consumerKind == .terminalAccess }.count,
                    connectedConsumerCount: groupedConsumers.filter(\.connected).count,
                    allocatedDailyTokenBudget: groupedConsumers.reduce(Int64(0)) { partial, consumer in
                        partial + max(Int64(0), consumer.dailyTokenLimit)
                    },
                    unlimitedBudgetConsumerCount: groupedConsumers.filter { $0.dailyTokenLimit <= 0 }.count,
                    observedDailyTokensUsed: groupedConsumers.reduce(Int64(0)) { partial, consumer in
                        partial + max(Int64(0), consumer.dailyTokenUsed)
                    },
                    remainingDailyTokenBudget: groupedConsumers.reduce(Int64(0)) { partial, consumer in
                        partial + max(Int64(0), consumer.remainingDailyTokenBudget)
                    }
                )
            }
            .sorted(by: sortUserProjection(_:_:))
    }

    private static func grpcConsumerProjection(
        client: HubGRPCClientEntry,
        deviceStatus: GRPCDeviceStatusEntry?,
        allFamilyKeys: [String],
        familyDisplayNameByKey: [String: String],
        remoteModelFamilyByLookupToken: [String: SupplierDescriptor]
    ) -> RemoteQuotaCenterClientProjection? {
        let trimmedCapabilities = Set(client.capabilities.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        let legacyPaidEnabled = trimmedCapabilities.contains("ai.generate.paid")
        let legacyWebFetchEnabled = trimmedCapabilities.contains("web.fetch")
        let profile = client.approvedTrustProfile

        let paidMode: String
        let paidTitle: String
        let allowedModelIds: [String]
        let defaultWebFetchEnabled: Bool
        let dailyTokenLimit: Int64

        if client.policyMode == .newProfile, let profile {
            paidMode = profile.paidModelPolicy.mode.rawValue
            switch profile.paidModelPolicy.mode {
            case .off:
                paidTitle = HubUIStrings.Settings.GRPC.DeviceList.policyModeLabel("off")
            case .allPaidModels:
                paidTitle = HubUIStrings.Settings.GRPC.DeviceList.policyModeLabel("all_paid_models")
            case .customSelectedModels:
                paidTitle = HubUIStrings.Settings.GRPC.DeviceList.policyModeLabel("custom_selected_models")
            }
            allowedModelIds = profile.paidModelPolicy.allowedModelIds
            defaultWebFetchEnabled = profile.networkPolicy.defaultWebFetchEnabled
            dailyTokenLimit = Int64(max(0, profile.budgetPolicy.dailyTokenLimit))
        } else {
            guard legacyPaidEnabled else { return nil }
            paidMode = "legacy_grant"
            paidTitle = HubUIStrings.Settings.GRPC.DeviceList.policyModeLabel("legacy_grant")
            allowedModelIds = []
            defaultWebFetchEnabled = legacyWebFetchEnabled
            dailyTokenLimit = max(
                Int64(0),
                deviceStatus?.dailyTokenLimit ?? 0
            )
        }

        if paidMode == HubPaidModelSelectionMode.off.rawValue {
            return nil
        }

        let allowsAllFamilies = paidMode == HubPaidModelSelectionMode.allPaidModels.rawValue || paidMode == "legacy_grant"
        let familyDescriptors = familyDescriptors(
            allowsAllFamilies: allowsAllFamilies,
            allowedModelIds: allowedModelIds,
            allFamilyKeys: allFamilyKeys,
            familyDisplayNameByKey: familyDisplayNameByKey,
            remoteModelFamilyByLookupToken: remoteModelFamilyByLookupToken
        )

        let used = max(Int64(0), deviceStatus?.dailyTokenUsed ?? 0)
        let remaining = remainingBudget(
            dailyTokenLimit: dailyTokenLimit,
            dailyTokenUsed: used,
            deviceStatus: deviceStatus
        )
        let observedDailyTokensByFamily = observedDailyTokensByFamily(
            deviceStatus,
            remoteModelFamilyByLookupToken: remoteModelFamilyByLookupToken
        )

        let displayName = client.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? client.deviceId
            : client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let userId = client.userId.trimmingCharacters(in: .whitespacesAndNewlines)

        return RemoteQuotaCenterClientProjection(
            consumerKind: .pairedXT,
            grpcClient: client,
            terminalAccessKey: nil,
            deviceStatus: deviceStatus,
            referenceID: client.deviceId,
            deviceId: client.deviceId,
            name: displayName,
            userId: userId,
            appId: client.appId.trimmingCharacters(in: .whitespacesAndNewlines),
            paidPolicyMode: paidMode,
            paidPolicyTitle: paidTitle,
            paidModelCount: allowsAllFamilies ? 0 : allowedModelIds.count,
            allowsAllFamilies: allowsAllFamilies,
            familyKeys: familyDescriptors.map(\.key),
            familyDisplayNames: familyDescriptors.map(\.displayName),
            defaultWebFetchEnabled: defaultWebFetchEnabled,
            dailyTokenLimit: dailyTokenLimit,
            dailyTokenUsed: used,
            remainingDailyTokenBudget: remaining,
            observedDailyTokensByFamily: observedDailyTokensByFamily,
            topModel: deviceStatus?.topModel.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private static func terminalAccessConsumerProjection(
        accessKey: HubTerminalAccessKey,
        deviceStatus: GRPCDeviceStatusEntry?,
        allFamilyKeys: [String],
        familyDisplayNameByKey: [String: String],
        remoteModelFamilyByLookupToken: [String: SupplierDescriptor]
    ) -> RemoteQuotaCenterClientProjection? {
        guard accessKey.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ready",
              accessKey.enabled else {
            return nil
        }

        let paidMode = accessKey.paidModelSelectionMode.rawValue
        guard paidMode != HubPaidModelSelectionMode.off.rawValue else { return nil }

        let profile = accessKey.approvedTrustProfile
        let paidTitle: String
        switch accessKey.paidModelSelectionMode {
        case .off:
            paidTitle = HubUIStrings.Settings.GRPC.DeviceList.policyModeLabel("off")
        case .allPaidModels:
            paidTitle = HubUIStrings.Settings.GRPC.DeviceList.policyModeLabel("all_paid_models")
        case .customSelectedModels:
            paidTitle = HubUIStrings.Settings.GRPC.DeviceList.policyModeLabel("custom_selected_models")
        }

        let allowedModelIds = profile?.paidModelPolicy.allowedModelIds ?? []
        let allowsAllFamilies = accessKey.paidModelSelectionMode == .allPaidModels
        let familyDescriptors = familyDescriptors(
            allowsAllFamilies: allowsAllFamilies,
            allowedModelIds: allowedModelIds,
            allFamilyKeys: allFamilyKeys,
            familyDisplayNameByKey: familyDisplayNameByKey,
            remoteModelFamilyByLookupToken: remoteModelFamilyByLookupToken
        )

        let dailyTokenLimit = Int64(max(0, accessKey.dailyTokenLimit))
        let used = max(Int64(0), deviceStatus?.dailyTokenUsed ?? 0)
        let remaining = remainingBudget(
            dailyTokenLimit: dailyTokenLimit,
            dailyTokenUsed: used,
            deviceStatus: deviceStatus
        )
        let observedDailyTokensByFamily = observedDailyTokensByFamily(
            deviceStatus,
            remoteModelFamilyByLookupToken: remoteModelFamilyByLookupToken
        )

        return RemoteQuotaCenterClientProjection(
            consumerKind: .terminalAccess,
            grpcClient: nil,
            terminalAccessKey: accessKey,
            deviceStatus: deviceStatus,
            referenceID: accessKey.accessKeyID,
            deviceId: accessKey.deviceID.trimmingCharacters(in: .whitespacesAndNewlines),
            name: accessKey.resolvedName,
            userId: accessKey.userID.trimmingCharacters(in: .whitespacesAndNewlines),
            appId: accessKey.appID.trimmingCharacters(in: .whitespacesAndNewlines),
            paidPolicyMode: paidMode,
            paidPolicyTitle: paidTitle,
            paidModelCount: allowsAllFamilies ? 0 : allowedModelIds.count,
            allowsAllFamilies: allowsAllFamilies,
            familyKeys: familyDescriptors.map(\.key),
            familyDisplayNames: familyDescriptors.map(\.displayName),
            defaultWebFetchEnabled: accessKey.defaultWebFetchEnabled,
            dailyTokenLimit: dailyTokenLimit,
            dailyTokenUsed: used,
            remainingDailyTokenBudget: remaining,
            observedDailyTokensByFamily: observedDailyTokensByFamily,
            topModel: deviceStatus?.topModel.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private static func familyDescriptors(
        allowsAllFamilies: Bool,
        allowedModelIds: [String],
        allFamilyKeys: [String],
        familyDisplayNameByKey: [String: String],
        remoteModelFamilyByLookupToken: [String: SupplierDescriptor]
    ) -> [SupplierDescriptor] {
        if allowsAllFamilies {
            return uniqueOrderedFamilyDescriptors(
                allFamilyKeys.compactMap { key in
                    let displayName = familyDisplayNameByKey[key] ?? key
                    return SupplierDescriptor(key: key, displayName: displayName)
                }
            )
        }
        return uniqueOrderedFamilyDescriptors(
            allowedModelIds.compactMap {
                familyDescriptor(
                    lookupToken: $0,
                    remoteModelFamilyByLookupToken: remoteModelFamilyByLookupToken
                )
            }
        )
    }

    private static func remainingBudget(
        dailyTokenLimit: Int64,
        dailyTokenUsed: Int64,
        deviceStatus: GRPCDeviceStatusEntry?
    ) -> Int64 {
        if let deviceStatus {
            return max(Int64(0), deviceStatus.remainingDailyTokenBudget)
        }
        if dailyTokenLimit > 0 {
            return max(Int64(0), dailyTokenLimit - dailyTokenUsed)
        }
        return 0
    }

    private static func observedDailyTokensByFamily(
        _ deviceStatus: GRPCDeviceStatusEntry?,
        remoteModelFamilyByLookupToken: [String: SupplierDescriptor]
    ) -> [String: Int64] {
        guard let deviceStatus else { return [:] }
        var totals: [String: Int64] = [:]
        if deviceStatus.modelBreakdown.isEmpty {
            guard deviceStatus.dailyTokenUsed > 0,
                  let descriptor = familyDescriptor(
                    lookupToken: deviceStatus.topModel,
                    remoteModelFamilyByLookupToken: remoteModelFamilyByLookupToken
                  ) else {
                return totals
            }
            totals[descriptor.key, default: 0] += max(Int64(0), deviceStatus.dailyTokenUsed)
            return totals
        }
        for row in deviceStatus.modelBreakdown {
            guard let descriptor = familyDescriptor(
                lookupToken: row.modelId,
                remoteModelFamilyByLookupToken: remoteModelFamilyByLookupToken
            ) else {
                continue
            }
            totals[descriptor.key, default: 0] += max(Int64(0), row.totalTokens)
        }
        return totals
    }

    private static func observedDailyTokensByFamily(
        _ consumers: [RemoteQuotaCenterClientProjection]
    ) -> [String: Int64] {
        var totals: [String: Int64] = [:]
        for consumer in consumers {
            for (familyKey, tokenCount) in consumer.observedDailyTokensByFamily {
                totals[familyKey, default: 0] += max(Int64(0), tokenCount)
            }
        }
        return totals
    }

    private static func remoteModelFamilyLookup(
        _ remoteModels: [RemoteModelEntry]
    ) -> [String: SupplierDescriptor] {
        var out: [String: SupplierDescriptor] = [:]
        for model in remoteModels {
            guard let descriptor = familyDescriptor(for: model) else { continue }
            let tokens = [
                normalizedLookupToken(model.id),
                normalizedLookupToken(model.effectiveProviderModelID),
                normalizedLookupToken(model.name)
            ]
            for token in tokens where !token.isEmpty {
                out[token] = descriptor
            }
        }
        return out
    }

    private static func familyDescriptor(
        lookupToken rawLookupToken: String,
        remoteModelFamilyByLookupToken: [String: SupplierDescriptor]
    ) -> SupplierDescriptor? {
        let normalizedToken = normalizedLookupToken(rawLookupToken)
        if let exact = remoteModelFamilyByLookupToken[normalizedToken] {
            return exact
        }
        return familyDescriptorForModelID(rawLookupToken)
    }

    private static func familyDescriptor(for model: RemoteModelEntry) -> SupplierDescriptor? {
        if let exact = familyDescriptorForModelID(model.effectiveProviderModelID) {
            return exact
        }
        if let exact = familyDescriptorForModelID(model.id) {
            return exact
        }
        let provider = model.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = URL(string: model.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")?
            .host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return fallbackFamilyDescriptor(provider: provider, providerHost: host)
    }

    private static func familyDescriptorForModelID(_ rawModelID: String) -> SupplierDescriptor? {
        let normalized = rawModelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        let modelID = normalized
            .split(separator: "/")
            .last
            .map(String.init) ?? normalized

        if modelID.hasPrefix("gpt")
            || modelID.hasPrefix("o1")
            || modelID.hasPrefix("o3")
            || modelID.hasPrefix("o4")
            || modelID.hasPrefix("chatgpt") {
            return SupplierDescriptor(key: "openai", displayName: "OpenAI")
        }
        if modelID.hasPrefix("claude") {
            return SupplierDescriptor(key: "claude", displayName: "Claude")
        }
        if modelID.hasPrefix("gemini") {
            return SupplierDescriptor(key: "gemini", displayName: "Gemini")
        }
        if modelID.hasPrefix("deepseek") {
            return SupplierDescriptor(key: "deepseek", displayName: "DeepSeek")
        }
        if modelID.hasPrefix("qwen")
            || modelID.hasPrefix("qwq")
            || modelID.hasPrefix("qvq")
            || modelID.hasPrefix("tongyi") {
            return SupplierDescriptor(key: "qwen", displayName: "Qwen")
        }
        if modelID.hasPrefix("kimi") || modelID.hasPrefix("moonshot") {
            return SupplierDescriptor(key: "kimi", displayName: "Kimi")
        }
        if modelID.hasPrefix("grok") || modelID.hasPrefix("xai") {
            return SupplierDescriptor(key: "xai", displayName: "xAI")
        }
        if modelID.hasPrefix("glm") || modelID.hasPrefix("zhipu") {
            return SupplierDescriptor(key: "glm", displayName: "GLM")
        }
        if modelID.hasPrefix("mistral") {
            return SupplierDescriptor(key: "mistral", displayName: "Mistral")
        }
        if modelID.hasPrefix("llama") || modelID.hasPrefix("meta-llama") {
            return SupplierDescriptor(key: "llama", displayName: "Llama")
        }
        if modelID.hasPrefix("doubao") {
            return SupplierDescriptor(key: "doubao", displayName: "Doubao")
        }
        if modelID.hasPrefix("hunyuan") {
            return SupplierDescriptor(key: "hunyuan", displayName: "Hunyuan")
        }
        return nil
    }

    private static func fallbackFamilyDescriptor(
        provider: String,
        providerHost: String
    ) -> SupplierDescriptor? {
        let alias = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = providerHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if alias == "openai" || alias == "codex" || host.contains("openai.com") {
            return SupplierDescriptor(key: "openai", displayName: "OpenAI")
        }
        if alias == "claude" || alias == "anthropic" || host.contains("anthropic.com") {
            return SupplierDescriptor(key: "claude", displayName: "Claude")
        }
        if alias == "gemini" || alias == "google" || host.contains("googleapis.com") || host.contains("gemini") {
            return SupplierDescriptor(key: "gemini", displayName: "Gemini")
        }
        if alias == "qwen" || alias == "dashscope" || host.contains("dashscope") {
            return SupplierDescriptor(key: "qwen", displayName: "Qwen")
        }
        if alias == "deepseek" || host.contains("deepseek") {
            return SupplierDescriptor(key: "deepseek", displayName: "DeepSeek")
        }
        if alias == "xai" || alias == "grok" || host.contains("x.ai") || host.contains("grok") {
            return SupplierDescriptor(key: "xai", displayName: "xAI")
        }
        if alias == "glm" || alias == "zhipu" || host.contains("bigmodel.cn") || host.contains("glm") {
            return SupplierDescriptor(key: "glm", displayName: "GLM")
        }
        return nil
    }

    private static func uniqueOrderedFamilyDescriptors(
        _ values: [SupplierDescriptor]
    ) -> [SupplierDescriptor] {
        var out: [SupplierDescriptor] = []
        var seen: Set<String> = []
        for value in values {
            let key = value.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let displayName = value.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !displayName.isEmpty else { continue }
            guard seen.insert(key).inserted else { continue }
            out.append(SupplierDescriptor(key: key, displayName: displayName))
        }
        return out
    }

    private static func uniqueOrderedStrings(
        _ values: [String]
    ) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(normalized).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    private static func hasKnownQuotaData(_ account: ProviderKeyAccount) -> Bool {
        account.quota.dailyTokenCap > 0
            || account.quota.dailyTokensUsed > 0
            || account.quota.dailyTokensRemaining > 0
            || account.quota.totalTokensUsed > 0
            || account.quota.lastUsedAtMs > 0
            || account.quota.lastErrorAtMs > 0
            || !account.quota.usageWindows.isEmpty
    }

    private static func normalizedLookupToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func sortPaidClientProjection(
        _ lhs: RemoteQuotaCenterClientProjection,
        _ rhs: RemoteQuotaCenterClientProjection
    ) -> Bool {
        if lhs.connected != rhs.connected { return lhs.connected && !rhs.connected }
        if lhs.dailyTokenUsed != rhs.dailyTokenUsed { return lhs.dailyTokenUsed > rhs.dailyTokenUsed }
        if lhs.dailyTokenLimit != rhs.dailyTokenLimit { return lhs.dailyTokenLimit > rhs.dailyTokenLimit }
        if lhs.consumerKind != rhs.consumerKind {
            return lhs.consumerKind.rawValue.localizedCaseInsensitiveCompare(rhs.consumerKind.rawValue) == .orderedAscending
        }
        if lhs.name.localizedCaseInsensitiveCompare(rhs.name) != .orderedSame {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhs.referenceID.localizedCaseInsensitiveCompare(rhs.referenceID) == .orderedAscending
    }

    private static func sortFamilyProjection(
        _ lhs: RemoteQuotaCenterFamilyProjection,
        _ rhs: RemoteQuotaCenterFamilyProjection
    ) -> Bool {
        if lhs.observedDailyTokensUsed != rhs.observedDailyTokensUsed {
            return lhs.observedDailyTokensUsed > rhs.observedDailyTokensUsed
        }
        if lhs.assignedDailyTokenBudget != rhs.assignedDailyTokenBudget {
            return lhs.assignedDailyTokenBudget > rhs.assignedDailyTokenBudget
        }
        if lhs.assignedClientCount != rhs.assignedClientCount {
            return lhs.assignedClientCount > rhs.assignedClientCount
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func sortUserProjection(
        _ lhs: RemoteQuotaCenterUserProjection,
        _ rhs: RemoteQuotaCenterUserProjection
    ) -> Bool {
        if lhs.observedDailyTokensUsed != rhs.observedDailyTokensUsed {
            return lhs.observedDailyTokensUsed > rhs.observedDailyTokensUsed
        }
        if lhs.allocatedDailyTokenBudget != rhs.allocatedDailyTokenBudget {
            return lhs.allocatedDailyTokenBudget > rhs.allocatedDailyTokenBudget
        }
        if lhs.consumerCount != rhs.consumerCount {
            return lhs.consumerCount > rhs.consumerCount
        }
        if lhs.groupingKind != rhs.groupingKind {
            return lhs.groupingKind == .userID
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func consumerOwnerDescriptor(
        for consumer: RemoteQuotaCenterClientProjection
    ) -> ConsumerOwnerDescriptor {
        let userId = consumer.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !userId.isEmpty {
            return ConsumerOwnerDescriptor(
                groupingKind: .userID,
                key: "user:\(userId.lowercased())",
                groupingValue: userId,
                displayName: userId
            )
        }

        let fallbackDisplayName = consumer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? consumer.referenceID
            : consumer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConsumerOwnerDescriptor(
            groupingKind: .standaloneConsumer,
            key: "consumer:\(consumer.id)",
            groupingValue: consumer.referenceID,
            displayName: fallbackDisplayName
        )
    }
}

private struct SupplierDescriptor: Equatable {
    var key: String
    var displayName: String
}

private struct ConsumerOwnerDescriptor: Equatable {
    var groupingKind: RemoteQuotaCenterUserGroupingKind
    var key: String
    var groupingValue: String
    var displayName: String
}
