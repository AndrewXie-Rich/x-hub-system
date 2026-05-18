import XCTest
@testable import RELFlowHubCore

final class ProviderKeyStorageImportSyncTests: XCTestCase {
    override func tearDown() {
        unsetenv("XHUB_SOURCE_RUN_HOME")
        super.tearDown()
    }

    func testSyncImportedAccountsCreatesFormalStoreForConfigImportedOAuthVariants() throws {
        let home = try makeTempHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let codexDir = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let auth17 = codexDir.appendingPathComponent("auth17.json")
        let auth19 = codexDir.appendingPathComponent("auth19.json")
        let config = codexDir.appendingPathComponent("config 149.toml")
        try "".write(to: auth17, atomically: true, encoding: .utf8)
        try "".write(to: auth19, atomically: true, encoding: .utf8)
        try "".write(to: config, atomically: true, encoding: .utf8)

        let result = ProviderKeyStorage.syncImportedAccounts(
            [
                ProviderKeyImportedAccountInput(
                    provider: "codex",
                    email: "",
                    apiKey: "ey-auth17-access-token",
                    refreshToken: "refresh-auth17",
                    baseURL: "https://api.openai.com/v1",
                    proxyURL: "",
                    enabled: true,
                    authType: "oauth",
                    wireAPI: "chat_completions",
                    expiresAtMs: 0,
                    tier: "",
                    customHeaders: [:],
                    models: ["gpt-5.4"],
                    notes: "Imported via Add Remote Model",
                    priority: 0,
                    accountID: "acct-17",
                    sourceType: "auth_file",
                    sourceRef: auth17.path,
                    oauthSourceKey: "chatgpt",
                    authIndex: 0,
                    sourceOwners: []
                ),
                ProviderKeyImportedAccountInput(
                    provider: "codex",
                    email: "",
                    apiKey: "ey-auth19-access-token",
                    refreshToken: "refresh-auth19",
                    baseURL: "https://api.openai.com/v1",
                    proxyURL: "",
                    enabled: true,
                    authType: "oauth",
                    wireAPI: "chat_completions",
                    expiresAtMs: 0,
                    tier: "",
                    customHeaders: [:],
                    models: ["gpt-5.4"],
                    notes: "Imported via Add Remote Model",
                    priority: 0,
                    accountID: "acct-19",
                    sourceType: "auth_file",
                    sourceRef: auth19.path,
                    oauthSourceKey: "chatgpt",
                    authIndex: 0,
                    sourceOwners: []
                ),
            ],
            importSource: ProviderKeyImportSource(kind: "config_path", sourceRef: config.path)
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.errors, [])

        let snapshot = ProviderKeyStorage.load()
        XCTAssertEqual(snapshot.schemaVersion, "hub_provider_keys.v1")
        XCTAssertEqual(snapshot.totalAccounts, 2)
        XCTAssertEqual(snapshot.importSources.count, 1)
        XCTAssertEqual(snapshot.importSources.first?.kind, "config_path")
        XCTAssertEqual(
            snapshot.importSources.first?.sourceRef,
            config.standardizedFileURL.path
        )

        let accounts = snapshot.allAccounts.sorted {
            $0.sourceRef.localizedCaseInsensitiveCompare($1.sourceRef) == .orderedAscending
        }
        XCTAssertEqual(accounts.map(\.provider), ["codex", "codex"])
        XCTAssertEqual(accounts.map(\.authType), ["oauth", "oauth"])
        XCTAssertEqual(accounts.map(\.sourceType), ["auth_file", "auth_file"])
        XCTAssertEqual(
            accounts.map(\.sourceRef),
            [auth17.standardizedFileURL.path, auth19.standardizedFileURL.path]
        )
        XCTAssertEqual(Set(accounts.flatMap(\.models)), Set(["gpt-5.4"]))

        let resolved = try XCTUnwrap(
            ProviderKeyStorage.loadResolvedCredential(accountKey: accounts[1].accountKey)
        )
        XCTAssertEqual(resolved.refreshToken, "refresh-auth19")
        XCTAssertEqual(resolved.oauthSourceKey, "chatgpt")
        XCTAssertEqual(resolved.sourceRef, auth19.standardizedFileURL.path)

        let rawStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        let rawStoreData = try Data(contentsOf: rawStoreURL)
        let rawStore = try XCTUnwrap(
            JSONSerialization.jsonObject(with: rawStoreData) as? [String: Any]
        )
        let sourceStatuses = try XCTUnwrap(rawStore["import_source_statuses"] as? [String: Any])
        XCTAssertEqual(sourceStatuses.keys.sorted(), ["config_path:\(config.standardizedFileURL.path)"])
    }

