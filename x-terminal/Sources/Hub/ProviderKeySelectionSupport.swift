import Foundation

enum ProviderKeyAvailabilityState: Codable, Equatable, Sendable {
    case ready
    case cooldown(reasonCode: String, retryAtMs: Double)
    case blocked(reasonCode: String)
    case disabled(reasonCode: String)
    case stale(reasonCode: String)
}

struct ProviderKeyCandidateDecision: Codable, Equatable, Sendable {
    var accountKey: String
    var provider: String
    var poolID: String
    var wireAPI: String
    var availability: ProviderKeyAvailabilityState
    var score: Double
    var selected: Bool
    var reasonCode: String
    var retryAtMs: Double
    var retryAtSource: String = ""
    var statusMessage: String = ""
    var requiredMetadata: [String] = []
}

struct ProviderKeySelectionDecision: Codable, Equatable, Sendable {
    var requestedProvider: String
    var requestedModelId: String
    var strategy: String
    var selectionScope: String
    var selectedAccountKey: String
    var fallbackReasonCode: String
    var candidates: [ProviderKeyCandidateDecision]
}

private extension ProviderKeyAvailabilityState {
    var reasonCode: String {
        switch self {
        case .ready:
            return ""
        case .cooldown(let reasonCode, _):
            return reasonCode
        case .blocked(let reasonCode):
            return reasonCode
        case .disabled(let reasonCode):
            return reasonCode
        case .stale(let reasonCode):
            return reasonCode
        }
    }

    var retryAtMs: Double {
        switch self {
        case .cooldown(_, let retryAtMs):
            return retryAtMs
        case .ready, .blocked, .disabled, .stale:
            return 0
        }
    }

    var sortRank: Int {
        switch self {
        case .ready:
            return 0
        case .cooldown:
            return 1
        case .stale:
            return 2
        case .blocked:
            return 3
        case .disabled:
            return 4
        }
    }
}

enum ProviderKeySelectionSupport {
    static func inferProvider(fromModelId modelId: String) -> String {
        for candidate in modelLookupKeys(modelId) {
            if candidate.hasPrefix("openai/") { return "openai" }
            if candidate.hasPrefix("codex/") { return "codex" }
            if candidate.hasPrefix("gpt-") || candidate.hasPrefix("o1")
                || candidate.hasPrefix("o3") || candidate.hasPrefix("o4")
                || candidate.contains("chatgpt") || candidate.hasPrefix("deepseek") {
                return "openai"
            }
            if candidate.contains("codex") {
                return "codex"
            }
            if candidate.hasPrefix("claude") {
                return "claude"
            }
            if candidate.hasPrefix("gemini") || candidate.hasPrefix("gemma") {
                return "gemini"
            }
            if candidate.hasPrefix("qwen") || candidate.hasPrefix("qwq") {
                return "qwen"
            }
        }
        return ""
    }

    static func candidateProviders(for provider: String) -> [String] {
        switch normalizedToken(provider) {
        case "openai":
            return ["openai", "codex"]
        case "codex":
            return ["codex", "openai"]
        default:
            return [normalizedToken(provider)].filter { !$0.isEmpty }
        }
    }

    static func preferredAccounts(
        from accounts: [HubProviderKeysClient.ProviderAccount],
        forModelId modelId: String
    ) -> [HubProviderKeysClient.ProviderAccount] {
        let restrictedMatching = accounts.filter { account in
            !account.models.isEmpty && matchesModel(account, modelId: modelId)
        }
        if !restrictedMatching.isEmpty {
            return restrictedMatching
        }
        let matching = accounts.filter { matchesModel($0, modelId: modelId) }
        return matching.isEmpty ? accounts : matching
    }

    static func matchesModel(
        _ account: HubProviderKeysClient.ProviderAccount,
        modelId: String
    ) -> Bool {
        let patterns = account.models
            .map(normalizedToken(_:))
            .filter { !$0.isEmpty }
        guard !patterns.isEmpty else { return true }

        let lookup = Set(modelLookupKeys(modelId))
        guard !lookup.isEmpty else { return false }

        for pattern in patterns {
            if pattern == "*" || lookup.contains(pattern) {
                return true
            }
            if pattern.hasSuffix("*") {
                let prefix = String(pattern.dropLast())
                if lookup.contains(where: { $0.hasPrefix(prefix) }) {
                    return true
                }
            }
        }
        return false
    }

