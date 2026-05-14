import Foundation

enum HubProviderKeysClient {
    struct ProviderModelState: Codable, Equatable, Sendable {
        var status: String
        var reasonCode: String
        var statusMessage: String
        var nextRetryAtMs: Double
        var retryAtSource: String
        var lastErrorCode: String
        var lastErrorAtMs: Double
        var updatedAtMs: Double
    }

    struct ProviderRefreshState: Codable, Equatable, Sendable {
        var status: String
        var lastAttemptAtMs: Double
        var lastSuccessAtMs: Double
        var nextRefreshAtMs: Double
        var failureCount: Int
        var lastErrorCode: String
        var lastErrorMessage: String
    }

    struct ProviderImportSourceStatus: Codable, Equatable, Sendable {
        var sourceKey: String
        var kind: String
        var sourceRef: String
        var state: String
        var lastSyncAtMs: Double
        var lastImportedCount: Int
        var ownedAccountCount: Int
        var lastErrorCount: Int
        var lastErrors: [String]
        var updatedAtMs: Double
    }

    struct ProviderRuntimeAccountSnapshot: Codable, Equatable, Sendable {
        var accountKey: String
        var provider: String
        var email: String
        var enabled: Bool
        var authType: String
        var tier: String
        var baseURL: String
        var proxyURL: String
        var poolID: String
        var providerHost: String
        var wireAPI: String
        var accountID: String
        var sourceType: String
        var sourceRef: String
        var oauthSourceKey: String
        var authIndex: Int
        var expiresAtMs: Double
        var createdAtMs: Double
        var updatedAtMs: Double
        var lastRefreshAtMs: Double
        var models: [String]
        var sourceOwners: [String]
        var requiredRefreshMetadata: [String]
        var quota: KeyQuota
        var errorState: KeyErrorState
        var refreshState: ProviderRefreshState
        var modelStates: [String: ProviderModelState]
        var apiKeyRedacted: String
        var notes: String
        var priority: Int
    }

    struct ProviderRuntimeSnapshot: Codable, Equatable, Sendable {
        var accounts: [ProviderRuntimeAccountSnapshot]
        var importSourceStatuses: [ProviderImportSourceStatus]
        var updatedAtMs: Double
        var globalRoutingStrategy: String
        var providers: [ProviderSummary]
    }

    struct ProviderRouteCandidateDecision: Codable, Equatable, Sendable {
        var accountKey: String
        var provider: String
        var providerGroup: String
        var poolID: String
        var providerHost: String
        var wireAPI: String
        var state: String
        var reasonCode: String
        var statusMessage: String
        var retryAtMs: Double
        var retryAtSource: String
        var score: Double
        var selected: Bool
        var models: [String]
        var sourceOwners: [String]
        var requiredRefreshMetadata: [String]
        var modelStateKey: String
    }

    struct ProviderRouteDecision: Codable, Equatable, Sendable {
        var requestedProvider: String
        var requestedModelID: String
        var resolvedProvider: String
        var strategy: String
        var selectionScope: String
        var selectedAccountKey: String
        var fallbackReasonCode: String
        var availableCount: Int
        var totalCount: Int
        var candidates: [ProviderRouteCandidateDecision]
        var updatedAtMs: Double
    }

    struct ProviderAccount: Sendable {
        var accountKey: String
        var provider: String
        var poolID: String = ""
        var providerHost: String = ""
        var email: String
        var apiKeyRedacted: String
        var baseUrl: String
        var proxyUrl: String
        var enabled: Bool
        var authType: String
        var wireAPI: String = ""
        var expiresAtMs: Double
        var tier: String
        var models: [String]
        var priority: Int
        var notes: String
        var accountId: String = ""
        var sourceType: String = ""
        var sourceRef: String = ""
        var oauthSourceKey: String = ""
        var authIndex: Int = 0
        var lastRefreshAtMs: Double = 0
        var modelStates: [String: ProviderModelState] = [:]
    }

    struct ProviderSummary: Codable, Equatable, Sendable {
        var provider: String
        var totalAccounts: Int
        var enabledAccounts: Int
        var routingStrategy: String
    }

    struct ProviderPoolMember: Codable, Equatable, Sendable {
        var accountKey: String
        var provider: String
        var email: String
        var tier: String
        var enabled: Bool
        var authType: String
        var accountId: String
        var sourceRef: String
        var oauthSourceKey: String
        var poolID: String
        var state: String
        var reasonCode: String
        var statusMessage: String
        var retryAtMs: Double
        var expiresAtMs: Double
        var lastRefreshAtMs: Double
        var lastUsedAtMs: Double
        var dailyTokenCap: Int64
        var dailyTokensUsed: Int64
        var dailyTokensRemaining: Int64
        var totalTokensUsed: Int64
        var removable: Bool
        var removalReason: String
        var apiKeyRedacted: String
    }

    struct ProviderPool: Codable, Equatable, Sendable {
        var poolID: String
        var capabilityPoolID: String
        var provider: String
        var providerHost: String
        var wireAPI: String
        var modelID: String
        var modelFamily: String
        var state: String
        var sourceProviders: [String]
        var totalAccounts: Int
        var enabledAccounts: Int
        var readyAccounts: Int
        var cooldownAccounts: Int
        var blockedAccounts: Int
        var expiredAccounts: Int
        var disabledAccounts: Int
        var staleAccounts: Int
        var authFailedAccounts: Int
        var freeAccounts: Int
        var paidAccounts: Int
        var unknownTierAccounts: Int
        var removableAccounts: Int
        var knownQuotaAccounts: Int
        var dailyTokenCap: Int64
        var dailyTokensUsed: Int64
        var dailyTokensRemaining: Int64
        var totalTokensUsed: Int64
        var nextRetryAtMs: Double
        var lastUsedAtMs: Double
        var lastRefreshAtMs: Double
        var blockerReasonCodes: [String]
        var members: [ProviderPoolMember]
    }

