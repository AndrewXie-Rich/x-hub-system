import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class RemoteQuotaCenterSupportTests: XCTestCase {
    func testProjectionAggregatesUpstreamPoolsAndDownstreamBudgetsByFamily() {
        let snapshot = ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.v1",
            updatedAtMs: 1,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: [
                ProviderKeyProviderGroup(
                    provider: "openai",
                    accounts: [
                        makeAccount(
                            accountKey: "openai-team-a",
                            provider: "openai",
                            baseURL: "https://api.openai.com/v1",
                            models: ["gpt-5.4"],
                            dailyCap: 1_000,
                            dailyUsed: 300,
                            dailyRemaining: 700,
                            totalUsed: 5_000
                        )
                    ],
                    routingStrategy: "fill-first"
                ),
                ProviderKeyProviderGroup(
                    provider: "anthropic",
                    accounts: [
                        makeAccount(
                            accountKey: "claude-team-a",
                            provider: "anthropic",
                            baseURL: "https://api.anthropic.com/v1",
                            models: ["claude-3-7-sonnet"],
                            dailyCap: 500,
                            dailyUsed: 100,
                            dailyRemaining: 400,
                            totalUsed: 1_500
                        )
                    ],
                    routingStrategy: "fill-first"
                ),
            ]
        )

        let remoteModels = [
            RemoteModelEntry(
                id: "gpt-5.4",
                name: "GPT 5.4",
                backend: "openai",
                enabled: true,
                baseURL: "https://api.openai.com/v1",
                apiKeyRef: "openai-team-a",
                apiKey: "sk-openai"
            ),
            RemoteModelEntry(
                id: "claude-3-7-sonnet",
                name: "Claude 3.7 Sonnet",
                backend: "anthropic",
                enabled: true,
                baseURL: "https://api.anthropic.com/v1",
                apiKeyRef: "claude-team-a",
                apiKey: "sk-claude"
            ),
        ]

        let customClient = HubGRPCClientEntry(
            deviceId: "xt-dev-a",
            userId: "alice",
            name: "Alice XT",
            token: "tok-a",
            enabled: true,
            createdAtMs: 1,
            policyMode: .newProfile,
            approvedTrustProfile: HubGRPCClientEntry.buildApprovedTrustProfile(
                deviceId: "xt-dev-a",
                deviceName: "Alice XT",
                requestedCapabilities: ["models", "events", "ai.generate.local"],
                paidModelSelectionMode: .customSelectedModels,
                allowedPaidModels: ["gpt-5.4"],
                defaultWebFetchEnabled: false,
                dailyTokenLimit: 400,
                auditRef: "xt-dev-a"
            )
        )
        let allModelsClient = HubGRPCClientEntry(
            deviceId: "xt-dev-b",
            userId: "bob",
            name: "Bob XT",
            token: "tok-b",
            enabled: true,
            createdAtMs: 1,
            policyMode: .newProfile,
            approvedTrustProfile: HubGRPCClientEntry.buildApprovedTrustProfile(
                deviceId: "xt-dev-b",
                deviceName: "Bob XT",
                requestedCapabilities: ["models", "events", "ai.generate.local"],
                paidModelSelectionMode: .allPaidModels,
                allowedPaidModels: [],
                defaultWebFetchEnabled: true,
                dailyTokenLimit: 900,
                auditRef: "xt-dev-b"
            )
        )

        let deviceSnapshot = GRPCDevicesStatusSnapshot(
            schemaVersion: "grpc_devices_status.v2",
            updatedAtMs: 10,
            devices: [
                makeDeviceStatus(
                    deviceId: "xt-dev-a",
                    name: "Alice XT",
                    connected: true,
                    dailyTokenUsed: 120,
                    dailyTokenCap: 400,
                    remainingDailyTokenBudget: 280,
                    topModel: "gpt-5.4",
                    modelBreakdown: []
                ),
                makeDeviceStatus(
                    deviceId: "xt-dev-b",
                    name: "Bob XT",
                    connected: false,
                    dailyTokenUsed: 80,
                    dailyTokenCap: 900,
                    remainingDailyTokenBudget: 820,
                    topModel: "claude-3-7-sonnet",
                    modelBreakdown: []
                ),
            ]
        )

        let projection = RemoteQuotaCenterSupport.projection(
            providerKeySnapshot: snapshot,
            remoteModels: remoteModels,
            clients: [customClient, allModelsClient],
            deviceStatusSnapshot: deviceSnapshot
        )

        XCTAssertEqual(projection.overview.totalKeys, 2)
        XCTAssertEqual(projection.overview.totalDailyTokenCap, 1_500)
        XCTAssertEqual(projection.overview.totalDailyTokensUsed, 400)
        XCTAssertEqual(projection.overview.userCount, 2)
        XCTAssertEqual(projection.overview.paidClientCount, 2)
        XCTAssertEqual(projection.overview.connectedPaidClientCount, 1)
        XCTAssertEqual(projection.overview.allocatedDailyTokenBudget, 1_300)
        XCTAssertEqual(projection.overview.observedClientTokensUsed, 200)

        guard let openAI = projection.families.first(where: { $0.familyKey == "openai" }) else {
            return XCTFail("missing openai family projection")
        }
        XCTAssertEqual(openAI.assignedClientCount, 2)
        XCTAssertEqual(openAI.assignedDailyTokenBudget, 1_300)
        XCTAssertEqual(openAI.observedDailyTokensUsed, 120)
        XCTAssertTrue(openAI.isOversubscribed)

        guard let claude = projection.families.first(where: { $0.familyKey == "claude" }) else {
            return XCTFail("missing claude family projection")
        }
        XCTAssertEqual(claude.assignedClientCount, 1)
        XCTAssertEqual(claude.assignedDailyTokenBudget, 900)
        XCTAssertEqual(claude.observedDailyTokensUsed, 80)
    }

    func testLegacyPaidClientFallsBackToDeviceSnapshotBudgetAndAllFamilies() {
        let snapshot = ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.v1",
            updatedAtMs: 1,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: [
                ProviderKeyProviderGroup(
                    provider: "openai",
                    accounts: [
                        makeAccount(
                            accountKey: "openai-team-a",
                            provider: "openai",
                            baseURL: "https://api.openai.com/v1",
                            models: ["gpt-5.4"],
                            dailyCap: 1_000,
                            dailyUsed: 200,
                            dailyRemaining: 800,
                            totalUsed: 2_000
                        )
                    ],
                    routingStrategy: "fill-first"
                )
            ]
        )

        let legacyClient = HubGRPCClientEntry(
            deviceId: "xt-legacy",
            name: "Legacy XT",
            token: "tok-legacy",
            enabled: true,
            createdAtMs: 1,
            capabilities: ["models", "ai.generate.local", "ai.generate.paid", "web.fetch"],
            policyMode: .legacyGrant,
            approvedTrustProfile: nil
        )

        let projection = RemoteQuotaCenterSupport.projection(
            providerKeySnapshot: snapshot,
            remoteModels: [
                RemoteModelEntry(
                    id: "gpt-5.4",
                    name: "GPT 5.4",
                    backend: "openai",
                    enabled: true,
                    baseURL: "https://api.openai.com/v1",
                    apiKeyRef: "openai-team-a",
                    apiKey: "sk-openai"
                )
            ],
            clients: [legacyClient],
            deviceStatusSnapshot: GRPCDevicesStatusSnapshot(
                schemaVersion: "grpc_devices_status.v2",
                updatedAtMs: 10,
                devices: [
                    makeDeviceStatus(
                        deviceId: "xt-legacy",
                        name: "Legacy XT",
                        connected: true,
                        dailyTokenUsed: 50,
                        dailyTokenCap: 250,
                        remainingDailyTokenBudget: 200,
                        topModel: "gpt-5.4",
                        modelBreakdown: []
                    )
                ]
            )
        )

        guard let paidClient = projection.paidClients.first else {
            return XCTFail("missing paid client projection")
        }
        XCTAssertEqual(projection.overview.userCount, 1)
        XCTAssertEqual(paidClient.dailyTokenLimit, 250)
        XCTAssertEqual(paidClient.dailyTokenUsed, 50)
        XCTAssertTrue(paidClient.allowsAllFamilies)
        XCTAssertTrue(paidClient.defaultWebFetchEnabled)
        XCTAssertEqual(paidClient.paidPolicyMode, "legacy_grant")
    }

    func testProjectionIncludesReadyTerminalAccessConsumersInUnifiedLedger() throws {
        let snapshot = ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.v1",
            updatedAtMs: 1,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: [
                ProviderKeyProviderGroup(
                    provider: "openai",
                    accounts: [
                        makeAccount(
                            accountKey: "openai-team-a",
                            provider: "openai",
                            baseURL: "https://api.openai.com/v1",
                            models: ["gpt-5.4"],
                            dailyCap: 1_000,
                            dailyUsed: 200,
                            dailyRemaining: 800,
                            totalUsed: 2_000
                        )
                    ],
                    routingStrategy: "fill-first"
                ),
                ProviderKeyProviderGroup(
                    provider: "anthropic",
                    accounts: [
                        makeAccount(
                            accountKey: "claude-team-a",
                            provider: "anthropic",
                            baseURL: "https://api.anthropic.com/v1",
                            models: ["claude-3-7-sonnet"],
                            dailyCap: 900,
                            dailyUsed: 150,
                            dailyRemaining: 750,
                            totalUsed: 1_800
                        )
                    ],
                    routingStrategy: "fill-first"
                ),
            ]
        )

        let remoteModels = [
            RemoteModelEntry(
                id: "gpt-5.4",
                name: "GPT 5.4",
                backend: "openai",
                enabled: true,
                baseURL: "https://api.openai.com/v1",
                apiKeyRef: "openai-team-a",
                apiKey: "sk-openai"
            ),
            RemoteModelEntry(
                id: "claude-3-7-sonnet",
                name: "Claude 3.7 Sonnet",
                backend: "anthropic",
                enabled: true,
                baseURL: "https://api.anthropic.com/v1",
                apiKeyRef: "claude-team-a",
                apiKey: "sk-claude"
            ),
        ]

        let xtClient = HubGRPCClientEntry(
            deviceId: "xt-dev-a",
            userId: "alice",
            name: "Alice XT",
            token: "tok-a",
            enabled: true,
            createdAtMs: 1,
            policyMode: .newProfile,
            approvedTrustProfile: HubGRPCClientEntry.buildApprovedTrustProfile(
                deviceId: "xt-dev-a",
                deviceName: "Alice XT",
                requestedCapabilities: ["models", "events", "ai.generate.local"],
                paidModelSelectionMode: .customSelectedModels,
                allowedPaidModels: ["gpt-5.4"],
                defaultWebFetchEnabled: false,
                dailyTokenLimit: 400,
                auditRef: "xt-dev-a"
            )
        )

        let terminalAccessKey = try makeTerminalAccessKey(
            accessKeyID: "axhub_key_terminal",
            deviceID: "terminal-dev-a",
            userID: "ops",
            appID: "external_terminal",
            name: "Ops Shell",
            paidMode: .customSelectedModels,
            allowedModelIDs: ["claude-3-7-sonnet"],
            dailyTokenLimit: 250,
            defaultWebFetchEnabled: true
        )

        let deviceSnapshot = GRPCDevicesStatusSnapshot(
            schemaVersion: "grpc_devices_status.v2",
            updatedAtMs: 10,
            devices: [
                makeDeviceStatus(
                    deviceId: "xt-dev-a",
                    name: "Alice XT",
                    connected: true,
                    dailyTokenUsed: 120,
                    dailyTokenCap: 400,
                    remainingDailyTokenBudget: 280,
                    topModel: "gpt-5.4",
                    modelBreakdown: []
                ),
                makeDeviceStatus(
                    deviceId: "terminal-dev-a",
                    name: "Ops Shell",
                    connected: false,
                    dailyTokenUsed: 70,
                    dailyTokenCap: 250,
                    remainingDailyTokenBudget: 180,
                    topModel: "claude-3-7-sonnet",
                    modelBreakdown: []
                ),
            ]
        )

        let projection = RemoteQuotaCenterSupport.projection(
            providerKeySnapshot: snapshot,
            remoteModels: remoteModels,
            clients: [xtClient],
            terminalAccessKeys: [terminalAccessKey],
            deviceStatusSnapshot: deviceSnapshot
        )

        XCTAssertEqual(projection.overview.consumerCount, 2)
        XCTAssertEqual(projection.overview.userCount, 2)
        XCTAssertEqual(projection.overview.xtConsumerCount, 1)
        XCTAssertEqual(projection.overview.terminalConsumerCount, 1)
        XCTAssertEqual(projection.overview.connectedConsumerCount, 1)
        XCTAssertEqual(projection.overview.allocatedDailyTokenBudget, 650)
        XCTAssertEqual(projection.overview.observedConsumerTokensUsed, 190)

        guard let terminalConsumer = projection.consumers.first(where: { $0.consumerKind == .terminalAccess }) else {
            return XCTFail("missing terminal access consumer projection")
        }
        XCTAssertEqual(terminalConsumer.referenceID, "axhub_key_terminal")
        XCTAssertEqual(terminalConsumer.name, "Ops Shell")
        XCTAssertEqual(terminalConsumer.dailyTokenLimit, 250)
        XCTAssertEqual(terminalConsumer.dailyTokenUsed, 70)
        XCTAssertEqual(terminalConsumer.remainingDailyTokenBudget, 180)
        XCTAssertEqual(terminalConsumer.familyKeys, ["claude"])
        XCTAssertEqual(terminalConsumer.observedDailyTokensByFamily["claude"], 70)
        XCTAssertTrue(terminalConsumer.defaultWebFetchEnabled)

        guard let claude = projection.families.first(where: { $0.familyKey == "claude" }) else {
            return XCTFail("missing claude family projection")
        }
        XCTAssertEqual(claude.assignedClientCount, 1)
        XCTAssertEqual(claude.assignedDailyTokenBudget, 250)
        XCTAssertEqual(claude.observedDailyTokensUsed, 70)
    }

    func testProjectionTracksPerFamilyObservedUsageFromModelBreakdown() throws {
        let snapshot = ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.v1",
            updatedAtMs: 1,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: [
                ProviderKeyProviderGroup(
                    provider: "openai",
                    accounts: [
                        makeAccount(
                            accountKey: "openai-team-a",
                            provider: "openai",
                            baseURL: "https://api.openai.com/v1",
                            models: ["gpt-5.4"],
                            dailyCap: 1_000,
                            dailyUsed: 250,
                            dailyRemaining: 750,
                            totalUsed: 2_500
                        )
                    ],
                    routingStrategy: "fill-first"
                ),
                ProviderKeyProviderGroup(
                    provider: "anthropic",
                    accounts: [
                        makeAccount(
                            accountKey: "claude-team-a",
                            provider: "anthropic",
                            baseURL: "https://api.anthropic.com/v1",
                            models: ["claude-3-7-sonnet"],
                            dailyCap: 900,
                            dailyUsed: 180,
                            dailyRemaining: 720,
                            totalUsed: 1_800
                        )
                    ],
                    routingStrategy: "fill-first"
                ),
            ]
        )

        let remoteModels = [
            RemoteModelEntry(
                id: "gpt-5.4",
                name: "GPT 5.4",
                backend: "openai",
                enabled: true,
                baseURL: "https://api.openai.com/v1",
                apiKeyRef: "openai-team-a",
                apiKey: "sk-openai"
            ),
            RemoteModelEntry(
                id: "claude-3-7-sonnet",
                name: "Claude 3.7 Sonnet",
                backend: "anthropic",
                enabled: true,
                baseURL: "https://api.anthropic.com/v1",
                apiKeyRef: "claude-team-a",
                apiKey: "sk-claude"
            ),
        ]

        let xtClient = HubGRPCClientEntry(
            deviceId: "xt-dev-breakdown",
            userId: "alice",
            name: "Alice XT",
            token: "tok-breakdown",
            enabled: true,
            createdAtMs: 1,
            policyMode: .newProfile,
            approvedTrustProfile: HubGRPCClientEntry.buildApprovedTrustProfile(
                deviceId: "xt-dev-breakdown",
                deviceName: "Alice XT",
                requestedCapabilities: ["models", "events", "ai.generate.local"],
                paidModelSelectionMode: .customSelectedModels,
                allowedPaidModels: ["gpt-5.4", "claude-3-7-sonnet"],
                defaultWebFetchEnabled: false,
                dailyTokenLimit: 500,
                auditRef: "xt-dev-breakdown"
            )
        )

        let projection = RemoteQuotaCenterSupport.projection(
            providerKeySnapshot: snapshot,
            remoteModels: remoteModels,
            clients: [xtClient],
            deviceStatusSnapshot: GRPCDevicesStatusSnapshot(
                schemaVersion: "grpc_devices_status.v2",
                updatedAtMs: 10,
                devices: [
                    makeDeviceStatus(
                        deviceId: "xt-dev-breakdown",
                        name: "Alice XT",
                        connected: true,
                        dailyTokenUsed: 150,
                        dailyTokenCap: 500,
                        remainingDailyTokenBudget: 350,
                        topModel: "gpt-5.4",
                        modelBreakdown: [
                            try makeModelBreakdown(
                                deviceId: "xt-dev-breakdown",
                                deviceName: "Alice XT",
                                modelId: "gpt-5.4",
                                totalTokens: 90
                            ),
                            try makeModelBreakdown(
                                deviceId: "xt-dev-breakdown",
                                deviceName: "Alice XT",
                                modelId: "claude-3-7-sonnet",
                                totalTokens: 60
                            ),
                        ]
                    )
                ]
            )
        )

        guard let consumer = projection.consumers.first else {
            return XCTFail("missing consumer projection")
        }
        XCTAssertEqual(consumer.observedDailyTokensByFamily["openai"], 90)
        XCTAssertEqual(consumer.observedDailyTokensByFamily["claude"], 60)

        guard let openAI = projection.families.first(where: { $0.familyKey == "openai" }) else {
            return XCTFail("missing openai family projection")
        }
        XCTAssertEqual(openAI.observedDailyTokensUsed, 90)

        guard let claude = projection.families.first(where: { $0.familyKey == "claude" }) else {
            return XCTFail("missing claude family projection")
        }
        XCTAssertEqual(claude.observedDailyTokensUsed, 60)
    }

    func testProjectionGroupsXTAndTerminalConsumersUnderSameUserID() throws {
        let snapshot = ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.v1",
            updatedAtMs: 1,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: [
                ProviderKeyProviderGroup(
                    provider: "openai",
                    accounts: [
                        makeAccount(
                            accountKey: "openai-team-a",
                            provider: "openai",
                            baseURL: "https://api.openai.com/v1",
                            models: ["gpt-5.4"],
                            dailyCap: 1_000,
                            dailyUsed: 220,
                            dailyRemaining: 780,
                            totalUsed: 3_200
                        )
                    ],
                    routingStrategy: "fill-first"
                ),
                ProviderKeyProviderGroup(
                    provider: "anthropic",
                    accounts: [
                        makeAccount(
                            accountKey: "claude-team-a",
                            provider: "anthropic",
                            baseURL: "https://api.anthropic.com/v1",
                            models: ["claude-3-7-sonnet"],
                            dailyCap: 900,
                            dailyUsed: 180,
                            dailyRemaining: 720,
                            totalUsed: 2_400
                        )
                    ],
                    routingStrategy: "fill-first"
                ),
            ]
        )

        let remoteModels = [
            RemoteModelEntry(
                id: "gpt-5.4",
                name: "GPT 5.4",
                backend: "openai",
                enabled: true,
                baseURL: "https://api.openai.com/v1",
                apiKeyRef: "openai-team-a",
                apiKey: "sk-openai"
            ),
            RemoteModelEntry(
                id: "claude-3-7-sonnet",
                name: "Claude 3.7 Sonnet",
                backend: "anthropic",
                enabled: true,
                baseURL: "https://api.anthropic.com/v1",
                apiKeyRef: "claude-team-a",
                apiKey: "sk-claude"
            ),
        ]

        let xtClient = HubGRPCClientEntry(
            deviceId: "xt-dev-shared",
            userId: "shared-user",
            name: "Shared XT",
            token: "tok-shared",
            enabled: true,
            createdAtMs: 1,
            policyMode: .newProfile,
            approvedTrustProfile: HubGRPCClientEntry.buildApprovedTrustProfile(
                deviceId: "xt-dev-shared",
                deviceName: "Shared XT",
                requestedCapabilities: ["models", "events", "ai.generate.local"],
                paidModelSelectionMode: .customSelectedModels,
                allowedPaidModels: ["gpt-5.4"],
                defaultWebFetchEnabled: false,
                dailyTokenLimit: 300,
                auditRef: "xt-dev-shared"
            )
        )

        let terminalAccessKey = try makeTerminalAccessKey(
            accessKeyID: "axhub_key_shared",
            deviceID: "terminal-dev-shared",
            userID: "shared-user",
            appID: "external_terminal",
            name: "Shared Shell",
            paidMode: .customSelectedModels,
            allowedModelIDs: ["claude-3-7-sonnet"],
            dailyTokenLimit: 200,
            defaultWebFetchEnabled: true
        )

        let projection = RemoteQuotaCenterSupport.projection(
            providerKeySnapshot: snapshot,
            remoteModels: remoteModels,
            clients: [xtClient],
            terminalAccessKeys: [terminalAccessKey],
            deviceStatusSnapshot: GRPCDevicesStatusSnapshot(
                schemaVersion: "grpc_devices_status.v2",
                updatedAtMs: 10,
                devices: [
                    makeDeviceStatus(
                        deviceId: "xt-dev-shared",
                        name: "Shared XT",
                        connected: true,
                        dailyTokenUsed: 110,
                        dailyTokenCap: 300,
                        remainingDailyTokenBudget: 190,
                        topModel: "gpt-5.4",
                        modelBreakdown: []
                    ),
                    makeDeviceStatus(
                        deviceId: "terminal-dev-shared",
                        name: "Shared Shell",
                        connected: false,
                        dailyTokenUsed: 60,
                        dailyTokenCap: 200,
                        remainingDailyTokenBudget: 140,
                        topModel: "claude-3-7-sonnet",
                        modelBreakdown: []
                    )
                ]
            )
        )

        XCTAssertEqual(projection.overview.userCount, 1)
        XCTAssertEqual(projection.users.count, 1)

        guard let user = projection.users.first else {
            return XCTFail("missing user projection")
        }
        XCTAssertEqual(user.groupingKind, .userID)
        XCTAssertEqual(user.displayName, "shared-user")
        XCTAssertEqual(user.consumerCount, 2)
        XCTAssertEqual(user.xtConsumerCount, 1)
        XCTAssertEqual(user.terminalConsumerCount, 1)
        XCTAssertEqual(user.connectedConsumerCount, 1)
        XCTAssertEqual(user.allocatedDailyTokenBudget, 500)
        XCTAssertEqual(user.observedDailyTokensUsed, 170)
        XCTAssertEqual(user.remainingDailyTokenBudget, 330)
        XCTAssertEqual(user.familyKeys, ["openai", "claude"])
    }

    private func makeAccount(
        accountKey: String,
        provider: String,
        baseURL: String,
        models: [String],
        dailyCap: Int64,
        dailyUsed: Int64,
        dailyRemaining: Int64,
        totalUsed: Int64
    ) -> ProviderKeyAccount {
        ProviderKeyAccount(
            accountKey: accountKey,
            provider: provider,
            poolID: "",
            providerHost: URL(string: baseURL)?.host ?? "",
            email: "\(accountKey)@example.com",
            apiKeyRedacted: "sk-***",
            baseURL: baseURL,
            proxyURL: "",
            enabled: true,
            authType: "api_key",
            wireAPI: "responses",
            expiresAtMs: 0,
            tier: "team",
            customHeaders: [:],
            models: models,
            notes: "",
            priority: 0,
            accountId: accountKey,
            sourceType: "manual",
            sourceRef: "",
            oauthSourceKey: "",
            authIndex: 0,
            createdAtMs: 1,
            updatedAtMs: 1,
            lastRefreshAtMs: 1,
            quota: ProviderKeyQuota(
                dailyTokenCap: dailyCap,
                dailyTokensUsed: dailyUsed,
                dailyTokensRemaining: dailyRemaining,
                totalTokensUsed: totalUsed,
                lastUsedAtMs: 1,
                lastErrorAtMs: 0,
                consecutiveErrors: 0,
                cooldownUntilMs: 0
            ),
            errorState: ProviderKeyErrorState(
                status: "healthy",
                statusMessage: "",
                detailMessage: "",
                reasonCode: "",
                lastErrorCode: "",
                lastErrorAtMs: 0,
                nextRetryAtMs: 0,
                retryAtText: "",
                retryAtSource: "",
                autoDisabled: false
            )
        )
    }

    private func makeDeviceStatus(
        deviceId: String,
        name: String,
        connected: Bool,
        dailyTokenUsed: Int64,
        dailyTokenCap: Int64,
        remainingDailyTokenBudget: Int64,
        topModel: String,
        modelBreakdown: [GRPCDeviceModelBreakdownEntry]
    ) -> GRPCDeviceStatusEntry {
        GRPCDeviceStatusEntry(
            deviceId: deviceId,
            appId: "xt",
            name: name,
            peerIp: "127.0.0.1",
            connected: connected,
            activeEventSubscriptions: connected ? 1 : 0,
            connectedAtMs: 1,
            lastSeenAtMs: 1,
            quotaDay: "2026-04-23",
            dailyTokenUsed: dailyTokenUsed,
            dailyTokenCap: dailyTokenCap,
            dailyTokenLimit: dailyTokenCap,
            dailyTokenRemaining: remainingDailyTokenBudget,
            remainingDailyTokenBudget: remainingDailyTokenBudget,
            requestsToday: connected ? 1 : 0,
            blockedToday: 0,
            paidModelPolicyMode: "all_paid_models",
            defaultWebFetchEnabled: false,
            trustProfilePresent: true,
            trustMode: "trusted_daily",
            topModel: topModel,
            lastBlockedReason: "",
            lastDenyCode: "",
            modelBreakdown: modelBreakdown,
            lastActivity: nil,
            tokenSeries5m1h: nil
        )
    }

    private func makeModelBreakdown(
        deviceId: String,
        deviceName: String,
        modelId: String,
        totalTokens: Int64
    ) throws -> GRPCDeviceModelBreakdownEntry {
        let payload: [String: Any] = [
            "device_id": deviceId,
            "device_name": deviceName,
            "model_id": modelId,
            "day_bucket": "2026-04-23",
            "prompt_tokens": max(Int64(0), totalTokens / 2),
            "completion_tokens": max(Int64(0), totalTokens - (totalTokens / 2)),
            "total_tokens": totalTokens,
            "request_count": 1,
            "blocked_count": 0,
            "last_used_at_ms": 1,
            "last_blocked_at_ms": 0,
            "last_blocked_reason": "",
            "last_deny_code": "",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(GRPCDeviceModelBreakdownEntry.self, from: data)
    }

    private func makeTerminalAccessKey(
        accessKeyID: String,
        deviceID: String,
        userID: String,
        appID: String,
        name: String,
        paidMode: HubPaidModelSelectionMode,
        allowedModelIDs: [String],
        dailyTokenLimit: Int,
        defaultWebFetchEnabled: Bool
    ) throws -> HubTerminalAccessKey {
        let payload: [String: Any] = [
            "schema_version": "hub.client_access_key.v1",
            "access_key_id": accessKeyID,
            "auth_kind": "hub_access_key",
            "status": "ready",
            "status_reason": "",
            "device_id": deviceID,
            "user_id": userID,
            "app_id": appID,
            "name": name,
            "enabled": true,
            "policy_mode": HubGRPCClientPolicyMode.newProfile.rawValue,
            "trust_profile_present": true,
            "approved_trust_profile": [
                "schema_version": "hub.paired_terminal_trust_profile.v1",
                "device_id": deviceID,
                "device_name": name,
                "trust_mode": HubTrustProfileDefaults.trustMode,
                "mode": HubTrustedAutomationMode.standard.rawValue,
                "state": HubTrustedAutomationState.active.rawValue,
                "capabilities": ["models", "ai.generate.local", "ai.generate.paid"],
                "allowed_project_ids": [],
                "allowed_workspace_roots": [],
                "xt_binding_required": false,
                "auto_grant_profile": "",
                "device_permission_owner_ref": "",
                "paid_model_policy": [
                    "schema_version": "hub.paired_terminal_paid_model_policy.v1",
                    "mode": paidMode.rawValue,
                    "allowed_model_ids": allowedModelIDs
                ],
                "network_policy": [
                    "default_web_fetch_enabled": defaultWebFetchEnabled
                ],
                "budget_policy": [
                    "daily_token_limit": dailyTokenLimit,
                    "single_request_token_limit": HubTrustProfileDefaults.singleRequestTokenLimit
                ],
                "audit_ref": accessKeyID
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return try JSONDecoder().decode(HubTerminalAccessKey.self, from: data)
    }
}