    static func availability(
        account: HubProviderKeysClient.ProviderAccount,
        usage: HubProviderKeysClient.KeyUsageInfo?,
        nowMs: Double,
        modelId: String = ""
    ) -> ProviderKeyAvailabilityState {
        guard account.enabled else {
            return .disabled(reasonCode: "disabled")
        }
        if isExpired(account, nowMs: nowMs) {
            let blockingUsageReason = usage.map {
                normalizedReasonCode(
                    $0.errorState.reasonCode,
                    $0.errorState.lastErrorCode,
                    fallback: normalizedToken($0.errorState.status)
                )
            } ?? ""
            if blockingUsageReason == "unsupported_refresh_schema" {
                return .blocked(reasonCode: blockingUsageReason)
            }
            return .blocked(reasonCode: "token_expired")
        }
        guard let usage else {
            return .ready
        }

        let blockingUsageReason = normalizedReasonCode(
            usage.errorState.reasonCode,
            usage.errorState.lastErrorCode,
            fallback: normalizedToken(usage.errorState.status)
        )
        let status = normalizedToken(usage.errorState.status)
        let reason = blockingUsageReason.isEmpty
            ? normalizedReasonCode(
                usage.errorState.reasonCode,
                usage.errorState.lastErrorCode,
                fallback: status
            )
            : blockingUsageReason
        let retryAtMs = effectiveRetryAtMs(usage: usage, modelId: modelId)

        if usage.errorState.autoDisabled || status == "disabled" {
            return .disabled(reasonCode: reason.isEmpty ? "disabled" : reason)
        }

        if status == "auth_failed" || status == "blocked_auth" {
            return .blocked(reasonCode: reason.isEmpty ? "auth_failed" : reason)
        }

        if status == "blocked_config" {
            return .blocked(reasonCode: reason.isEmpty ? "blocked_config" : reason)
        }

        if let modelState = resolvedModelState(in: usage, modelId: modelId) {
            return availability(from: modelState)
        }

        if retryAtMs > nowMs {
            return .cooldown(
                reasonCode: reason.isEmpty ? "cooldown_active" : reason,
                retryAtMs: retryAtMs
            )
        }

        if usage.quota.dailyTokenCap > 0,
           usage.quota.dailyTokensUsed >= usage.quota.dailyTokenCap {
            return .blocked(reasonCode: reason.isEmpty ? "daily_token_cap_exceeded" : reason)
        }

        if status == "unknown_stale" || reason == "runtime_stale" {
            return .stale(reasonCode: reason.isEmpty ? "runtime_stale" : reason)
        }

        switch status {
        case "blocked_quota", "rate_limited":
            return .blocked(reasonCode: reason.isEmpty ? "blocked_quota" : reason)
        case "blocked_provider", "blocked_network":
            return .blocked(reasonCode: reason.isEmpty ? status : reason)
        default:
            return .ready
        }
    }

    static func isAvailable(
        account: HubProviderKeysClient.ProviderAccount,
        usage: HubProviderKeysClient.KeyUsageInfo?,
        nowMs: Double,
        modelId: String = ""
    ) -> Bool {
        if case .ready = availability(account: account, usage: usage, nowMs: nowMs, modelId: modelId) {
            return true
        }
        return false
    }

    static func scoreAccount(
        account: HubProviderKeysClient.ProviderAccount,
        usage: HubProviderKeysClient.KeyUsageInfo?,
        modelId: String,
        nowMs: Double
    ) -> Double {
        guard isAvailable(account: account, usage: usage, nowMs: nowMs, modelId: modelId) else {
            return -.greatestFiniteMagnitude
        }

        var score = Double(account.priority) * 100.0
        if matchesModel(account, modelId: modelId) {
            score += 250.0
        }

        guard let usage else {
            return score + 75.0
        }

        let status = normalizedToken(usage.errorState.status)
        if status == "healthy" {
            score += 150.0
        } else if status == "degraded" {
            score -= 100.0
        }

        if usage.quota.dailyTokenCap > 0 {
            let remainingRatio = Double(usage.quota.dailyTokensRemaining) / Double(usage.quota.dailyTokenCap)
            score += remainingRatio * 80.0
        } else {
            score += 25.0
        }

        if usage.quota.consecutiveErrors > 0 {
            score -= Double(usage.quota.consecutiveErrors) * 20.0
        }

        if effectiveRetryAtMs(usage: usage, modelId: modelId) > nowMs {
            score -= 500.0
        }

        return score
    }