    struct ProviderPoolList: Codable, Equatable, Sendable {
        var pools: [ProviderPool]
        var updatedAtMs: Double
        var routingStrategy: String
    }

    struct KeySummary: Sendable {
        var schemaVersion: String
        var updatedAtMs: Double
        var globalRoutingStrategy: String
        var providers: [ProviderSummary]
    }

    struct KeyQuota: Codable, Equatable, Sendable {
        var dailyTokenCap: Int64
        var dailyTokensUsed: Int64
        var dailyTokensRemaining: Int64
        var totalTokensUsed: Int64
        var lastUsedAtMs: Double
        var lastErrorAtMs: Double
        var consecutiveErrors: Int
        var cooldownUntilMs: Double
    }

    struct KeyErrorState: Codable, Equatable, Sendable {
        var status: String
        var statusMessage: String
        var reasonCode: String
        var lastErrorCode: String
        var lastErrorAtMs: Double
        var nextRetryAtMs: Double
        var retryAtSource: String
        var autoDisabled: Bool
    }

    struct KeyUsageInfo: Sendable {
        var accountKey: String
        var provider: String
        var quota: KeyQuota
        var errorState: KeyErrorState
        var modelStates: [String: ProviderModelState] = [:]
    }

    struct ImportResult: Sendable {
        var ok: Bool
        var imported: Int
        var errors: [String]
    }

    struct OAuthLoginStartResult: Sendable {
        var ok: Bool
        var error: String
        var provider: String
        var state: String
        var authURL: String
        var redirectURI: String
        var status: String
        var expiresAtMs: Double
    }

    struct OAuthLoginSubmitResult: Sendable {
        var ok: Bool
        var error: String
        var provider: String
        var state: String
        var status: String
    }

    struct OAuthLoginStatus: Sendable {
        var ok: Bool
        var error: String
        var provider: String
        var state: String
        var status: String
        var expiresAtMs: Double
        var updatedAtMs: Double
        var authURL: String
        var redirectURI: String
        var statusMessage: String
        var accountKey: String
        var email: String
        var authFilePath: String
        var imported: Int

        var isTerminal: Bool {
            status == "ok" || status == "error" || status == "expired" || status == "unknown"
        }
    }

    struct OperationResult: Sendable {
        var ok: Bool
        var error: String
    }

    struct RemoveProviderKeysResult: Sendable {
        var ok: Bool
        var removed: Int
        var missingAccountKeys: [String]
        var error: String
    }

    struct ReportKeyErrorResult: Sendable {
        var ok: Bool
        var error: String
        var autoDisabled: Bool
    }

    struct ProviderKeyRuntimeFeedback: Sendable {
        var accountKey: String
        var modelID: String = ""
        var outcome: String
        var httpStatus: Int = 0
        var reasonCode: String = ""
        var statusMessage: String = ""
        var tokensUsed: Int64 = 0
        var costUsd: Double = 0
        var latencyMs: Int64 = 0
        var occurredAtMs: Int64 = 0
        var nextRetryAtMs: Int64 = 0
        var retryAtSource: String = ""
    }

    private static let cacheQueue = DispatchQueue(label: "hub_provider_keys_client.cache")
    private static var cachedSummary: KeySummary?
    private static var cachedSummaryAt: Double = 0
    private static let cacheTTL: Double = 15.0

    static func listProviderKeys() async -> [ProviderAccount] {
        guard let result = await runProviderKeysScript(method: "ListProviderKeys", payload: [:]) else {
            return []
        }
        guard let accounts = result["accounts"] as? [[String: Any]] else {
            return []
        }
        return accounts.compactMap { parseProviderAccount($0) }
    }

    static func listProviderKeyPools(
        provider: String = "",
        modelID: String = "",
        includeMembers: Bool = false
    ) async -> ProviderPoolList {
        let payload: [String: Any] = [
            "provider": provider,
            "model_id": modelID,
            "include_members": includeMembers,
        ]
        guard let result = await runProviderKeysScript(method: "ListProviderKeyPools", payload: payload) else {
            return ProviderPoolList(pools: [], updatedAtMs: 0, routingStrategy: "fill-first")
        }
        let pools = (result["pools"] as? [[String: Any]])?.compactMap { parseProviderPool($0) } ?? []
        return ProviderPoolList(
            pools: pools,
            updatedAtMs: doubleValue(result["updated_at_ms"]),
            routingStrategy: stringValue(result["routing_strategy"])
        )
    }

    static func getProviderKeyRuntimeSnapshot(
        provider: String = ""
    ) async -> ProviderRuntimeSnapshot? {
        let payload: [String: Any] = [
            "provider": provider,
        ]
        guard let result = await runProviderKeysScript(method: "GetProviderKeyRuntimeSnapshot", payload: payload) else {
            return nil
        }
        let accounts = (result["accounts"] as? [[String: Any]] ?? []).compactMap { parseProviderRuntimeAccountSnapshot($0) }
        let importStatuses = (result["import_source_statuses"] as? [[String: Any]] ?? []).compactMap {
            parseProviderImportSourceStatus($0)
        }
        let providers = (result["providers"] as? [[String: Any]] ?? []).map { p -> ProviderSummary in
            ProviderSummary(
                provider: stringValue(p["provider"]),
                totalAccounts: intValue(p["total_accounts"]),
                enabledAccounts: intValue(p["enabled_accounts"]),
                routingStrategy: stringValue(p["routing_strategy"]).isEmpty ? "fill-first" : stringValue(p["routing_strategy"])
            )
        }
        return ProviderRuntimeSnapshot(
            accounts: accounts,
            importSourceStatuses: importStatuses,
            updatedAtMs: doubleValue(result["updated_at_ms"]),
            globalRoutingStrategy: stringValue(result["global_routing_strategy"]).isEmpty ? "fill-first" : stringValue(result["global_routing_strategy"]),
            providers: providers
        )
    }

