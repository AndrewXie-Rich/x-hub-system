import Foundation

actor ProviderKeyManager {
    static let shared = ProviderKeyManager()

    private struct SelectionResolution {
        var decision: ProviderKeySelectionDecision
        var selectedAccount: HubProviderKeysClient.ProviderAccount?
    }

    private var accountsCache: [String: [HubProviderKeysClient.ProviderAccount]] = [:]
    private var accountsCacheAt: Double = 0
    private let accountsCacheTTL: Double = 30.0

    private var usageCache: [String: HubProviderKeysClient.KeyUsageInfo] = [:]
    private var usageCacheAt: Double = 0
    private let usageCacheTTL: Double = 10.0
    private var poolCache: [String: HubProviderKeysClient.ProviderPool] = [:]
    private var poolCacheAt: [String: Double] = [:]
    private let poolCacheTTL: Double = 10.0

    private var lastSelectedAccountKey: [String: String] = [:]
    private var lastSelectionDecision: [String: ProviderKeySelectionDecision] = [:]
    private var lastSelectionDecisionByProvider: [String: ProviderKeySelectionDecision] = [:]
    private var lastSelectionDecisionByModelLookup: [String: ProviderKeySelectionDecision] = [:]

    func resolveProviderKey(forModelId modelId: String) async -> HubProviderKeysClient.ProviderAccount? {
        await resolveSelection(forModelId: modelId).selectedAccount
    }

    func resolveProviderKeyDecision(forModelId modelId: String) async -> ProviderKeySelectionDecision {
        await resolveSelection(forModelId: modelId).decision
    }

    func reportFeedback(_ feedback: HubProviderKeysClient.ProviderKeyRuntimeFeedback) async -> Bool {
        guard !feedback.accountKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        invalidateUsageCache(accountKey: feedback.accountKey)
        invalidatePoolCache()

        let result: HubProviderKeysClient.ReportKeyErrorResult
        if feedback.outcome == "success" {
            _ = await HubProviderKeysClient.reportKeyUsage(
                accountKey: feedback.accountKey,
                tokensUsed: feedback.tokensUsed,
                costUsd: feedback.costUsd,
                modelID: feedback.modelID,
                latencyMs: feedback.latencyMs,
                occurredAtMs: feedback.occurredAtMs
            )
            result = HubProviderKeysClient.ReportKeyErrorResult(ok: true, error: "", autoDisabled: false)
        } else {
            result = await HubProviderKeysClient.reportKeyError(
                accountKey: feedback.accountKey,
                errorCode: feedback.reasonCode,
                modelID: feedback.modelID,
                outcome: feedback.outcome,
                httpStatus: feedback.httpStatus,
                reasonCode: feedback.reasonCode,
                statusMessage: feedback.statusMessage,
                latencyMs: feedback.latencyMs,
                occurredAtMs: feedback.occurredAtMs,
                nextRetryAtMs: feedback.nextRetryAtMs,
                retryAtSource: feedback.retryAtSource
            )
        }
        if result.autoDisabled {
            invalidateAccountsCache()
        }
        return result.autoDisabled
    }

    func reportUsage(
        accountKey: String,
        modelID: String,
        tokensUsed: Int64,
        costUsd: Double,
        latencyMs: Int64 = 0,
        occurredAtMs: Int64 = 0
    ) async {
        _ = await reportFeedback(
            ProviderKeyRuntimeFeedbackSupport.successFeedback(
                accountKey: accountKey,
                modelID: modelID,
                tokensUsed: tokensUsed,
                costUsd: costUsd,
                latencyMs: latencyMs,
                occurredAtMs: occurredAtMs == 0
                    ? Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
                    : occurredAtMs
            )
        )
    }

    func reportError(
        accountKey: String,
        modelID: String,
        error: Error,
        statusMessage: String? = nil,
        httpStatus: Int? = nil,
        latencyMs: Int64 = 0,
        occurredAtMs: Int64 = 0
    ) async -> Bool {
        await reportFeedback(
            ProviderKeyRuntimeFeedbackSupport.failureFeedback(
                accountKey: accountKey,
                modelID: modelID,
                error: error,
                statusMessage: statusMessage,
                httpStatus: httpStatus,
                latencyMs: latencyMs,
                occurredAtMs: occurredAtMs == 0
                    ? Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
                    : occurredAtMs
            )
        )
    }

    func resetErrorState(accountKey: String) async {
        invalidateUsageCache(accountKey: accountKey)
        invalidatePoolCache()
        _ = await HubProviderKeysClient.resetKeyErrorState(accountKey: accountKey)
    }

    func refreshAccounts() async {
        invalidateAccountsCache()
        invalidatePoolCache()
        _ = await HubProviderKeysClient.getProviderKeySummary(forceRefresh: true)
    }

    func resetForHubProfileChange() {
        invalidateAccountsCache()
        invalidatePoolCache()
        usageCache.removeAll()
        usageCacheAt = 0
        lastSelectedAccountKey.removeAll()
        ProviderKeySelectionSnapshotStore.shared.removeAll()
    }

    func getUsageForAccount(accountKey: String) async -> HubProviderKeysClient.KeyUsageInfo? {
        let now = Date().timeIntervalSince1970
        if let cached = usageCache[accountKey], (now - usageCacheAt) < usageCacheTTL {
            return cached
        }

        let info = await HubProviderKeysClient.getKeyUsage(accountKey: accountKey)
        if let info = info {
            usageCache[accountKey] = info
            usageCacheAt = now
        }
        return info
    }

    func lastSelectedAccountKeyFor(provider: String) -> String? {
        if let exact = lastSelectedAccountKey[provider] {
            return exact
        }
        let prefix = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "::"
        return lastSelectedAccountKey.first(where: { $0.key.hasPrefix(prefix) })?.value
    }

    func lastSelectionDecisionFor(provider: String) -> ProviderKeySelectionDecision? {
        let normalizedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = lastSelectionDecisionByProvider[normalizedProvider] {
            return exact
        }
        if let exact = lastSelectionDecision[provider] {
            return exact
        }
        let prefix = normalizedProvider + "::"
        if let exact = lastSelectionDecision.first(where: { $0.key.hasPrefix(prefix) })?.value {
            return exact
        }
        return ProviderKeySelectionSnapshotStore.shared.decision(forProvider: provider)
    }

    func lastSelectionDecisionForModel(modelId: String) -> ProviderKeySelectionDecision? {
        let lookupKeys = ProviderKeySelectionSupport.modelLookupKeys(modelId)
        for key in lookupKeys {
            if let decision = lastSelectionDecisionByModelLookup[key] {
                return decision
            }
        }
        let provider = ProviderKeySelectionSupport.inferProvider(fromModelId: modelId)
        if !provider.isEmpty, let decision = lastSelectionDecisionFor(provider: provider) {
            return decision
        }
        return ProviderKeySelectionSnapshotStore.shared.decision(forModelId: modelId)
    }

    func resolveProviderKeyPool(
        forModelId modelId: String,
        forceRefresh: Bool = false
    ) async -> HubProviderKeysClient.ProviderPool? {
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedModelId.isEmpty else { return nil }

        let now = Date().timeIntervalSince1970
        if !forceRefresh,
           let cached = poolCache[normalizedModelId],
           let cachedAt = poolCacheAt[normalizedModelId],
           (now - cachedAt) < poolCacheTTL {
            return cached
        }

        let provider = ProviderKeySelectionSupport.inferProvider(fromModelId: modelId)
        let poolList = await HubProviderKeysClient.listProviderKeyPools(
            provider: provider,
            modelID: modelId,
            includeMembers: true
        )
        if let selectedPool = selectProviderPool(from: poolList.pools, provider: provider) {
            poolCache[normalizedModelId] = selectedPool
            poolCacheAt[normalizedModelId] = now
            ProviderKeyPoolSnapshotStore.shared.record(pool: selectedPool, modelId: modelId)
            return selectedPool
        }

        return ProviderKeyPoolSnapshotStore.shared.pool(forModelId: modelId)
    }

    func lastProviderKeyPoolForModel(modelId: String) -> HubProviderKeysClient.ProviderPool? {
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cached = poolCache[normalizedModelId] {
            return cached
        }
        return ProviderKeyPoolSnapshotStore.shared.pool(forModelId: modelId)
    }

    // MARK: - Private

    private func resolveSelection(
        forModelId modelId: String
    ) async -> SelectionResolution {
        let provider = ProviderKeySelectionSupport.inferProvider(fromModelId: modelId)
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !provider.isEmpty else {
            return SelectionResolution(
                decision: ProviderKeySelectionDecision(
                    requestedProvider: "",
                    requestedModelId: normalizedModelId,
                    strategy: "fill-first",
                    selectionScope: "unknown::\(normalizedModelId)",
                    selectedAccountKey: "",
                    fallbackReasonCode: "unknown_model_provider",
                    candidates: []
                ),
                selectedAccount: nil
            )
        }

        let poolProviders = ProviderKeySelectionSupport.candidateProviders(for: provider)
        let accounts = ProviderKeySelectionSupport.preferredAccounts(
            from: await loadAccounts(for: poolProviders),
            forModelId: modelId
        )

        if let routeDecision = await HubProviderKeysClient.getProviderKeyRouteDecision(modelID: modelId, provider: provider) {
            let decision = selectionDecision(from: routeDecision)
            let selectedAccount = accounts.first { $0.accountKey == decision.selectedAccountKey }
            if let selectedAccount {
                lastSelectedAccountKey[decision.selectionScope] = selectedAccount.accountKey
            }
            _ = await resolveProviderKeyPool(forModelId: modelId)
            lastSelectionDecision[decision.selectionScope] = decision
            lastSelectionDecisionByProvider[provider] = decision
            for lookupKey in ProviderKeySelectionSupport.modelLookupKeys(modelId) {
                lastSelectionDecisionByModelLookup[lookupKey] = decision
            }
            ProviderKeySelectionSnapshotStore.shared.record(decision: decision, modelId: modelId)
            return SelectionResolution(decision: decision, selectedAccount: selectedAccount)
        }

        let summary = await HubProviderKeysClient.getProviderKeySummary()
        let providerSummary = summary.providers.first { $0.provider == provider }
            ?? summary.providers.first { poolProviders.contains($0.provider) }
        let strategy = providerSummary?.routingStrategy ?? summary.globalRoutingStrategy
        let selectionScope = ProviderKeySelectionSupport.selectionScopeKey(
            provider: provider,
            modelId: modelId,
            accounts: accounts
        )
        let runtimeMetadataSnapshot = await HubProviderKeyAccountRuntimeMetadataSnapshotStore.refreshFromHub(
            allowCompatibilityFallback: true
        )
        let runtimeMetadataByAccount = runtimeMetadataSnapshot.mapValues(\.requiredRefreshMetadata)

        var usageByAccount: [String: HubProviderKeysClient.KeyUsageInfo] = [:]
        for account in accounts {
            if let usage = await getUsageForAccount(accountKey: account.accountKey) {
                usageByAccount[account.accountKey] = usage
            }
        }

        let decision = ProviderKeySelectionSupport.selectionDecision(
            provider: provider,
            modelId: modelId,
            strategy: strategy,
            selectionScope: selectionScope,
            accounts: accounts,
            usageByAccount: usageByAccount,
            requiredMetadataByAccount: runtimeMetadataByAccount,
            nowMs: Date().timeIntervalSince1970 * 1000,
            lastSelectedAccountKey: lastSelectedAccountKey[selectionScope]
        )
        let selectedAccount = accounts.first { $0.accountKey == decision.selectedAccountKey }
        if let selectedAccount {
            lastSelectedAccountKey[selectionScope] = selectedAccount.accountKey
        }
        _ = await resolveProviderKeyPool(forModelId: modelId)
        lastSelectionDecision[selectionScope] = decision
        lastSelectionDecisionByProvider[provider] = decision
        for lookupKey in ProviderKeySelectionSupport.modelLookupKeys(modelId) {
            lastSelectionDecisionByModelLookup[lookupKey] = decision
        }
        ProviderKeySelectionSnapshotStore.shared.record(decision: decision, modelId: modelId)
        return SelectionResolution(decision: decision, selectedAccount: selectedAccount)
    }

    private func selectionDecision(
        from routeDecision: HubProviderKeysClient.ProviderRouteDecision
    ) -> ProviderKeySelectionDecision {
        ProviderKeySelectionDecision(
            requestedProvider: routeDecision.requestedProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            requestedModelId: routeDecision.requestedModelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            strategy: routeDecision.strategy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().isEmpty
                ? "fill-first"
                : routeDecision.strategy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            selectionScope: routeDecision.selectionScope,
            selectedAccountKey: routeDecision.selectedAccountKey,
            fallbackReasonCode: routeDecision.fallbackReasonCode,
            candidates: routeDecision.candidates.map { candidate in
                ProviderKeyCandidateDecision(
                    accountKey: candidate.accountKey,
                    provider: candidate.provider,
                    poolID: candidate.poolID,
                    wireAPI: candidate.wireAPI,
                    availability: availabilityState(from: candidate),
                    score: candidate.score,
                    selected: candidate.selected,
                    reasonCode: candidate.reasonCode,
                    retryAtMs: candidate.retryAtMs,
                    retryAtSource: candidate.retryAtSource,
                    statusMessage: candidate.statusMessage,
                    requiredMetadata: candidate.requiredRefreshMetadata
                )
            }
        )
    }

    private func availabilityState(
        from candidate: HubProviderKeysClient.ProviderRouteCandidateDecision
    ) -> ProviderKeyAvailabilityState {
        let reasonCode = candidate.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch candidate.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ready":
            return .ready
        case "cooldown":
            return .cooldown(
                reasonCode: reasonCode.isEmpty ? "cooldown_active" : reasonCode,
                retryAtMs: candidate.retryAtMs
            )
        case "disabled":
            return .disabled(reasonCode: reasonCode.isEmpty ? "disabled" : reasonCode)
        case "stale":
            return .stale(reasonCode: reasonCode.isEmpty ? "runtime_stale" : reasonCode)
        case "blocked", "expired":
            return .blocked(reasonCode: reasonCode.isEmpty ? "blocked" : reasonCode)
        default:
            return .blocked(reasonCode: reasonCode.isEmpty ? "unavailable" : reasonCode)
        }
    }

    private func loadAccounts(for providers: [String]) async -> [HubProviderKeysClient.ProviderAccount] {
        let now = Date().timeIntervalSince1970
        if (now - accountsCacheAt) < accountsCacheTTL, !accountsCache.isEmpty {
            return flattenAccounts(for: providers, grouped: accountsCache)
        }

        let allAccounts = await HubProviderKeysClient.listProviderKeys()
        var grouped: [String: [HubProviderKeysClient.ProviderAccount]] = [:]
        for account in allAccounts {
            grouped[account.provider, default: []].append(account)
        }
        accountsCache = grouped
        accountsCacheAt = now

        return flattenAccounts(for: providers, grouped: grouped)
    }

    private func flattenAccounts(
        for providers: [String],
        grouped: [String: [HubProviderKeysClient.ProviderAccount]]
    ) -> [HubProviderKeysClient.ProviderAccount] {
        providers.flatMap { grouped[$0] ?? [] }
    }

    private func selectProviderPool(
        from pools: [HubProviderKeysClient.ProviderPool],
        provider: String
    ) -> HubProviderKeysClient.ProviderPool? {
        let normalizedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = normalizedProvider.isEmpty
            ? pools
            : pools.filter { $0.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedProvider }
        let candidates = filtered.isEmpty ? pools : filtered

        return candidates.sorted { lhs, rhs in
            if lhs.readyAccounts != rhs.readyAccounts {
                return lhs.readyAccounts > rhs.readyAccounts
            }
            if lhs.totalAccounts != rhs.totalAccounts {
                return lhs.totalAccounts > rhs.totalAccounts
            }
            if lhs.lastRefreshAtMs != rhs.lastRefreshAtMs {
                return lhs.lastRefreshAtMs > rhs.lastRefreshAtMs
            }
            return lhs.capabilityPoolID < rhs.capabilityPoolID
        }.first
    }

    private func roundRobinSelect(
        from accounts: [HubProviderKeysClient.ProviderAccount],
        selectionScope: String
    ) async -> HubProviderKeysClient.ProviderAccount {
        let lastKey = lastSelectedAccountKey[selectionScope]
        var nextIndex = 0
        if let lastKey = lastKey,
           let lastIndex = accounts.firstIndex(where: { $0.accountKey == lastKey }) {
            nextIndex = (lastIndex + 1) % accounts.count
        }
        return accounts[nextIndex]
    }

    private func prioritySelect(
        from accounts: [HubProviderKeysClient.ProviderAccount],
        modelId: String
    ) async -> HubProviderKeysClient.ProviderAccount {
        let nowMs = Date().timeIntervalSince1970 * 1000
        var best: HubProviderKeysClient.ProviderAccount?
        var bestScore: Double = -.greatestFiniteMagnitude

        for account in accounts {
            let usage = await getUsageForAccount(accountKey: account.accountKey)
            let score = ProviderKeySelectionSupport.scoreAccount(
                account: account,
                usage: usage,
                modelId: modelId,
                nowMs: nowMs
            )
            if score > bestScore {
                bestScore = score
                best = account
            }
        }

        return best ?? accounts[0]
    }

    private func quotaAwareSelect(
        from accounts: [HubProviderKeysClient.ProviderAccount],
        modelId: String
    ) async -> HubProviderKeysClient.ProviderAccount {
        var best: HubProviderKeysClient.ProviderAccount?
        var bestScore: Double = -.greatestFiniteMagnitude
        let nowMs = Date().timeIntervalSince1970 * 1000

        for account in accounts {
            let usage = await getUsageForAccount(accountKey: account.accountKey)
            let score = ProviderKeySelectionSupport.scoreAccount(
                account: account,
                usage: usage,
                modelId: modelId,
                nowMs: nowMs
            )
            if score > bestScore {
                bestScore = score
                best = account
            }
        }

        return best ?? accounts[0]
    }

    private func fillFirstSelect(
        from accounts: [HubProviderKeysClient.ProviderAccount],
        modelId: String
    ) async -> HubProviderKeysClient.ProviderAccount {
        var best: HubProviderKeysClient.ProviderAccount?
        var bestScore: Double = -.greatestFiniteMagnitude
        let nowMs = Date().timeIntervalSince1970 * 1000

        for account in accounts {
            let usage = await getUsageForAccount(accountKey: account.accountKey)
            let score = ProviderKeySelectionSupport.fillFirstScore(
                account: account,
                usage: usage,
                modelId: modelId,
                nowMs: nowMs
            )
            if score > bestScore {
                bestScore = score
                best = account
            }
        }

        return best ?? accounts[0]
    }

    private func availableAccounts(
        from accounts: [HubProviderKeysClient.ProviderAccount],
        modelId: String
    ) async -> [HubProviderKeysClient.ProviderAccount] {
        let nowMs = Date().timeIntervalSince1970 * 1000
        var out: [HubProviderKeysClient.ProviderAccount] = []
        for account in accounts {
            let usage = await getUsageForAccount(accountKey: account.accountKey)
            if ProviderKeySelectionSupport.matchesModel(account, modelId: modelId),
               ProviderKeySelectionSupport.isAvailable(
                account: account,
                usage: usage,
                nowMs: nowMs
               ) {
                out.append(account)
            }
        }
        return out
    }

    private func invalidateAccountsCache() {
        accountsCache = [:]
        accountsCacheAt = 0
        lastSelectionDecision = [:]
        lastSelectionDecisionByProvider = [:]
        lastSelectionDecisionByModelLookup = [:]
        HubProviderKeysClient.invalidateCache()
    }

    private func invalidateUsageCache(accountKey: String) {
        usageCache.removeValue(forKey: accountKey)
    }

    private func invalidatePoolCache() {
        poolCache.removeAll()
        poolCacheAt.removeAll()
        ProviderKeyPoolSnapshotStore.shared.removeAll()
    }
}
