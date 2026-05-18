import XCTest
@testable import RELFlowHubCore

final class ProviderKeyStorageQuotaFamilyTests: XCTestCase {
    func testDerivedQuotaPoolsGroupByModelFamilyAndKeepSharedPoolsMarked() throws {
        let snapshot = ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.v1",
            updatedAtMs: 0,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: [
                ProviderKeyProviderGroup(
                    provider: "openai",
                    accounts: [
                        account(
                            accountKey: "openai:primary",
                            provider: "openai",
                            poolID: "openai:primary",
                            providerHost: "api.openai.com",
                            baseURL: "https://api.openai.com/v1",
                            models: ["gpt-5.4"],
                            dailyCap: 1_000,
                            dailyUsed: 400,
                            totalUsed: 5_000
                        ),
                    ],
                    routingStrategy: "fill-first"
                ),
                ProviderKeyProviderGroup(
                    provider: "openai_compatible",
                    accounts: [
                        account(
                            accountKey: "relay:alpha",
                            provider: "openai_compatible",
                            poolID: "relay:alpha",
                            providerHost: "api.picfix.pro",
                            baseURL: "https://api.picfix.pro/v1",
                            wireAPI: "responses",
                            models: ["gpt-5.4", "glm-5", "kimi-k2.5"],
                            dailyCap: 2_000,
                            dailyUsed: 800,
                            totalUsed: 7_000
                        ),
                        account(
                            accountKey: "relay:beta",
                            provider: "openai_compatible",
                            poolID: "relay:beta",
                            providerHost: "api.picfix.pro",
                            baseURL: "https://api.picfix.pro/v1",
                            wireAPI: "responses",
                            models: ["gpt-5.4", "qwen3.6-plus"],
                            dailyCap: 1_500,
                            dailyUsed: 600,
                            totalUsed: 4_000
                        ),
                    ],
                    routingStrategy: "fill-first"
                ),
            ]
        )

        let keyPools = snapshot.keyPools
        let relayAlpha = try XCTUnwrap(keyPools.first(where: { $0.poolID == "relay:alpha" }))
        XCTAssertEqual(Set(relayAlpha.supportedFamilyDisplayNames), Set(["OpenAI", "GLM", "Kimi"]))
        XCTAssertTrue(relayAlpha.hasSharedQuotaBoundary)

        let openAI = try XCTUnwrap(snapshot.quotaPools.first(where: { $0.familyKey == "openai" }))
        XCTAssertEqual(openAI.displayName, "OpenAI")
        XCTAssertEqual(openAI.totalSources, 3)
        XCTAssertEqual(openAI.dedicatedSources, 1)
        XCTAssertEqual(openAI.sharedSources, 2)
        XCTAssertEqual(openAI.exclusiveDailyTokenCap, 1_000)
        XCTAssertEqual(openAI.exclusiveDailyTokensUsed, 400)
        XCTAssertEqual(openAI.sharedDailyTokenCap, 3_500)
        XCTAssertEqual(openAI.sharedDailyTokensUsed, 1_400)
        XCTAssertEqual(Set(openAI.sharedWithFamilyDisplayNames), Set(["GLM", "Kimi", "Qwen"]))

        let glm = try XCTUnwrap(snapshot.quotaPools.first(where: { $0.familyKey == "glm" }))
        XCTAssertEqual(glm.totalSources, 1)
        XCTAssertEqual(glm.dedicatedSources, 0)
        XCTAssertEqual(glm.sharedSources, 1)
        XCTAssertEqual(glm.sharedDailyTokenCap, 2_000)
        XCTAssertEqual(glm.sharedDailyTokensUsed, 800)
        XCTAssertEqual(glm.exclusiveDailyTokenCap, 0)
        XCTAssertEqual(glm.sharedWithFamilyDisplayNames, ["Kimi", "OpenAI"])