    static func getProviderKeyRouteDecision(
        modelID: String,
        provider: String = ""
    ) async -> ProviderRouteDecision? {
        let payload: [String: Any] = [
            "model_id": modelID,
            "provider": provider,
        ]
        guard let result = await runProviderKeysScript(method: "GetProviderKeyRouteDecision", payload: payload),
              let rawDecision = result["decision"] as? [String: Any] else {
            return nil
        }
        return parseProviderRouteDecision(rawDecision)
    }

    static func addProviderKey(
        provider: String,
        apiKey: String,
        authType: String = "api_key",
        email: String = "",
        baseUrl: String = "",
        proxyUrl: String = "",
        wireAPI: String = "",
        tier: String = "",
        models: [String] = [],
        priority: Int = 0,
        notes: String = ""
    ) async -> OperationResult {
        let payload: [String: Any] = [
            "provider": provider,
            "api_key": apiKey,
            "auth_type": authType,
            "email": email,
            "base_url": baseUrl,
            "proxy_url": proxyUrl,
            "wire_api": wireAPI,
            "tier": tier,
            "models": models,
            "priority": priority,
            "notes": notes,
        ]
        guard let result = await runProviderKeysScript(method: "AddProviderKey", payload: payload) else {
            return OperationResult(ok: false, error: "script_failed")
        }
        return OperationResult(
            ok: boolValue(result["ok"]),
            error: stringValue(result["error"])
        )
    }

    static func removeProviderKey(accountKey: String) async -> OperationResult {
        let payload: [String: Any] = ["account_key": accountKey]
        guard let result = await runProviderKeysScript(method: "RemoveProviderKey", payload: payload) else {
            return OperationResult(ok: false, error: "script_failed")
        }
        return OperationResult(
            ok: boolValue(result["ok"]),
            error: stringValue(result["error"])
        )
    }

    static func removeProviderKeys(accountKeys: [String]) async -> RemoveProviderKeysResult {
        let payload: [String: Any] = ["account_keys": accountKeys]
        guard let result = await runProviderKeysScript(method: "RemoveProviderKeys", payload: payload) else {
            return RemoveProviderKeysResult(ok: false, removed: 0, missingAccountKeys: [], error: "script_failed")
        }
        return RemoveProviderKeysResult(
            ok: boolValue(result["ok"]),
            removed: intValue(result["removed"]),
            missingAccountKeys: (result["missing_account_keys"] as? [String]) ?? [],
            error: stringValue(result["error"])
        )
    }

    static func updateProviderKey(
        accountKey: String,
        fields: [String: Any]
    ) async -> OperationResult {
        var payload = fields
        payload["account_key"] = accountKey
        guard let result = await runProviderKeysScript(method: "UpdateProviderKey", payload: payload) else {
            return OperationResult(ok: false, error: "script_failed")
        }
        return OperationResult(
            ok: boolValue(result["ok"]),
            error: stringValue(result["error"])
        )
    }

    static func setProviderRoutingStrategy(
        provider: String,
        strategy: String
    ) async -> OperationResult {
        let payload: [String: Any] = [
            "provider": provider,
            "strategy": strategy,
        ]
        guard let result = await runProviderKeysScript(method: "SetProviderRoutingStrategy", payload: payload) else {
            return OperationResult(ok: false, error: "script_failed")
        }
        return OperationResult(
            ok: boolValue(result["ok"]),
            error: stringValue(result["error"])
        )
    }

    static func importProviderKeys(
        authDir: String = "",
        configPath: String = ""
    ) async -> ImportResult {
        let payload: [String: Any] = [
            "auth_dir": authDir,
            "config_path": configPath,
        ]
        guard let result = await runProviderKeysScript(method: "ImportProviderKeys", payload: payload) else {
            return ImportResult(ok: false, imported: 0, errors: ["script_failed"])
        }
        let errors = (result["errors"] as? [String]) ?? []
        return ImportResult(
            ok: boolValue(result["ok"]),
            imported: intValue(result["imported"]),
            errors: errors
        )
    }

    static func startProviderOAuthLogin(
        provider: String,
        redirectURI: String = ""
    ) async -> OAuthLoginStartResult {
        let payload: [String: Any] = [
            "provider": provider,
            "redirect_uri": redirectURI,
        ]
        guard let result = await runProviderKeysScript(method: "StartProviderOAuthLogin", payload: payload) else {
            return OAuthLoginStartResult(
                ok: false,
                error: "script_failed",
                provider: provider,
                state: "",
                authURL: "",
                redirectURI: "",
                status: "error",
                expiresAtMs: 0
            )
        }
        return OAuthLoginStartResult(
            ok: boolValue(result["ok"]),
            error: stringValue(result["error"]),
            provider: stringValue(result["provider"]),
            state: stringValue(result["state"]),
            authURL: stringValue(result["auth_url"]),
            redirectURI: stringValue(result["redirect_uri"]),
            status: stringValue(result["status"]).isEmpty ? "error" : stringValue(result["status"]),
            expiresAtMs: doubleValue(result["expires_at_ms"])
        )
    }

