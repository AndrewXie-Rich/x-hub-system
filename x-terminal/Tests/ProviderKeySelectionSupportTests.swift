import Foundation
import Testing
@testable import XTerminal

struct ProviderKeySelectionSupportTests {
    @Test
    func candidateProvidersShareOpenAICodexPool() {
        #expect(ProviderKeySelectionSupport.candidateProviders(for: "openai") == ["openai", "codex"])
        #expect(ProviderKeySelectionSupport.candidateProviders(for: "codex") == ["codex", "openai"])
        #expect(ProviderKeySelectionSupport.candidateProviders(for: "claude") == ["claude"])
    }

    @Test
    func preferredAccountsFavorModelScopedEntries() {
        let generic = makeAccount(accountKey: "openai:generic", email: "generic")
        let targeted = makeAccount(
            accountKey: "openai:targeted",
            email: "targeted",
            models: ["gpt-4o"]
        )

        let preferred = ProviderKeySelectionSupport.preferredAccounts(
            from: [generic, targeted],
            forModelId: "gpt-4o"
        )

        #expect(preferred.map(\.accountKey) == ["openai:targeted"])
    }

    @Test
    func availabilityTreatsFutureRetryWindowAsCooldown() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let account = makeAccount(accountKey: "openai:cooldown")
        let usage = makeUsage(
            accountKey: account.accountKey,
            status: "blocked_network",
            reasonCode: "provider_timeout",
            nextRetryAtMs: nowMs + 60_000
        )

        let availability = ProviderKeySelectionSupport.availability(
            account: account,
            usage: usage,
            nowMs: nowMs
        )