    func testSyncImportedAccountsMergesManualModelsIntoOneFormalAccount() throws {
        let home = try makeTempHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let first = ProviderKeyStorage.syncImportedAccounts(
            [
                ProviderKeyImportedAccountInput(
                    provider: "openai",
                    email: "",
                    apiKey: "sk-live-shared-key",
                    refreshToken: "",
                    baseURL: "https://api.picfix.pro/v1",
                    proxyURL: "",
                    enabled: true,
                    authType: "api_key",
                    wireAPI: "responses",
                    expiresAtMs: 0,
                    tier: "",
                    customHeaders: [:],
                    models: ["glm-5"],
                    notes: "Imported via Add Remote Model",
                    priority: 0,
                    accountID: "",
                    sourceType: "",
                    sourceRef: "",
                    oauthSourceKey: "",
                    authIndex: 0,
                    sourceOwners: []
                ),
            ]
        )
        XCTAssertTrue(first.ok)

        let second = ProviderKeyStorage.syncImportedAccounts(
            [
                ProviderKeyImportedAccountInput(
                    provider: "openai",
                    email: "",
                    apiKey: "sk-live-shared-key",
                    refreshToken: "",
                    baseURL: "https://api.picfix.pro/v1",
                    proxyURL: "",
                    enabled: true,
                    authType: "api_key",
                    wireAPI: "responses",
                    expiresAtMs: 0,
                    tier: "",
                    customHeaders: [:],
                    models: ["qwen3.6-plus", "gpt-5.4"],
                    notes: "Imported via Add Remote Model",
                    priority: 0,
                    accountID: "",
                    sourceType: "",
                    sourceRef: "",
                    oauthSourceKey: "",
                    authIndex: 0,
                    sourceOwners: []
                ),
            ]
        )
        XCTAssertTrue(second.ok)

        let snapshot = ProviderKeyStorage.load()
        XCTAssertEqual(snapshot.totalAccounts, 1)
        let account = try XCTUnwrap(snapshot.allAccounts.first)
        XCTAssertEqual(account.provider, "openai")
        XCTAssertEqual(account.providerHost, "api.picfix.pro")
        XCTAssertEqual(account.wireAPI, "responses")
        XCTAssertEqual(Set(account.models), Set(["glm-5", "qwen3.6-plus", "gpt-5.4"]))
        XCTAssertTrue(snapshot.quotaPools.contains(where: { $0.familyKey == "glm" }))
        XCTAssertTrue(snapshot.quotaPools.contains(where: { $0.familyKey == "qwen" }))
        XCTAssertTrue(snapshot.quotaPools.contains(where: { $0.familyKey == "openai" }))
    }