        let qwen = try XCTUnwrap(snapshot.quotaPools.first(where: { $0.familyKey == "qwen" }))
        XCTAssertEqual(qwen.totalSources, 1)
        XCTAssertEqual(qwen.sharedSources, 1)
        XCTAssertEqual(qwen.sharedWithFamilyDisplayNames, ["OpenAI"])
    }

    func testOfficialOpenAIPoolIgnoresForeignModelFamilies() throws {
        let snapshot = ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.v1",
            updatedAtMs: 0,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: [
                ProviderKeyProviderGroup(
                    provider: "openai",
                    accounts: [
                        account(
                            accountKey: "openai:polluted",
                            provider: "openai",
                            poolID: "openai:polluted",
                            providerHost: "api.openai.com",
                            baseURL: "https://api.openai.com/v1",
                            models: ["gpt-5.4", "deepseek-chat", "gemini-2.5-pro"],
                            dailyCap: 1_000,
                            dailyUsed: 250,
                            totalUsed: 1_500
                        ),
                    ],
                    routingStrategy: "fill-first"
                ),
            ]
        )

        let keyPool = try XCTUnwrap(snapshot.keyPools.first(where: { $0.poolID == "openai:polluted" }))
        XCTAssertEqual(keyPool.supplierKey, "openai")
        XCTAssertEqual(keyPool.supportedFamilyKeys, ["openai"])
        XCTAssertFalse(keyPool.hasSharedQuotaBoundary)

        let openAI = try XCTUnwrap(snapshot.quotaPools.first(where: { $0.familyKey == "openai" }))
        XCTAssertEqual(openAI.totalSources, 1)
        XCTAssertFalse(snapshot.quotaPools.contains(where: { $0.familyKey == "deepseek" }))
        XCTAssertFalse(snapshot.quotaPools.contains(where: { $0.familyKey == "gemini" }))
    }

    func testOpenAIProviderWithKnownVendorHostUsesHostSupplier() throws {
        let snapshot = ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.v1",
            updatedAtMs: 0,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: [
                ProviderKeyProviderGroup(
                    provider: "openai",
                    accounts: [
                        account(
                            accountKey: "deepseek:compat",
                            provider: "openai",
                            poolID: "deepseek:compat",
                            providerHost: "api.deepseek.com",
                            baseURL: "https://api.deepseek.com/v1",
                            models: ["deepseek-chat"],
                            dailyCap: 2_000,
                            dailyUsed: 900,
                            totalUsed: 4_000
                        ),
                    ],
                    routingStrategy: "fill-first"
                ),
            ]
        )

        let keyPool = try XCTUnwrap(snapshot.keyPools.first(where: { $0.poolID == "deepseek:compat" }))
        XCTAssertEqual(keyPool.supplierKey, "deepseek")
        XCTAssertEqual(keyPool.supplierDisplayName, "DeepSeek")
        XCTAssertEqual(keyPool.providerDisplayName, "DeepSeek")
        XCTAssertEqual(keyPool.supportedFamilyKeys, ["deepseek"])

        let deepSeek = try XCTUnwrap(snapshot.quotaPools.first(where: { $0.familyKey == "deepseek" }))
        XCTAssertEqual(deepSeek.totalSources, 1)
        XCTAssertFalse(snapshot.quotaPools.contains(where: { $0.familyKey == "openai" }))
    }

    func testDerivedQuotaPoolsFallbackToProviderFamilyWhenModelsAreMissing() throws {
        let snapshot = ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.v1",
            updatedAtMs: 0,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: [
                ProviderKeyProviderGroup(
                    provider: "gemini",
                    accounts: [
                        account(
                            accountKey: "gemini:primary",
                            provider: "gemini",
                            poolID: "gemini:primary",
                            providerHost: "generativelanguage.googleapis.com",
                            baseURL: "https://generativelanguage.googleapis.com/v1beta",
                            models: [],
                            dailyCap: 0,
                            dailyUsed: 0,
                            totalUsed: 0
                        ),
                    ],
                    routingStrategy: "fill-first"
                ),
            ]
        )

        let geminiPool = try XCTUnwrap(snapshot.quotaPools.first(where: { $0.familyKey == "gemini" }))
        XCTAssertEqual(geminiPool.displayName, "Gemini")
        XCTAssertEqual(geminiPool.totalSources, 1)
        XCTAssertEqual(geminiPool.sharedSources, 0)
        XCTAssertEqual(geminiPool.dedicatedSources, 1)
    }

    func testFamilyQuotaPoolIgnoresBlockedMembersThatDoNotServeCurrentFamily() throws {
        let snapshot = ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.v1",
            updatedAtMs: 0,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: [
                ProviderKeyProviderGroup(
                    provider: "openai_compatible",
                    accounts: [
                        account(
                            accountKey: "relay:glm-only",
                            provider: "openai_compatible",
                            poolID: "relay:shared",
                            providerHost: "api.picfix.pro",
                            baseURL: "https://api.picfix.pro/v1",
                            wireAPI: "responses",
                            models: ["glm-5", "kimi-k2.5"],
                            dailyCap: 2_000,
                            dailyUsed: 800,
                            totalUsed: 7_000,
                            errorState: ProviderKeyErrorState(
                                status: "disabled",
                                statusMessage: "glm canary failed",
                                detailMessage: "No available channel for model glm-5",
                                reasonCode: "model_not_found",
                                lastErrorCode: "model_not_found",
                                lastErrorAtMs: 1,
                                autoDisabled: false
                            )
                        ),
                        account(
                            accountKey: "relay:qwen-ready",
                            provider: "openai_compatible",
                            poolID: "relay:shared",
                            providerHost: "api.picfix.pro",
                            baseURL: "https://api.picfix.pro/v1",
                            wireAPI: "responses",
                            models: ["qwen3.6-plus", "gpt-5.4"],
                            dailyCap: 1_500,
                            dailyUsed: 600,
                            totalUsed: 4_000
                        ),
                    ],
                    routingStrategy: "fill-first"
                ),
            ]
        )

        let qwen = try XCTUnwrap(snapshot.quotaPools.first(where: { $0.familyKey == "qwen" }))
        XCTAssertEqual(qwen.totalSources, 1)
        XCTAssertEqual(qwen.totalAccounts, 1)
        XCTAssertEqual(qwen.readyAccounts, 1)
        XCTAssertEqual(qwen.blockedAccounts, 0)
        XCTAssertEqual(qwen.state, "ready")
        XCTAssertEqual(qwen.issueSummary, "")

        let qwenSource = try XCTUnwrap(qwen.sources.first)
        XCTAssertEqual(qwenSource.totalAccounts, 1)
        XCTAssertEqual(qwenSource.readyAccounts, 1)
        XCTAssertEqual(qwenSource.blockedAccounts, 0)
        XCTAssertEqual(qwenSource.state, "ready")
        XCTAssertEqual(qwenSource.issueSummary, "")
    }

    private func account(
        accountKey: String,
        provider: String,
        poolID: String,
        providerHost: String,
        baseURL: String,
        wireAPI: String = "responses",
        models: [String],
        dailyCap: Int64,
        dailyUsed: Int64,
        totalUsed: Int64,
        errorState: ProviderKeyErrorState = ProviderKeyErrorState(
            status: "healthy",
            lastErrorCode: "",
            lastErrorAtMs: 0,
            autoDisabled: false
        )
    ) -> ProviderKeyAccount {
        ProviderKeyAccount(
            accountKey: accountKey,
            provider: provider,
            poolID: poolID,
            providerHost: providerHost,
            email: "",
            apiKeyRedacted: "sk-****",
            baseURL: baseURL,
            proxyURL: "",
            enabled: true,
            authType: "api_key",
            wireAPI: wireAPI,
            expiresAtMs: 0,
            tier: "",
            customHeaders: [:],
            models: models,
            notes: "",
            priority: 0,
            accountId: accountKey,
            sourceType: "",
            sourceRef: "",
            oauthSourceKey: "",
            authIndex: 0,
            createdAtMs: 0,
            updatedAtMs: 0,
            lastRefreshAtMs: 0,
            quota: ProviderKeyQuota(
                dailyTokenCap: dailyCap,
                dailyTokensUsed: dailyUsed,
                dailyTokensRemaining: max(0, dailyCap - dailyUsed),
                totalTokensUsed: totalUsed,
                lastUsedAtMs: 0,
                lastErrorAtMs: 0,
                consecutiveErrors: 0,
                cooldownUntilMs: 0
            ),
            errorState: errorState
        )
    }
}
