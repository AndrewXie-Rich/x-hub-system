import CryptoKit
import Foundation

public struct ProviderKeyAccount: Identifiable, Codable, Equatable, Sendable {
    public var id: String { accountKey }
    public var accountKey: String
    public var provider: String
    public var poolID: String = ""
    public var providerHost: String = ""
    public var email: String
    public var apiKeyRedacted: String
    public var baseURL: String
    public var proxyURL: String
    public var enabled: Bool
    public var authType: String
    public var wireAPI: String = ""
    public var expiresAtMs: Int64
    public var tier: String
    public var customHeaders: [String: String]
    public var models: [String]
    public var notes: String
    public var priority: Int
    public var accountId: String = ""
    public var sourceType: String = ""
    public var sourceRef: String = ""
    public var oauthSourceKey: String = ""
    public var authIndex: Int = 0
    public var runtimeAuthIndex: String = ""
    public var createdAtMs: Int64
    public var updatedAtMs: Int64
    public var lastRefreshAtMs: Int64 = 0
    public var quota: ProviderKeyQuota
    public var errorState: ProviderKeyErrorState
    public var refreshState: ProviderKeyRefreshState = ProviderKeyRefreshState()

    public enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case provider
        case poolID = "pool_id"
        case providerHost = "provider_host"
        case email
        case apiKeyRedacted = "api_key"
        case baseURL = "base_url"
        case proxyURL = "proxy_url"
        case enabled
        case authType = "auth_type"
        case wireAPI = "wire_api"
        case expiresAtMs = "expires_at_ms"
        case tier
        case customHeaders = "custom_headers"
        case models
        case notes
        case priority
        case accountId = "account_id"
        case sourceType = "source_type"
        case sourceRef = "source_ref"
        case oauthSourceKey = "oauth_source_key"
        case authIndex = "auth_index"
        case runtimeAuthIndex = "runtime_auth_index"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case lastRefreshAtMs = "last_refresh_at_ms"
        case quota
        case errorState = "error_state"
        case refreshState = "refresh_state"
    }
}

public struct ProviderKeyUsageWindow: Codable, Equatable, Sendable {
    public var key: String
    public var source: String
    public var windowKey: String
    public var label: String
    public var limitWindowSeconds: Int
    public var usedPercent: Double
    public var usedBasisPoints: Int
    public var remainingBasisPoints: Int
    public var limited: Bool
    public var resetAtMs: Int64
    public var updatedAtMs: Int64

    public enum CodingKeys: String, CodingKey {
        case key
        case source
        case windowKey = "window_key"
        case label
        case limitWindowSeconds = "limit_window_seconds"
        case usedPercent = "used_percent"
        case usedBasisPoints = "used_basis_points"
        case remainingBasisPoints = "remaining_basis_points"
        case limited
        case resetAtMs = "reset_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    public init(
        key: String = "",
        source: String = "",
        windowKey: String = "",
        label: String = "",
        limitWindowSeconds: Int = 0,
        usedPercent: Double = 0,
        usedBasisPoints: Int = 0,
        remainingBasisPoints: Int = 0,
        limited: Bool = false,
        resetAtMs: Int64 = 0,
        updatedAtMs: Int64 = 0
    ) {
        self.key = key
        self.source = source
        self.windowKey = windowKey
        self.label = label
        self.limitWindowSeconds = limitWindowSeconds
        self.usedPercent = usedPercent
        self.usedBasisPoints = usedBasisPoints
        self.remainingBasisPoints = remainingBasisPoints
        self.limited = limited
        self.resetAtMs = resetAtMs
        self.updatedAtMs = updatedAtMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try container.decodeIfPresent(String.self, forKey: .key) ?? "",
            source: try container.decodeIfPresent(String.self, forKey: .source) ?? "",
            windowKey: try container.decodeIfPresent(String.self, forKey: .windowKey) ?? "",
            label: try container.decodeIfPresent(String.self, forKey: .label) ?? "",
            limitWindowSeconds: try container.decodeIfPresent(Int.self, forKey: .limitWindowSeconds) ?? 0,
            usedPercent: try container.decodeIfPresent(Double.self, forKey: .usedPercent) ?? 0,
            usedBasisPoints: try container.decodeIfPresent(Int.self, forKey: .usedBasisPoints) ?? 0,
            remainingBasisPoints: try container.decodeIfPresent(Int.self, forKey: .remainingBasisPoints) ?? 0,
            limited: try container.decodeIfPresent(Bool.self, forKey: .limited) ?? false,
            resetAtMs: try container.decodeIfPresent(Int64.self, forKey: .resetAtMs) ?? 0,
            updatedAtMs: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMs) ?? 0
        )
    }
}

public struct ProviderKeyQuota: Codable, Equatable, Sendable {
    public var dailyTokenCap: Int64
    public var dailyTokensUsed: Int64
    public var dailyTokensRemaining: Int64
    public var totalTokensUsed: Int64
    public var lastUsedAtMs: Int64
    public var lastErrorAtMs: Int64
    public var consecutiveErrors: Int
    public var cooldownUntilMs: Int64
    public var reason: String = ""
    public var nextRecoverAtMs: Int64 = 0
    public var usageWindows: [ProviderKeyUsageWindow] = []

    public enum CodingKeys: String, CodingKey {
        case dailyTokenCap = "daily_token_cap"
        case dailyTokensUsed = "daily_tokens_used"
        case dailyTokensRemaining = "daily_tokens_remaining"
        case totalTokensUsed = "total_tokens_used"
        case lastUsedAtMs = "last_used_at_ms"
        case lastErrorAtMs = "last_error_at_ms"
        case consecutiveErrors = "consecutive_errors"
        case cooldownUntilMs = "cooldown_until_ms"
        case reason
        case nextRecoverAtMs = "next_recover_at_ms"
        case usageWindows = "usage_windows"
    }

    public init(
        dailyTokenCap: Int64 = 0,
        dailyTokensUsed: Int64 = 0,
        dailyTokensRemaining: Int64 = 0,
        totalTokensUsed: Int64 = 0,
        lastUsedAtMs: Int64 = 0,
        lastErrorAtMs: Int64 = 0,
        consecutiveErrors: Int = 0,
        cooldownUntilMs: Int64 = 0,
        reason: String = "",
        nextRecoverAtMs: Int64 = 0,
        usageWindows: [ProviderKeyUsageWindow] = []
    ) {
        self.dailyTokenCap = dailyTokenCap
        self.dailyTokensUsed = dailyTokensUsed
        self.dailyTokensRemaining = dailyTokensRemaining
        self.totalTokensUsed = totalTokensUsed
        self.lastUsedAtMs = lastUsedAtMs
        self.lastErrorAtMs = lastErrorAtMs
        self.consecutiveErrors = consecutiveErrors
        self.cooldownUntilMs = cooldownUntilMs
        self.reason = reason
        self.nextRecoverAtMs = nextRecoverAtMs
        self.usageWindows = usageWindows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dailyTokenCap: try container.decodeIfPresent(Int64.self, forKey: .dailyTokenCap) ?? 0,
            dailyTokensUsed: try container.decodeIfPresent(Int64.self, forKey: .dailyTokensUsed) ?? 0,
            dailyTokensRemaining: try container.decodeIfPresent(Int64.self, forKey: .dailyTokensRemaining) ?? 0,
            totalTokensUsed: try container.decodeIfPresent(Int64.self, forKey: .totalTokensUsed) ?? 0,
            lastUsedAtMs: try container.decodeIfPresent(Int64.self, forKey: .lastUsedAtMs) ?? 0,
            lastErrorAtMs: try container.decodeIfPresent(Int64.self, forKey: .lastErrorAtMs) ?? 0,
            consecutiveErrors: try container.decodeIfPresent(Int.self, forKey: .consecutiveErrors) ?? 0,
            cooldownUntilMs: try container.decodeIfPresent(Int64.self, forKey: .cooldownUntilMs) ?? 0,
            reason: try container.decodeIfPresent(String.self, forKey: .reason) ?? "",
            nextRecoverAtMs: try container.decodeIfPresent(Int64.self, forKey: .nextRecoverAtMs) ?? 0,
            usageWindows: try container.decodeIfPresent([ProviderKeyUsageWindow].self, forKey: .usageWindows) ?? []
        )
    }
}

public struct ProviderKeyRefreshState: Codable, Equatable, Sendable {
    public var status: String = "idle"
    public var lastAttemptAtMs: Int64 = 0
    public var lastSuccessAtMs: Int64 = 0
    public var nextRefreshAtMs: Int64 = 0
    public var failureCount: Int = 0
    public var lastErrorCode: String = ""
    public var lastErrorMessage: String = ""

    public init(
        status: String = "idle",
        lastAttemptAtMs: Int64 = 0,
        lastSuccessAtMs: Int64 = 0,
        nextRefreshAtMs: Int64 = 0,
        failureCount: Int = 0,
        lastErrorCode: String = "",
        lastErrorMessage: String = ""
    ) {
        self.status = status
        self.lastAttemptAtMs = lastAttemptAtMs
        self.lastSuccessAtMs = lastSuccessAtMs
        self.nextRefreshAtMs = nextRefreshAtMs
        self.failureCount = failureCount
        self.lastErrorCode = lastErrorCode
        self.lastErrorMessage = lastErrorMessage
    }

    public enum CodingKeys: String, CodingKey {
        case status
        case lastAttemptAtMs = "last_attempt_at_ms"
        case lastSuccessAtMs = "last_success_at_ms"
        case nextRefreshAtMs = "next_refresh_at_ms"
        case failureCount = "failure_count"
        case lastErrorCode = "last_error_code"
        case lastErrorMessage = "last_error_message"
    }
}

public struct ProviderKeyErrorState: Codable, Equatable, Sendable {
    public var status: String
    public var statusMessage: String = ""
    public var detailMessage: String = ""
    public var reasonCode: String = ""
    public var lastErrorCode: String
    public var lastErrorAtMs: Int64
    public var nextRetryAtMs: Int64 = 0
    public var retryAtText: String = ""
    public var retryAtSource: String = ""
    public var autoDisabled: Bool

    public enum CodingKeys: String, CodingKey {
        case status
        case statusMessage = "status_message"
        case detailMessage = "detail_message"
        case reasonCode = "reason_code"
        case lastErrorCode = "last_error_code"
        case lastErrorAtMs = "last_error_at_ms"
        case nextRetryAtMs = "next_retry_at_ms"
        case retryAtText = "retry_at_text"
        case retryAtSource = "retry_at_source"
        case autoDisabled = "auto_disabled"
    }
}

public struct ProviderKeyProviderGroup: Identifiable, Equatable, Sendable {
    public var id: String { provider }
    public var provider: String
    public var accounts: [ProviderKeyAccount]
    public var routingStrategy: String
}

public struct ProviderKeyImportSourceStatus: Identifiable, Equatable, Sendable {
    public var id: String { sourceKey }
    public var sourceKey: String
    public var kind: String
    public var sourceRef: String
    public var state: String
    public var lastSyncAtMs: Int64
    public var lastImportedCount: Int
    public var ownedAccountCount: Int
    public var lastErrorCount: Int
    public var lastErrors: [String]
    public var updatedAtMs: Int64
}

public struct ProviderKeyImportSource: Equatable, Sendable {
    public var kind: String
    public var sourceRef: String

    public init(kind: String, sourceRef: String) {
        self.kind = kind
        self.sourceRef = sourceRef
    }
}

public struct ProviderKeyImportedAccountInput: Equatable, Sendable {
    public var provider: String
    public var email: String
    public var apiKey: String
    public var refreshToken: String
    public var baseURL: String
    public var proxyURL: String
    public var enabled: Bool
    public var authType: String
    public var wireAPI: String
    public var expiresAtMs: Int64
    public var tier: String
    public var customHeaders: [String: String]
    public var models: [String]
    public var notes: String
    public var priority: Int
    public var accountID: String
    public var sourceType: String
    public var sourceRef: String
    public var oauthSourceKey: String
    public var authIndex: Int
    public var runtimeAuthIndex: String
    public var runtimeStatus: String
    public var statusMessage: String
    public var reasonCode: String
    public var nextRetryAtMs: Int64
    public var lastRefreshAtMs: Int64
    public var refreshStatus: String
    public var nextRefreshAtMs: Int64
    public var quotaReason: String
    public var quotaNextRecoverAtMs: Int64
    public var sourceOwners: [String]

    public init(
        provider: String,
        email: String,
        apiKey: String,
        refreshToken: String,
        baseURL: String,
        proxyURL: String,
        enabled: Bool,
        authType: String,
        wireAPI: String,
        expiresAtMs: Int64,
        tier: String,
        customHeaders: [String: String],
        models: [String],
        notes: String,
        priority: Int,
        accountID: String,
        sourceType: String,
        sourceRef: String,
        oauthSourceKey: String,
        authIndex: Int,
        runtimeAuthIndex: String = "",
        runtimeStatus: String = "",
        statusMessage: String = "",
        reasonCode: String = "",
        nextRetryAtMs: Int64 = 0,
        lastRefreshAtMs: Int64 = 0,
        refreshStatus: String = "",
        nextRefreshAtMs: Int64 = 0,
        quotaReason: String = "",
        quotaNextRecoverAtMs: Int64 = 0,
        sourceOwners: [String]
    ) {
        self.provider = provider
        self.email = email
        self.apiKey = apiKey
        self.refreshToken = refreshToken
        self.baseURL = baseURL
        self.proxyURL = proxyURL
        self.enabled = enabled
        self.authType = authType
        self.wireAPI = wireAPI
        self.expiresAtMs = expiresAtMs
        self.tier = tier
        self.customHeaders = customHeaders
        self.models = models
        self.notes = notes
        self.priority = priority
        self.accountID = accountID
        self.sourceType = sourceType
        self.sourceRef = sourceRef
        self.oauthSourceKey = oauthSourceKey
        self.authIndex = authIndex
        self.runtimeAuthIndex = runtimeAuthIndex
        self.runtimeStatus = runtimeStatus
        self.statusMessage = statusMessage
        self.reasonCode = reasonCode
        self.nextRetryAtMs = nextRetryAtMs
        self.lastRefreshAtMs = lastRefreshAtMs
        self.refreshStatus = refreshStatus
        self.nextRefreshAtMs = nextRefreshAtMs
        self.quotaReason = quotaReason
        self.quotaNextRecoverAtMs = quotaNextRecoverAtMs
        self.sourceOwners = sourceOwners
    }
}

public struct ProviderKeyImportSyncResult: Equatable, Sendable {
    public var ok: Bool
    public var importedCount: Int
    public var prunedCount: Int
    public var errors: [String]
}

public struct ProviderKeyImportSourceRemovalResult: Equatable, Sendable {
    public var ok: Bool
    public var removedSourceCount: Int
    public var removedAccountCount: Int
    public var detachedAccountCount: Int
    public var errors: [String]
}

public struct ProviderKeyPoolMemberState: Identifiable, Equatable, Sendable {
    public var id: String { account.accountKey }
    public var account: ProviderKeyAccount
    public var state: String
    public var isRoutable: Bool
    public var nextRetryAtMs: Int64
    public var retryAtSource: String
    public var reasonCode: String
    public var reasonMessage: String
    public var detailMessage: String
}

public struct ProviderKeyPoolSnapshot: Identifiable, Equatable, Sendable {
    public var id: String { poolID }
    public var poolID: String
    public var supplierKey: String
    public var supplierDisplayName: String
    public var provider: String
    public var providerDisplayName: String
    public var providerHost: String
    public var wireAPI: String
    public var routingStrategy: String
    public var state: String
    public var members: [ProviderKeyPoolMemberState]
    public var totalAccounts: Int
    public var enabledAccounts: Int
    public var readyAccounts: Int
    public var degradedAccounts: Int
    public var cooldownAccounts: Int
    public var blockedAccounts: Int
    public var disabledAccounts: Int
    public var staleAccounts: Int
    public var totalDailyTokenCap: Int64
    public var totalDailyTokensUsed: Int64
    public var totalDailyTokensRemaining: Int64
    public var totalTokensUsed: Int64
    public var earliestRetryAtMs: Int64
    public var lastRefreshAtMs: Int64
    public var hasQuotaData: Bool
    public var supportedFamilyKeys: [String]
    public var supportedFamilyDisplayNames: [String]
    public var issueSummary: String
    public var issueDetail: String

    public var hasSharedQuotaBoundary: Bool {
        supportedFamilyKeys.count > 1
    }
}

public struct ProviderQuotaPoolSnapshot: Identifiable, Equatable, Sendable {
    public var id: String { familyKey }
    public var familyKey: String
    public var displayName: String
    public var state: String
    public var providerHosts: [String]
    public var supplierKeys: [String]
    public var supplierDisplayNames: [String]
    public var sources: [ProviderQuotaPoolSourceSnapshot]
    public var totalSources: Int
    public var dedicatedSources: Int
    public var sharedSources: Int
    public var totalAccounts: Int
    public var readyAccounts: Int
    public var degradedAccounts: Int
    public var cooldownAccounts: Int
    public var blockedAccounts: Int
    public var disabledAccounts: Int
    public var staleAccounts: Int
    public var exclusiveDailyTokenCap: Int64
    public var exclusiveDailyTokensUsed: Int64
    public var exclusiveDailyTokensRemaining: Int64
    public var exclusiveTotalTokensUsed: Int64
    public var sharedDailyTokenCap: Int64
    public var sharedDailyTokensUsed: Int64
    public var sharedDailyTokensRemaining: Int64
    public var sharedTotalTokensUsed: Int64
    public var earliestRetryAtMs: Int64
    public var hasExclusiveQuotaData: Bool
    public var hasSharedQuotaData: Bool
    public var sharedWithFamilyDisplayNames: [String]
    public var issueSummary: String
    public var issueDetail: String