        #expect(
            availability == .cooldown(
                reasonCode: "provider_timeout",
                retryAtMs: usage.errorState.nextRetryAtMs
            )
        )
    }

    @Test
    func availabilityTreatsUnknownStaleAsStale() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let account = makeAccount(accountKey: "openai:stale")
        let usage = makeUsage(
            accountKey: account.accountKey,
            status: "unknown_stale",
            reasonCode: "runtime_stale"
        )

        let availability = ProviderKeySelectionSupport.availability(
            account: account,
            usage: usage,
            nowMs: nowMs
        )

        #expect(availability == .stale(reasonCode: "runtime_stale"))
    }

    @Test
    func availabilityBlocksAuthFailuresFailClosed() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let account = makeAccount(accountKey: "openai:auth")
        let usage = makeUsage(
            accountKey: account.accountKey,
            status: "blocked_auth",
            reasonCode: "missing_scope"
        )

        let availability = ProviderKeySelectionSupport.availability(
            account: account,
            usage: usage,
            nowMs: nowMs
        )

        #expect(availability == .blocked(reasonCode: "missing_scope"))
    }

    @Test
    func availabilityPrefersUnsupportedRefreshSchemaOverGenericTokenExpired() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let account = makeAccount(
            accountKey: "gemini:oauth",
            expiresAtMs: nowMs - 1_000
        )
        let usage = makeUsage(
            accountKey: account.accountKey,
            status: "blocked_config",
            reasonCode: "unsupported_refresh_schema"
        )

        let availability = ProviderKeySelectionSupport.availability(
            account: account,
            usage: usage,
            nowMs: nowMs
        )

        #expect(availability == .blocked(reasonCode: "unsupported_refresh_schema"))
    }

    @Test
    func selectionDecisionReportsStalePoolFallback() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let account = makeAccount(accountKey: "openai:stale")
        let usage = makeUsage(
            accountKey: account.accountKey,
            status: "unknown_stale",
            reasonCode: "runtime_stale"
        )

        let decision = ProviderKeySelectionSupport.selectionDecision(
            provider: "openai",
            modelId: "gpt-4o",
            strategy: "fill-first",
            selectionScope: "openai::gpt-4o",
            accounts: [account],
            usageByAccount: [account.accountKey: usage],
            nowMs: nowMs,
            lastSelectedAccountKey: nil
        )

        #expect(decision.selectedAccountKey.isEmpty)
        #expect(decision.fallbackReasonCode == "all_keys_stale")
        #expect(decision.candidates.count == 1)
        #expect(decision.candidates[0].availability == .stale(reasonCode: "runtime_stale"))
    }

    @Test
    func selectionScopeUsesPoolIdentityWhenPresent() {
        let account = makeAccount(
            accountKey: "openai:pooled",
            poolID: "openai:api.openai.com:chat_completions"
        )

        let scope = ProviderKeySelectionSupport.selectionScopeKey(
            provider: "openai",
            modelId: "gpt-4o",
            accounts: [account]
        )

        #expect(scope == "openai::openai:api.openai.com:chat_completions")
    }

    @Test
    func selectionDecisionCarriesRefreshDiagnosticsAndMetadataHints() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let account = makeAccount(accountKey: "gemini:oauth")
        let usage = makeUsage(
            accountKey: account.accountKey,
            status: "blocked_config",
            reasonCode: "missing_oauth_client"
        )
        var usageWithMessage = usage
        usageWithMessage.errorState.statusMessage = "gemini refresh requires oauth client id and secret"
        usageWithMessage.errorState.retryAtSource = "manual"

        let decision = ProviderKeySelectionSupport.selectionDecision(
            provider: "gemini",
            modelId: "gemini-2.5-pro",
            strategy: "fill-first",
            selectionScope: "gemini::gemini-2.5-pro",
            accounts: [account],
            usageByAccount: [account.accountKey: usageWithMessage],
            requiredMetadataByAccount: [account.accountKey: ["client_id", "client_secret", "token_uri"]],
            nowMs: nowMs,
            lastSelectedAccountKey: nil
        )

        #expect(decision.selectedAccountKey.isEmpty)
        #expect(decision.candidates.count == 1)
        #expect(decision.candidates[0].reasonCode == "missing_oauth_client")
        #expect(decision.candidates[0].retryAtSource == "manual")
        #expect(decision.candidates[0].statusMessage.contains("client id and secret"))
        #expect(decision.candidates[0].requiredMetadata == ["client_id", "client_secret", "token_uri"])
    }

    @Test
    func modelStateReadyOverridesAggregateProviderBlockForTargetModel() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let account = makeAccount(accountKey: "openai:model-state")
        var usage = makeUsage(
            accountKey: account.accountKey,
            status: "blocked_provider",
            reasonCode: "model_not_supported"
        )
        usage.errorState.statusMessage = "aggregate provider block"
        usage.modelStates = [
            "gpt-4o": HubProviderKeysClient.ProviderModelState(
                status: "ready",
                reasonCode: "",
                statusMessage: "",
                nextRetryAtMs: 0,
                retryAtSource: "",
                lastErrorCode: "",
                lastErrorAtMs: 0,
                updatedAtMs: nowMs
            ),
            "o1": HubProviderKeysClient.ProviderModelState(
                status: "blocked",
                reasonCode: "model_not_supported",
                statusMessage: "o1 unavailable",
                nextRetryAtMs: 0,
                retryAtSource: "",
                lastErrorCode: "model_not_supported",
                lastErrorAtMs: nowMs,
                updatedAtMs: nowMs
            ),
        ]

        #expect(
            ProviderKeySelectionSupport.availability(
                account: account,
                usage: usage,
                nowMs: nowMs,
                modelId: "gpt-4o"
            ) == .ready
        )
        #expect(
            ProviderKeySelectionSupport.availability(
                account: account,
                usage: usage,
                nowMs: nowMs,
                modelId: "o1"
            ) == .blocked(reasonCode: "model_not_supported")
        )
    }

    @Test
    func selectionDecisionUsesModelStateShardsPerModel() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let first = makeAccount(accountKey: "openai:first", email: "first")
        let second = makeAccount(accountKey: "openai:second", email: "second")

        var firstUsage = makeUsage(
            accountKey: first.accountKey,
            status: "blocked_provider",
            reasonCode: "model_not_supported"
        )
        firstUsage.modelStates = [
            "gpt-4o": HubProviderKeysClient.ProviderModelState(
                status: "ready",
                reasonCode: "",
                statusMessage: "",
                nextRetryAtMs: 0,
                retryAtSource: "",
                lastErrorCode: "",
                lastErrorAtMs: 0,
                updatedAtMs: nowMs
            ),
            "o1": HubProviderKeysClient.ProviderModelState(
                status: "blocked",
                reasonCode: "model_not_supported",
                statusMessage: "o1 unavailable",
                nextRetryAtMs: 0,
                retryAtSource: "",
                lastErrorCode: "model_not_supported",
                lastErrorAtMs: nowMs,
                updatedAtMs: nowMs
            ),
        ]

        var secondUsage = makeUsage(
            accountKey: second.accountKey,
            status: "blocked_provider",
            reasonCode: "model_not_supported"
        )
        secondUsage.modelStates = [
            "gpt-4o": HubProviderKeysClient.ProviderModelState(
                status: "blocked",
                reasonCode: "model_not_supported",
                statusMessage: "gpt-4o unavailable",
                nextRetryAtMs: 0,
                retryAtSource: "",
                lastErrorCode: "model_not_supported",
                lastErrorAtMs: nowMs,
                updatedAtMs: nowMs
            ),
            "o1": HubProviderKeysClient.ProviderModelState(
                status: "ready",
                reasonCode: "",
                statusMessage: "",
                nextRetryAtMs: 0,
                retryAtSource: "",
                lastErrorCode: "",
                lastErrorAtMs: 0,
                updatedAtMs: nowMs
            ),
        ]

        let gpt4oDecision = ProviderKeySelectionSupport.selectionDecision(
            provider: "openai",
            modelId: "gpt-4o",
            strategy: "fill-first",
            selectionScope: "openai::gpt-4o",
            accounts: [first, second],
            usageByAccount: [
                first.accountKey: firstUsage,
                second.accountKey: secondUsage,
            ],
            nowMs: nowMs,
            lastSelectedAccountKey: nil
        )
        #expect(gpt4oDecision.selectedAccountKey == first.accountKey)

        let o1Decision = ProviderKeySelectionSupport.selectionDecision(
            provider: "openai",
            modelId: "o1",
            strategy: "fill-first",
            selectionScope: "openai::o1",
            accounts: [first, second],
            usageByAccount: [
                first.accountKey: firstUsage,
                second.accountKey: secondUsage,
            ],
            nowMs: nowMs,
            lastSelectedAccountKey: nil
        )
        #expect(o1Decision.selectedAccountKey == second.accountKey)
    }

    private func makeAccount(
        accountKey: String,
        email: String = "",
        poolID: String = "",
        models: [String] = [],
        expiresAtMs: Double = 0
    ) -> HubProviderKeysClient.ProviderAccount {
        HubProviderKeysClient.ProviderAccount(
            accountKey: accountKey,
            provider: "openai",
            poolID: poolID,
            providerHost: "api.openai.com",
            email: email,
            apiKeyRedacted: "sk-...test",
            baseUrl: "https://api.openai.com/v1",
            proxyUrl: "",
            enabled: true,
            authType: "api_key",
            wireAPI: "chat_completions",
            expiresAtMs: expiresAtMs,
            tier: "",
            models: models,
            priority: 0,
            notes: "",
            accountId: "",
            sourceType: "",
            sourceRef: "",
            oauthSourceKey: "",
            authIndex: 0,
            lastRefreshAtMs: 0
        )
    }

    private func makeUsage(
        accountKey: String,
        status: String,
        reasonCode: String,
        nextRetryAtMs: Double = 0
    ) -> HubProviderKeysClient.KeyUsageInfo {
        HubProviderKeysClient.KeyUsageInfo(
            accountKey: accountKey,
            provider: "openai",
            quota: HubProviderKeysClient.KeyQuota(
                dailyTokenCap: 0,
                dailyTokensUsed: 0,
                dailyTokensRemaining: 0,
                totalTokensUsed: 0,
                lastUsedAtMs: 0,
                lastErrorAtMs: 0,
                consecutiveErrors: 0,
                cooldownUntilMs: 0
            ),
            errorState: HubProviderKeysClient.KeyErrorState(
                status: status,
                statusMessage: "",
                reasonCode: reasonCode,
                lastErrorCode: reasonCode,
                lastErrorAtMs: 0,
                nextRetryAtMs: nextRetryAtMs,
                retryAtSource: nextRetryAtMs > 0 ? "scheduler" : "",
                autoDisabled: false
            )
        )
    }
}