    static func submitProviderOAuthCallback(
        provider: String,
        state: String,
        code: String = "",
        redirectURL: String = "",
        error: String = ""
    ) async -> OAuthLoginSubmitResult {
        let payload: [String: Any] = [
            "provider": provider,
            "state": state,
            "code": code,
            "redirect_url": redirectURL,
            "error": error,
        ]
        guard let result = await runProviderKeysScript(method: "SubmitProviderOAuthCallback", payload: payload) else {
            return OAuthLoginSubmitResult(
                ok: false,
                error: "script_failed",
                provider: provider,
                state: state,
                status: "error"
            )
        }
        return OAuthLoginSubmitResult(
            ok: boolValue(result["ok"]),
            error: stringValue(result["error"]),
            provider: stringValue(result["provider"]),
            state: stringValue(result["state"]).isEmpty ? state : stringValue(result["state"]),
            status: stringValue(result["status"]).isEmpty ? "error" : stringValue(result["status"])
        )
    }

    static func getProviderOAuthLoginStatus(state: String) async -> OAuthLoginStatus {
        let payload: [String: Any] = ["state": state]
        guard let result = await runProviderKeysScript(method: "GetProviderOAuthLoginStatus", payload: payload) else {
            return OAuthLoginStatus(
                ok: false,
                error: "script_failed",
                provider: "",
                state: state,
                status: "unknown",
                expiresAtMs: 0,
                updatedAtMs: 0,
                authURL: "",
                redirectURI: "",
                statusMessage: "",
                accountKey: "",
                email: "",
                authFilePath: "",
                imported: 0
            )
        }
        return OAuthLoginStatus(
            ok: boolValue(result["ok"]),
            error: stringValue(result["error"]),
            provider: stringValue(result["provider"]),
            state: stringValue(result["state"]).isEmpty ? state : stringValue(result["state"]),
            status: stringValue(result["status"]).isEmpty ? "unknown" : stringValue(result["status"]),
            expiresAtMs: doubleValue(result["expires_at_ms"]),
            updatedAtMs: doubleValue(result["updated_at_ms"]),
            authURL: stringValue(result["auth_url"]),
            redirectURI: stringValue(result["redirect_uri"]),
            statusMessage: stringValue(result["status_message"]),
            accountKey: stringValue(result["account_key"]),
            email: stringValue(result["email"]),
            authFilePath: stringValue(result["auth_file_path"]),
            imported: intValue(result["imported"])
        )
    }

    static func getProviderKeySummary(forceRefresh: Bool = false) async -> KeySummary {
        let now = Date().timeIntervalSince1970
        let cached = cacheQueue.sync { () -> KeySummary? in
            guard !forceRefresh,
                  let cachedSummary,
                  (now - cachedSummaryAt) < cacheTTL else {
                return nil
            }
            return cachedSummary
        }
        if let cached {
            return cached
        }

        guard let result = await runProviderKeysScript(method: "GetProviderKeySummary", payload: [:]) else {
            return KeySummary(schemaVersion: "", updatedAtMs: 0, globalRoutingStrategy: "fill-first", providers: [])
        }

        let providers = (result["providers"] as? [[String: Any]] ?? []).map { p -> ProviderSummary in
            ProviderSummary(
                provider: stringValue(p["provider"]),
                totalAccounts: intValue(p["total_accounts"]),
                enabledAccounts: intValue(p["enabled_accounts"]),
                routingStrategy: stringValue(p["routing_strategy"]).isEmpty ? "fill-first" : stringValue(p["routing_strategy"])
            )
        }

        let summary = KeySummary(
            schemaVersion: stringValue(result["schema_version"]),
            updatedAtMs: doubleValue(result["updated_at_ms"]),
            globalRoutingStrategy: stringValue(result["global_routing_strategy"]).isEmpty ? "fill-first" : stringValue(result["global_routing_strategy"]),
            providers: providers
        )

        cacheQueue.sync {
            cachedSummary = summary
            cachedSummaryAt = now
        }

        return summary
    }

    static func reportKeyUsage(
        accountKey: String,
        tokensUsed: Int64,
        costUsd: Double,
        modelID: String = "",
        latencyMs: Int64 = 0,
        occurredAtMs: Int64 = 0
    ) async -> OperationResult {
        let payload: [String: Any] = [
            "account_key": accountKey,
            "tokens_used": Int(tokensUsed),
            "cost_usd": costUsd,
            "model_id": modelID,
            "latency_ms": Int(latencyMs),
            "occurred_at_ms": Int(occurredAtMs),
        ]
        guard let result = await runProviderKeysScript(method: "ReportKeyUsage", payload: payload) else {
            return OperationResult(ok: false, error: "script_failed")
        }
        return OperationResult(
            ok: boolValue(result["ok"]),
            error: stringValue(result["error"])
        )
    }