    static func fillFirstScore(
        account: HubProviderKeysClient.ProviderAccount,
        usage: HubProviderKeysClient.KeyUsageInfo?,
        modelId: String,
        nowMs: Double
    ) -> Double {
        guard isAvailable(account: account, usage: usage, nowMs: nowMs, modelId: modelId) else {
            return -.greatestFiniteMagnitude
        }

        var score = Double(account.priority)
        if matchesModel(account, modelId: modelId) {
            score += 500.0
        }

        guard let usage else {
            return score + 100.0
        }

        let status = normalizedToken(usage.errorState.status)
        if status == "healthy" {
            score += 1000.0
        } else if status == "degraded" {
            score -= 200.0
        }

        if usage.quota.consecutiveErrors > 0 {
            score -= Double(usage.quota.consecutiveErrors) * 50.0
        }

        if usage.quota.dailyTokenCap > 0 {
            let remainingRatio = Double(usage.quota.dailyTokensRemaining) / Double(usage.quota.dailyTokenCap)
            score += remainingRatio * 100.0
        }

        return score
    }

    static func selectAccount(
        from accounts: [HubProviderKeysClient.ProviderAccount],
        usageByAccount: [String: HubProviderKeysClient.KeyUsageInfo],
        strategy: String,
        modelId: String,
        nowMs: Double,
        lastSelectedAccountKey: String?
    ) -> HubProviderKeysClient.ProviderAccount? {
        let readyAccounts = accounts.filter { account in
            isAvailable(
                account: account,
                usage: usageByAccount[account.accountKey],
                nowMs: nowMs,
                modelId: modelId
            )
        }
        guard !readyAccounts.isEmpty else { return nil }

        switch strategy {
        case "round-robin":
            guard let lastSelectedAccountKey,
                  let lastIndex = readyAccounts.firstIndex(where: { $0.accountKey == lastSelectedAccountKey }) else {
                return readyAccounts[0]
            }
            let nextIndex = (lastIndex + 1) % readyAccounts.count
            return readyAccounts[nextIndex]
        case "priority", "quota-aware":
            return readyAccounts.max { lhs, rhs in
                scoreAccount(
                    account: lhs,
                    usage: usageByAccount[lhs.accountKey],
                    modelId: modelId,
                    nowMs: nowMs
                ) < scoreAccount(
                    account: rhs,
                    usage: usageByAccount[rhs.accountKey],
                    modelId: modelId,
                    nowMs: nowMs
                )
            }
        case "fill-first":
            fallthrough
        default:
            return readyAccounts.max { lhs, rhs in
                fillFirstScore(
                    account: lhs,
                    usage: usageByAccount[lhs.accountKey],
                    modelId: modelId,
                    nowMs: nowMs
                ) < fillFirstScore(
                    account: rhs,
                    usage: usageByAccount[rhs.accountKey],
                    modelId: modelId,
                    nowMs: nowMs
                )
            }
        }
    }