    func testSyncImportedAccountsSupportsCLIProxyOAuthSourceAndRuntimeMetadata() throws {
        let home = try makeTempHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let importedDir = home.appendingPathComponent("cliproxy-oauth", isDirectory: true)
        try FileManager.default.createDirectory(at: importedDir, withIntermediateDirectories: true)
        let authFile = importedDir.appendingPathComponent("claude-user.json")
        try "{}".write(to: authFile, atomically: true, encoding: .utf8)

        let source = ProviderKeyImportSource(
            kind: "cliproxy_oauth",
            sourceRef: "http://127.0.0.1:8317/"
        )

        let first = ProviderKeyStorage.syncImportedAccounts(
            [
                ProviderKeyImportedAccountInput(
                    provider: "claude",
                    email: "claude-user@example.com",
                    apiKey: "claude-access-token",
                    refreshToken: "claude-refresh-token",
                    baseURL: "https://api.anthropic.com/v1",
                    proxyURL: "",
                    enabled: true,
                    authType: "oauth",
                    wireAPI: "",
                    expiresAtMs: 1_900_000_000_000,
                    tier: "",
                    customHeaders: [:],
                    models: ["claude-sonnet-4-5"],
                    notes: "Imported from CLIProxy OAuth",
                    priority: 0,
                    accountID: "acct-claude-1",
                    sourceType: "auth_file",
                    sourceRef: authFile.path,
                    oauthSourceKey: "claude",
                    authIndex: 0,
                    runtimeAuthIndex: "runtime-claude-001",
                    runtimeStatus: "active",
                    statusMessage: "free tier available",
                    reasonCode: "",
                    nextRetryAtMs: 1_800_000_000_000,
                    lastRefreshAtMs: 1_799_000_000_000,
                    refreshStatus: "scheduled",
                    nextRefreshAtMs: 1_801_000_000_000,
                    quotaReason: "free_quota_refresh_pending",
                    quotaNextRecoverAtMs: 1_802_000_000_000,
                    sourceOwners: []
                ),
            ],
            importSource: source
        )

        XCTAssertTrue(first.ok)
        XCTAssertEqual(first.importedCount, 1)

        let snapshot = ProviderKeyStorage.load()
        XCTAssertEqual(snapshot.totalAccounts, 1)
        XCTAssertEqual(snapshot.importSources.count, 1)
        XCTAssertEqual(snapshot.importSources.first?.kind, "cliproxy_oauth")
        XCTAssertEqual(snapshot.importSources.first?.sourceRef, "http://127.0.0.1:8317")

        let account = try XCTUnwrap(snapshot.allAccounts.first)
        XCTAssertEqual(account.provider, "claude")
        XCTAssertEqual(account.runtimeAuthIndex, "runtime-claude-001")
        XCTAssertEqual(account.errorState.statusMessage, "free tier available")
        XCTAssertEqual(account.quota.reason, "free_quota_refresh_pending")
        XCTAssertEqual(account.quota.nextRecoverAtMs, 1_802_000_000_000)
        XCTAssertEqual(account.refreshState.status, "scheduled")
        XCTAssertEqual(account.refreshState.nextRefreshAtMs, 1_801_000_000_000)

        let resolved = try XCTUnwrap(
            ProviderKeyStorage.loadResolvedCredential(accountKey: account.accountKey)
        )
        XCTAssertEqual(resolved.runtimeAuthIndex, "runtime-claude-001")
        XCTAssertEqual(resolved.refreshState.status, "scheduled")
        XCTAssertEqual(resolved.refreshState.nextRefreshAtMs, 1_801_000_000_000)

        let second = ProviderKeyStorage.syncImportedAccounts([], importSource: source)
        XCTAssertTrue(second.ok)
        XCTAssertEqual(second.prunedCount, 1)

        let prunedSnapshot = ProviderKeyStorage.load()
        XCTAssertEqual(prunedSnapshot.totalAccounts, 0)
        XCTAssertEqual(prunedSnapshot.importSources.first?.ownedAccountCount, 0)
    }