    static func reportKeyError(
        accountKey: String,
        errorCode: String,
        modelID: String = "",
        outcome: String = "",
        httpStatus: Int = 0,
        reasonCode: String = "",
        statusMessage: String = "",
        latencyMs: Int64 = 0,
        occurredAtMs: Int64 = 0,
        nextRetryAtMs: Int64 = 0,
        retryAtSource: String = ""
    ) async -> ReportKeyErrorResult {
        let payload: [String: Any] = [
            "account_key": accountKey,
            "error_code": errorCode,
            "model_id": modelID,
            "outcome": outcome,
            "http_status": httpStatus,
            "reason_code": reasonCode,
            "status_message": statusMessage,
            "latency_ms": Int(latencyMs),
            "occurred_at_ms": Int(occurredAtMs),
            "next_retry_at_ms": Int(nextRetryAtMs),
            "retry_at_source": retryAtSource,
        ]
        guard let result = await runProviderKeysScript(method: "ReportKeyError", payload: payload) else {
            return ReportKeyErrorResult(ok: false, error: "script_failed", autoDisabled: false)
        }
        return ReportKeyErrorResult(
            ok: boolValue(result["ok"]),
            error: stringValue(result["error"]),
            autoDisabled: boolValue(result["auto_disabled"])
        )
    }

    static func getKeyUsage(accountKey: String) async -> KeyUsageInfo? {
        let payload: [String: Any] = ["account_key": accountKey]
        guard let result = await runProviderKeysScript(method: "GetKeyUsage", payload: payload) else {
            return nil
        }
        let q = result["quota"] as? [String: Any] ?? [:]
        let e = result["error_state"] as? [String: Any] ?? [:]
        return KeyUsageInfo(
            accountKey: stringValue(result["account_key"]),
            provider: stringValue(result["provider"]),
            quota: KeyQuota(
                dailyTokenCap: int64Value(q["daily_token_cap"]),
                dailyTokensUsed: int64Value(q["daily_tokens_used"]),
                dailyTokensRemaining: int64Value(q["daily_tokens_remaining"]),
                totalTokensUsed: int64Value(q["total_tokens_used"]),
                lastUsedAtMs: doubleValue(q["last_used_at_ms"]),
                lastErrorAtMs: doubleValue(q["last_error_at_ms"]),
                consecutiveErrors: intValue(q["consecutive_errors"]),
                cooldownUntilMs: doubleValue(q["cooldown_until_ms"])
            ),
            errorState: KeyErrorState(
                status: stringValue(e["status"]).isEmpty ? "healthy" : stringValue(e["status"]),
                statusMessage: stringValue(e["status_message"]),
                reasonCode: stringValue(e["reason_code"]),
                lastErrorCode: stringValue(e["last_error_code"]),
                lastErrorAtMs: doubleValue(e["last_error_at_ms"]),
                nextRetryAtMs: doubleValue(e["next_retry_at_ms"]),
                retryAtSource: stringValue(e["retry_at_source"]),
                autoDisabled: boolValue(e["auto_disabled"])
            ),
            modelStates: parseProviderModelStateMap(result["model_states"])
        )
    }

    static func resetKeyErrorState(accountKey: String) async -> OperationResult {
        let payload: [String: Any] = ["account_key": accountKey]
        guard let result = await runProviderKeysScript(method: "ResetKeyErrorState", payload: payload) else {
            return OperationResult(ok: false, error: "script_failed")
        }
        return OperationResult(
            ok: boolValue(result["ok"]),
            error: stringValue(result["error"])
        )
    }

    static func invalidateCache() {
        cacheQueue.sync {
            cachedSummary = nil
            cachedSummaryAt = 0
        }
    }

    // MARK: - Private