    static func selectionDecision(
        provider: String,
        modelId: String,
        strategy: String,
        selectionScope: String,
        accounts: [HubProviderKeysClient.ProviderAccount],
        usageByAccount: [String: HubProviderKeysClient.KeyUsageInfo],
        requiredMetadataByAccount: [String: [String]] = [:],
        nowMs: Double,
        lastSelectedAccountKey: String?
    ) -> ProviderKeySelectionDecision {
        let selected = selectAccount(
            from: accounts,
            usageByAccount: usageByAccount,
            strategy: strategy,
            modelId: modelId,
            nowMs: nowMs,
            lastSelectedAccountKey: lastSelectedAccountKey
        )
        let selectedAccountKey = selected?.accountKey ?? ""

        let candidates = accounts.map { account -> ProviderKeyCandidateDecision in
            let usage = usageByAccount[account.accountKey]
            let availability = availability(account: account, usage: usage, nowMs: nowMs, modelId: modelId)
            let retryAtMs = usage.map { effectiveRetryAtMs(usage: $0, modelId: modelId) } ?? availability.retryAtMs
            let retryAtSource = usage.map { effectiveRetryAtSource(usage: $0, modelId: modelId) } ?? ""
            let statusMessage = usage.map { effectiveStatusMessage(usage: $0, modelId: modelId) } ?? ""
            let requiredMetadata = requiredMetadataByAccount[account.accountKey] ?? []
            let score: Double
            switch strategy {
            case "priority", "quota-aware":
                score = scoreAccount(account: account, usage: usage, modelId: modelId, nowMs: nowMs)
            case "round-robin":
                score = isAvailable(account: account, usage: usage, nowMs: nowMs, modelId: modelId) ? 0 : -.greatestFiniteMagnitude
            case "fill-first":
                fallthrough
            default:
                score = fillFirstScore(account: account, usage: usage, modelId: modelId, nowMs: nowMs)
            }

            let selected = account.accountKey == selectedAccountKey
            let reasonCode = selected ? "selected_by_scheduler" : candidateReasonCode(for: availability)
            return ProviderKeyCandidateDecision(
                accountKey: account.accountKey,
                provider: account.provider,
                poolID: account.poolID,
                wireAPI: account.wireAPI,
                availability: availability,
                score: score,
                selected: selected,
                reasonCode: reasonCode,
                retryAtMs: retryAtMs,
                retryAtSource: retryAtSource,
                statusMessage: statusMessage,
                requiredMetadata: requiredMetadata
            )
        }.sorted { lhs, rhs in
            if lhs.selected != rhs.selected {
                return lhs.selected && !rhs.selected
            }
            if lhs.availability.sortRank != rhs.availability.sortRank {
                return lhs.availability.sortRank < rhs.availability.sortRank
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.accountKey < rhs.accountKey
        }

        return ProviderKeySelectionDecision(
            requestedProvider: normalizedToken(provider),
            requestedModelId: normalizedToken(modelId),
            strategy: normalizedToken(strategy).isEmpty ? "fill-first" : normalizedToken(strategy),
            selectionScope: selectionScope,
            selectedAccountKey: selectedAccountKey,
            fallbackReasonCode: selected == nil ? fallbackReasonCode(for: candidates) : "",
            candidates: candidates
        )
    }

    static func selectionScopeKey(
        provider: String,
        modelId: String,
        accounts: [HubProviderKeysClient.ProviderAccount]
    ) -> String {
        let poolIDs = Array(Set(accounts.map(\.poolID).filter { !$0.isEmpty })).sorted()
        if poolIDs.count == 1, let poolID = poolIDs.first {
            return "\(normalizedToken(provider))::\(poolID)"
        }
        return "\(normalizedToken(provider))::\(normalizedToken(modelId))"
    }

    static func effectiveRetryAtMs(
        usage: HubProviderKeysClient.KeyUsageInfo,
        modelId: String = ""
    ) -> Double {
        if let modelState = resolvedModelState(in: usage, modelId: modelId) {
            return modelState.nextRetryAtMs
        }
        return max(usage.quota.cooldownUntilMs, usage.errorState.nextRetryAtMs)
    }

    static func isExpired(
        _ account: HubProviderKeysClient.ProviderAccount,
        nowMs: Double
    ) -> Bool {
        guard account.expiresAtMs > 0 else { return false }
        return account.expiresAtMs < nowMs
    }

    static func modelLookupKeys(_ modelId: String) -> [String] {
        let raw = normalizedToken(modelId)
        guard !raw.isEmpty else { return [] }

        var out: [String] = []
        var seen = Set<String>()
        func append(_ value: String) {
            let token = normalizedToken(value)
            guard !token.isEmpty, !seen.contains(token) else { return }
            seen.insert(token)
            out.append(token)
        }

        append(raw)
        if raw.contains("/") {
            let parts = raw.split(separator: "/").map(String.init)
            parts.forEach(append)
            if let last = parts.last {
                append(last)
            }
        }
        if raw.hasPrefix("models/") {
            append(String(raw.dropFirst("models/".count)))
        }
        return out
    }

    private static func resolvedModelState(
        in usage: HubProviderKeysClient.KeyUsageInfo,
        modelId: String
    ) -> HubProviderKeysClient.ProviderModelState? {
        let lookup = modelLookupKeys(modelId)
        guard !lookup.isEmpty else { return nil }

        for candidate in lookup {
            if let state = usage.modelStates[candidate] {
                return state
            }
        }
        for (pattern, state) in usage.modelStates where pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast())
            guard !prefix.isEmpty else { continue }
            if lookup.contains(where: { $0.hasPrefix(prefix) }) {
                return state
            }
        }
        return nil
    }

    private static func availability(
        from modelState: HubProviderKeysClient.ProviderModelState
    ) -> ProviderKeyAvailabilityState {
        let status = normalizedToken(modelState.status)
        let reason = normalizedReasonCode(
            modelState.reasonCode,
            modelState.lastErrorCode,
            fallback: status
        )
        switch status {
        case "ready":
            return .ready
        case "cooldown":
            return .cooldown(
                reasonCode: reason.isEmpty ? "cooldown_active" : reason,
                retryAtMs: modelState.nextRetryAtMs
            )
        case "disabled":
            return .disabled(reasonCode: reason.isEmpty ? "disabled" : reason)
        case "stale":
            return .stale(reasonCode: reason.isEmpty ? "runtime_stale" : reason)
        case "blocked":
            return .blocked(reasonCode: reason.isEmpty ? "blocked" : reason)
        default:
            return .ready
        }
    }

    private static func effectiveRetryAtSource(
        usage: HubProviderKeysClient.KeyUsageInfo,
        modelId: String
    ) -> String {
        if let modelState = resolvedModelState(in: usage, modelId: modelId),
           !normalizedToken(modelState.retryAtSource).isEmpty {
            return modelState.retryAtSource
        }
        return usage.errorState.retryAtSource
    }

    private static func effectiveStatusMessage(
        usage: HubProviderKeysClient.KeyUsageInfo,
        modelId: String
    ) -> String {
        if let modelState = resolvedModelState(in: usage, modelId: modelId),
           !normalizedToken(modelState.statusMessage).isEmpty {
            return modelState.statusMessage
        }
        return usage.errorState.statusMessage
    }

    private static func normalizedReasonCode(
        _ primary: String,
        _ secondary: String,
        fallback: String
    ) -> String {
        let first = normalizedToken(primary)
        if !first.isEmpty { return first }
        let second = normalizedToken(secondary)
        if !second.isEmpty { return second }
        return normalizedToken(fallback)
    }

    private static func normalizedToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func candidateReasonCode(for availability: ProviderKeyAvailabilityState) -> String {
        switch availability {
        case .ready:
            return "lower_ranked_by_strategy"
        case .cooldown, .blocked, .disabled, .stale:
            return availability.reasonCode
        }
    }

    private static func fallbackReasonCode(
        for candidates: [ProviderKeyCandidateDecision]
    ) -> String {
        guard !candidates.isEmpty else { return "no_keys_for_provider" }

        let states = candidates.map(\.availability)
        if states.allSatisfy({ state in
            if case .disabled = state { return true }
            return false
        }) {
            return "all_keys_disabled"
        }
        if states.allSatisfy({ state in
            if case .cooldown = state { return true }
            return false
        }) {
            return "all_keys_in_cooldown"
        }
        if states.allSatisfy({ state in
            if case .stale = state { return true }
            return false
        }) {
            return "all_keys_stale"
        }
        if states.allSatisfy({ state in
            switch state {
            case .blocked(let reasonCode), .disabled(let reasonCode):
                return [
                    "auth_failed",
                    "blocked_auth",
                    "missing_scope",
                    "token_expired",
                    "auth_missing",
                ].contains(reasonCode)
            case .ready, .cooldown, .stale:
                return false
            }
        }) {
            return "all_keys_auth_blocked"
        }
        if states.allSatisfy({ state in
            switch state {
            case .blocked(let reasonCode):
                return [
                    "rate_limited",
                    "blocked_quota",
                    "quota_exceeded",
                    "daily_token_cap_exceeded",
                ].contains(reasonCode)
            case .ready, .cooldown, .disabled, .stale:
                return false
            }
        }) {
            return "all_keys_rate_limited"
        }
        return "all_keys_unavailable"
    }
}