    public var hasQuotaData: Bool {
        hasExclusiveQuotaData || hasSharedQuotaData
    }
}

public struct ProviderQuotaPoolSourceSnapshot: Identifiable, Equatable, Sendable {
    public var id: String { "\(familyKey):\(poolID)" }
    public var familyKey: String
    public var poolID: String
    public var supplierKey: String
    public var supplierDisplayName: String
    public var provider: String
    public var providerDisplayName: String
    public var providerHost: String
    public var wireAPI: String
    public var routingStrategy: String
    public var state: String
    public var members: [ProviderKeyPoolMemberState]
    public var totalAccounts: Int
    public var enabledAccounts: Int
    public var readyAccounts: Int
    public var degradedAccounts: Int
    public var cooldownAccounts: Int
    public var blockedAccounts: Int
    public var disabledAccounts: Int
    public var staleAccounts: Int
    public var totalDailyTokenCap: Int64
    public var totalDailyTokensUsed: Int64
    public var totalDailyTokensRemaining: Int64
    public var totalTokensUsed: Int64
    public var earliestRetryAtMs: Int64
    public var lastRefreshAtMs: Int64
    public var hasQuotaData: Bool
    public var supportedFamilyKeys: [String]
    public var supportedFamilyDisplayNames: [String]
    public var sharedWithFamilyKeys: [String]
    public var sharedWithFamilyDisplayNames: [String]
    public var issueSummary: String
    public var issueDetail: String

    public var hasSharedQuotaBoundary: Bool {
        !sharedWithFamilyKeys.isEmpty
    }
}

public struct ProviderKeyResolvedCredential: Equatable, Sendable {
    public var accountKey: String
    public var provider: String
    public var poolID: String = ""
    public var providerHost: String = ""
    public var apiKey: String
    public var refreshToken: String
    public var baseURL: String
    public var proxyURL: String
    public var enabled: Bool
    public var authType: String
    public var wireAPI: String = ""
    public var expiresAtMs: Int64
    public var customHeaders: [String: String]
    public var models: [String]
    public var accountId: String = ""
    public var oauthSourceKey: String = ""
    public var authIndex: Int = 0
    public var runtimeAuthIndex: String = ""
    public var sourceType: String = ""
    public var sourceRef: String = ""
    public var statusMessage: String = ""
    public var reasonCode: String = ""
    public var lastRefreshAtMs: Int64 = 0
    public var refreshState: ProviderKeyRefreshState = ProviderKeyRefreshState()
    public var nextRetryAtMs: Int64 = 0
    public var retryAtSource: String = ""

    public init(
        accountKey: String,
        provider: String,
        poolID: String = "",
        providerHost: String = "",
        apiKey: String,
        refreshToken: String,
        baseURL: String,
        proxyURL: String,
        enabled: Bool,
        authType: String,
        wireAPI: String = "",
        expiresAtMs: Int64,
        customHeaders: [String: String],
        models: [String],
        accountId: String = "",
        oauthSourceKey: String = "",
        authIndex: Int = 0,
        runtimeAuthIndex: String = "",
        sourceType: String = "",
        sourceRef: String = "",
        statusMessage: String = "",
        reasonCode: String = "",
        lastRefreshAtMs: Int64 = 0,
        refreshState: ProviderKeyRefreshState = ProviderKeyRefreshState(),
        nextRetryAtMs: Int64 = 0,
        retryAtSource: String = ""
    ) {
        self.accountKey = accountKey
        self.provider = provider
        self.poolID = poolID
        self.providerHost = providerHost
        self.apiKey = apiKey
        self.refreshToken = refreshToken
        self.baseURL = baseURL
        self.proxyURL = proxyURL
        self.enabled = enabled
        self.authType = authType
        self.wireAPI = wireAPI
        self.expiresAtMs = expiresAtMs
        self.customHeaders = customHeaders
        self.models = models
        self.accountId = accountId
        self.oauthSourceKey = oauthSourceKey
        self.authIndex = authIndex
        self.runtimeAuthIndex = runtimeAuthIndex
        self.sourceType = sourceType
        self.sourceRef = sourceRef
        self.statusMessage = statusMessage
        self.reasonCode = reasonCode
        self.lastRefreshAtMs = lastRefreshAtMs
        self.refreshState = refreshState
        self.nextRetryAtMs = nextRetryAtMs
        self.retryAtSource = retryAtSource
    }
}

public struct ProviderKeyResolvedCredentialPool: Equatable, Sendable {
    public var poolID: String
    public var provider: String
    public var routingStrategy: String
    public var credentials: [ProviderKeyResolvedCredential]

    public init(
        poolID: String,
        provider: String,
        routingStrategy: String,
        credentials: [ProviderKeyResolvedCredential]
    ) {
        self.poolID = poolID
        self.provider = provider
        self.routingStrategy = routingStrategy
        self.credentials = credentials
    }
}

public struct ProviderKeyStoreSnapshot: Equatable, Sendable {
    public var schemaVersion: String
    public var updatedAtMs: Int64
    public var globalRoutingStrategy: String
    public var importSources: [ProviderKeyImportSourceStatus]
    public var providerGroups: [ProviderKeyProviderGroup]

    public var allAccounts: [ProviderKeyAccount] {
        providerGroups.flatMap(\.accounts)
    }

    public var keyPools: [ProviderKeyPoolSnapshot] {
        ProviderKeyStorage.derivedKeyPools(from: self)
    }

    public var quotaPools: [ProviderQuotaPoolSnapshot] {
        ProviderKeyStorage.derivedQuotaPools(from: self)
    }

    public var totalAccounts: Int {
        providerGroups.reduce(0) { $0 + $1.accounts.count }
    }

    public var enabledAccounts: Int {
        providerGroups.reduce(0) { $0 + $1.accounts.filter(\.enabled).count }
    }

    public var healthyAccounts: Int {
        providerGroups.reduce(0) { $0 + $1.accounts.filter { $0.enabled && $0.errorState.status == "healthy" }.count }
    }

    public var readyAccounts: Int {
        keyPools.reduce(0) { $0 + $1.readyAccounts }
    }

    public var cooldownAccounts: Int {
        keyPools.reduce(0) { $0 + $1.cooldownAccounts }
    }

    public var blockedAccounts: Int {
        keyPools.reduce(0) { $0 + $1.blockedAccounts }
    }

    public var disabledPoolAccounts: Int {
        keyPools.reduce(0) { $0 + $1.disabledAccounts }
    }

    public var staleAccounts: Int {
        keyPools.reduce(0) { $0 + $1.staleAccounts }
    }
}

public struct ProviderKeyStoreDerivedSnapshot: Equatable, Sendable {
    public var keyPools: [ProviderKeyPoolSnapshot]
    public var quotaPools: [ProviderQuotaPoolSnapshot]
    public var totalAccounts: Int
    public var enabledAccounts: Int
    public var healthyAccounts: Int
    public var readyAccounts: Int
    public var cooldownAccounts: Int
    public var blockedAccounts: Int
    public var disabledPoolAccounts: Int
    public var staleAccounts: Int

    public init(
        keyPools: [ProviderKeyPoolSnapshot],
        quotaPools: [ProviderQuotaPoolSnapshot],
        totalAccounts: Int,
        enabledAccounts: Int,
        healthyAccounts: Int,
        readyAccounts: Int,
        cooldownAccounts: Int,
        blockedAccounts: Int,
        disabledPoolAccounts: Int,
        staleAccounts: Int
    ) {
        self.keyPools = keyPools
        self.quotaPools = quotaPools
        self.totalAccounts = totalAccounts
        self.enabledAccounts = enabledAccounts
        self.healthyAccounts = healthyAccounts
        self.readyAccounts = readyAccounts
        self.cooldownAccounts = cooldownAccounts
        self.blockedAccounts = blockedAccounts
        self.disabledPoolAccounts = disabledPoolAccounts
        self.staleAccounts = staleAccounts
    }
}

public enum ProviderKeyStorage {
    static let fileName = "hub_provider_keys.json"