    func testLoadPreservesProviderQuotaUsageWindows() throws {
        let home = try makeTempHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let result = ProviderKeyStorage.syncImportedAccounts(
            [
                makeOpenAIPoolInput(
                    email: "quota-windows@example.com",
                    apiKey: "sk-quota-window-account",
                    models: ["gpt-5.4"],
                    priority: 0
                ),
            ]
        )
        XCTAssertTrue(result.ok)

        var raw = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: ProviderKeyStorage.url())) as? [String: Any]
        )
        var providers = try XCTUnwrap(raw["providers"] as? [String: Any])
        var provider = try XCTUnwrap(providers["openai"] as? [String: Any])
        var accounts = try XCTUnwrap(provider["accounts"] as? [[String: Any]])
        var account = try XCTUnwrap(accounts.first)
        var quota = account["quota"] as? [String: Any] ?? [:]
        quota["usage_windows"] = [
            [
                "key": "rate_limit:primary:18000",
                "source": "rate_limit",
                "window_key": "primary",
                "label": "primary 5-hour window",
                "limit_window_seconds": 18_000,
                "used_percent": 42.5,
                "used_basis_points": 4_250,
                "remaining_basis_points": 5_750,
                "limited": false,
                "reset_at_ms": 1_900_000_000_000,
                "updated_at_ms": 1_899_999_000_000
            ],
            [
                "key": "rate_limit:secondary:604800",
                "source": "rate_limit",
                "window_key": "secondary",
                "label": "secondary 7-day window",
                "limit_window_seconds": 604_800,
                "used_percent": 71.25,
                "used_basis_points": 7_125,
                "remaining_basis_points": 2_875,
                "limited": false,
                "reset_at_ms": 1_900_604_800_000,
                "updated_at_ms": 1_899_999_000_000
            ]
        ]
        account["quota"] = quota
        accounts[0] = account
        provider["accounts"] = accounts
        providers["openai"] = provider
        raw["providers"] = providers
        let patchedData = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
        try patchedData.write(to: ProviderKeyStorage.url(), options: .atomic)

        let snapshot = ProviderKeyStorage.load()
        let parsedAccount = try XCTUnwrap(snapshot.allAccounts.first)
        XCTAssertEqual(parsedAccount.quota.usageWindows.count, 2)

        let fiveHourWindow = try XCTUnwrap(
            parsedAccount.quota.usageWindows.first { $0.limitWindowSeconds == 18_000 }
        )
        XCTAssertEqual(fiveHourWindow.source, "rate_limit")
        XCTAssertEqual(fiveHourWindow.windowKey, "primary")
        XCTAssertEqual(fiveHourWindow.usedPercent, 42.5, accuracy: 0.001)
        XCTAssertEqual(fiveHourWindow.usedBasisPoints, 4_250)
        XCTAssertEqual(fiveHourWindow.remainingBasisPoints, 5_750)
        XCTAssertEqual(fiveHourWindow.resetAtMs, 1_900_000_000_000)

        let sevenDayWindow = try XCTUnwrap(
            parsedAccount.quota.usageWindows.first { $0.limitWindowSeconds == 604_800 }
        )
        XCTAssertEqual(sevenDayWindow.windowKey, "secondary")
        XCTAssertEqual(sevenDayWindow.usedPercent, 71.25, accuracy: 0.001)
        XCTAssertEqual(sevenDayWindow.usedBasisPoints, 7_125)
        XCTAssertEqual(sevenDayWindow.remainingBasisPoints, 2_875)
    }

    func testRoutableCredentialPoolSkipsAccountCoolingOnlyByQuotaRecoverTime() throws {
        let home = try makeTempHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let result = ProviderKeyStorage.syncImportedAccounts(
            [
                makeOpenAIPoolInput(
                    email: "cooling@example.com",
                    apiKey: "sk-cooling-account",
                    models: ["GPT5.5"],
                    priority: 20
                ),
                makeOpenAIPoolInput(
                    email: "ready@example.com",
                    apiKey: "sk-ready-account",
                    models: ["gpt-5.5"],
                    priority: 1
                ),
            ]
        )
        XCTAssertTrue(result.ok)

        var raw = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: ProviderKeyStorage.url())) as? [String: Any]
        )
        var providers = try XCTUnwrap(raw["providers"] as? [String: Any])
        var provider = try XCTUnwrap(providers["openai"] as? [String: Any])
        var accounts = try XCTUnwrap(provider["accounts"] as? [[String: Any]])
        let futureRecoverAtMs = Int64((Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000.0).rounded())

        for index in accounts.indices where accounts[index]["email"] as? String == "cooling@example.com" {
            var account = accounts[index]
            var quota = account["quota"] as? [String: Any] ?? [:]
            quota["cooldown_until_ms"] = 0
            quota["next_recover_at_ms"] = futureRecoverAtMs
            quota["reason"] = "free_quota_refresh_pending"
            account["quota"] = quota
            var errorState = account["error_state"] as? [String: Any] ?? [:]
            errorState["status"] = "healthy"
            errorState["next_retry_at_ms"] = 0
            errorState["retry_at_source"] = ""
            account["error_state"] = errorState
            account["next_retry_at_ms"] = 0
            account["retry_at_source"] = ""
            accounts[index] = account
        }

        provider["accounts"] = accounts
        providers["openai"] = provider
        raw["providers"] = providers
        let patchedData = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
        try patchedData.write(to: ProviderKeyStorage.url(), options: .atomic)

        let snapshot = ProviderKeyStorage.load()
        let readyAccount = try XCTUnwrap(snapshot.allAccounts.first(where: { $0.email == "ready@example.com" }))
        let coolingAccount = try XCTUnwrap(snapshot.allAccounts.first(where: { $0.email == "cooling@example.com" }))
        let keyPool = try XCTUnwrap(snapshot.keyPools.first(where: { $0.poolID == readyAccount.poolID }))
        XCTAssertEqual(keyPool.readyAccounts, 1)
        XCTAssertEqual(keyPool.cooldownAccounts, 1)

        let pool = try XCTUnwrap(
            ProviderKeyStorage.loadRoutableCredentialPool(
                provider: "openai",
                poolID: readyAccount.poolID,
                modelID: "openai/gpt5.5"
            )
        )
        XCTAssertEqual(pool.credentials.map(\.accountKey), [readyAccount.accountKey])
        XCTAssertFalse(pool.credentials.map(\.accountKey).contains(coolingAccount.accountKey))
    }

    private func makeTempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-key-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeOpenAIPoolInput(
        email: String,
        apiKey: String,
        models: [String],
        priority: Int
    ) -> ProviderKeyImportedAccountInput {
        ProviderKeyImportedAccountInput(
            provider: "openai",
            email: email,
            apiKey: apiKey,
            refreshToken: "",
            baseURL: "https://api.openai.com/v1",
            proxyURL: "",
            enabled: true,
            authType: "api_key",
            wireAPI: "responses",
            expiresAtMs: 0,
            tier: "",
            customHeaders: [:],
            models: models,
            notes: "test",
            priority: priority,
            accountID: "",
            sourceType: "",
            sourceRef: "",
            oauthSourceKey: "",
            authIndex: 0,
            sourceOwners: []
        )
    }
}