    private static func runProviderKeysScript(
        method: String,
        payload: [String: Any]
    ) async -> [String: Any]? {
        guard let baseEnv = resolveHubEnv() else { return nil }
        guard let (nodeBin, clientKitHub) = resolveNodeAndCwd(env: baseEnv) else { return nil }

        let payloadJSON = (try? JSONSerialization.data(withJSONObject: payload, options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        var scriptEnv = baseEnv
        scriptEnv["XTERMINAL_PROVIDER_KEYS_METHOD"] = method
        scriptEnv["XTERMINAL_PROVIDER_KEYS_PAYLOAD"] = payloadJSON

        let script = providerKeysScriptSource()

        do {
            let result = try ProcessCapture.run(
                nodeBin,
                ["--input-type=module", "-"],
                cwd: clientKitHub,
                stdin: script.data(using: .utf8),
                timeoutSec: 15.0,
                env: scriptEnv
            )
            guard result.exitCode == 0 else { return nil }
            guard let jsonLine = extractTrailingJSONObjectLine(result.combined),
                  let data = jsonLine.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return obj
        } catch {
            return nil
        }
    }

    private static func resolveHubEnv() -> [String: String]? {
        let stateDir = XTProcessPaths.defaultAxhubStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        guard FileManager.default.fileExists(atPath: hubEnv.path) else { return nil }
        return readEnvExports(from: hubEnv)
    }

    private static func resolveNodeAndCwd(env: [String: String]) -> (String, URL)? {
        let stateDir = XTProcessPaths.defaultAxhubStateDir()
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        guard FileManager.default.fileExists(atPath: clientKitHub.path) else { return nil }
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: env) else { return nil }
        return (nodeBin, clientKitHub)
    }

    private static func resolveNodeExecutable(clientKitBaseDir: URL, env: [String: String]) -> String? {
        let fm = FileManager.default
        let override = stringValue(env["AXHUBCTL_NODE_BIN"])
        if !override.isEmpty, fm.isExecutableFile(atPath: override) {
            return override
        }

        let clientKitNode = clientKitBaseDir.appendingPathComponent("bin/relflowhub_node").path
        if fm.isExecutableFile(atPath: clientKitNode) {
            return clientKitNode
        }

        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        for candidate in candidates where fm.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private static func readEnvExports(from fileURL: URL) -> [String: String] {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            var candidate = trimmed
            if candidate.hasPrefix("export ") {
                candidate = String(candidate.dropFirst("export ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let eq = candidate.firstIndex(of: "=") else { continue }
            let key = String(candidate[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(candidate[candidate.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            out[key] = unquoteShellValue(value)
        }
        return out
    }

    private static func unquoteShellValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }

        if trimmed.hasPrefix("'"), trimmed.hasSuffix("'") {
            return String(trimmed.dropFirst().dropLast())
        }

        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            let inner = String(trimmed.dropFirst().dropLast())
            return inner
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }

        return trimmed
    }

    private static func providerKeysScriptSource() -> String {
        return """
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => { process.stdout.write(JSON.stringify(obj) + '\\n'); };

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', 'Bearer ' + tok);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }
  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) { if (fs.existsSync(p)) return p; }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true, longs: String, enums: String, defaults: true, oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function main() {
  const method = safe(process.env.XTERMINAL_PROVIDER_KEYS_METHOD || '');
  const payloadRaw = safe(process.env.XTERMINAL_PROVIDER_KEYS_PAYLOAD || '{}');
  let payload;
  try { payload = JSON.parse(payloadRaw); } catch { payload = {}; }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubProviderKeys) throw new Error('hub_provider_keys_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = host + ':' + port;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const pkClient = new proto.HubProviderKeys(addr, creds, options);

  const req = { client, ...payload };

  const resp = await new Promise((resolve, reject) => {
    pkClient[method](req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });

  out(resp);
}

main().catch((e) => { out({ ok: false, error: String(e?.message || e) }); process.exitCode = 1; });
"""
    }

    private static func parseProviderAccount(_ raw: [String: Any]) -> ProviderAccount? {
        let accountKey = stringValue(raw["account_key"])
        guard !accountKey.isEmpty else { return nil }
        return ProviderAccount(
            accountKey: accountKey,
            provider: stringValue(raw["provider"]),
            poolID: stringValue(raw["pool_id"]),
            providerHost: stringValue(raw["provider_host"]),
            email: stringValue(raw["email"]),
            apiKeyRedacted: stringValue(raw["api_key_redacted"]),
            baseUrl: stringValue(raw["base_url"]),
            proxyUrl: stringValue(raw["proxy_url"]),
            enabled: boolValue(raw["enabled"]),
            authType: stringValue(raw["auth_type"]),
            wireAPI: stringValue(raw["wire_api"]),
            expiresAtMs: doubleValue(raw["expires_at_ms"]),
            tier: stringValue(raw["tier"]),
            models: (raw["models"] as? [String]) ?? [],
            priority: intValue(raw["priority"]),
            notes: stringValue(raw["notes"]),
            accountId: stringValue(raw["account_id"]),
            sourceType: stringValue(raw["source_type"]),
            sourceRef: stringValue(raw["source_ref"]),
            oauthSourceKey: stringValue(raw["oauth_source_key"]),
            authIndex: intValue(raw["auth_index"]),
            lastRefreshAtMs: doubleValue(raw["last_refresh_at_ms"]),
            modelStates: parseProviderModelStateMap(raw["model_states"])
        )
    }

    private static func parseProviderModelStateMap(_ raw: Any?) -> [String: ProviderModelState] {
        guard let rawMap = raw as? [String: Any] else { return [:] }
        var result: [String: ProviderModelState] = [:]
        for (rawKey, rawValue) in rawMap {
            guard let state = rawValue as? [String: Any] else { continue }
            let modelID = stringValue(rawKey).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !modelID.isEmpty else { continue }
            result[modelID] = ProviderModelState(
                status: stringValue(state["status"]),
                reasonCode: stringValue(state["reason_code"]),
                statusMessage: stringValue(state["status_message"]),
                nextRetryAtMs: doubleValue(state["next_retry_at_ms"]),
                retryAtSource: stringValue(state["retry_at_source"]),
                lastErrorCode: stringValue(state["last_error_code"]),
                lastErrorAtMs: doubleValue(state["last_error_at_ms"]),
                updatedAtMs: doubleValue(state["updated_at_ms"])
            )
        }
        return result
    }

    private static func parseProviderPoolMember(_ raw: [String: Any]) -> ProviderPoolMember? {
        let accountKey = stringValue(raw["account_key"])
        guard !accountKey.isEmpty else { return nil }
        return ProviderPoolMember(
            accountKey: accountKey,
            provider: stringValue(raw["provider"]),
            email: stringValue(raw["email"]),
            tier: stringValue(raw["tier"]),
            enabled: boolValue(raw["enabled"]),
            authType: stringValue(raw["auth_type"]),
            accountId: stringValue(raw["account_id"]),
            sourceRef: stringValue(raw["source_ref"]),
            oauthSourceKey: stringValue(raw["oauth_source_key"]),
            poolID: stringValue(raw["pool_id"]),
            state: stringValue(raw["state"]),
            reasonCode: stringValue(raw["reason_code"]),
            statusMessage: stringValue(raw["status_message"]),
            retryAtMs: doubleValue(raw["retry_at_ms"]),
            expiresAtMs: doubleValue(raw["expires_at_ms"]),
            lastRefreshAtMs: doubleValue(raw["last_refresh_at_ms"]),
            lastUsedAtMs: doubleValue(raw["last_used_at_ms"]),
            dailyTokenCap: int64Value(raw["daily_token_cap"]),
            dailyTokensUsed: int64Value(raw["daily_tokens_used"]),
            dailyTokensRemaining: int64Value(raw["daily_tokens_remaining"]),
            totalTokensUsed: int64Value(raw["total_tokens_used"]),
            removable: boolValue(raw["removable"]),
            removalReason: stringValue(raw["removal_reason"]),
            apiKeyRedacted: stringValue(raw["api_key_redacted"])
        )
    }

    private static func parseProviderPool(_ raw: [String: Any]) -> ProviderPool? {
        let poolID = stringValue(raw["pool_id"])
        guard !poolID.isEmpty else { return nil }
        return ProviderPool(
            poolID: poolID,
            capabilityPoolID: stringValue(raw["capability_pool_id"]),
            provider: stringValue(raw["provider"]),
            providerHost: stringValue(raw["provider_host"]),
            wireAPI: stringValue(raw["wire_api"]),
            modelID: stringValue(raw["model_id"]),
            modelFamily: stringValue(raw["model_family"]),
            state: stringValue(raw["state"]),
            sourceProviders: (raw["source_providers"] as? [String]) ?? [],
            totalAccounts: intValue(raw["total_accounts"]),
            enabledAccounts: intValue(raw["enabled_accounts"]),
            readyAccounts: intValue(raw["ready_accounts"]),
            cooldownAccounts: intValue(raw["cooldown_accounts"]),
            blockedAccounts: intValue(raw["blocked_accounts"]),
            expiredAccounts: intValue(raw["expired_accounts"]),
            disabledAccounts: intValue(raw["disabled_accounts"]),
            staleAccounts: intValue(raw["stale_accounts"]),
            authFailedAccounts: intValue(raw["auth_failed_accounts"]),
            freeAccounts: intValue(raw["free_accounts"]),
            paidAccounts: intValue(raw["paid_accounts"]),
            unknownTierAccounts: intValue(raw["unknown_tier_accounts"]),
            removableAccounts: intValue(raw["removable_accounts"]),
            knownQuotaAccounts: intValue(raw["known_quota_accounts"]),
            dailyTokenCap: int64Value(raw["daily_token_cap"]),
            dailyTokensUsed: int64Value(raw["daily_tokens_used"]),
            dailyTokensRemaining: int64Value(raw["daily_tokens_remaining"]),
            totalTokensUsed: int64Value(raw["total_tokens_used"]),
            nextRetryAtMs: doubleValue(raw["next_retry_at_ms"]),
            lastUsedAtMs: doubleValue(raw["last_used_at_ms"]),
            lastRefreshAtMs: doubleValue(raw["last_refresh_at_ms"]),
            blockerReasonCodes: (raw["blocker_reason_codes"] as? [String]) ?? [],
            members: (raw["members"] as? [[String: Any]])?.compactMap { parseProviderPoolMember($0) } ?? []
        )
    }

    private static func parseProviderRefreshState(_ raw: [String: Any]) -> ProviderRefreshState {
        ProviderRefreshState(
            status: stringValue(raw["status"]).isEmpty ? "idle" : stringValue(raw["status"]),
            lastAttemptAtMs: doubleValue(raw["last_attempt_at_ms"]),
            lastSuccessAtMs: doubleValue(raw["last_success_at_ms"]),
            nextRefreshAtMs: doubleValue(raw["next_refresh_at_ms"]),
            failureCount: intValue(raw["failure_count"]),
            lastErrorCode: stringValue(raw["last_error_code"]),
            lastErrorMessage: stringValue(raw["last_error_message"])
        )
    }

    private static func parseProviderImportSourceStatus(_ raw: [String: Any]) -> ProviderImportSourceStatus? {
        let sourceKey = stringValue(raw["source_key"])
        guard !sourceKey.isEmpty else { return nil }
        return ProviderImportSourceStatus(
            sourceKey: sourceKey,
            kind: stringValue(raw["kind"]),
            sourceRef: stringValue(raw["source_ref"]),
            state: stringValue(raw["state"]).isEmpty ? "pending" : stringValue(raw["state"]),
            lastSyncAtMs: doubleValue(raw["last_sync_at_ms"]),
            lastImportedCount: intValue(raw["last_imported_count"]),
            ownedAccountCount: intValue(raw["owned_account_count"]),
            lastErrorCount: intValue(raw["last_error_count"]),
            lastErrors: (raw["last_errors"] as? [String]) ?? [],
            updatedAtMs: doubleValue(raw["updated_at_ms"])
        )
    }

    private static func parseProviderRuntimeAccountSnapshot(_ raw: [String: Any]) -> ProviderRuntimeAccountSnapshot? {
        let accountKey = stringValue(raw["account_key"])
        guard !accountKey.isEmpty else { return nil }
        let quotaRaw = raw["quota"] as? [String: Any] ?? [:]
        let errorRaw = raw["error_state"] as? [String: Any] ?? [:]
        let refreshRaw = raw["refresh_state"] as? [String: Any] ?? [:]
        return ProviderRuntimeAccountSnapshot(
            accountKey: accountKey,
            provider: stringValue(raw["provider"]),
            email: stringValue(raw["email"]),
            enabled: boolValue(raw["enabled"]),
            authType: stringValue(raw["auth_type"]).isEmpty ? "api_key" : stringValue(raw["auth_type"]),
            tier: stringValue(raw["tier"]),
            baseURL: stringValue(raw["base_url"]),
            proxyURL: stringValue(raw["proxy_url"]),
            poolID: stringValue(raw["pool_id"]),
            providerHost: stringValue(raw["provider_host"]),
            wireAPI: stringValue(raw["wire_api"]),
            accountID: stringValue(raw["account_id"]),
            sourceType: stringValue(raw["source_type"]),
            sourceRef: stringValue(raw["source_ref"]),
            oauthSourceKey: stringValue(raw["oauth_source_key"]),
            authIndex: intValue(raw["auth_index"]),
            expiresAtMs: doubleValue(raw["expires_at_ms"]),
            createdAtMs: doubleValue(raw["created_at_ms"]),
            updatedAtMs: doubleValue(raw["updated_at_ms"]),
            lastRefreshAtMs: doubleValue(raw["last_refresh_at_ms"]),
            models: (raw["models"] as? [String]) ?? [],
            sourceOwners: (raw["source_owners"] as? [String]) ?? [],
            requiredRefreshMetadata: (raw["required_refresh_metadata"] as? [String]) ?? [],
            quota: KeyQuota(
                dailyTokenCap: int64Value(quotaRaw["daily_token_cap"]),
                dailyTokensUsed: int64Value(quotaRaw["daily_tokens_used"]),
                dailyTokensRemaining: int64Value(quotaRaw["daily_tokens_remaining"]),
                totalTokensUsed: int64Value(quotaRaw["total_tokens_used"]),
                lastUsedAtMs: doubleValue(quotaRaw["last_used_at_ms"]),
                lastErrorAtMs: doubleValue(quotaRaw["last_error_at_ms"]),
                consecutiveErrors: intValue(quotaRaw["consecutive_errors"]),
                cooldownUntilMs: doubleValue(quotaRaw["cooldown_until_ms"])
            ),
            errorState: KeyErrorState(
                status: stringValue(errorRaw["status"]).isEmpty ? "healthy" : stringValue(errorRaw["status"]),
                statusMessage: stringValue(errorRaw["status_message"]),
                reasonCode: stringValue(errorRaw["reason_code"]),
                lastErrorCode: stringValue(errorRaw["last_error_code"]),
                lastErrorAtMs: doubleValue(errorRaw["last_error_at_ms"]),
                nextRetryAtMs: doubleValue(errorRaw["next_retry_at_ms"]),
                retryAtSource: stringValue(errorRaw["retry_at_source"]),
                autoDisabled: boolValue(errorRaw["auto_disabled"])
            ),
            refreshState: parseProviderRefreshState(refreshRaw),
            modelStates: parseProviderModelStateMap(raw["model_states"]),
            apiKeyRedacted: stringValue(raw["api_key_redacted"]),
            notes: stringValue(raw["notes"]),
            priority: intValue(raw["priority"])
        )
    }

    private static func parseProviderRouteCandidateDecision(_ raw: [String: Any]) -> ProviderRouteCandidateDecision? {
        let accountKey = stringValue(raw["account_key"])
        guard !accountKey.isEmpty else { return nil }
        return ProviderRouteCandidateDecision(
            accountKey: accountKey,
            provider: stringValue(raw["provider"]),
            providerGroup: stringValue(raw["provider_group"]),
            poolID: stringValue(raw["pool_id"]),
            providerHost: stringValue(raw["provider_host"]),
            wireAPI: stringValue(raw["wire_api"]),
            state: stringValue(raw["state"]),
            reasonCode: stringValue(raw["reason_code"]),
            statusMessage: stringValue(raw["status_message"]),
            retryAtMs: doubleValue(raw["retry_at_ms"]),
            retryAtSource: stringValue(raw["retry_at_source"]),
            score: doubleValue(raw["score"]),
            selected: boolValue(raw["selected"]),
            models: (raw["models"] as? [String]) ?? [],
            sourceOwners: (raw["source_owners"] as? [String]) ?? [],
            requiredRefreshMetadata: (raw["required_refresh_metadata"] as? [String]) ?? [],
            modelStateKey: stringValue(raw["model_state_key"])
        )
    }

    private static func parseProviderRouteDecision(_ raw: [String: Any]) -> ProviderRouteDecision? {
        ProviderRouteDecision(
            requestedProvider: stringValue(raw["requested_provider"]),
            requestedModelID: stringValue(raw["requested_model_id"]),
            resolvedProvider: stringValue(raw["resolved_provider"]),
            strategy: stringValue(raw["strategy"]).isEmpty ? "fill-first" : stringValue(raw["strategy"]),
            selectionScope: stringValue(raw["selection_scope"]),
            selectedAccountKey: stringValue(raw["selected_account_key"]),
            fallbackReasonCode: stringValue(raw["fallback_reason_code"]),
            availableCount: intValue(raw["available_count"]),
            totalCount: intValue(raw["total_count"]),
            candidates: (raw["candidates"] as? [[String: Any]])?.compactMap { parseProviderRouteCandidateDecision($0) } ?? [],
            updatedAtMs: doubleValue(raw["updated_at_ms"])
        )
    }

    private static func extractTrailingJSONObjectLine(_ output: String) -> String? {
        let lines = output.components(separatedBy: "\n").reversed()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
                return trimmed
            }
        }
        return nil
    }

    private static func boolValue(_ v: Any?) -> Bool {
        switch v {
        case let b as Bool: return b
        case let s as String: return s.lowercased() == "true"
        case let n as NSNumber: return n.boolValue
        default: return false
        }
    }

    private static func stringValue(_ v: Any?) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }

    private static func intValue(_ v: Any?) -> Int {
        switch v {
        case let n as Int: return n
        case let n as Double: return Int(n)
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? 0
        default: return 0
        }
    }

    private static func int64Value(_ v: Any?) -> Int64 {
        switch v {
        case let n as Int64: return n
        case let n as Int: return Int64(n)
        case let n as Double: return Int64(n)
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s) ?? 0
        default: return 0
        }
    }

    private static func doubleValue(_ v: Any?) -> Double {
        switch v {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }
}