    static func url() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    private static func candidateURLs() -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            candidates.append(url)
        }

        if let group = SharedPaths.appGroupDirectory() {
            append(group.appendingPathComponent(fileName))
        }
        for base in SharedPaths.hubDirectoryCandidates() {
            append(base.appendingPathComponent(fileName))
        }

        return candidates
    }

    public static func load() -> ProviderKeyStoreSnapshot {
        for candidate in candidateURLs() {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { continue }
            return parseSnapshot(raw)
        }

        if let legacy = synthesizedLegacySnapshot() {
            return legacy
        }

        return ProviderKeyStoreSnapshot(
            schemaVersion: "",
            updatedAtMs: 0,
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: []
        )
    }

    public static func loadRustRuntimeSnapshotData(_ data: Data) -> ProviderKeyStoreSnapshot? {
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return parseRustRuntimeSnapshot(raw)
    }

    public static func derivedSnapshot(from snapshot: ProviderKeyStoreSnapshot) -> ProviderKeyStoreDerivedSnapshot {
        let keyPools = derivedKeyPools(from: snapshot)
        let quotaPools = derivedQuotaPools(from: snapshot, keyPools: keyPools)
        return ProviderKeyStoreDerivedSnapshot(
            keyPools: keyPools,
            quotaPools: quotaPools,
            totalAccounts: snapshot.totalAccounts,
            enabledAccounts: snapshot.enabledAccounts,
            healthyAccounts: snapshot.healthyAccounts,
            readyAccounts: keyPools.reduce(0) { $0 + $1.readyAccounts },
            cooldownAccounts: keyPools.reduce(0) { $0 + $1.cooldownAccounts },
            blockedAccounts: keyPools.reduce(0) { $0 + $1.blockedAccounts },
            disabledPoolAccounts: keyPools.reduce(0) { $0 + $1.disabledAccounts },
            staleAccounts: keyPools.reduce(0) { $0 + $1.staleAccounts }
        )
    }

    public static func loadResolvedCredential(accountKey: String) -> ProviderKeyResolvedCredential? {
        let target = accountKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        for candidate in candidateURLs() {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { continue }
            guard let providers = raw["providers"] as? [String: Any] else { continue }

            for (providerKey, providerVal) in providers {
                guard let providerObj = providerVal as? [String: Any] else { continue }
                guard let accountsArr = providerObj["accounts"] as? [[String: Any]] else { continue }

                for accountRaw in accountsArr {
                    guard stringValue(accountRaw["account_key"]) == target else { continue }
                    return resolvedCredential(from: accountRaw, providerKey: providerKey)
                }
            }
        }

        return nil
    }

    public static func loadResolvedCredential(
        apiKey: String,
        provider: String? = nil,
        baseURL: String? = nil
    ) -> ProviderKeyResolvedCredential? {
        let targetAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetAPIKey.isEmpty else { return nil }

        let allowedProviders = matchedProviderAliases(for: provider)
        let normalizedBaseHost = hostToken(baseURL)
        var bestMatch: (credential: ProviderKeyResolvedCredential, score: Int)? = nil

        for candidate in candidateURLs() {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { continue }
            guard let providers = raw["providers"] as? [String: Any] else { continue }

            for (providerKey, providerVal) in providers {
                guard let providerObj = providerVal as? [String: Any] else { continue }
                guard let accountsArr = providerObj["accounts"] as? [[String: Any]] else { continue }

                for accountRaw in accountsArr {
                    let credential = resolvedCredential(from: accountRaw, providerKey: providerKey)
                    guard credential.apiKey == targetAPIKey else { continue }

                    var score = 0
                    if !allowedProviders.isEmpty,
                       allowedProviders.contains(normalizedProviderAlias(credential.provider)) {
                        score += 4
                    }
                    if !normalizedBaseHost.isEmpty {
                        if hostToken(credential.baseURL) == normalizedBaseHost {
                            score += 2
                        } else if hostToken(credential.proxyURL) == normalizedBaseHost {
                            score += 1
                        }
                    }
                    if !credential.accountId.isEmpty {
                        score += 1
                    }
                    if credential.authType.lowercased() == "oauth" {
                        score += 1
                    }

                    if let currentBest = bestMatch {
                        if score > currentBest.score {
                            bestMatch = (credential, score)
                        }
                    } else {
                        bestMatch = (credential, score)
                    }
                }
            }
        }

        return bestMatch?.credential
    }

    public static func loadRoutableCredentialPool(
        provider: String,
        poolID: String,
        modelID: String
    ) -> ProviderKeyResolvedCredentialPool? {
        let targetPoolID = stringValue(poolID)
        guard !targetPoolID.isEmpty else { return nil }

        let allowedProviders = matchedProviderAliases(for: provider)
        let targetModel = normalizedModelRoutingToken(modelID)
        let nowMs = currentTimestampMs()
        var foundPool = false
        var resolvedProvider = ""
        var routingStrategy = "fill-first"
        var candidates: [(credential: ProviderKeyResolvedCredential, member: ProviderKeyPoolMemberState)] = []

        for candidate in candidateURLs() {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { continue }
            guard let providers = raw["providers"] as? [String: Any] else { continue }

            for (providerKey, providerVal) in providers.sorted(by: { $0.key < $1.key }) {
                let providerAlias = normalizedProviderAlias(providerKey)
                if !allowedProviders.isEmpty, !allowedProviders.contains(providerAlias) {
                    continue
                }
                guard let providerObj = providerVal as? [String: Any] else { continue }
                let groupRoutingStrategy = stringValue(providerObj["routing_strategy"]).isEmpty
                    ? "fill-first"
                    : stringValue(providerObj["routing_strategy"])
                guard let accountsArr = providerObj["accounts"] as? [[String: Any]] else { continue }

                for accountRaw in accountsArr {
                    guard let account = parseAccount(accountRaw) else { continue }
                    guard normalizedLookupToken(account.poolID) == normalizedLookupToken(targetPoolID) else { continue }
                    foundPool = true
                    resolvedProvider = resolvedProvider.isEmpty ? providerKey : resolvedProvider
                    routingStrategy = groupRoutingStrategy
                    guard accountSupportsModel(account, normalizedTargetModel: targetModel) else { continue }

                    let member = derivedPoolMemberState(for: account, nowMs: nowMs)
                    guard member.isRoutable else { continue }
                    let credential = resolvedCredential(from: accountRaw, providerKey: providerKey)
                    guard credential.enabled,
                          !credential.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continue
                    }
                    candidates.append((credential, member))
                }
            }
        }

        guard foundPool else { return nil }
        let sorted = candidates.sorted(by: sortRoutableCredentialCandidates(_:_:))
        return ProviderKeyResolvedCredentialPool(
            poolID: targetPoolID,
            provider: resolvedProvider.isEmpty ? provider : resolvedProvider,
            routingStrategy: routingStrategy,
            credentials: sorted.map(\.credential)
        )
    }

    static func derivedKeyPools(from snapshot: ProviderKeyStoreSnapshot) -> [ProviderKeyPoolSnapshot] {
        let nowMs = currentTimestampMs()
        var buckets: [String: (group: ProviderKeyProviderGroup, members: [ProviderKeyPoolMemberState])] = [:]

        for group in snapshot.providerGroups {
            for account in group.accounts {
                let poolID = account.poolID.isEmpty
                    ? derivedPoolID(
                        provider: account.provider,
                        providerHost: account.providerHost,
                        wireAPI: account.wireAPI,
                        baseURL: account.baseURL,
                        proxyURL: account.proxyURL,
                        customHeaders: account.customHeaders
                    )
                    : account.poolID
                var bucket = buckets[poolID] ?? (group, [])
                bucket.members.append(derivedPoolMemberState(for: account, nowMs: nowMs))
                buckets[poolID] = bucket
            }
        }

        return buckets
            .map { poolID, bucket in
                let members = bucket.members.sorted(by: sortPoolMembers(_:_:))
                let sampleAccount = members.first?.account
                let provider = sampleAccount?.provider ?? bucket.group.provider
                let providerHost = sampleAccount?.providerHost ?? ""
                let wireAPI = firstNonEmpty(sampleAccount?.wireAPI ?? "", "default")
                let supplier = supplierDescriptor(
                    provider: provider,
                    providerHost: providerHost
                )
                let supportedFamilies = supportedFamilyDescriptors(
                    for: members.map(\.account),
                    provider: provider,
                    providerHost: providerHost
                )
                let totalAccounts = members.count
                let enabledAccounts = members.filter { $0.account.enabled }.count
                let readyAccounts = members.filter { $0.state == "ready" || $0.state == "degraded" }.count
                let degradedAccounts = members.filter { $0.state == "degraded" }.count
                let cooldownAccounts = members.filter { $0.state == "cooldown" }.count
                let blockedAccounts = members.filter { $0.state == "blocked" }.count
                let disabledAccounts = members.filter { $0.state == "disabled" }.count
                let staleAccounts = members.filter { $0.state == "stale" }.count
                let totalDailyTokenCap = members.reduce(Int64(0)) { $0 + max(Int64(0), $1.account.quota.dailyTokenCap) }
                let totalDailyTokensUsed = members.reduce(Int64(0)) { $0 + max(Int64(0), $1.account.quota.dailyTokensUsed) }
                let totalDailyTokensRemaining = members.reduce(Int64(0)) { $0 + max(Int64(0), $1.account.quota.dailyTokensRemaining) }
                let totalTokensUsed = members.reduce(Int64(0)) { $0 + max(Int64(0), $1.account.quota.totalTokensUsed) }
                let earliestRetryAtMs = members
                    .map(\.nextRetryAtMs)
                    .filter { $0 > nowMs }
                    .min() ?? 0
                let lastRefreshAtMs = members
                    .map { max($0.account.lastRefreshAtMs, $0.account.updatedAtMs) }
                    .max() ?? 0
                let hasQuotaData = members.contains {
                    $0.account.quota.dailyTokenCap > 0
                        || $0.account.quota.dailyTokensUsed > 0
                        || $0.account.quota.dailyTokensRemaining > 0
                        || $0.account.quota.totalTokensUsed > 0
                        || !$0.account.quota.usageWindows.isEmpty
                }
                let issue = poolIssueSummary(from: members)

                return ProviderKeyPoolSnapshot(
                    poolID: poolID,
                    supplierKey: supplier.key,
                    supplierDisplayName: supplier.displayName,
                    provider: provider,
                    providerDisplayName: providerDisplayName(
                        provider: provider,
                        providerHost: providerHost
                    ),
                    providerHost: providerHost,
                    wireAPI: wireAPI,
                    routingStrategy: bucket.group.routingStrategy,
                    state: derivedAggregateState(
                        total: totalAccounts,
                        ready: readyAccounts,
                        cooldown: cooldownAccounts,
                        blocked: blockedAccounts,
                        disabled: disabledAccounts,
                        stale: staleAccounts
                    ),
                    members: members,
                    totalAccounts: totalAccounts,
                    enabledAccounts: enabledAccounts,
                    readyAccounts: readyAccounts,
                    degradedAccounts: degradedAccounts,
                    cooldownAccounts: cooldownAccounts,
                    blockedAccounts: blockedAccounts,
                    disabledAccounts: disabledAccounts,
                    staleAccounts: staleAccounts,
                    totalDailyTokenCap: totalDailyTokenCap,
                    totalDailyTokensUsed: totalDailyTokensUsed,
                    totalDailyTokensRemaining: totalDailyTokensRemaining,
                    totalTokensUsed: totalTokensUsed,
                    earliestRetryAtMs: earliestRetryAtMs,
                    lastRefreshAtMs: lastRefreshAtMs,
                    hasQuotaData: hasQuotaData,
                    supportedFamilyKeys: supportedFamilies.map(\.key),
                    supportedFamilyDisplayNames: supportedFamilies.map(\.displayName),
                    issueSummary: issue.summary,
                    issueDetail: issue.detail
                )
            }
            .sorted(by: sortKeyPools(_:_:))
    }

    static func derivedQuotaPools(
        from snapshot: ProviderKeyStoreSnapshot,
        keyPools precomputedKeyPools: [ProviderKeyPoolSnapshot]? = nil
    ) -> [ProviderQuotaPoolSnapshot] {
        let nowMs = currentTimestampMs()
        let keyPools = precomputedKeyPools ?? derivedKeyPools(from: snapshot)
        var buckets: [String: [ProviderQuotaPoolSourceSnapshot]] = [:]

        for pool in keyPools {
            let familyKeys = pool.supportedFamilyKeys.isEmpty ? [pool.supplierKey] : pool.supportedFamilyKeys
            for familyKey in familyKeys {
                guard let source = projectedQuotaPoolSource(pool, familyKey: familyKey) else { continue }
                buckets[familyKey, default: []].append(source)
            }
        }

        return buckets.map { familyKey, sources in
            let sortedSources = sources.sorted(by: sortQuotaPoolSources(_:_:))
            let dedicatedSources = sortedSources.filter { !$0.hasSharedQuotaBoundary }
            let sharedSources = sortedSources.filter(\.hasSharedQuotaBoundary)
            let displayName = sortedSources
                .compactMap { source in
                    zip(source.supportedFamilyKeys, source.supportedFamilyDisplayNames)
                        .first(where: { $0.0 == familyKey })?
                        .1
                }
                .first ?? familyDisplayName(for: familyKey)
            let totalAccounts = sortedSources.reduce(0) { $0 + $1.totalAccounts }
            let readyAccounts = sortedSources.reduce(0) { $0 + $1.readyAccounts }
            let degradedAccounts = sortedSources.reduce(0) { $0 + $1.degradedAccounts }
            let cooldownAccounts = sortedSources.reduce(0) { $0 + $1.cooldownAccounts }
            let blockedAccounts = sortedSources.reduce(0) { $0 + $1.blockedAccounts }
            let disabledAccounts = sortedSources.reduce(0) { $0 + $1.disabledAccounts }
            let staleAccounts = sortedSources.reduce(0) { $0 + $1.staleAccounts }
            let exclusiveDailyTokenCap = dedicatedSources.reduce(Int64(0)) { $0 + $1.totalDailyTokenCap }
            let exclusiveDailyTokensUsed = dedicatedSources.reduce(Int64(0)) { $0 + $1.totalDailyTokensUsed }
            let exclusiveDailyTokensRemaining = dedicatedSources.reduce(Int64(0)) { $0 + $1.totalDailyTokensRemaining }
            let exclusiveTotalTokensUsed = dedicatedSources.reduce(Int64(0)) { $0 + $1.totalTokensUsed }
            let sharedDailyTokenCap = sharedSources.reduce(Int64(0)) { $0 + $1.totalDailyTokenCap }
            let sharedDailyTokensUsed = sharedSources.reduce(Int64(0)) { $0 + $1.totalDailyTokensUsed }
            let sharedDailyTokensRemaining = sharedSources.reduce(Int64(0)) { $0 + $1.totalDailyTokensRemaining }
            let sharedTotalTokensUsed = sharedSources.reduce(Int64(0)) { $0 + $1.totalTokensUsed }
            let earliestRetryAtMs = sortedSources
                .map(\.earliestRetryAtMs)
                .filter { $0 > nowMs }
                .min() ?? 0
            let hasExclusiveQuotaData = dedicatedSources.contains { $0.hasQuotaData }
            let hasSharedQuotaData = sharedSources.contains { $0.hasQuotaData }
            let providerHosts = Array(Set(sortedSources.map(\.providerHost).filter { !$0.isEmpty })).sorted()
            let supplierKeys = Array(Set(sortedSources.map(\.supplierKey))).sorted()
            let supplierDisplayNames = Array(Set(sortedSources.map(\.supplierDisplayName))).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            let sharedWithFamilyDisplayNames = Array(Set(
                sharedSources.flatMap(\.sharedWithFamilyDisplayNames)
            )).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            let issue = quotaPoolIssueSummary(from: sortedSources)

            return ProviderQuotaPoolSnapshot(
                familyKey: familyKey,
                displayName: displayName,
                state: derivedAggregateState(
                    total: totalAccounts,
                    ready: readyAccounts,
                    cooldown: cooldownAccounts,
                    blocked: blockedAccounts,
                    disabled: disabledAccounts,
                    stale: staleAccounts
                ),
                providerHosts: providerHosts,
                supplierKeys: supplierKeys,
                supplierDisplayNames: supplierDisplayNames,
                sources: sortedSources,
                totalSources: sortedSources.count,
                dedicatedSources: dedicatedSources.count,
                sharedSources: sharedSources.count,
                totalAccounts: totalAccounts,
                readyAccounts: readyAccounts,
                degradedAccounts: degradedAccounts,
                cooldownAccounts: cooldownAccounts,
                blockedAccounts: blockedAccounts,
                disabledAccounts: disabledAccounts,
                staleAccounts: staleAccounts,
                exclusiveDailyTokenCap: exclusiveDailyTokenCap,
                exclusiveDailyTokensUsed: exclusiveDailyTokensUsed,
                exclusiveDailyTokensRemaining: exclusiveDailyTokensRemaining,
                exclusiveTotalTokensUsed: exclusiveTotalTokensUsed,
                sharedDailyTokenCap: sharedDailyTokenCap,
                sharedDailyTokensUsed: sharedDailyTokensUsed,
                sharedDailyTokensRemaining: sharedDailyTokensRemaining,
                sharedTotalTokensUsed: sharedTotalTokensUsed,
                earliestRetryAtMs: earliestRetryAtMs,
                hasExclusiveQuotaData: hasExclusiveQuotaData,
                hasSharedQuotaData: hasSharedQuotaData,
                sharedWithFamilyDisplayNames: sharedWithFamilyDisplayNames,
                issueSummary: issue.summary,
                issueDetail: issue.detail
            )
        }
        .sorted { lhs, rhs in
            if lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) != .orderedSame {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.familyKey < rhs.familyKey
        }
    }

    private static func synthesizedLegacySnapshot() -> ProviderKeyStoreSnapshot? {
        let remoteSnapshot = RemoteModelStorage.load()
        let remoteModels = remoteSnapshot.models
        guard !remoteModels.isEmpty else { return nil }

        let healthSnapshot = RemoteKeyHealthStorage.load()
        let healthByKey = Dictionary(uniqueKeysWithValues: healthSnapshot.records.map { ($0.keyReference, $0) })
        let accounts = Dictionary(grouping: remoteModels, by: { RemoteModelStorage.keyReference(for: $0) })
            .compactMap { keyReference, models -> ProviderKeyAccount? in
                synthesizedLegacyAccount(
                    keyReference: keyReference,
                    models: models,
                    health: healthByKey[keyReference],
                    snapshotUpdatedAtMs: Int64((remoteSnapshot.updatedAt * 1000.0).rounded())
                )
            }
            .sorted { lhs, rhs in
                if lhs.provider.localizedCaseInsensitiveCompare(rhs.provider) != .orderedSame {
                    return lhs.provider.localizedCaseInsensitiveCompare(rhs.provider) == .orderedAscending
                }
                if lhs.poolID.localizedCaseInsensitiveCompare(rhs.poolID) != .orderedSame {
                    return lhs.poolID.localizedCaseInsensitiveCompare(rhs.poolID) == .orderedAscending
                }
                return lhs.accountKey.localizedCaseInsensitiveCompare(rhs.accountKey) == .orderedAscending
            }
        guard !accounts.isEmpty else { return nil }

        let providerGroups = Dictionary(grouping: accounts, by: \.provider)
            .map { provider, accounts in
                ProviderKeyProviderGroup(
                    provider: provider,
                    accounts: accounts,
                    routingStrategy: "fill-first"
                )
            }
            .sorted { lhs, rhs in
                lhs.provider.localizedCaseInsensitiveCompare(rhs.provider) == .orderedAscending
            }

        return ProviderKeyStoreSnapshot(
            schemaVersion: "hub_provider_keys.legacy_derived.v1",
            updatedAtMs: max(
                Int64((remoteSnapshot.updatedAt * 1000.0).rounded()),
                Int64((healthSnapshot.updatedAt * 1000.0).rounded())
            ),
            globalRoutingStrategy: "fill-first",
            importSources: [],
            providerGroups: providerGroups
        )
    }

    public static func updateResolvedCredential(
        accountKey: String,
        apiKey: String? = nil,
        refreshToken: String? = nil,
        expiresAtMs: Int64? = nil
    ) -> Bool {
        let target = accountKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }

        for candidate in candidateURLs() {
            guard var raw = readMutableSnapshot(at: candidate),
                  var providers = raw["providers"] as? [String: Any] else {
                continue
            }

            var changed = false
            providerLoop: for (providerKey, providerVal) in providers {
                guard var providerObj = providerVal as? [String: Any],
                      var accountsArr = providerObj["accounts"] as? [[String: Any]] else {
                    continue
                }

                for index in accountsArr.indices {
                    guard stringValue(accountsArr[index]["account_key"]) == target else { continue }
                    if let apiKey {
                        accountsArr[index]["api_key"] = apiKey
                    }
                    if let refreshToken {
                        accountsArr[index]["refresh_token"] = refreshToken
                    }
                    if let expiresAtMs {
                        accountsArr[index]["expires_at_ms"] = expiresAtMs
                    }
                    accountsArr[index]["updated_at_ms"] = currentTimestampMs()
                    providerObj["accounts"] = accountsArr
                    providers[providerKey] = providerObj
                    raw["providers"] = providers
                    raw["updated_at_ms"] = currentTimestampMs()
                    changed = true
                    break providerLoop
                }
            }

            if changed {
                return writeMutableSnapshot(raw, to: candidate)
            }
        }

        return false
    }

    @discardableResult
    public static func syncImportedAccounts(
        _ inputs: [ProviderKeyImportedAccountInput],
        importSource: ProviderKeyImportSource? = nil
    ) -> ProviderKeyImportSyncResult {
        let nowMs = currentTimestampMs()
        let destination = url()
        let sourceKey = normalizedImportSourceKey(importSource)

        guard !inputs.isEmpty || importSource != nil else {
            return ProviderKeyImportSyncResult(
                ok: false,
                importedCount: 0,
                prunedCount: 0,
                errors: ["missing_provider_key_inputs"]
            )
        }

        var raw = readMutableSnapshot(at: destination) ?? emptyMutableSnapshot()
        registerImportSourceIfNeeded(&raw, importSource: importSource, sourceKey: sourceKey, nowMs: nowMs)

        var importedCount = 0
        var errors: [String] = []
        var resolvedAccountKeys: Set<String> = []

        for input in inputs {
            guard let normalizedAccount = normalizedMutableAccount(
                from: input,
                ownerKey: sourceKey,
                nowMs: nowMs
            ) else {
                errors.append("invalid_provider_key_input")
                continue
            }
            let accountKey = stringValue(normalizedAccount["account_key"])
            upsertMutableAccount(normalizedAccount, into: &raw, nowMs: nowMs)
            if !accountKey.isEmpty {
                resolvedAccountKeys.insert(accountKey)
            }
            importedCount += 1
        }

        let prunedCount: Int
        if let sourceKey, errors.isEmpty {
            prunedCount = pruneOwnedAccounts(
                from: &raw,
                ownerKey: sourceKey,
                desiredAccountKeys: resolvedAccountKeys
            )
        } else {
            prunedCount = 0
        }

        if let importSource {
            updateImportSourceStatus(
                &raw,
                importSource: importSource,
                sourceKey: sourceKey,
                state: errors.isEmpty ? "ready" : "sync_failed",
                lastImportedCount: importedCount,
                ownedAccountCount: sourceKey.map { countOwnedAccounts(in: raw, ownerKey: $0) } ?? 0,
                errors: errors,
                nowMs: nowMs
            )
        }

        raw["updated_at_ms"] = nowMs
        let ok = writeMutableSnapshot(raw, to: destination)
        return ProviderKeyImportSyncResult(
            ok: ok && errors.isEmpty,
            importedCount: ok ? importedCount : 0,
            prunedCount: ok ? prunedCount : 0,
            errors: ok ? errors : (errors + ["save_failed"])
        )
    }

    @discardableResult
    public static func recordImportSourceSyncFailure(
        _ importSource: ProviderKeyImportSource,
        errors: [String]
    ) -> Bool {
        let nowMs = currentTimestampMs()
        let destination = url()
        let sourceKey = normalizedImportSourceKey(importSource)
        guard let sourceKey else { return false }

        var raw = readMutableSnapshot(at: destination) ?? emptyMutableSnapshot()
        registerImportSourceIfNeeded(&raw, importSource: importSource, sourceKey: sourceKey, nowMs: nowMs)
        updateImportSourceStatus(
            &raw,
            importSource: importSource,
            sourceKey: sourceKey,
            state: "sync_failed",
            lastImportedCount: 0,
            ownedAccountCount: countOwnedAccounts(in: raw, ownerKey: sourceKey),
            errors: errors.isEmpty ? ["unknown_sync_failure"] : errors,
            nowMs: nowMs
        )
        raw["updated_at_ms"] = nowMs
        return writeMutableSnapshot(raw, to: destination)
    }

    @discardableResult
    public static func removeImportSource(
        _ source: ProviderKeyImportSourceStatus,
        removeOwnedAccounts: Bool
    ) -> ProviderKeyImportSourceRemovalResult {
        removeImportSource(
            sourceKey: source.sourceKey,
            kind: source.kind,
            sourceRef: source.sourceRef,
            removeOwnedAccounts: removeOwnedAccounts
        )
    }

    @discardableResult
    public static func removeImportSource(
        sourceKey rawSourceKey: String,
        kind rawKind: String = "",
        sourceRef rawSourceRef: String = "",
        removeOwnedAccounts: Bool = false
    ) -> ProviderKeyImportSourceRemovalResult {
        let sourceKey = firstNonEmpty(
            stringValue(rawSourceKey),
            normalizedImportSourceKey(
                ProviderKeyImportSource(kind: rawKind, sourceRef: rawSourceRef)
            ) ?? ""
        )
        guard !sourceKey.isEmpty else {
            return ProviderKeyImportSourceRemovalResult(
                ok: false,
                removedSourceCount: 0,
                removedAccountCount: 0,
                detachedAccountCount: 0,
                errors: ["missing_import_source_key"]
            )
        }

        let candidate = candidateURLs().first { url in
            guard let raw = readMutableSnapshot(at: url) else { return false }
            return mutableSnapshotContainsImportSource(raw, sourceKey: sourceKey)
        } ?? url()

        guard var raw = readMutableSnapshot(at: candidate) else {
            return ProviderKeyImportSourceRemovalResult(
                ok: false,
                removedSourceCount: 0,
                removedAccountCount: 0,
                detachedAccountCount: 0,
                errors: ["provider_key_store_missing"]
            )
        }

        guard mutableSnapshotContainsImportSource(raw, sourceKey: sourceKey) else {
            return ProviderKeyImportSourceRemovalResult(
                ok: false,
                removedSourceCount: 0,
                removedAccountCount: 0,
                detachedAccountCount: 0,
                errors: ["import_source_not_found"]
            )
        }

        let nowMs = currentTimestampMs()
        let removedSourceCount = removeImportSourceMetadata(
            from: &raw,
            sourceKey: sourceKey
        )
        let accountRemoval = removeImportSourceOwnership(
            from: &raw,
            ownerKey: sourceKey,
            removeOwnedAccounts: removeOwnedAccounts,
            nowMs: nowMs
        )

        raw["updated_at_ms"] = nowMs
        guard writeMutableSnapshot(raw, to: candidate) else {
            return ProviderKeyImportSourceRemovalResult(
                ok: false,
                removedSourceCount: 0,
                removedAccountCount: 0,
                detachedAccountCount: 0,
                errors: ["save_failed"]
            )
        }

        return ProviderKeyImportSourceRemovalResult(
            ok: true,
            removedSourceCount: removedSourceCount,
            removedAccountCount: accountRemoval.removedCount,
            detachedAccountCount: accountRemoval.detachedCount,
            errors: []
        )
    }

    private static func parseSnapshot(_ raw: [String: Any]) -> ProviderKeyStoreSnapshot {
        let schemaVersion = stringValue(raw["schema_version"])
        let updatedAtMs = int64Value(raw["updated_at_ms"])
        let globalRoutingStrategy = stringValue(raw["routing_strategy"]).isEmpty ? "fill-first" : stringValue(raw["routing_strategy"])

        var groups: [ProviderKeyProviderGroup] = []
        if let providers = raw["providers"] as? [String: Any] {
            for (providerKey, providerVal) in providers.sorted(by: { $0.key < $1.key }) {
                guard let providerObj = providerVal as? [String: Any] else { continue }
                let routingStrategy = stringValue(providerObj["routing_strategy"]).isEmpty ? "fill-first" : stringValue(providerObj["routing_strategy"])
                var accounts: [ProviderKeyAccount] = []
                if let accountsArr = providerObj["accounts"] as? [[String: Any]] {
                    for acctRaw in accountsArr {
                        if let acct = parseAccount(acctRaw) {
                            accounts.append(acct)
                        }
                    }
                }
                groups.append(ProviderKeyProviderGroup(
                    provider: providerKey,
                    accounts: accounts,
                    routingStrategy: routingStrategy
                ))
            }
        }

        let importSources = parseImportSourceStatuses(raw["import_source_statuses"])

        return ProviderKeyStoreSnapshot(
            schemaVersion: schemaVersion,
            updatedAtMs: updatedAtMs,
            globalRoutingStrategy: globalRoutingStrategy,
            importSources: importSources,
            providerGroups: groups
        )
    }

    private static func parseRustRuntimeSnapshot(_ raw: [String: Any]) -> ProviderKeyStoreSnapshot? {
        if raw.keys.contains("ok"), !(raw["ok"] as? Bool ?? false) {
            return nil
        }

        let snapshotRaw = raw["snapshot"] as? [String: Any] ?? raw
        guard let accountsRaw = snapshotRaw["accounts"] as? [[String: Any]] else {
            return nil
        }

        let providerStrategies = rustProviderStrategies(snapshotRaw["providers"])
        var groupedAccounts: [String: [[String: Any]]] = [:]
        for accountRaw in accountsRaw {
            var account = accountRaw
            let provider = stringValue(account["provider"])
            guard !provider.isEmpty else { continue }
            if stringValue(account["api_key"]).isEmpty {
                account["api_key"] = stringValue(account["api_key_redacted"])
            }
            if stringValue(account["auth_type"]).isEmpty {
                account["auth_type"] = "api_key"
            }
            groupedAccounts[provider, default: []].append(account)
        }

        var providers: [String: Any] = [:]
        for (provider, accounts) in groupedAccounts {
            providers[provider] = [
                "routing_strategy": providerStrategies[provider] ?? firstNonEmpty(
                    stringValue(snapshotRaw["global_routing_strategy"]),
                    "fill-first"
                ),
                "accounts": accounts
            ]
        }

        let rawStore: [String: Any] = [
            "schema_version": firstNonEmpty(
                stringValue(snapshotRaw["schema_version"]),
                stringValue(raw["snapshot_schema_version"]),
                "xhub.provider_key_snapshot.v1"
            ),
            "updated_at_ms": snapshotRaw["updated_at_ms"] ?? 0,
            "routing_strategy": firstNonEmpty(
                stringValue(snapshotRaw["global_routing_strategy"]),
                stringValue(snapshotRaw["routing_strategy"]),
                "fill-first"
            ),
            "import_source_statuses": normalizeRustImportSourceStatuses(snapshotRaw["import_source_statuses"]),
            "providers": providers
        ]
        return parseSnapshot(rawStore)
    }

    private static func rustProviderStrategies(_ raw: Any?) -> [String: String] {
        if let providerMap = raw as? [String: Any] {
            var out: [String: String] = [:]
            for (provider, value) in providerMap {
                guard let object = value as? [String: Any] else { continue }
                let strategy = stringValue(object["routing_strategy"])
                if !strategy.isEmpty {
                    out[provider] = strategy
                }
            }
            return out
        }

        guard let providerArray = raw as? [[String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for object in providerArray {
            let provider = stringValue(object["provider"])
            let strategy = stringValue(object["routing_strategy"])
            if !provider.isEmpty, !strategy.isEmpty {
                out[provider] = strategy
            }
        }
        return out
    }

    private static func normalizeRustImportSourceStatuses(_ raw: Any?) -> [String: Any] {
        if let sourceMap = raw as? [String: Any] {
            return sourceMap
        }
        guard let sourceArray = raw as? [[String: Any]] else { return [:] }

        var out: [String: Any] = [:]
        for source in sourceArray {
            let sourceKey = firstNonEmpty(
                stringValue(source["source_key"]),
                "\(stringValue(source["kind"])):\(stringValue(source["source_ref"]))"
            )
            guard !sourceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            out[sourceKey] = source
        }
        return out
    }

    private static func parseImportSourceStatuses(_ raw: Any?) -> [ProviderKeyImportSourceStatus] {
        guard let sourceMap = raw as? [String: Any] else { return [] }
        return sourceMap
            .sorted { $0.key < $1.key }
            .compactMap { sourceKey, sourceVal in
                guard let sourceObj = sourceVal as? [String: Any] else { return nil }
                let inferred = parseImportSourceKey(sourceKey)
                let kind = firstNonEmpty(stringValue(sourceObj["kind"]), inferred?.kind ?? "")
                let sourceRef = firstNonEmpty(stringValue(sourceObj["source_ref"]), inferred?.sourceRef ?? "")
                guard !kind.isEmpty, !sourceRef.isEmpty else { return nil }
                let lastErrors = stringArrayValue(sourceObj["last_errors"])
                return ProviderKeyImportSourceStatus(
                    sourceKey: sourceKey,
                    kind: kind,
                    sourceRef: sourceRef,
                    state: stringValue(sourceObj["state"]).isEmpty ? "pending" : stringValue(sourceObj["state"]),
                    lastSyncAtMs: int64Value(sourceObj["last_sync_at_ms"]),
                    lastImportedCount: intValue(sourceObj["last_imported_count"]),
                    ownedAccountCount: intValue(sourceObj["owned_account_count"]),
                    lastErrorCount: max(intValue(sourceObj["last_error_count"]), lastErrors.count),
                    lastErrors: lastErrors,
                    updatedAtMs: int64Value(sourceObj["updated_at_ms"])
                )
            }
    }

    private static func parseAccount(_ raw: [String: Any]) -> ProviderKeyAccount? {
        let provider = stringValue(raw["provider"])
        if provider.isEmpty { return nil }

        let apiKey = stringValue(raw["api_key"])
        let refreshToken = stringValue(raw["refresh_token"])
        let authType = stringValue(raw["auth_type"]).isEmpty ? "api_key" : stringValue(raw["auth_type"])
        let baseURL = stringValue(raw["base_url"])
        let proxyURL = stringValue(raw["proxy_url"])

        if authType == "api_key" && apiKey.isEmpty { return nil }
        if authType == "oauth" && apiKey.isEmpty && refreshToken.isEmpty { return nil }

        let accountKey = stringValue(raw["account_key"])
        if accountKey.isEmpty { return nil }

        let quotaRaw = raw["quota"] as? [String: Any] ?? [:]
        let errorRaw = raw["error_state"] as? [String: Any] ?? [:]
        let refreshRaw = raw["refresh_state"] as? [String: Any] ?? [:]
        let customHeaders: [String: String]
        if let ch = raw["custom_headers"] as? [String: String] {
            customHeaders = ch
        } else {
            customHeaders = [:]
        }
        let wireAPI = normalizedWireAPI(stringValue(raw["wire_api"]))
        let providerHost = firstNonEmpty(
            stringValue(raw["provider_host"]),
            derivedProviderHost(
                provider: provider,
                baseURL: baseURL,
                proxyURL: proxyURL
            )
        )
        let poolID = firstNonEmpty(
            stringValue(raw["pool_id"]),
            derivedPoolID(
                provider: provider,
                providerHost: providerHost,
                wireAPI: wireAPI,
                baseURL: baseURL,
                proxyURL: proxyURL,
                customHeaders: customHeaders
            )
        )
        let nextRetryAtMs = resolvedNextRetryAtMs(raw: raw, quotaRaw: quotaRaw, errorRaw: errorRaw)
        let retryAtSource = resolvedRetryAtSource(raw: raw, quotaRaw: quotaRaw, errorRaw: errorRaw)

        let models: [String]
        if let m = raw["models"] as? [String] {
            models = m
        } else {
            models = []
        }

        return ProviderKeyAccount(
            accountKey: accountKey,
            provider: provider,
            poolID: poolID,
            providerHost: providerHost,
            email: stringValue(raw["email"]),
            apiKeyRedacted: redactApiKey(apiKey),
            baseURL: baseURL,
            proxyURL: proxyURL,
            enabled: raw["enabled"] as? Bool ?? true,
            authType: authType,
            wireAPI: wireAPI,
            expiresAtMs: int64Value(raw["expires_at_ms"]),
            tier: stringValue(raw["tier"]),
            customHeaders: customHeaders,
            models: models,
            notes: stringValue(raw["notes"]),
            priority: intValue(raw["priority"]),
            accountId: stringValue(raw["account_id"]),
            sourceType: stringValue(raw["source_type"]),
            sourceRef: stringValue(raw["source_ref"]),
            oauthSourceKey: stringValue(raw["oauth_source_key"]),
            authIndex: intValue(raw["auth_index"]),
            runtimeAuthIndex: stringValue(raw["runtime_auth_index"]),
            createdAtMs: int64Value(raw["created_at_ms"]),
            updatedAtMs: int64Value(raw["updated_at_ms"]),
            lastRefreshAtMs: int64Value(raw["last_refresh_at_ms"]),
            quota: ProviderKeyQuota(
                dailyTokenCap: int64Value(quotaRaw["daily_token_cap"]),
                dailyTokensUsed: int64Value(quotaRaw["daily_tokens_used"]),
                dailyTokensRemaining: int64Value(quotaRaw["daily_tokens_remaining"]),
                totalTokensUsed: int64Value(quotaRaw["total_tokens_used"]),
                lastUsedAtMs: int64Value(quotaRaw["last_used_at_ms"]),
                lastErrorAtMs: int64Value(quotaRaw["last_error_at_ms"]),
                consecutiveErrors: intValue(quotaRaw["consecutive_errors"]),
                cooldownUntilMs: int64Value(quotaRaw["cooldown_until_ms"]),
                reason: stringValue(quotaRaw["reason"]),
                nextRecoverAtMs: int64Value(quotaRaw["next_recover_at_ms"]),
                usageWindows: parseQuotaUsageWindows(quotaRaw["usage_windows"])
            ),
            errorState: ProviderKeyErrorState(
                status: stringValue(errorRaw["status"]).isEmpty ? "healthy" : stringValue(errorRaw["status"]),
                statusMessage: firstNonEmpty(
                    stringValue(errorRaw["status_message"]),
                    stringValue(raw["status_message"])
                ),
                detailMessage: firstNonEmpty(
                    stringValue(errorRaw["detail_message"]),
                    stringValue(raw["detail_message"])
                ),
                reasonCode: firstNonEmpty(
                    stringValue(errorRaw["reason_code"]),
                    stringValue(raw["reason_code"]),
                    stringValue(errorRaw["last_error_code"])
                ),
                lastErrorCode: stringValue(errorRaw["last_error_code"]),
                lastErrorAtMs: int64Value(errorRaw["last_error_at_ms"]),
                nextRetryAtMs: nextRetryAtMs,
                retryAtText: firstNonEmpty(
                    stringValue(errorRaw["retry_at_text"]),
                    stringValue(raw["retry_at_text"])
                ),
                retryAtSource: retryAtSource,
                autoDisabled: errorRaw["auto_disabled"] as? Bool ?? false
            ),
            refreshState: ProviderKeyRefreshState(
                status: firstNonEmpty(stringValue(refreshRaw["status"]), "idle"),
                lastAttemptAtMs: int64Value(refreshRaw["last_attempt_at_ms"]),
                lastSuccessAtMs: int64Value(refreshRaw["last_success_at_ms"]),
                nextRefreshAtMs: int64Value(refreshRaw["next_refresh_at_ms"]),
                failureCount: intValue(refreshRaw["failure_count"]),
                lastErrorCode: stringValue(refreshRaw["last_error_code"]),
                lastErrorMessage: stringValue(refreshRaw["last_error_message"])
            )
        )
    }

    private static func redactApiKey(_ key: String) -> String {
        let s = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count <= 8 { return "****" }
        return String(s.prefix(4)) + "..." + String(s.suffix(4))
    }

    private static func resolvedCredential(
        from raw: [String: Any],
        providerKey: String
    ) -> ProviderKeyResolvedCredential {
        let quotaRaw = raw["quota"] as? [String: Any] ?? [:]
        let errorRaw = raw["error_state"] as? [String: Any] ?? [:]
        let refreshRaw = raw["refresh_state"] as? [String: Any] ?? [:]
        let provider = stringValue(raw["provider"]).isEmpty ? providerKey : stringValue(raw["provider"])
        let baseURL = stringValue(raw["base_url"])
        let proxyURL = stringValue(raw["proxy_url"])
        let customHeaders: [String: String]
        if let rawHeaders = raw["custom_headers"] as? [String: String] {
            customHeaders = rawHeaders
        } else {
            customHeaders = [:]
        }
        let wireAPI = normalizedWireAPI(stringValue(raw["wire_api"]))
        let providerHost = firstNonEmpty(
            stringValue(raw["provider_host"]),
            derivedProviderHost(
                provider: provider,
                baseURL: baseURL,
                proxyURL: proxyURL
            )
        )
        let poolID = firstNonEmpty(
            stringValue(raw["pool_id"]),
            derivedPoolID(
                provider: provider,
                providerHost: providerHost,
                wireAPI: wireAPI,
                baseURL: baseURL,
                proxyURL: proxyURL,
                customHeaders: customHeaders
            )
        )

        let models: [String]
        if let rawModels = raw["models"] as? [String] {
            models = rawModels
        } else {
            models = []
        }

        return ProviderKeyResolvedCredential(
            accountKey: stringValue(raw["account_key"]),
            provider: provider,
            poolID: poolID,
            providerHost: providerHost,
            apiKey: stringValue(raw["api_key"]),
            refreshToken: stringValue(raw["refresh_token"]),
            baseURL: baseURL,
            proxyURL: proxyURL,
            enabled: raw["enabled"] as? Bool ?? true,
            authType: stringValue(raw["auth_type"]).isEmpty ? "api_key" : stringValue(raw["auth_type"]),
            wireAPI: wireAPI,
            expiresAtMs: int64Value(raw["expires_at_ms"]),
            customHeaders: customHeaders,
            models: models,
            accountId: stringValue(raw["account_id"]),
            oauthSourceKey: stringValue(raw["oauth_source_key"]),
            authIndex: intValue(raw["auth_index"]),
            runtimeAuthIndex: stringValue(raw["runtime_auth_index"]),
            sourceType: stringValue(raw["source_type"]),
            sourceRef: stringValue(raw["source_ref"]),
            statusMessage: firstNonEmpty(
                stringValue(errorRaw["status_message"]),
                stringValue(raw["status_message"])
            ),
            reasonCode: firstNonEmpty(
                stringValue(errorRaw["reason_code"]),
                stringValue(raw["reason_code"]),
                stringValue(errorRaw["last_error_code"])
            ),
            lastRefreshAtMs: int64Value(raw["last_refresh_at_ms"]),
            refreshState: ProviderKeyRefreshState(
                status: firstNonEmpty(stringValue(refreshRaw["status"]), "idle"),
                lastAttemptAtMs: int64Value(refreshRaw["last_attempt_at_ms"]),
                lastSuccessAtMs: int64Value(refreshRaw["last_success_at_ms"]),
                nextRefreshAtMs: int64Value(refreshRaw["next_refresh_at_ms"]),
                failureCount: intValue(refreshRaw["failure_count"]),
                lastErrorCode: stringValue(refreshRaw["last_error_code"]),
                lastErrorMessage: stringValue(refreshRaw["last_error_message"])
            ),
            nextRetryAtMs: resolvedNextRetryAtMs(raw: raw, quotaRaw: quotaRaw, errorRaw: errorRaw),
            retryAtSource: resolvedRetryAtSource(raw: raw, quotaRaw: quotaRaw, errorRaw: errorRaw)
        )
    }

    private static func matchedProviderAliases(for rawProvider: String?) -> Set<String> {
        let normalized = normalizedProviderAlias(rawProvider)
        guard !normalized.isEmpty else { return [] }

        switch normalized {
        case "openai", "openai_compatible", "remote_catalog", "codex":
            return ["openai", "openai_compatible", "remote_catalog", "codex"]
        case "anthropic", "claude":
            return ["anthropic", "claude"]
        default:
            return [normalized]
        }
    }

    private static func normalizedProviderAlias(_ rawProvider: String?) -> String {
        let normalized = stringValue(rawProvider).lowercased()
        if normalized == "chatgpt" || normalized == "openai-chatgpt" {
            return "codex"
        }
        let canonical = RemoteProviderEndpoints.canonicalBackend(normalized)
        if !canonical.isEmpty {
            return canonical
        }
        return normalized
    }

    private static func normalizedLookupToken(_ raw: String?) -> String {
        stringValue(raw).lowercased()
    }

    private static func normalizedModelRoutingToken(_ raw: String) -> String {
        let stripped = RemoteProviderEndpoints.stripModelRef(raw)
        return RemoteProviderEndpoints.normalizedOpenAIModelID(stripped)
    }

    private static func accountSupportsModel(
        _ account: ProviderKeyAccount,
        normalizedTargetModel: String
    ) -> Bool {
        guard !normalizedTargetModel.isEmpty else { return true }
        let models = account.models.map(normalizedModelRoutingToken(_:))
        guard !models.isEmpty else { return true }
        return models.contains(normalizedTargetModel)
    }

    private static func sortRoutableCredentialCandidates(
        _ lhs: (credential: ProviderKeyResolvedCredential, member: ProviderKeyPoolMemberState),
        _ rhs: (credential: ProviderKeyResolvedCredential, member: ProviderKeyPoolMemberState)
    ) -> Bool {
        let lhsStateRank = lhs.member.state == "ready" ? 0 : 1
        let rhsStateRank = rhs.member.state == "ready" ? 0 : 1
        if lhsStateRank != rhsStateRank {
            return lhsStateRank < rhsStateRank
        }
        if lhs.member.account.priority != rhs.member.account.priority {
            return lhs.member.account.priority > rhs.member.account.priority
        }
        return lhs.credential.accountKey.localizedCaseInsensitiveCompare(rhs.credential.accountKey) == .orderedAscending
    }

    private static func canonicalPoolProvider(_ rawProvider: String?) -> String {
        switch normalizedProviderAlias(rawProvider) {
        case "codex", "openai":
            return "openai"
        case "anthropic", "claude":
            return "claude"
        case "google", "gemini":
            return "gemini"
        default:
            return normalizedProviderAlias(rawProvider)
        }
    }

    private static func hostToken(_ rawURL: String?) -> String {
        let value = stringValue(rawURL)
        guard !value.isEmpty,
              let components = URLComponents(string: value),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty else {
            return ""
        }
        return host
    }

    private static func normalizedOriginScope(_ rawURL: String?) -> String {
        let value = stringValue(rawURL)
        guard !value.isEmpty,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !scheme.isEmpty,
              !host.isEmpty else {
            return ""
        }

        let portText: String
        if let port = components.port, port > 0 {
            portText = ":\(port)"
        } else {
            portText = ""
        }

        let path = stringValue(components.path).replacingOccurrences(
            of: "/+$",
            with: "",
            options: .regularExpression
        ).lowercased()
        return "\(scheme)://\(host)\(portText)\(path)"
    }

    private static func emptyMutableSnapshot() -> [String: Any] {
        [
            "schema_version": "hub_provider_keys.v1",
            "updated_at_ms": 0,
            "routing_strategy": "fill-first",
            "import_sources": [],
            "import_source_statuses": [:],
            "providers": [:]
        ]
    }

    private static func normalizedImportSourceKey(_ importSource: ProviderKeyImportSource?) -> String? {
        guard let importSource else { return nil }
        let kind = stringValue(importSource.kind).lowercased()
        let sourceRef = standardizedSourceReference(importSource.sourceRef)
        guard (kind == "auth_dir" || kind == "config_path" || kind == "cliproxy_oauth"),
              !sourceRef.isEmpty else {
            return nil
        }
        return "\(kind):\(sourceRef)"
    }

    private static func standardizedSourceReference(_ rawValue: String?) -> String {
        let value = stringValue(rawValue)
        guard !value.isEmpty else { return "" }
        if let normalizedURL = normalizedHTTPURLString(value) {
            return normalizedURL
        }
        return standardizedPath(value)
    }

    private static func standardizedPath(_ rawPath: String?) -> String {
        let value = stringValue(rawPath)
        guard !value.isEmpty else { return "" }
        return URL(fileURLWithPath: value).standardizedFileURL.path
    }

    private static func normalizedHTTPURLString(_ rawValue: String) -> String? {
        guard var components = URLComponents(string: rawValue),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty else {
            return nil
        }

        components.scheme = scheme
        components.host = host
        components.user = nil
        components.password = nil
        components.fragment = nil

        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443) {
            components.port = nil
        }

        var path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
        if path == "/" {
            path = ""
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path

        return components.string?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedStoreProvider(_ rawProvider: String) -> String {
        switch normalizedProviderAlias(rawProvider) {
        case "codex":
            return "codex"
        case "openai", "openai_compatible", "remote_catalog":
            return "openai"
        case "anthropic", "claude":
            return "claude"
        case "gemini", "google":
            return "gemini"
        case "qwen":
            return "qwen"
        case "iflow":
            return "iflow"
        case "kimi":
            return "kimi"
        case "kiro":
            return "kiro"
        case "copilot":
            return "copilot"
        case "antigravity":
            return "antigravity"
        case "custom":
            return "custom"
        default:
            return stringValue(rawProvider).isEmpty ? "" : "custom"
        }
    }

    private static func normalizedAuthType(_ rawAuthType: String) -> String {
        stringValue(rawAuthType).lowercased() == "oauth" ? "oauth" : "api_key"
    }

    private static func normalizedCustomHeadersMap(_ rawHeaders: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in rawHeaders {
            let normalizedKey = stringValue(key).lowercased()
            let normalizedValue = stringValue(value)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { continue }
            out[normalizedKey] = normalizedValue
        }
        return out
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for value in values {
            let normalized = stringValue(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            out.append(normalized)
        }
        return out.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private static func buildManualAccountKey(
        provider: String,
        email: String,
        apiKey: String
    ) -> String {
        let digest = SHA256.hash(data: Data("\(provider):\(email):\(apiKey)".utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(12)
        return "\(provider):\(hash)"
    }

    private static func buildImportedFileAccountKey(
        provider: String,
        sourceRef: String,
        oauthSourceKey: String,
        accountID: String,
        email: String,
        authIndex: Int,
        runtimeAuthIndex: String
    ) -> String {
        let identity: String
        if !accountID.isEmpty {
            identity = "\(oauthSourceKey.isEmpty ? provider : oauthSourceKey):\(accountID):\(identityToken(authIndex: authIndex, runtimeAuthIndex: runtimeAuthIndex))"
        } else if !email.isEmpty {
            identity = "\(oauthSourceKey.isEmpty ? provider : oauthSourceKey):\(email):\(identityToken(authIndex: authIndex, runtimeAuthIndex: runtimeAuthIndex))"
        } else {
            identity = sourceRef
        }
        let digest = SHA256.hash(data: Data("\(provider):\(identity)".utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return "\(provider):\(hash)"
    }

    private static func identityToken(authIndex: Int, runtimeAuthIndex: String) -> String {
        if authIndex > 0 {
            return "\(authIndex)"
        }
        let runtimeToken = stringValue(runtimeAuthIndex)
        if !runtimeToken.isEmpty {
            return runtimeToken
        }
        return "0"
    }

    private static func normalizedMutableAccount(
        from input: ProviderKeyImportedAccountInput,
        ownerKey: String?,
        nowMs: Int64
    ) -> [String: Any]? {
        let provider = normalizedStoreProvider(input.provider)
        guard !provider.isEmpty else { return nil }

        let authType = normalizedAuthType(input.authType)
        let apiKey = stringValue(input.apiKey)
        let refreshToken = stringValue(input.refreshToken)
        if authType == "api_key" && apiKey.isEmpty {
            return nil
        }
        if authType == "oauth" && apiKey.isEmpty && refreshToken.isEmpty {
            return nil
        }

        let email = stringValue(input.email)
        let baseURL = stringValue(input.baseURL)
        let proxyURL = stringValue(input.proxyURL)
        let wireAPI = normalizedWireAPI(stringValue(input.wireAPI))
        let providerHost = firstNonEmpty(
            hostToken(baseURL),
            hostToken(proxyURL),
            defaultProviderHost(provider)
        )
        let customHeaders = normalizedCustomHeadersMap(input.customHeaders)
        let sourceRef = standardizedPath(input.sourceRef)
        let sourceType = stringValue(input.sourceType)
        let oauthSourceKey = stringValue(input.oauthSourceKey)
        let accountID = stringValue(input.accountID)
        let authIndex = max(0, input.authIndex)
        let runtimeAuthIndex = stringValue(input.runtimeAuthIndex)
        let runtimeStatus = stringValue(input.runtimeStatus).lowercased()
        let statusMessage = stringValue(input.statusMessage)
        let reasonCode = resolvedImportedReasonCode(
            explicit: stringValue(input.reasonCode),
            runtimeStatus: runtimeStatus,
            quotaReason: stringValue(input.quotaReason)
        )
        let nextRetryAtMs = max(Int64(0), input.nextRetryAtMs)
        let lastRefreshAtMs = max(Int64(0), input.lastRefreshAtMs)
        let nextRefreshAtMs = max(Int64(0), input.nextRefreshAtMs)
        let quotaReason = stringValue(input.quotaReason)
        let quotaNextRecoverAtMs = max(Int64(0), input.quotaNextRecoverAtMs)
        let cooldownUntilMs = max(nextRetryAtMs, quotaNextRecoverAtMs)
        let retryAtSource = quotaNextRecoverAtMs > 0 ? "quota" : (nextRetryAtMs > 0 ? "scheduler" : "")
        let errorStatus = importedErrorStatus(
            enabled: input.enabled,
            runtimeStatus: runtimeStatus,
            nextRetryAtMs: nextRetryAtMs,
            cooldownUntilMs: cooldownUntilMs
        )
        let refreshStatus = normalizedImportedRefreshStatus(
            stringValue(input.refreshStatus),
            runtimeStatus: runtimeStatus,
            nextRefreshAtMs: nextRefreshAtMs
        )
        let models = uniqueStrings(input.models)
        let notes = stringValue(input.notes)
        let sourceOwners = uniqueStrings(
            input.sourceOwners + (ownerKey.map { [$0] } ?? [])
        )
        let accountKey: String
        if sourceType == "auth_file", !sourceRef.isEmpty {
            accountKey = buildImportedFileAccountKey(
                provider: provider,
                sourceRef: sourceRef,
                oauthSourceKey: oauthSourceKey,
                accountID: accountID,
                email: email,
                authIndex: authIndex,
                runtimeAuthIndex: runtimeAuthIndex
            )
        } else {
            accountKey = buildManualAccountKey(
                provider: provider,
                email: email,
                apiKey: apiKey
            )
        }

        return [
            "account_key": accountKey,
            "provider": provider,
            "pool_id": derivedPoolID(
                provider: provider,
                providerHost: providerHost,
                wireAPI: wireAPI,
                baseURL: baseURL,
                proxyURL: proxyURL,
                customHeaders: customHeaders
            ),
            "provider_host": providerHost,
            "email": email,
            "api_key": apiKey,
            "refresh_token": refreshToken,
            "base_url": baseURL,
            "proxy_url": proxyURL,
            "enabled": input.enabled,
            "auth_type": authType,
            "wire_api": wireAPI,
            "expires_at_ms": max(Int64(0), input.expiresAtMs),
            "tier": stringValue(input.tier),
            "custom_headers": customHeaders,
            "models": models,
            "notes": notes,
            "priority": max(0, input.priority),
            "account_id": accountID,
            "source_type": sourceType,
            "source_ref": sourceRef,
            "oauth_source_key": oauthSourceKey,
            "auth_index": authIndex,
            "runtime_auth_index": runtimeAuthIndex,
            "source_owners": sourceOwners,
            "created_at_ms": nowMs,
            "updated_at_ms": nowMs,
            "last_refresh_at_ms": lastRefreshAtMs,
            "status_message": statusMessage,
            "reason_code": reasonCode,
            "next_retry_at_ms": nextRetryAtMs,
            "retry_at_source": retryAtSource,
            "quota": [
                "daily_token_cap": 0,
                "daily_tokens_used": 0,
                "daily_tokens_remaining": 0,
                "total_tokens_used": 0,
                "last_used_at_ms": 0,
                "last_error_at_ms": 0,
                "consecutive_errors": 0,
                "cooldown_until_ms": cooldownUntilMs,
                "reason": quotaReason,
                "next_recover_at_ms": quotaNextRecoverAtMs
            ],
            "error_state": [
                "status": errorStatus,
                "status_message": statusMessage,
                "detail_message": quotaReason == statusMessage ? "" : quotaReason,
                "reason_code": reasonCode,
                "last_error_code": "",
                "last_error_at_ms": 0,
                "next_retry_at_ms": nextRetryAtMs,
                "retry_at_text": "",
                "retry_at_source": retryAtSource,
                "auto_disabled": false
            ],
            "refresh_state": [
                "status": refreshStatus,
                "last_attempt_at_ms": lastRefreshAtMs,
                "last_success_at_ms": lastRefreshAtMs,
                "next_refresh_at_ms": nextRefreshAtMs,
                "failure_count": 0,
                "last_error_code": "",
                "last_error_message": ""
            ]
        ]
    }

    private static func registerImportSourceIfNeeded(
        _ raw: inout [String: Any],
        importSource: ProviderKeyImportSource?,
        sourceKey: String?,
        nowMs: Int64
    ) {
        guard let importSource, let sourceKey else { return }
        let existingSources = stringArrayValue(raw["import_sources"])
        raw["import_sources"] = uniqueStrings(existingSources + [sourceKey])

        var statuses = raw["import_source_statuses"] as? [String: Any] ?? [:]
        if statuses[sourceKey] == nil {
            statuses[sourceKey] = [
                "kind": stringValue(importSource.kind).lowercased(),
                "source_ref": standardizedSourceReference(importSource.sourceRef),
                "state": "pending",
                "last_sync_at_ms": 0,
                "last_imported_count": 0,
                "owned_account_count": 0,
                "last_error_count": 0,
                "last_errors": [],
                "updated_at_ms": nowMs
            ]
        }
        raw["import_source_statuses"] = statuses
    }

    private static func upsertMutableAccount(
        _ account: [String: Any],
        into raw: inout [String: Any],
        nowMs: Int64
    ) {
        let provider = stringValue(account["provider"])
        guard !provider.isEmpty else { return }

        var providers = raw["providers"] as? [String: Any] ?? [:]
        var providerObject = providers[provider] as? [String: Any] ?? [
            "accounts": [],
            "routing_strategy": "fill-first"
        ]
        var accounts = providerObject["accounts"] as? [[String: Any]] ?? []

        if let index = accounts.firstIndex(where: { mutableAccountsMatch($0, account) }) {
            var existing = accounts[index]
            existing["email"] = stringValue(account["email"])
            existing["api_key"] = stringValue(account["api_key"])
            existing["refresh_token"] = stringValue(account["refresh_token"])
            existing["base_url"] = stringValue(account["base_url"])
            existing["proxy_url"] = stringValue(account["proxy_url"])
            existing["enabled"] = account["enabled"] as? Bool ?? true
            existing["auth_type"] = stringValue(account["auth_type"])
            existing["wire_api"] = stringValue(account["wire_api"])
            existing["provider_host"] = stringValue(account["provider_host"])
            existing["pool_id"] = stringValue(account["pool_id"])
            existing["expires_at_ms"] = int64Value(account["expires_at_ms"])
            existing["tier"] = stringValue(account["tier"])
            existing["custom_headers"] = account["custom_headers"] as? [String: String] ?? [:]
            existing["models"] = uniqueStrings(
                stringArrayValue(existing["models"]) + stringArrayValue(account["models"])
            )
            let incomingNotes = stringValue(account["notes"])
            if !incomingNotes.isEmpty {
                existing["notes"] = incomingNotes
            }
            existing["priority"] = intValue(account["priority"])
            let incomingAccountID = stringValue(account["account_id"])
            if !incomingAccountID.isEmpty {
                existing["account_id"] = incomingAccountID
            }
            let incomingSourceType = stringValue(account["source_type"])
            if !incomingSourceType.isEmpty {
                existing["source_type"] = incomingSourceType
            }
            let incomingSourceRef = stringValue(account["source_ref"])
            if !incomingSourceRef.isEmpty {
                existing["source_ref"] = incomingSourceRef
            }
            let incomingOAuthSourceKey = stringValue(account["oauth_source_key"])
            if !incomingOAuthSourceKey.isEmpty {
                existing["oauth_source_key"] = incomingOAuthSourceKey
            }
            existing["auth_index"] = intValue(account["auth_index"])
            existing["runtime_auth_index"] = stringValue(account["runtime_auth_index"])
            existing["source_owners"] = uniqueStrings(
                stringArrayValue(existing["source_owners"]) + stringArrayValue(account["source_owners"])
            )
            existing["last_refresh_at_ms"] = int64Value(account["last_refresh_at_ms"])
            existing["status_message"] = stringValue(account["status_message"])
            existing["reason_code"] = stringValue(account["reason_code"])
            existing["next_retry_at_ms"] = int64Value(account["next_retry_at_ms"])
            existing["retry_at_source"] = stringValue(account["retry_at_source"])

            var existingQuota = existing["quota"] as? [String: Any] ?? [:]
            let incomingQuota = account["quota"] as? [String: Any] ?? [:]
            existingQuota["cooldown_until_ms"] = int64Value(incomingQuota["cooldown_until_ms"])
            existingQuota["reason"] = stringValue(incomingQuota["reason"])
            existingQuota["next_recover_at_ms"] = int64Value(incomingQuota["next_recover_at_ms"])
            existing["quota"] = existingQuota

            var existingErrorState = existing["error_state"] as? [String: Any] ?? [:]
            let incomingErrorState = account["error_state"] as? [String: Any] ?? [:]
            existingErrorState["status"] = firstNonEmpty(
                stringValue(incomingErrorState["status"]),
                stringValue(existingErrorState["status"]),
                "healthy"
            )
            existingErrorState["status_message"] = stringValue(incomingErrorState["status_message"])
            existingErrorState["detail_message"] = stringValue(incomingErrorState["detail_message"])
            existingErrorState["reason_code"] = stringValue(incomingErrorState["reason_code"])
            existingErrorState["next_retry_at_ms"] = int64Value(incomingErrorState["next_retry_at_ms"])
            existingErrorState["retry_at_source"] = stringValue(incomingErrorState["retry_at_source"])
            existing["error_state"] = existingErrorState

            var existingRefreshState = existing["refresh_state"] as? [String: Any] ?? [:]
            let incomingRefreshState = account["refresh_state"] as? [String: Any] ?? [:]
            existingRefreshState["status"] = firstNonEmpty(
                stringValue(incomingRefreshState["status"]),
                stringValue(existingRefreshState["status"]),
                "idle"
            )
            existingRefreshState["last_attempt_at_ms"] = int64Value(incomingRefreshState["last_attempt_at_ms"])
            existingRefreshState["last_success_at_ms"] = int64Value(incomingRefreshState["last_success_at_ms"])
            existingRefreshState["next_refresh_at_ms"] = int64Value(incomingRefreshState["next_refresh_at_ms"])
            existing["refresh_state"] = existingRefreshState
            existing["updated_at_ms"] = nowMs
            if int64Value(existing["created_at_ms"]) == 0 {
                existing["created_at_ms"] = nowMs
            }
            accounts[index] = existing
        } else {
            accounts.append(account)
        }

        providerObject["accounts"] = accounts
        providers[provider] = providerObject
        raw["providers"] = providers
    }

    private static func mutableAccountsMatch(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        let lhsAccountKey = stringValue(lhs["account_key"])
        let rhsAccountKey = stringValue(rhs["account_key"])
        if !lhsAccountKey.isEmpty, lhsAccountKey == rhsAccountKey {
            return true
        }

        let lhsSourceType = stringValue(lhs["source_type"])
        let rhsSourceType = stringValue(rhs["source_type"])
        let lhsSourceRef = stringValue(lhs["source_ref"])
        let rhsSourceRef = stringValue(rhs["source_ref"])
        if lhsSourceType == "auth_file",
           rhsSourceType == "auth_file",
           !lhsSourceRef.isEmpty,
           lhsSourceRef == rhsSourceRef {
            return true
        }

        let lhsAPIKey = stringValue(lhs["api_key"])
        let rhsAPIKey = stringValue(rhs["api_key"])
        return !lhsAPIKey.isEmpty && lhsAPIKey == rhsAPIKey
    }

    private static func pruneOwnedAccounts(
        from raw: inout [String: Any],
        ownerKey: String,
        desiredAccountKeys: Set<String>
    ) -> Int {
        var providers = raw["providers"] as? [String: Any] ?? [:]
        var removedCount = 0

        for (providerKey, providerValue) in providers {
            guard var providerObject = providerValue as? [String: Any],
                  let accountRows = providerObject["accounts"] as? [[String: Any]] else {
                continue
            }

            var nextRows: [[String: Any]] = []
            for var row in accountRows {
                let owners = uniqueStrings(stringArrayValue(row["source_owners"]))
                guard owners.contains(ownerKey) else {
                    nextRows.append(row)
                    continue
                }

                let accountKey = stringValue(row["account_key"])
                if desiredAccountKeys.contains(accountKey) {
                    row["source_owners"] = owners
                    nextRows.append(row)
                    continue
                }

                let remainingOwners = owners.filter { $0 != ownerKey }
                if !remainingOwners.isEmpty {
                    row["source_owners"] = remainingOwners
                    nextRows.append(row)
                    continue
                }

                removedCount += 1
            }

            if nextRows.isEmpty {
                providers.removeValue(forKey: providerKey)
            } else {
                providerObject["accounts"] = nextRows
                providers[providerKey] = providerObject
            }
        }

        raw["providers"] = providers
        return removedCount
    }

    private static func mutableSnapshotContainsImportSource(
        _ raw: [String: Any],
        sourceKey: String
    ) -> Bool {
        if stringArrayValue(raw["import_sources"]).contains(sourceKey) {
            return true
        }
        if let statuses = raw["import_source_statuses"] as? [String: Any],
           statuses[sourceKey] != nil {
            return true
        }
        return countOwnedAccounts(in: raw, ownerKey: sourceKey) > 0
    }

    private static func removeImportSourceMetadata(
        from raw: inout [String: Any],
        sourceKey: String
    ) -> Int {
        var removed = false

        let sources = stringArrayValue(raw["import_sources"])
        let nextSources = sources.filter { $0 != sourceKey }
        if nextSources.count != sources.count {
            removed = true
            raw["import_sources"] = nextSources
        }

        var statuses = raw["import_source_statuses"] as? [String: Any] ?? [:]
        if statuses.removeValue(forKey: sourceKey) != nil {
            removed = true
            raw["import_source_statuses"] = statuses
        }

        return removed ? 1 : 0
    }

    private static func removeImportSourceOwnership(
        from raw: inout [String: Any],
        ownerKey: String,
        removeOwnedAccounts: Bool,
        nowMs: Int64
    ) -> (removedCount: Int, detachedCount: Int) {
        var providers = raw["providers"] as? [String: Any] ?? [:]
        var removedCount = 0
        var detachedCount = 0

        for (providerKey, providerValue) in providers {
            guard var providerObject = providerValue as? [String: Any],
                  let accountRows = providerObject["accounts"] as? [[String: Any]] else {
                continue
            }

            var nextRows: [[String: Any]] = []
            for var row in accountRows {
                let owners = uniqueStrings(stringArrayValue(row["source_owners"]))
                guard owners.contains(ownerKey) else {
                    nextRows.append(row)
                    continue
                }

                let remainingOwners = owners.filter { $0 != ownerKey }
                if removeOwnedAccounts, remainingOwners.isEmpty {
                    removedCount += 1
                    continue
                }

                row["source_owners"] = remainingOwners
                row["updated_at_ms"] = nowMs
                detachedCount += 1
                nextRows.append(row)
            }

            if nextRows.isEmpty {
                providers.removeValue(forKey: providerKey)
            } else {
                providerObject["accounts"] = nextRows
                providers[providerKey] = providerObject
            }
        }

        raw["providers"] = providers
        return (removedCount, detachedCount)
    }

    private static func countOwnedAccounts(
        in raw: [String: Any],
        ownerKey: String
    ) -> Int {
        guard let providers = raw["providers"] as? [String: Any] else {
            return 0
        }

        var total = 0
        for providerValue in providers.values {
            guard let providerObject = providerValue as? [String: Any],
                  let accounts = providerObject["accounts"] as? [[String: Any]] else {
                continue
            }
            total += accounts.filter {
                uniqueStrings(stringArrayValue($0["source_owners"])).contains(ownerKey)
            }.count
        }
        return total
    }

    private static func updateImportSourceStatus(
        _ raw: inout [String: Any],
        importSource: ProviderKeyImportSource,
        sourceKey: String?,
        state: String,
        lastImportedCount: Int,
        ownedAccountCount: Int,
        errors: [String],
        nowMs: Int64
    ) {
        guard let sourceKey else { return }
        var statuses = raw["import_source_statuses"] as? [String: Any] ?? [:]
        statuses[sourceKey] = [
            "kind": stringValue(importSource.kind).lowercased(),
            "source_ref": standardizedSourceReference(importSource.sourceRef),
            "state": state,
            "last_sync_at_ms": nowMs,
            "last_imported_count": max(0, lastImportedCount),
            "owned_account_count": max(0, ownedAccountCount),
            "last_error_count": max(0, errors.count),
            "last_errors": Array(errors.prefix(4)),
            "updated_at_ms": nowMs
        ]
        raw["import_source_statuses"] = statuses
    }

    private static func readMutableSnapshot(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return raw
    }

    private static func writeMutableSnapshot(_ raw: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        let destination = url.standardizedFileURL
        let tmp = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp.\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tmp, to: destination)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }

    private static func currentTimestampMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }

    private static func stringValue(_ any: Any?) -> String {
        if let s = any as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = any as? NSNumber { return n.stringValue }
        return ""
    }

    private static func intValue(_ any: Any?) -> Int {
        if let v = any as? Int { return v }
        if let v = any as? Double { return Int(v) }
        if let v = any as? NSNumber { return v.intValue }
        return 0
    }

    private static func int64Value(_ any: Any?) -> Int64 {
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? Double { return Int64(v) }
        if let v = any as? NSNumber { return v.int64Value }
        return 0
    }

    private static func doubleValue(_ any: Any?) -> Double {
        if let v = any as? Double { return v }
        if let v = any as? Float { return Double(v) }
        if let v = any as? Int { return Double(v) }
        if let v = any as? Int64 { return Double(v) }
        if let v = any as? NSNumber { return v.doubleValue }
        return 0
    }

    private static func clampedPercent(_ any: Any?) -> Double {
        let value = doubleValue(any)
        guard value.isFinite else { return 0 }
        return max(0, min(100, value))
    }

    private static func clampedBasisPoints(_ value: Int) -> Int {
        max(0, min(10_000, value))
    }

    private static func parseQuotaUsageWindow(_ raw: [String: Any]) -> ProviderKeyUsageWindow? {
        let source = firstNonEmpty(
            stringValue(raw["source"]),
            stringValue(raw["window_source"]),
            "rate_limit"
        ).lowercased()
        let windowKey = firstNonEmpty(
            stringValue(raw["window_key"]),
            stringValue(raw["window"]),
            stringValue(raw["key"])
        ).lowercased()
        let limitWindowSeconds = max(0, intValue(raw["limit_window_seconds"] ?? raw["window_seconds"]))
        let usedPercent = clampedPercent(raw["used_percent"])
        let usedBasisPoints = clampedBasisPoints(
            raw["used_basis_points"] == nil
                ? Int((usedPercent * 100).rounded())
                : intValue(raw["used_basis_points"])
        )
        let remainingBasisPoints = clampedBasisPoints(
            raw["remaining_basis_points"] == nil
                ? 10_000 - usedBasisPoints
                : intValue(raw["remaining_basis_points"])
        )
        let rawResetAtMs = int64Value(raw["reset_at_ms"] ?? raw["reset_at"])
        let resetAtMs = rawResetAtMs > 0 && rawResetAtMs < 1_000_000_000_000
            ? rawResetAtMs * 1000
            : rawResetAtMs
        let updatedAtMs = int64Value(raw["updated_at_ms"])
        let label = firstNonEmpty(
            stringValue(raw["label"]),
            stringValue(raw["display_name"])
        )
        let key = firstNonEmpty(
            stringValue(raw["key"]),
            [source, windowKey.isEmpty ? "window" : windowKey, limitWindowSeconds > 0 ? String(limitWindowSeconds) : label]
                .filter { !$0.isEmpty }
                .joined(separator: ":")
        )

        if key.isEmpty,
           label.isEmpty,
           limitWindowSeconds <= 0,
           usedPercent <= 0,
           resetAtMs <= 0,
           updatedAtMs <= 0 {
            return nil
        }

        return ProviderKeyUsageWindow(
            key: key,
            source: source,
            windowKey: windowKey,
            label: label,
            limitWindowSeconds: limitWindowSeconds,
            usedPercent: usedPercent,
            usedBasisPoints: usedBasisPoints,
            remainingBasisPoints: remainingBasisPoints,
            limited: raw["limited"] as? Bool ?? false,
            resetAtMs: resetAtMs,
            updatedAtMs: updatedAtMs
        )
    }

    private static func parseQuotaUsageWindows(_ any: Any?) -> [ProviderKeyUsageWindow] {
        guard let values = any as? [Any] else { return [] }
        var out: [ProviderKeyUsageWindow] = []
        var seen: Set<String> = []
        for value in values {
            guard let raw = value as? [String: Any],
                  let window = parseQuotaUsageWindow(raw) else {
                continue
            }
            let dedupeKey = firstNonEmpty(
                window.key,
                "\(window.source):\(window.windowKey):\(window.limitWindowSeconds)"
            )
            guard seen.insert(dedupeKey).inserted else { continue }
            out.append(window)
        }
        return out.sorted {
            if $0.source != $1.source {
                return $0.source < $1.source
            }
            return $0.limitWindowSeconds < $1.limitWindowSeconds
        }
    }

    private static func stringArrayValue(_ any: Any?) -> [String] {
        guard let values = any as? [Any] else { return [] }
        var out: [String] = []
        var seen: Set<String> = []
        for value in values {
            let normalized = stringValue(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            out.append(normalized)
        }
        return out
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        for value in values {
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private struct ParsedImportSourceKey {
        var kind: String
        var sourceRef: String
    }

    private static func parseImportSourceKey(_ raw: String) -> ParsedImportSourceKey? {
        let token = stringValue(raw)
        guard let separator = token.firstIndex(of: ":") else { return nil }
        let kind = stringValue(String(token[..<separator]))
        let sourceRef = stringValue(String(token[token.index(after: separator)...]))
        guard !kind.isEmpty, !sourceRef.isEmpty else { return nil }
        return ParsedImportSourceKey(kind: kind, sourceRef: sourceRef)
    }

    private static func normalizedWireAPI(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "chatcompletions", "chat_completions", "chat/completions":
            return "chat_completions"
        case "responses", "responses_api":
            return "responses"
        default:
            return normalized
        }
    }

    private static func defaultProviderHost(_ rawProvider: String?) -> String {
        switch canonicalPoolProvider(rawProvider) {
        case "openai":
            return "api.openai.com"
        case "claude":
            return "api.anthropic.com"
        case "gemini":
            return "generativelanguage.googleapis.com"
        case "antigravity":
            return "cloudcode-pa.googleapis.com"
        case "kimi":
            return "api.moonshot.cn"
        default:
            return ""
        }
    }

    private static func derivedProviderHost(
        provider: String,
        baseURL: String,
        proxyURL: String
    ) -> String {
        let direct = hostToken(baseURL)
        if !direct.isEmpty {
            return direct
        }
        let proxy = hostToken(proxyURL)
        if !proxy.isEmpty {
            return proxy
        }
        return defaultProviderHost(provider)
    }

    private static func nonDefaultBasePathScope(
        provider: String,
        baseURL: String
    ) -> String {
        let value = stringValue(baseURL)
        guard !value.isEmpty,
              let components = URLComponents(string: value) else {
            return ""
        }

        let path = stringValue(components.path)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
            .lowercased()
        let defaults: Set<String>
        switch normalizedProviderAlias(provider) {
        case "openai", "openai_compatible", "codex", "remote_catalog", "claude", "anthropic":
            defaults = ["", "/", "/v1"]
        case "gemini":
            defaults = ["", "/", "/v1", "/v1beta"]
        default:
            defaults = ["", "/"]
        }
        return defaults.contains(path) ? "" : path
    }

    private static func canonicalizedCustomHeaders(_ rawHeaders: [String: String]) -> [(String, String)] {
        rawHeaders.compactMap { key, value -> (String, String)? in
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { return nil }
            return (normalizedKey, normalizedValue)
        }
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 {
                return lhs.0 < rhs.0
            }
            return lhs.1 < rhs.1
        }
    }

    private static func shortFingerprint(_ raw: String) -> String {
        let data = Data(raw.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    private static func derivedPoolBoundaryFingerprint(
        provider: String,
        baseURL: String,
        proxyURL: String,
        customHeaders: [String: String]
    ) -> String {
        var parts: [String] = []
        let basePath = nonDefaultBasePathScope(provider: provider, baseURL: baseURL)
        if !basePath.isEmpty {
            parts.append("base_path=\(basePath)")
        }

        let proxyScope = normalizedOriginScope(proxyURL)
        if !proxyScope.isEmpty {
            parts.append("proxy_scope=\(proxyScope)")
        }

        for (key, value) in canonicalizedCustomHeaders(customHeaders) {
            parts.append("header:\(key)=\(value)")
        }

        guard !parts.isEmpty else {
            return ""
        }
        return shortFingerprint(parts.joined(separator: "\n"))
    }

    private static func derivedPoolID(
        provider: String,
        providerHost: String,
        wireAPI: String,
        baseURL: String,
        proxyURL: String,
        customHeaders: [String: String]
    ) -> String {
        let canonicalProvider = canonicalPoolProvider(provider)
        let hostPart = firstNonEmpty(providerHost, defaultProviderHost(provider), "default")
        let wirePart = wireAPI.isEmpty ? "default" : wireAPI
        let boundaryFingerprint = derivedPoolBoundaryFingerprint(
            provider: provider,
            baseURL: baseURL,
            proxyURL: proxyURL,
            customHeaders: customHeaders
        )
        if boundaryFingerprint.isEmpty {
            return "\(canonicalProvider):\(hostPart):\(wirePart)"
        }
        return "\(canonicalProvider):\(hostPart):\(wirePart):\(boundaryFingerprint)"
    }

    private static func resolvedNextRetryAtMs(
        raw: [String: Any],
        quotaRaw: [String: Any],
        errorRaw: [String: Any]
    ) -> Int64 {
        let explicit = int64Value(raw["next_retry_at_ms"])
        if explicit > 0 {
            return explicit
        }
        let errorState = int64Value(errorRaw["next_retry_at_ms"])
        if errorState > 0 {
            return errorState
        }
        return max(
            int64Value(quotaRaw["cooldown_until_ms"]),
            int64Value(quotaRaw["next_recover_at_ms"])
        )
    }

    private static func resolvedQuotaCooldownAtMs(_ quotaRaw: [String: Any]) -> Int64 {
        max(
            int64Value(quotaRaw["cooldown_until_ms"]),
            int64Value(quotaRaw["next_recover_at_ms"])
        )
    }

    private static func resolvedRetryAtSource(
        raw: [String: Any],
        quotaRaw: [String: Any],
        errorRaw: [String: Any]
    ) -> String {
        let explicitRaw = stringValue(raw["retry_at_source"])
        if !explicitRaw.isEmpty {
            let explicit = normalizedRetryAtSource(
                explicitRaw,
                status: stringValue(errorRaw["status"]),
                reasonCode: firstNonEmpty(
                    stringValue(errorRaw["reason_code"]),
                    stringValue(errorRaw["last_error_code"])
                ),
                nextRetryAtMs: resolvedNextRetryAtMs(raw: raw, quotaRaw: quotaRaw, errorRaw: errorRaw),
                quotaCooldownUntilMs: resolvedQuotaCooldownAtMs(quotaRaw)
            )
            if !explicit.isEmpty {
                return explicit
            }
        }
        let errorStateRaw = stringValue(errorRaw["retry_at_source"])
        if !errorStateRaw.isEmpty {
            let errorState = normalizedRetryAtSource(
                errorStateRaw,
                status: stringValue(errorRaw["status"]),
                reasonCode: firstNonEmpty(
                    stringValue(errorRaw["reason_code"]),
                    stringValue(errorRaw["last_error_code"])
                ),
                nextRetryAtMs: int64Value(errorRaw["next_retry_at_ms"]),
                quotaCooldownUntilMs: resolvedQuotaCooldownAtMs(quotaRaw)
            )
            if !errorState.isEmpty {
                return errorState
            }
        }
        let nextRetryAtMs = resolvedNextRetryAtMs(raw: raw, quotaRaw: quotaRaw, errorRaw: errorRaw)
        let inferred = normalizedRetryAtSource(
            "",
            status: stringValue(errorRaw["status"]),
            reasonCode: firstNonEmpty(
                stringValue(errorRaw["reason_code"]),
                stringValue(errorRaw["last_error_code"])
            ),
            nextRetryAtMs: nextRetryAtMs,
            quotaCooldownUntilMs: resolvedQuotaCooldownAtMs(quotaRaw)
        )
        if !inferred.isEmpty {
            return inferred
        }
        return ""
    }

    private static func normalizedRetryAtSource(
        _ raw: String,
        status: String,
        reasonCode: String,
        nextRetryAtMs: Int64,
        quotaCooldownUntilMs: Int64
    ) -> String {
        let normalized = stringValue(raw).lowercased()
        switch normalized {
        case "quota_refresh", "codex_usage":
            return "usage_window"
        case "quota", "provider_header", "usage_window", "scheduler", "refresh", "manual":
            return normalized
        case "refresh_schema":
            return "manual"
        default:
            break
        }

        let normalizedStatus = stringValue(status).lowercased()
        let normalizedReason = stringValue(reasonCode).lowercased()

        if normalizedReason == "token_expired" {
            return "refresh"
        }
        if [
            "missing_scope",
            "scope_missing",
            "auth_missing",
            "model_not_supported",
            "model_not_configured",
            "unsupported_refresh_schema",
        ].contains(normalizedReason)
            || ["blocked_auth", "auth_failed", "blocked_config"].contains(normalizedStatus) {
            return "manual"
        }
        if ["blocked_quota", "rate_limited"].contains(normalizedStatus) || quotaCooldownUntilMs > 0 {
            return max(nextRetryAtMs, quotaCooldownUntilMs) > 0 ? "quota" : ""
        }
        if ["blocked_network", "blocked_provider", "degraded"].contains(normalizedStatus) {
            return nextRetryAtMs > 0 ? "scheduler" : ""
        }
        return ""
    }

    private static func resolvedImportedReasonCode(
        explicit: String,
        runtimeStatus: String,
        quotaReason: String
    ) -> String {
        if !explicit.isEmpty {
            return explicit
        }
        if !quotaReason.isEmpty {
            return "quota_exceeded"
        }
        switch runtimeStatus {
        case "disabled":
            return "disabled"
        case "error":
            return "provider_error"
        default:
            return ""
        }
    }

    private static func importedErrorStatus(
        enabled: Bool,
        runtimeStatus: String,
        nextRetryAtMs: Int64,
        cooldownUntilMs: Int64
    ) -> String {
        let nowMs = currentTimestampMs()
        if !enabled || runtimeStatus == "disabled" {
            return "disabled"
        }
        if max(nextRetryAtMs, cooldownUntilMs) > nowMs {
            return "rate_limited"
        }
        switch runtimeStatus {
        case "refreshing", "pending", "error":
            return "degraded"
        default:
            return "healthy"
        }
    }

    private static func normalizedImportedRefreshStatus(
        _ raw: String,
        runtimeStatus: String,
        nextRefreshAtMs: Int64
    ) -> String {
        let normalized = stringValue(raw).lowercased()
        if !normalized.isEmpty {
            return normalized
        }
        if runtimeStatus == "refreshing" {
            return "refreshing"
        }
        if nextRefreshAtMs > 0 {
            return "scheduled"
        }
        return "idle"
    }

    private static func synthesizedLegacyAccount(
        keyReference: String,
        models: [RemoteModelEntry],
        health: RemoteKeyHealthRecord?,
        snapshotUpdatedAtMs: Int64
    ) -> ProviderKeyAccount? {
        let normalizedKeyReference = keyReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKeyReference.isEmpty else { return nil }
        let sortedModels = models.sorted { lhs, rhs in
            lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
        guard let sample = sortedModels.first else { return nil }

        let provider = legacyProviderIdentifier(for: sample, keyReference: normalizedKeyReference)
        guard !provider.isEmpty else { return nil }

        let baseURL = sample.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wireAPI = normalizedWireAPI(sample.wireAPI ?? "")
        let providerHost = firstNonEmpty(
            health?.providerHost ?? "",
            hostToken(baseURL),
            derivedProviderHost(
                provider: provider,
                baseURL: baseURL,
                proxyURL: ""
            )
        )
        let poolID = derivedPoolID(
            provider: provider,
            providerHost: providerHost,
            wireAPI: wireAPI,
            baseURL: baseURL,
            proxyURL: "",
            customHeaders: [:]
        )
        let modelIDs = Array(Set(sortedModels.map { model in
            model.effectiveProviderModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
        let enabled = sortedModels.contains { $0.enabled }
        let healthState = legacyErrorState(from: health)
        let updatedAtMs = max(
            snapshotUpdatedAtMs,
            Int64((health?.lastCheckedAt ?? 0) * 1000.0)
        )

        return ProviderKeyAccount(
            accountKey: normalizedKeyReference,
            provider: provider,
            poolID: poolID,
            providerHost: providerHost,
            email: "",
            apiKeyRedacted: legacyAccountLabel(for: normalizedKeyReference),
            baseURL: baseURL,
            proxyURL: "",
            enabled: enabled,
            authType: "api_key",
            wireAPI: wireAPI,
            expiresAtMs: 0,
            tier: "",
            customHeaders: [:],
            models: modelIDs,
            notes: "legacy_remote_models_derived",
            priority: 0,
            accountId: normalizedKeyReference,
            sourceType: "remote_models_legacy",
            sourceRef: RemoteModelStorage.url().path,
            oauthSourceKey: "",
            authIndex: legacyAccountIndex(from: normalizedKeyReference),
            createdAtMs: snapshotUpdatedAtMs,
            updatedAtMs: updatedAtMs,
            lastRefreshAtMs: Int64((health?.lastCheckedAt ?? 0) * 1000.0),
            quota: ProviderKeyQuota(
                dailyTokenCap: 0,
                dailyTokensUsed: 0,
                dailyTokensRemaining: 0,
                totalTokensUsed: 0,
                lastUsedAtMs: Int64((health?.lastSuccessAt ?? 0) * 1000.0),
                lastErrorAtMs: healthState.lastErrorAtMs,
                consecutiveErrors: health == nil || health?.state == .healthy ? 0 : 1,
                cooldownUntilMs: 0
            ),
            errorState: healthState
        )
    }

    private static func legacyProviderIdentifier(
        for model: RemoteModelEntry,
        keyReference: String
    ) -> String {
        let backend = normalizedProviderAlias(model.backend)
        if !backend.isEmpty {
            return backend
        }
        let token = keyReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = token.firstIndex(of: ":") else { return "" }
        return normalizedProviderAlias(String(token[..<separator]))
    }

    private static func legacyAccountLabel(for keyReference: String) -> String {
        let normalized = keyReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "legacy-key" }
        let parts = normalized.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            return String(parts[1])
        }
        return normalized
    }

    private static func legacyAccountIndex(from keyReference: String) -> Int {
        let normalized = keyReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hash = normalized.lastIndex(of: "#") else { return 0 }
        return Int(normalized[normalized.index(after: hash)...]) ?? 0
    }

    private static func legacyErrorState(from health: RemoteKeyHealthRecord?) -> ProviderKeyErrorState {
        guard let health else {
            return ProviderKeyErrorState(
                status: "degraded",
                statusMessage: "这把 key 还没有检测结果。",
                detailMessage: "",
                reasonCode: "health_missing",
                lastErrorCode: "",
                lastErrorAtMs: 0,
                nextRetryAtMs: 0,
                retryAtText: "",
                retryAtSource: "",
                autoDisabled: false
            )
        }

        let status: String
        switch health.state {
        case .healthy:
            status = "healthy"
        case .degraded, .unknownStale:
            status = "degraded"
        case .blockedQuota:
            status = "rate_limited"
        case .blockedAuth:
            status = "auth_failed"
        case .blockedNetwork, .blockedProvider, .blockedConfig:
            status = "disabled"
        }

        return ProviderKeyErrorState(
            status: status,
            statusMessage: firstNonEmpty(health.summary, health.detail),
            detailMessage: health.detail.trimmingCharacters(in: .whitespacesAndNewlines) == health.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                ? ""
                : health.detail.trimmingCharacters(in: .whitespacesAndNewlines),
            reasonCode: health.state.rawValue,
            lastErrorCode: health.state.rawValue,
            lastErrorAtMs: Int64(health.lastCheckedAt * 1000.0),
            nextRetryAtMs: 0,
            retryAtText: health.retryAtText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            retryAtSource: "legacy_remote_key_health",
            autoDisabled: false
        )
    }

    private struct SupplierDescriptor {
        var key: String
        var displayName: String
    }

    private static func strictProviderFamilyDescriptor(
        provider: String,
        providerHost: String
    ) -> SupplierDescriptor? {
        if let hostDescriptor = knownHostSupplierDescriptor(providerHost: providerHost) {
            if let familyDescriptor = familyDescriptor(forProviderAlias: hostDescriptor.key) {
                return familyDescriptor
            }
            if isConcreteModelFamilyKey(hostDescriptor.key) {
                return hostDescriptor
            }
            return nil
        }

        let alias = normalizedProviderAlias(provider)
        if alias == "openai" || alias == "codex" {
            return providerHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? familyDescriptor(forProviderAlias: alias)
                : nil
        }
        if alias == "openai_compatible"
            || alias == "remote_catalog"
            || alias == "custom" {
            return nil
        }
        return familyDescriptor(forProviderAlias: alias)
    }

    private static func isConcreteModelFamilyKey(_ rawKey: String) -> Bool {
        switch rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "openai",
             "glm",
             "qwen",
             "kimi",
             "claude",
             "gemini",
             "deepseek",
             "minimax",
             "mimo",
             "xai",
             "llama",
             "mistral",
             "doubao",
             "hunyuan",
             "ernie",
             "baichuan",
             "yi",
             "stepfun":
            return true
        default:
            return false
        }
    }

    private static func familyDescriptor(forProviderAlias alias: String) -> SupplierDescriptor? {
        switch alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "openai", "codex":
            return SupplierDescriptor(key: "openai", displayName: "OpenAI")
        case "glm", "zhipu":
            return SupplierDescriptor(key: "glm", displayName: "GLM")
        case "qwen", "dashscope":
            return SupplierDescriptor(key: "qwen", displayName: "Qwen")
        case "kimi", "moonshot":
            return SupplierDescriptor(key: "kimi", displayName: "Kimi")
        case "claude", "anthropic":
            return SupplierDescriptor(key: "claude", displayName: "Claude")
        case "gemini", "google":
            return SupplierDescriptor(key: "gemini", displayName: "Gemini")
        case "deepseek":
            return SupplierDescriptor(key: "deepseek", displayName: "DeepSeek")
        case "minimax":
            return SupplierDescriptor(key: "minimax", displayName: "MiniMax")
        case "mimo":
            return SupplierDescriptor(key: "mimo", displayName: "Mimo")
        case "xai", "grok":
            return SupplierDescriptor(key: "xai", displayName: "xAI")
        case "mistral":
            return SupplierDescriptor(key: "mistral", displayName: "Mistral")
        default:
            return nil
        }
    }

    private static func knownHostSupplierDescriptor(providerHost: String) -> SupplierDescriptor? {
        let host = providerHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty else { return nil }

        if host.contains("bigmodel.cn") || host.contains("zhipu") || host.contains("glm") {
            return SupplierDescriptor(key: "glm", displayName: "GLM")
        }
        if host.contains("dashscope") {
            return SupplierDescriptor(key: "dashscope", displayName: "DashScope")
        }
        if host.contains("moonshot") || host.contains("kimi") {
            return SupplierDescriptor(key: "kimi", displayName: "Kimi")
        }
        if host.contains("anthropic.com") {
            return SupplierDescriptor(key: "claude", displayName: "Claude")
        }
        if host.contains("googleapis.com") || host.contains("gemini") {
            return SupplierDescriptor(key: "gemini", displayName: "Gemini")
        }
        if host.contains("deepseek") {
            return SupplierDescriptor(key: "deepseek", displayName: "DeepSeek")
        }
        if host.contains("openrouter.ai") {
            return SupplierDescriptor(key: "openrouter", displayName: "OpenRouter")
        }
        if host.contains("groq.com") {
            return SupplierDescriptor(key: "groq", displayName: "Groq")
        }
        if host.contains("mistral.ai") {
            return SupplierDescriptor(key: "mistral", displayName: "Mistral")
        }
        if host.contains("x.ai") || host.contains("grok") {
            return SupplierDescriptor(key: "xai", displayName: "xAI")
        }
        if host.contains("openai.com") || host.contains("openai.azure.com") {
            return SupplierDescriptor(key: "openai", displayName: "OpenAI")
        }
        return nil
    }

    private static func supportedFamilyDescriptors(
        for accounts: [ProviderKeyAccount],
        provider: String,
        providerHost: String
    ) -> [SupplierDescriptor] {
        let strictFamily = strictProviderFamilyDescriptor(provider: provider, providerHost: providerHost)
        var descriptors: [SupplierDescriptor] = []
        var seen: Set<String> = []

        func append(_ descriptor: SupplierDescriptor?) {
            guard let descriptor else { return }
            let key = descriptor.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !displayName.isEmpty else { return }
            guard seen.insert(key).inserted else { return }
            descriptors.append(SupplierDescriptor(key: key, displayName: displayName))
        }

        for account in accounts {
            for modelID in account.models {
                append(familyDescriptor(forModelID: modelID))
            }
        }

        if let strictFamily {
            let matchingDescriptors = descriptors.filter { $0.key == strictFamily.key }
            descriptors = matchingDescriptors.isEmpty ? [strictFamily] : matchingDescriptors
        } else if descriptors.isEmpty {
            append(fallbackFamilyDescriptor(provider: provider, providerHost: providerHost))
        }

        if descriptors.isEmpty {
            append(SupplierDescriptor(key: "unknown", displayName: "Unknown"))
        }

        return descriptors.sorted { lhs, rhs in
            if lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) != .orderedSame {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.key < rhs.key
        }
    }

    private static func projectedQuotaPoolSource(
        _ pool: ProviderKeyPoolSnapshot,
        familyKey: String
    ) -> ProviderQuotaPoolSourceSnapshot? {
        let normalizedFamilyKey = familyKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedFamilyKey.isEmpty else { return nil }

        let relevantMembers = pool.members.filter { member in
            accountSupportsFamily(
                member.account,
                familyKey: normalizedFamilyKey,
                provider: pool.provider,
                providerHost: pool.providerHost
            )
        }
        guard !relevantMembers.isEmpty else { return nil }

        let supportedFamilies = supportedFamilyDescriptors(
            for: relevantMembers.map(\.account),
            provider: pool.provider,
            providerHost: pool.providerHost
        )
        let supportedFamilyKeys = supportedFamilies.map(\.key)
        guard supportedFamilyKeys.contains(normalizedFamilyKey) else { return nil }

        let totalAccounts = relevantMembers.count
        let enabledAccounts = relevantMembers.filter { $0.account.enabled }.count
        let readyAccounts = relevantMembers.filter { $0.state == "ready" || $0.state == "degraded" }.count
        let degradedAccounts = relevantMembers.filter { $0.state == "degraded" }.count
        let cooldownAccounts = relevantMembers.filter { $0.state == "cooldown" }.count
        let blockedAccounts = relevantMembers.filter { $0.state == "blocked" }.count
        let disabledAccounts = relevantMembers.filter { $0.state == "disabled" }.count
        let staleAccounts = relevantMembers.filter { $0.state == "stale" }.count
        let totalDailyTokenCap = relevantMembers.reduce(Int64(0)) { $0 + max(Int64(0), $1.account.quota.dailyTokenCap) }
        let totalDailyTokensUsed = relevantMembers.reduce(Int64(0)) { $0 + max(Int64(0), $1.account.quota.dailyTokensUsed) }
        let totalDailyTokensRemaining = relevantMembers.reduce(Int64(0)) { $0 + max(Int64(0), $1.account.quota.dailyTokensRemaining) }
        let totalTokensUsed = relevantMembers.reduce(Int64(0)) { $0 + max(Int64(0), $1.account.quota.totalTokensUsed) }
        let earliestRetryAtMs = relevantMembers
            .map(\.nextRetryAtMs)
            .filter { $0 > 0 }
            .min() ?? 0
        let lastRefreshAtMs = relevantMembers
            .map { max($0.account.lastRefreshAtMs, $0.account.updatedAtMs) }
            .max() ?? 0
        let hasQuotaData = relevantMembers.contains {
            $0.account.quota.dailyTokenCap > 0
                || $0.account.quota.dailyTokensUsed > 0
                || $0.account.quota.dailyTokensRemaining > 0
                || $0.account.quota.totalTokensUsed > 0
                || !$0.account.quota.usageWindows.isEmpty
        }
        let issue = poolIssueSummary(from: relevantMembers)
        let sharedFamilies = supportedFamilies.filter { $0.key != normalizedFamilyKey }

        return ProviderQuotaPoolSourceSnapshot(
            familyKey: normalizedFamilyKey,
            poolID: pool.poolID,
            supplierKey: pool.supplierKey,
            supplierDisplayName: pool.supplierDisplayName,
            provider: pool.provider,
            providerDisplayName: pool.providerDisplayName,
            providerHost: pool.providerHost,
            wireAPI: pool.wireAPI,
            routingStrategy: pool.routingStrategy,
            state: derivedAggregateState(
                total: totalAccounts,
                ready: readyAccounts,
                cooldown: cooldownAccounts,
                blocked: blockedAccounts,
                disabled: disabledAccounts,
                stale: staleAccounts
            ),
            members: relevantMembers.sorted(by: sortPoolMembers(_:_:)),
            totalAccounts: totalAccounts,
            enabledAccounts: enabledAccounts,
            readyAccounts: readyAccounts,
            degradedAccounts: degradedAccounts,
            cooldownAccounts: cooldownAccounts,
            blockedAccounts: blockedAccounts,
            disabledAccounts: disabledAccounts,
            staleAccounts: staleAccounts,
            totalDailyTokenCap: totalDailyTokenCap,
            totalDailyTokensUsed: totalDailyTokensUsed,
            totalDailyTokensRemaining: totalDailyTokensRemaining,
            totalTokensUsed: totalTokensUsed,
            earliestRetryAtMs: earliestRetryAtMs,
            lastRefreshAtMs: lastRefreshAtMs,
            hasQuotaData: hasQuotaData,
            supportedFamilyKeys: supportedFamilies.map(\.key),
            supportedFamilyDisplayNames: supportedFamilies.map(\.displayName),
            sharedWithFamilyKeys: sharedFamilies.map(\.key),
            sharedWithFamilyDisplayNames: sharedFamilies.map(\.displayName),
            issueSummary: issue.summary,
            issueDetail: issue.detail
        )
    }

    private static func accountSupportsFamily(
        _ account: ProviderKeyAccount,
        familyKey: String,
        provider: String,
        providerHost: String
    ) -> Bool {
        let normalizedFamilyKey = familyKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedFamilyKey.isEmpty else { return false }
        let families = supportedFamilyDescriptors(
            for: [account],
            provider: provider,
            providerHost: providerHost
        )
        return families.contains { $0.key == normalizedFamilyKey }
    }

    private static func familyDescriptor(forModelID rawModelID: String) -> SupplierDescriptor? {
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
        if modelID.hasPrefix("glm") || modelID.hasPrefix("zhipu") {
            return SupplierDescriptor(key: "glm", displayName: "GLM")
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
        if modelID.hasPrefix("claude") {
            return SupplierDescriptor(key: "claude", displayName: "Claude")
        }
        if modelID.hasPrefix("gemini") {
            return SupplierDescriptor(key: "gemini", displayName: "Gemini")
        }
        if modelID.hasPrefix("deepseek") {
            return SupplierDescriptor(key: "deepseek", displayName: "DeepSeek")
        }
        if modelID.hasPrefix("minimax") {
            return SupplierDescriptor(key: "minimax", displayName: "MiniMax")
        }
        if modelID.hasPrefix("mimo") {
            return SupplierDescriptor(key: "mimo", displayName: "Mimo")
        }
        if modelID.hasPrefix("grok") || modelID.hasPrefix("xai") {
            return SupplierDescriptor(key: "xai", displayName: "xAI")
        }
        if modelID.hasPrefix("llama") || modelID.hasPrefix("meta-llama") {
            return SupplierDescriptor(key: "llama", displayName: "Llama")
        }
        if modelID.hasPrefix("mistral") {
            return SupplierDescriptor(key: "mistral", displayName: "Mistral")
        }
        if modelID.hasPrefix("doubao") {
            return SupplierDescriptor(key: "doubao", displayName: "Doubao")
        }
        if modelID.hasPrefix("hunyuan") {
            return SupplierDescriptor(key: "hunyuan", displayName: "Hunyuan")
        }
        if modelID.hasPrefix("ernie") || modelID.hasPrefix("wenxin") {
            return SupplierDescriptor(key: "ernie", displayName: "ERNIE")
        }
        if modelID.hasPrefix("baichuan") {
            return SupplierDescriptor(key: "baichuan", displayName: "Baichuan")
        }
        if modelID.hasPrefix("yi-") || modelID == "yi" {
            return SupplierDescriptor(key: "yi", displayName: "Yi")
        }
        if modelID.hasPrefix("step") {
            return SupplierDescriptor(key: "stepfun", displayName: "StepFun")
        }
        if modelID.hasPrefix("openrouter") {
            return SupplierDescriptor(key: "openrouter", displayName: "OpenRouter")
        }
        return nil
    }

    private static func fallbackFamilyDescriptor(
        provider: String,
        providerHost: String
    ) -> SupplierDescriptor? {
        let alias = normalizedProviderAlias(provider)
        let host = providerHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let hostDescriptor = knownHostSupplierDescriptor(providerHost: providerHost) {
            return familyDescriptor(forProviderAlias: hostDescriptor.key) ?? hostDescriptor
        }
        if let aliasDescriptor = familyDescriptor(forProviderAlias: alias) {
            return aliasDescriptor
        }
        if alias == "openai" || alias == "codex" || host.contains("openai.com") {
            return SupplierDescriptor(key: "openai", displayName: "OpenAI")
        }
        if alias == "glm"
            || alias == "zhipu"
            || host.contains("bigmodel.cn")
            || host.contains("zhipu")
            || host.contains("glm") {
            return SupplierDescriptor(key: "glm", displayName: "GLM")
        }
        if alias == "qwen" || alias == "dashscope" || host.contains("dashscope") {
            return SupplierDescriptor(key: "qwen", displayName: "Qwen")
        }
        if alias == "claude" || alias == "anthropic" || host.contains("anthropic.com") {
            return SupplierDescriptor(key: "claude", displayName: "Claude")
        }
        if alias == "gemini"
            || alias == "google"
            || host.contains("googleapis.com")
            || host.contains("gemini") {
            return SupplierDescriptor(key: "gemini", displayName: "Gemini")
        }
        if alias == "deepseek" || host.contains("deepseek") {
            return SupplierDescriptor(key: "deepseek", displayName: "DeepSeek")
        }
        if alias == "mistral" || host.contains("mistral.ai") {
            return SupplierDescriptor(key: "mistral", displayName: "Mistral")
        }
        if alias == "xai"
            || alias == "grok"
            || host.contains("x.ai")
            || host.contains("grok") {
            return SupplierDescriptor(key: "xai", displayName: "xAI")
        }
        if alias == "openrouter" || host.contains("openrouter.ai") {
            return SupplierDescriptor(key: "openrouter", displayName: "OpenRouter")
        }
        if !host.isEmpty {
            return SupplierDescriptor(key: host, displayName: host)
        }
        guard !alias.isEmpty else { return nil }
        return SupplierDescriptor(key: alias, displayName: prettyProviderName(alias))
    }

    private static func familyDisplayName(for familyKey: String) -> String {
        let normalized = familyKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "openai":
            return "OpenAI"
        case "glm":
            return "GLM"
        case "qwen":
            return "Qwen"
        case "kimi":
            return "Kimi"
        case "claude":
            return "Claude"
        case "gemini":
            return "Gemini"
        case "deepseek":
            return "DeepSeek"
        case "minimax":
            return "MiniMax"
        case "mimo":
            return "Mimo"
        case "xai":
            return "xAI"
        case "llama":
            return "Llama"
        case "mistral":
            return "Mistral"
        case "doubao":
            return "Doubao"
        case "hunyuan":
            return "Hunyuan"
        case "ernie":
            return "ERNIE"
        case "baichuan":
            return "Baichuan"
        case "yi":
            return "Yi"
        case "stepfun":
            return "StepFun"
        case "openrouter":
            return "OpenRouter"
        default:
            return normalized.isEmpty ? "Unknown" : prettyProviderName(normalized)
        }
    }

    private static func derivedPoolMemberState(
        for account: ProviderKeyAccount,
        nowMs: Int64
    ) -> ProviderKeyPoolMemberState {
        let quotaCooldownAtMs = max(account.quota.cooldownUntilMs, account.quota.nextRecoverAtMs)
        let nextRetryAtMs = max(account.errorState.nextRetryAtMs, quotaCooldownAtMs)
        let reasonCode = firstNonEmpty(
            account.errorState.reasonCode,
            account.errorState.lastErrorCode
        )
        var reasonMessage = firstNonEmpty(
            account.errorState.statusMessage,
            account.errorState.reasonCode,
            account.errorState.lastErrorCode
        )
        let detailMessage = account.errorState.detailMessage

        let state: String
        let isRoutable: Bool
        if !account.enabled {
            state = "disabled"
            isRoutable = false
            if reasonMessage.isEmpty {
                reasonMessage = "该 key 当前被手动停用。"
            }
        } else if account.expiresAtMs > 0 && account.expiresAtMs <= nowMs {
            state = "stale"
            isRoutable = false
            if reasonMessage.isEmpty {
                reasonMessage = "OAuth 会话已过期，需要重新登录或刷新凭证。"
            }
        } else if account.errorState.autoDisabled
            || account.errorState.status == "auth_failed"
            || account.errorState.status == "disabled" {
            state = "blocked"
            isRoutable = false
            if reasonMessage.isEmpty {
                reasonMessage = "认证失败或 Provider 已明确拒绝这个 key。"
            }
        } else if account.errorState.status == "rate_limited"
            || quotaCooldownAtMs > nowMs
            || nextRetryAtMs > nowMs {
            state = "cooldown"
            isRoutable = false
            if reasonMessage.isEmpty {
                reasonMessage = "当前 key 正在额度或限流冷却中。"
            }
        } else if account.errorState.status == "degraded" {
            state = "degraded"
            isRoutable = true
            if reasonMessage.isEmpty {
                reasonMessage = "当前 key 仍可用，但默认会后排。"
            }
        } else {
            state = "ready"
            isRoutable = true
        }

        return ProviderKeyPoolMemberState(
            account: account,
            state: state,
            isRoutable: isRoutable,
            nextRetryAtMs: nextRetryAtMs,
            retryAtSource: account.errorState.retryAtSource,
            reasonCode: reasonCode,
            reasonMessage: reasonMessage,
            detailMessage: detailMessage
        )
    }

    private static func poolIssueSummary(
        from members: [ProviderKeyPoolMemberState]
    ) -> (summary: String, detail: String) {
        guard let issue = members.first(where: {
            (!$0.reasonMessage.isEmpty || !$0.detailMessage.isEmpty) && $0.state != "ready"
        }) else {
            return ("", "")
        }
        let summary = firstNonEmpty(issue.reasonMessage, issue.detailMessage)
        let detail = issue.detailMessage == summary ? "" : issue.detailMessage
        return (summary, detail)
    }

    private static func quotaPoolIssueSummary(
        from sources: [ProviderQuotaPoolSourceSnapshot]
    ) -> (summary: String, detail: String) {
        guard let source = sources.first(where: { !$0.issueSummary.isEmpty || !$0.issueDetail.isEmpty }) else {
            return ("", "")
        }
        return (source.issueSummary, source.issueDetail)
    }

    private static func sortPoolMembers(
        _ lhs: ProviderKeyPoolMemberState,
        _ rhs: ProviderKeyPoolMemberState
    ) -> Bool {
        let lhsRank = memberStateSortRank(lhs.state)
        let rhsRank = memberStateSortRank(rhs.state)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        let lhsTitle = firstNonEmpty(lhs.account.email, lhs.account.apiKeyRedacted, lhs.account.accountKey)
        let rhsTitle = firstNonEmpty(rhs.account.email, rhs.account.apiKeyRedacted, rhs.account.accountKey)
        if lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) != .orderedSame {
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
        }
        return lhs.account.accountKey < rhs.account.accountKey
    }

    private static func sortKeyPools(
        _ lhs: ProviderKeyPoolSnapshot,
        _ rhs: ProviderKeyPoolSnapshot
    ) -> Bool {
        if lhs.supplierDisplayName.localizedCaseInsensitiveCompare(rhs.supplierDisplayName) != .orderedSame {
            return lhs.supplierDisplayName.localizedCaseInsensitiveCompare(rhs.supplierDisplayName) == .orderedAscending
        }
        if lhs.providerHost.localizedCaseInsensitiveCompare(rhs.providerHost) != .orderedSame {
            return lhs.providerHost.localizedCaseInsensitiveCompare(rhs.providerHost) == .orderedAscending
        }
        return lhs.poolID < rhs.poolID
    }

    private static func sortQuotaPoolSources(
        _ lhs: ProviderQuotaPoolSourceSnapshot,
        _ rhs: ProviderQuotaPoolSourceSnapshot
    ) -> Bool {
        if lhs.supplierDisplayName.localizedCaseInsensitiveCompare(rhs.supplierDisplayName) != .orderedSame {
            return lhs.supplierDisplayName.localizedCaseInsensitiveCompare(rhs.supplierDisplayName) == .orderedAscending
        }
        if lhs.providerHost.localizedCaseInsensitiveCompare(rhs.providerHost) != .orderedSame {
            return lhs.providerHost.localizedCaseInsensitiveCompare(rhs.providerHost) == .orderedAscending
        }
        return lhs.poolID < rhs.poolID
    }

    private static func memberStateSortRank(_ state: String) -> Int {
        switch state {
        case "blocked":
            return 0
        case "stale":
            return 1
        case "cooldown":
            return 2
        case "degraded":
            return 3
        case "ready":
            return 4
        case "disabled":
            return 5
        default:
            return 6
        }
    }

    private static func derivedAggregateState(
        total: Int,
        ready: Int,
        cooldown: Int,
        blocked: Int,
        disabled: Int,
        stale: Int
    ) -> String {
        guard total > 0 else { return "empty" }
        if ready == total {
            return "ready"
        }
        if disabled == total {
            return "disabled"
        }
        if blocked + stale == total {
            return "blocked"
        }
        if cooldown > 0 && ready == 0 && blocked == 0 && stale == 0 {
            return "cooldown"
        }
        return "mixed"
    }

    private static func providerDisplayName(
        provider: String,
        providerHost: String
    ) -> String {
        let supplier = supplierDescriptor(provider: provider, providerHost: providerHost)
        if !supplier.displayName.isEmpty {
            return supplier.displayName
        }
        let alias = normalizedProviderAlias(provider)
        if !alias.isEmpty {
            return prettyProviderName(alias)
        }
        if !providerHost.isEmpty {
            return providerHost
        }
        return provider
    }

    private static func supplierDescriptor(
        provider: String,
        providerHost: String
    ) -> SupplierDescriptor {
        let alias = normalizedProviderAlias(provider)
        let host = providerHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let hostDescriptor = knownHostSupplierDescriptor(providerHost: providerHost) {
            return hostDescriptor
        }
        if alias == "zhipu"
            || alias == "glm"
            || host.contains("bigmodel.cn")
            || host.contains("zhipu")
            || host.contains("glm") {
            return SupplierDescriptor(key: "glm", displayName: "GLM")
        }
        if alias == "openai"
            || alias == "codex"
            || host.contains("openai.com")
            || host.contains("openai.azure.com") {
            return SupplierDescriptor(key: "openai", displayName: "OpenAI")
        }
        if alias == "claude"
            || alias == "anthropic"
            || host.contains("anthropic.com") {
            return SupplierDescriptor(key: "claude", displayName: "Claude")
        }
        if alias == "gemini"
            || alias == "google"
            || host.contains("googleapis.com")
            || host.contains("gemini") {
            return SupplierDescriptor(key: "gemini", displayName: "Gemini")
        }
        if alias == "openrouter" || host.contains("openrouter.ai") {
            return SupplierDescriptor(key: "openrouter", displayName: "OpenRouter")
        }
        if alias == "groq" || host.contains("groq.com") {
            return SupplierDescriptor(key: "groq", displayName: "Groq")
        }
        if alias == "deepseek" || host.contains("deepseek") {
            return SupplierDescriptor(key: "deepseek", displayName: "DeepSeek")
        }
        if alias == "mistral" || host.contains("mistral.ai") {
            return SupplierDescriptor(key: "mistral", displayName: "Mistral")
        }
        if alias == "xai"
            || alias == "grok"
            || host.contains("x.ai")
            || host.contains("grok") {
            return SupplierDescriptor(key: "xai", displayName: "xAI")
        }
        if alias == "qwen"
            || alias == "dashscope"
            || host.contains("dashscope") {
            return SupplierDescriptor(key: "dashscope", displayName: "DashScope")
        }
        if !host.isEmpty {
            return SupplierDescriptor(key: host, displayName: host)
        }
        let normalized = firstNonEmpty(alias, canonicalPoolProvider(provider))
        return SupplierDescriptor(
            key: normalized.isEmpty ? "unknown" : normalized,
            displayName: normalized.isEmpty ? "Unknown" : prettyProviderName(normalized)
        )
    }

    private static func prettyProviderName(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        switch normalized.lowercased() {
        case "openai_compatible":
            return "OpenAI Compatible"
        case "remote_catalog":
            return "Remote Catalog"
        default:
            return normalized
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { token in
                    let lower = token.lowercased()
                    if lower == "api" {
                        return "API"
                    }
                    return lower.prefix(1).uppercased() + lower.dropFirst()
                }
                .joined(separator: " ")
        }
    }
}
