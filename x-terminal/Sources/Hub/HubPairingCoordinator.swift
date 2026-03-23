import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum HubRemoteRoute: String, Sendable {
    case none
    case lan
    case internet
    case internetTunnel
}

struct HubRemoteConnectOptions: Sendable {
    var grpcPort: Int
    var pairingPort: Int
    var deviceName: String
    var internetHost: String
    var axhubctlPath: String
    var stateDir: URL?
}

struct HubRemoteConnectReport: Sendable {
    var ok: Bool
    var route: HubRemoteRoute
    var summary: String
    var logLines: [String]
    var reasonCode: String?

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

enum HubRemoteProgressPhase: String, Sendable {
    case discover
    case bootstrap
    case connect
}

enum HubRemoteProgressState: String, Sendable {
    case started
    case succeeded
    case failed
    case skipped
}

struct HubRemoteProgressEvent: Sendable {
    var phase: HubRemoteProgressPhase
    var state: HubRemoteProgressState
    var detail: String?
}

struct HubRemotePortProbeResult: Sendable {
    var ok: Bool
    var pairingPort: Int
    var grpcPort: Int
    var reasonCode: String?
    var candidates: [HubDiscoveredHubCandidateSummary]
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubDiscoveredHubCandidateSummary: Identifiable, Equatable, Sendable {
    var host: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String?
    var hubInstanceID: String?
    var lanDiscoveryName: String?

    var id: String {
        if let hubInstanceID = hubInstanceID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hubInstanceID.isEmpty {
            return hubInstanceID.lowercased()
        }
        let internet = (internetHost ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(host.lowercased())|\(pairingPort)|\(grpcPort)|\(internet)"
    }

    var displayName: String {
        if let lanDiscoveryName = lanDiscoveryName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lanDiscoveryName.isEmpty {
            return lanDiscoveryName
        }
        if let hubInstanceID = hubInstanceID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hubInstanceID.isEmpty {
            return hubInstanceID
        }
        return host
    }
}

private struct HubPairingDiscoveryPayload: Decodable, Sendable {
    var ok: Bool?
    var service: String?
    var hubHostHint: String?
    var pairingPort: Int?
    var grpcPort: Int?
    var internetHostHint: String?
    var hubInstanceID: String?
    var lanDiscoveryName: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case service
        case hubHostHint = "hub_host_hint"
        case pairingPort = "pairing_port"
        case grpcPort = "grpc_port"
        case internetHostHint = "internet_host_hint"
        case hubInstanceID = "hub_instance_id"
        case lanDiscoveryName = "lan_discovery_name"
    }

    var matchesPairingService: Bool {
        if ok == true { return true }
        let normalizedService = (service ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedService.contains("pair")
    }
}

private struct HubLANDiscoveryCandidate: Sendable {
    var host: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String?
    var hubInstanceID: String?
    var lanDiscoveryName: String?
    var logLines: [String]
}

private struct HubLANDiscoveryProbeMatch: Sendable {
    var host: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String?
    var hubInstanceID: String?
    var lanDiscoveryName: String?
}

private struct HubCachedPairingInfo: Sendable {
    var host: String?
    var internetHost: String?
    var pairingPort: Int?
    var grpcPort: Int?
    var hubInstanceID: String?
    var lanDiscoveryName: String?
}

private struct HubLANDiscoveryAttempt: Sendable {
    var candidate: HubLANDiscoveryCandidate?
    var reasonCode: String?
    var candidates: [HubLANDiscoveryCandidate]
    var logLines: [String]
}

private struct HubLANDiscoveryScanPlan: Sendable {
    var hosts: [String]
    var networkSummaries: [String]
}

struct HubRemoteResetResult: Sendable {
    var ok: Bool
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteModelsResult: Sendable {
    var ok: Bool
    var models: [HubModel]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

private func canonicalHubAppID(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let lower = trimmed.lowercased()
    let compact = lower.unicodeScalars.reduce(into: "") { partialResult, scalar in
        let value = scalar.value
        if (value >= 48 && value <= 57) || (value >= 97 && value <= 122) {
            partialResult.unicodeScalars.append(scalar)
        }
    }
    if compact == "xterminal" || compact == "axterminal" {
        return "x_terminal"
    }

    var normalized = ""
    normalized.reserveCapacity(lower.count)
    var lastWasUnderscore = false
    for scalar in lower.unicodeScalars {
        let value = scalar.value
        if (value >= 48 && value <= 57) || (value >= 97 && value <= 122) {
            normalized.unicodeScalars.append(scalar)
            lastWasUnderscore = false
        } else if value == 95 || value == 45 || value == 32 {
            if !lastWasUnderscore {
                normalized.append("_")
                lastWasUnderscore = true
            }
        }
    }

    let finalValue = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return finalValue.isEmpty ? nil : finalValue
}

struct HubRemoteGenerateResult: Sendable {
    var ok: Bool
    var text: String
    var modelId: String?
    var requestedModelId: String? = nil
    var actualModelId: String? = nil
    var runtimeProvider: String? = nil
    var executionPath: String? = nil
    var fallbackReasonCode: String? = nil
    var promptTokens: Int? = nil
    var completionTokens: Int? = nil
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

enum HubRemoteGrantDecision: String, Sendable {
    case approved
    case queued
    case denied
    case failed
}

struct HubRemoteGrantResult: Sendable {
    var ok: Bool
    var decision: HubRemoteGrantDecision
    var grantRequestId: String?
    var expiresAtSec: Double?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteWebFetchResult: Sendable {
    var ok: Bool
    var status: Int
    var finalURL: String
    var contentType: String
    var truncated: Bool
    var bytes: Int
    var text: String
    var errorMessage: String?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteProjectSyncPayload: Sendable {
    var projectId: String
    var rootPath: String
    var displayName: String
    var statusDigest: String?
    var lastSummaryAt: Double?
    var lastEventAt: Double?
    var updatedAt: Double?
}

struct HubRemoteProjectConversationPayload: Sendable {
    var projectId: String
    var threadKey: String
    var requestId: String
    var createdAtMs: Int64
    var userText: String
    var assistantText: String
}

struct HubRemoteSupervisorConversationPayload: Sendable {
    var threadKey: String
    var requestId: String
    var createdAtMs: Int64
    var userText: String
    var assistantText: String
}

struct HubRemoteCanonicalMemoryItem: Codable, Equatable, Sendable {
    var key: String
    var value: String
}

struct HubRemoteProjectCanonicalMemoryPayload: Sendable {
    var projectId: String
    var items: [HubRemoteCanonicalMemoryItem]
}

struct HubRemoteDeviceCanonicalMemoryPayload: Sendable {
    var items: [HubRemoteCanonicalMemoryItem]
}

struct HubRemoteNotificationPayload: Sendable {
    var source: String
    var title: String
    var body: String
    var dedupeKey: String?
    var actionURL: String?
    var unread: Bool
}

struct HubRemoteMutationResult: Sendable {
    var ok: Bool
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSkillCatalogEntry: Sendable {
    var skillID: String
    var name: String
    var version: String
    var description: String
    var publisherID: String
    var capabilitiesRequired: [String]
    var sourceID: String
    var packageSHA256: String
    var installHint: String
    var riskLevel: String
    var requiresGrant: Bool
    var sideEffectClass: String
}

struct HubRemoteOfficialSkillChannelStatus: Sendable {
    var channelID: String
    var status: String
    var updatedAtMs: Int64
    var lastAttemptAtMs: Int64
    var lastSuccessAtMs: Int64
    var skillCount: Int
    var errorCode: String
    var maintenanceEnabled: Bool
    var maintenanceIntervalMs: Int64
    var maintenanceLastRunAtMs: Int64
    var maintenanceSourceKind: String
    var lastTransitionAtMs: Int64
    var lastTransitionKind: String
    var lastTransitionSummary: String
}

struct HubRemoteSkillsSearchResult: Sendable {
    var ok: Bool
    var source: String
    var updatedAtMs: Int64
    var results: [HubRemoteSkillCatalogEntry]
    var reasonCode: String?
    var officialChannelStatus: HubRemoteOfficialSkillChannelStatus? = nil
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSkillPinResult: Sendable {
    var ok: Bool
    var source: String
    var scope: String
    var userId: String
    var projectId: String
    var skillId: String
    var packageSHA256: String
    var previousPackageSHA256: String
    var updatedAtMs: Int64
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteResolvedSkillEntry: Sendable {
    var scope: String
    var skill: HubRemoteSkillCatalogEntry
}

struct HubRemoteResolvedSkillsResult: Sendable {
    var ok: Bool
    var source: String
    var skills: [HubRemoteResolvedSkillEntry]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteAgentImportStageResult: Sendable {
    var ok: Bool
    var source: String
    var stagingId: String?
    var status: String?
    var auditRef: String?
    var preflightStatus: String?
    var skillId: String?
    var policyScope: String?
    var findingsCount: Int
    var vetterStatus: String?
    var vetterCriticalCount: Int
    var vetterWarnCount: Int
    var vetterAuditRef: String?
    var recordPath: String?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteAgentImportRecordResult: Sendable {
    var ok: Bool
    var source: String
    var selector: String?
    var stagingId: String?
    var status: String?
    var auditRef: String?
    var schemaVersion: String?
    var skillId: String?
    var projectId: String?
    var recordJSON: String?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSkillPackageUploadResult: Sendable {
    var ok: Bool
    var source: String
    var packageSHA256: String?
    var alreadyPresent: Bool
    var skillId: String?
    var version: String?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteAgentImportPromoteResult: Sendable {
    var ok: Bool
    var source: String
    var stagingId: String?
    var status: String?
    var auditRef: String?
    var packageSHA256: String?
    var scope: String?
    var skillId: String?
    var previousPackageSHA256: String?
    var recordPath: String?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteMemorySnapshotResult: Sendable {
    var ok: Bool
    var source: String
    var canonicalEntries: [String]
    var workingEntries: [String]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteMemoryRetrievalItem: Sendable {
    var ref: String
    var sourceKind: String
    var summary: String
    var snippet: String
    var score: Double
    var redacted: Bool
}

struct HubRemoteMemoryRetrievalResult: Sendable {
    var ok: Bool
    var schemaVersion: String?
    var requestId: String?
    var status: String?
    var resolvedScope: String?
    var source: String
    var scope: String
    var auditRef: String
    var reasonCode: String?
    var denyCode: String?
    var results: [HubRemoteMemoryRetrievalItem]
    var truncated: Bool
    var budgetUsedChars: Int
    var truncatedItems: Int
    var redactedItems: Int
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSchedulerScopeCount: Sendable {
    var scopeKey: String
    var count: Int
}

struct HubRemoteSchedulerQueueItem: Sendable {
    var requestId: String
    var scopeKey: String
    var enqueuedAtMs: Double
    var queuedMs: Int
}

struct HubRemoteSchedulerStatusResult: Sendable {
    var ok: Bool
    var source: String
    var updatedAtMs: Double
    var inFlightTotal: Int
    var queueDepth: Int
    var oldestQueuedMs: Int
    var inFlightByScope: [HubRemoteSchedulerScopeCount]
    var queuedByScope: [HubRemoteSchedulerScopeCount]
    var queueItems: [HubRemoteSchedulerQueueItem]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemotePendingGrantItem: Sendable {
    var grantRequestId: String
    var requestId: String
    var deviceId: String
    var userId: String
    var appId: String
    var projectId: String
    var capability: String
    var modelId: String
    var reason: String
    var requestedTtlSec: Int
    var requestedTokenCap: Int
    var status: String
    var decision: String
    var createdAtMs: Double
    var decidedAtMs: Double
}

struct HubRemotePendingGrantRequestsResult: Sendable {
    var ok: Bool
    var source: String
    var updatedAtMs: Double
    var items: [HubRemotePendingGrantItem]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSupervisorCandidateReviewQueueItem: Sendable {
    var schemaVersion: String
    var reviewId: String
    var requestId: String
    var evidenceRef: String
    var reviewState: String
    var durablePromotionState: String
    var promotionBoundary: String
    var deviceId: String
    var userId: String
    var appId: String
    var threadId: String
    var threadKey: String
    var projectId: String
    var projectIds: [String]
    var scopes: [String]
    var recordTypes: [String]
    var auditRefs: [String]
    var idempotencyKeys: [String]
    var candidateCount: Int
    var summaryLine: String
    var mirrorTarget: String
    var localStoreRole: String
    var carrierKind: String
    var carrierSchemaVersion: String
    var pendingChangeId: String
    var pendingChangeStatus: String
    var editSessionId: String
    var docId: String
    var writebackRef: String
    var stageCreatedAtMs: Double
    var stageUpdatedAtMs: Double
    var latestEmittedAtMs: Double
    var createdAtMs: Double
    var updatedAtMs: Double
}

struct HubRemoteSupervisorCandidateReviewQueueResult: Sendable {
    var ok: Bool
    var source: String
    var updatedAtMs: Double
    var items: [HubRemoteSupervisorCandidateReviewQueueItem]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteConnectorIngressReceipt: Sendable {
    var receiptId: String
    var requestId: String
    var projectId: String
    var connector: String
    var targetId: String
    var ingressType: String
    var channelScope: String
    var sourceId: String
    var messageId: String
    var dedupeKey: String
    var receivedAtMs: Double
    var eventSequence: Int64
    var deliveryState: String
    var runtimeState: String
}

struct HubRemoteConnectorIngressReceiptsResult: Sendable {
    var ok: Bool
    var source: String
    var updatedAtMs: Double
    var items: [HubRemoteConnectorIngressReceipt]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteRuntimeSurfaceOverrideItem: Sendable {
    var projectId: String
    var overrideMode: AXProjectRuntimeSurfaceHubOverrideMode
    var updatedAtMs: Double
    var reason: String
    var auditRef: String
}

struct HubRemoteRuntimeSurfaceOverridesResult: Sendable {
    var ok: Bool
    var source: String
    var updatedAtMs: Double
    var items: [HubRemoteRuntimeSurfaceOverrideItem]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

@available(*, deprecated, message: "Use HubRemoteRuntimeSurfaceOverrideItem")
typealias HubRemoteAutonomyPolicyOverrideItem = HubRemoteRuntimeSurfaceOverrideItem

@available(*, deprecated, message: "Use HubRemoteRuntimeSurfaceOverridesResult")
typealias HubRemoteAutonomyPolicyOverridesResult = HubRemoteRuntimeSurfaceOverridesResult

private enum HubRemoteRuntimeSurfaceCompatContract {
    static let failureReasonCode = "remote_autonomy_policy_overrides_failed"
    static let legacyProjectIdEnv = "XTERMINAL_AUTONOMY_OVERRIDE_PROJECT_ID"
    static let legacyLimitEnv = "XTERMINAL_AUTONOMY_OVERRIDE_LIMIT"
    static let grpcMethod = "GetAutonomyPolicyOverrides"
}

enum HubRemotePendingGrantActionDecision: String, Sendable {
    case approved
    case denied
    case failed
}

struct HubRemotePendingGrantActionResult: Sendable {
    var ok: Bool
    var decision: HubRemotePendingGrantActionDecision
    var grantRequestId: String?
    var grantId: String?
    var expiresAtMs: Double?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSupervisorCandidateReviewStageResult: Sendable {
    var ok: Bool
    var staged: Bool
    var idempotent: Bool
    var source: String
    var reviewState: String
    var durablePromotionState: String
    var promotionBoundary: String
    var candidateRequestId: String?
    var evidenceRef: String?
    var editSessionId: String?
    var pendingChangeId: String?
    var docId: String?
    var baseVersion: String?
    var workingVersion: String?
    var sessionRevision: Int64
    var status: String?
    var markdown: String?
    var createdAtMs: Double
    var updatedAtMs: Double
    var expiresAtMs: Double
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteLongtermMarkdownReviewResult: Sendable {
    var ok: Bool
    var source: String
    var pendingChangeId: String?
    var editSessionId: String?
    var docId: String?
    var status: String?
    var reviewDecision: String?
    var policyDecision: String?
    var findingsJSON: String?
    var redactedCount: Int
    var reviewedAtMs: Double
    var approvedAtMs: Double
    var markdown: String?
    var autoRejected: Bool
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteLongtermMarkdownWritebackResult: Sendable {
    var ok: Bool
    var source: String
    var pendingChangeId: String?
    var status: String?
    var candidateId: String?
    var queueStatus: String?
    var writtenAtMs: Double
    var docId: String?
    var sourceVersion: String?
    var changeLogId: String?
    var evidenceRef: String?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSupervisorBriefProjection: Sendable {
    var schemaVersion: String
    var projectionId: String
    var projectionKind: String
    var projectId: String
    var runId: String
    var missionId: String
    var trigger: String
    var status: String
    var criticalBlocker: String
    var topline: String
    var nextBestAction: String
    var pendingGrantCount: Int
    var ttsScript: [String]
    var cardSummary: String
    var evidenceRefs: [String]
    var generatedAtMs: Double
    var expiresAtMs: Double
    var auditRef: String
}

struct HubRemoteSupervisorBriefProjectionResult: Sendable {
    var ok: Bool
    var source: String
    var projection: HubRemoteSupervisorBriefProjection?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteVoiceGrantChallenge: Sendable {
    var challengeId: String
    var templateId: String
    var actionDigest: String
    var scopeDigest: String
    var amountDigest: String
    var challengeCode: String
    var riskLevel: String
    var requiresMobileConfirm: Bool
    var allowVoiceOnly: Bool
    var boundDeviceId: String
    var mobileTerminalId: String
    var issuedAtMs: Double
    var expiresAtMs: Double
}

struct HubRemoteVoiceGrantChallengeResult: Sendable {
    var ok: Bool
    var source: String
    var challenge: HubRemoteVoiceGrantChallenge?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

enum HubRemoteVoiceGrantVerificationDecision: String, Sendable {
    case allow
    case deny
    case failed
}

struct HubRemoteVoiceGrantVerificationResult: Sendable {
    var ok: Bool
    var verified: Bool
    var decision: HubRemoteVoiceGrantVerificationDecision
    var source: String
    var denyCode: String?
    var challengeId: String?
    var transcriptHash: String?
    var semanticMatchScore: Double
    var challengeMatch: Bool
    var deviceBindingOK: Bool
    var mobileConfirmed: Bool
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSecretVaultItem: Sendable {
    var itemId: String
    var scope: String
    var name: String
    var sensitivity: String
    var createdAtMs: Double
    var updatedAtMs: Double
}

struct HubRemoteSecretVaultItemsResult: Sendable {
    var ok: Bool
    var source: String
    var updatedAtMs: Double
    var items: [HubRemoteSecretVaultItem]
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSecretVaultCreateResult: Sendable {
    var ok: Bool
    var source: String
    var item: HubRemoteSecretVaultItem?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSecretVaultUseResult: Sendable {
    var ok: Bool
    var source: String
    var leaseId: String?
    var useToken: String?
    var itemId: String?
    var expiresAtMs: Double?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSecretVaultRedeemResult: Sendable {
    var ok: Bool
    var source: String
    var leaseId: String?
    var itemId: String?
    var plaintext: String?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

enum HubBundledToolSupport {
    static func defaultApplicationSupportBase(fileManager: FileManager = .default) -> URL {
        if let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return base
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    static func toolSupportBinDirectory(
        applicationSupportBase: URL = defaultApplicationSupportBase()
    ) -> URL {
        applicationSupportBase
            .appendingPathComponent("X-Terminal", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    static func defaultAxhubctlFallbackCandidates(
        homeDirectory: URL = XTProcessPaths.realHomeDirectory()
    ) -> [String] {
        [
            homeDirectory
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("axhubctl", isDirectory: false)
                .path,
        ]
    }
}

actor HubPairingCoordinator {
    static let shared = HubPairingCoordinator()

    func hasHubEnv(stateDir: URL?) -> Bool {
        let base = stateDir ?? defaultStateDir()
        let env = base.appendingPathComponent("hub.env")
        guard FileManager.default.fileExists(atPath: env.path) else { return false }
        let token = readEnvValue(from: env, key: "HUB_CLIENT_TOKEN") ?? ""
        return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func suggestedAxhubctlPath(override rawOverride: String = "") -> String? {
        let override = rawOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = resolveAxhubctlExecutable(override: override)
        switch resolved {
        case .direct(let path):
            return path
        case .bashScript(let path):
            return path
        case .viaEnv:
            return nil
        }
    }

    func ensureConnected(
        options rawOptions: HubRemoteConnectOptions,
        allowBootstrap: Bool,
        onProgress: (@Sendable (HubRemoteProgressEvent) -> Void)? = nil
    ) async -> HubRemoteConnectReport {
        var opts = sanitize(rawOptions)
        var logs: [String] = []
        var discoveredHubHost: String?
        let cachedPairing = loadCachedPairingInfo(stateDir: opts.stateDir)
        if nonEmpty(opts.internetHost) == nil, let cachedInternetHost = cachedPairing.internetHost {
            opts.internetHost = cachedInternetHost
        }
        let customEnv = discoveryEnv(internetHost: opts.internetHost)

        let hasEnv = hasHubEnv(stateDir: opts.stateDir)
        let effectiveAllowBootstrap: Bool
        if allowBootstrap {
            effectiveAllowBootstrap = true
        } else if !hasEnv {
            effectiveAllowBootstrap = true
            logs.append("[repair] missing hub.env; promote reconnect to bootstrap.")
        } else {
            effectiveAllowBootstrap = false
        }

        if effectiveAllowBootstrap {
            // Always try discover during one-click setup so stale pairing ports can self-heal.
            logs.append("[1/3] Discover Hub ...")
            emit(onProgress, .discover, .started, nil)
            var discoverSuccess = false
            var discoverUnsupported = false
            var lastDiscoverOutput = ""
            let candidates = orderedPairingPortCandidates(opts.pairingPort)
            var localDiscoveryBlockedReason: String?

            if !shouldRequireConfiguredHubHost(options: opts) {
                let lanFallback = await discoverHubOnLAN(
                    options: opts,
                    pairingPorts: candidates,
                    cachedPairing: cachedPairing
                )
                logs.append(contentsOf: lanFallback.logLines)
                if let candidate = lanFallback.candidate {
                    discoverSuccess = true
                    opts.pairingPort = candidate.pairingPort
                    opts.grpcPort = candidate.grpcPort
                    if nonEmpty(opts.internetHost) == nil,
                       let discoveredInternetHost = nonEmpty(candidate.internetHost) {
                        opts.internetHost = discoveredInternetHost
                    }
                    discoveredHubHost = candidate.host
                } else if let reason = lanFallback.reasonCode {
                    localDiscoveryBlockedReason = reason
                    lastDiscoverOutput = reason
                }
            }

            if !discoverSuccess, localDiscoveryBlockedReason == nil {
                let probeStateDir = makeEphemeralStateDir(prefix: "xterminal_discover_probe")
                var discoverOpts = opts
                discoverOpts.stateDir = probeStateDir
                for p in candidates {
                    let discover = runAxhubctl(
                        args: [
                            "discover",
                            "--pairing-port", "\(p)",
                            "--timeout-sec", "3",
                        ],
                        options: discoverOpts,
                        env: customEnv,
                        timeoutSec: 30.0
                    )
                    appendStepLogs(into: &logs, step: discover)
                    lastDiscoverOutput = discover.output
                    if discover.exitCode == 0 {
                        let parsedHost = parseStringField(discover.output, fieldName: "host")
                        if shouldRequireConfiguredHubHost(options: opts),
                           !hostMatchesConfiguredHost(discoveredHost: parsedHost, options: opts) {
                            logs.append("[discover] ignore host mismatch (want \(opts.internetHost), got \(parsedHost ?? "unknown"))")
                            continue
                        }

                        discoverSuccess = true
                        opts.pairingPort = parsePortField(discover.output, fieldName: "pairing_port") ?? p
                        opts.grpcPort = parsePortField(discover.output, fieldName: "grpc_port") ?? opts.grpcPort
                        if nonEmpty(opts.internetHost) == nil,
                           let parsedInternetHost = parseStringField(discover.output, fieldName: "internet_host") {
                            opts.internetHost = parsedInternetHost
                        }
                        if let parsedHost, !parsedHost.isEmpty {
                            discoveredHubHost = parsedHost
                        }
                        break
                    } else if isUnknownCommand(discover.output, command: "discover") {
                        discoverUnsupported = true
                        break
                    }
                }
                removeEphemeralStateDir(probeStateDir)
            }

            if discoverSuccess {
                emit(onProgress, .discover, .succeeded, nil)
            } else if let blockedReason = localDiscoveryBlockedReason, hasEnv {
                logs.append("[discover] multiple LAN hubs detected; keep existing paired profile.")
                emit(onProgress, .discover, .failed, blockedReason)
            } else if let blockedReason = localDiscoveryBlockedReason {
                emit(onProgress, .discover, .failed, blockedReason)
                emit(onProgress, .bootstrap, .skipped, "blocked_by_discover_failure")
                emit(onProgress, .connect, .skipped, "blocked_by_discover_failure")
                return HubRemoteConnectReport(
                    ok: false,
                    route: .none,
                    summary: blockedReason,
                    logLines: logs,
                    reasonCode: blockedReason
                )
            } else if discoverUnsupported {
                if let configuredHost = nonEmpty(opts.internetHost) {
                    discoveredHubHost = configuredHost
                    logs.append("[discover] axhubctl missing discover; use configured host: \(configuredHost)")
                    emit(onProgress, .discover, .skipped, "discover_unsupported_using_configured_host")
                } else if let cachedHost = nonEmpty(cachedPairing.host) {
                    discoveredHubHost = cachedHost
                    if let pair = cachedPairing.pairingPort {
                        opts.pairingPort = pair
                    }
                    if let grpc = cachedPairing.grpcPort {
                        opts.grpcPort = grpc
                    }
                    logs.append("[discover] axhubctl missing discover; use cached host: \(cachedHost)")
                    emit(onProgress, .discover, .skipped, "discover_unsupported_using_cached_host")
                } else {
                    let reason = "discover_unsupported_need_hub_host"
                    emit(onProgress, .discover, .failed, reason)
                    emit(onProgress, .bootstrap, .skipped, "blocked_by_discover_failure")
                    emit(onProgress, .connect, .skipped, "blocked_by_discover_failure")
                    return HubRemoteConnectReport(
                        ok: false,
                        route: .none,
                        summary: reason,
                        logLines: logs,
                        reasonCode: reason
                    )
                }
            } else if shouldRequireConfiguredHubHost(options: opts) {
                // Cross-device scenario: the configured host is authoritative; do not downgrade to localhost.
                discoveredHubHost = opts.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
                logs.append("[discover] fallback to configured host: \(discoveredHubHost ?? opts.internetHost)")
                emit(onProgress, .discover, .skipped, "using_configured_hub_host")
            } else if hasEnv {
                // Existing paired profile: continue with cached profile even if discover failed.
                let reason = inferFailureCode(from: lastDiscoverOutput, fallback: "discover_failed_using_cached_profile")
                emit(onProgress, .discover, .failed, reason)
            } else {
                let reason = inferFailureCode(from: lastDiscoverOutput, fallback: "discover_failed")
                emit(onProgress, .discover, .failed, reason)
                emit(onProgress, .bootstrap, .skipped, "blocked_by_discover_failure")
                emit(onProgress, .connect, .skipped, "blocked_by_discover_failure")
                return HubRemoteConnectReport(
                    ok: false,
                    route: .none,
                    summary: reason,
                    logLines: logs,
                    reasonCode: reason
                )
            }
        } else {
            emit(onProgress, .discover, .skipped, "bootstrap_disabled")
            emit(onProgress, .bootstrap, .skipped, "bootstrap_disabled")
        }

        if effectiveAllowBootstrap && !hasEnv {
            logs.append("[2/3] Pair + bootstrap (wait approval) ...")
            emit(onProgress, .bootstrap, .started, nil)
            let bootstrapHost = preferredBootstrapHub(discoveredHubHost: discoveredHubHost, options: opts)
            let bootstrap = runAxhubctl(
                args: [
                    "bootstrap",
                    "--hub", bootstrapHost,
                    "--pairing-port", "\(opts.pairingPort)",
                    "--grpc-port", "\(opts.grpcPort)",
                    "--device-name", opts.deviceName,
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 1_300.0
            )
            appendStepLogs(into: &logs, step: bootstrap)

            if bootstrap.exitCode != 0, shouldFallbackLegacyBootstrap(bootstrap.output) {
                logs.append("[bootstrap-fallback] bootstrap failed; try legacy knock/wait.")
                let fallbackResult = runLegacyBootstrapFlow(
                    options: opts,
                    hubHost: bootstrapHost,
                    grpcPort: opts.grpcPort,
                    preferredPairingPort: opts.pairingPort,
                    env: customEnv,
                    logs: &logs
                )
                if fallbackResult.ok {
                    opts.pairingPort = fallbackResult.pairingPort
                } else {
                    let reason = fallbackResult.reasonCode ?? "bootstrap_failed"
                    emit(onProgress, .bootstrap, .failed, reason)
                    emit(onProgress, .connect, .skipped, "blocked_by_bootstrap_failure")
                    return HubRemoteConnectReport(
                        ok: false,
                        route: .none,
                        summary: reason,
                        logLines: logs,
                        reasonCode: reason
                    )
                }
            } else if bootstrap.exitCode != 0 {
                let reason = inferFailureCode(from: bootstrap.output, fallback: "bootstrap_failed")
                emit(onProgress, .bootstrap, .failed, reason)
                emit(onProgress, .connect, .skipped, "blocked_by_bootstrap_failure")
                return HubRemoteConnectReport(
                    ok: false,
                    route: .none,
                    summary: reason,
                    logLines: logs,
                    reasonCode: reason
                )
            }
            emit(onProgress, .bootstrap, .succeeded, nil)
        } else if effectiveAllowBootstrap {
            logs.append("[2/3] Bootstrap already paired (cached profile).")
            emit(onProgress, .bootstrap, .succeeded, "already_paired")
        }

        var firstConnect = connectWithFallback(
            options: opts,
            primaryHubHost: discoveredHubHost,
            env: customEnv,
            logs: &logs,
            onProgress: onProgress,
            startProgress: true,
            autoReconnect: false
        )
        if firstConnect.ok {
            return firstConnect
        }

        // If one-click setup starts from an existing profile and connect fails, try a bootstrap refresh once.
        if effectiveAllowBootstrap && hasEnv {
            logs.append("[2/3] Refresh pairing via bootstrap (connect failed with cached profile) ...")
            emit(onProgress, .bootstrap, .started, "refresh")
            let refreshBootstrap = runAxhubctl(
                args: [
                    "bootstrap",
                    "--hub", preferredBootstrapHub(discoveredHubHost: discoveredHubHost, options: opts),
                    "--pairing-port", "\(opts.pairingPort)",
                    "--grpc-port", "\(opts.grpcPort)",
                    "--device-name", opts.deviceName,
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 1_300.0
            )
            appendStepLogs(into: &logs, step: refreshBootstrap)
            guard refreshBootstrap.exitCode == 0 else {
                let reason = inferFailureCode(from: refreshBootstrap.output, fallback: "bootstrap_refresh_failed")
                emit(onProgress, .bootstrap, .failed, reason)
                emit(onProgress, .connect, .failed, reason)
                return HubRemoteConnectReport(
                    ok: false,
                    route: .none,
                    summary: reason,
                    logLines: logs,
                    reasonCode: reason
                )
            }
            emit(onProgress, .bootstrap, .succeeded, "refresh")

            firstConnect = connectWithFallback(
                options: opts,
                primaryHubHost: discoveredHubHost,
                env: customEnv,
                logs: &logs,
                onProgress: onProgress,
                startProgress: true,
                autoReconnect: false
            )
            return firstConnect
        }

        return firstConnect
    }

    private func connectWithFallback(
        options opts: HubRemoteConnectOptions,
        primaryHubHost: String?,
        env customEnv: [String: String],
        logs: inout [String],
        onProgress: (@Sendable (HubRemoteProgressEvent) -> Void)?,
        startProgress: Bool,
        autoReconnect: Bool
    ) -> HubRemoteConnectReport {
        let preferredHub = preferredConnectHub(primaryHubHost: primaryHubHost, options: opts)
        let useAutoDiscovery = normalizeHost(preferredHub) == "auto"
        if autoReconnect {
            logs.append(useAutoDiscovery
                ? "[3/3] Connect + auto-reconnect probe (LAN first) ..."
                : "[3/3] Connect + auto-reconnect probe (preferred host: \(preferredHub)) ...")
        } else {
            logs.append(useAutoDiscovery
                ? "[3/3] Connect probe (LAN first) ..."
                : "[3/3] Connect probe (preferred host: \(preferredHub)) ...")
        }
        if startProgress {
            emit(onProgress, .connect, .started, "lan")
        }
        if hasHubEnv(stateDir: opts.stateDir), !hasInstalledClientKit(stateDir: opts.stateDir) {
            let repairHosts = connectRepairHosts(primaryHubHost: preferredHub, options: opts)
            if maybeInstallClientKit(
                options: opts,
                hosts: repairHosts,
                env: customEnv,
                logs: &logs
            ) {
                logs.append("[repair] client kit restored before connect probe.")
            }
        }
        var lanArgs: [String] = [
            "connect",
            "--hub", preferredHub,
            "--pairing-port", "\(opts.pairingPort)",
            "--grpc-port", "\(opts.grpcPort)",
            "--timeout-sec", "2",
        ]
        if autoReconnect {
            lanArgs += [
                "--auto-reconnect",
                "--max-failures", "4",
                "--max-backoff-sec", "10",
            ]
        }
        let lanConnect = runAxhubctl(
            args: lanArgs,
            options: opts,
            env: customEnv,
            timeoutSec: 90.0
        )
        appendStepLogs(into: &logs, step: lanConnect)
        if lanConnect.exitCode == 0 {
            emit(onProgress, .connect, .succeeded, "lan")
            return HubRemoteConnectReport(
                ok: true,
                route: .lan,
                summary: "connected_lan",
                logLines: logs,
                reasonCode: nil
            )
        }

        if isUnknownCommand(lanConnect.output, command: "connect") {
            return legacyConnectWithListModels(
                options: opts,
                env: customEnv,
                logs: &logs,
                onProgress: onProgress
            )
        }

        if opts.internetHost.isEmpty {
            let reason = inferFailureCode(from: lanConnect.output, fallback: "connect_failed")
            emit(onProgress, .connect, .failed, reason)
            return HubRemoteConnectReport(
                ok: false,
                route: .none,
                summary: reason,
                logLines: logs,
                reasonCode: reason
            )
        }

        logs.append("[fallback] Try internet host direct ...")
        var internetArgs: [String] = [
            "connect",
            "--hub", opts.internetHost,
            "--pairing-port", "\(opts.pairingPort)",
            "--grpc-port", "\(opts.grpcPort)",
            "--timeout-sec", "2",
        ]
        if autoReconnect {
            internetArgs += [
                "--auto-reconnect",
                "--max-failures", "4",
                "--max-backoff-sec", "12",
            ]
        }
        let internetConnect = runAxhubctl(
            args: internetArgs,
            options: opts,
            env: customEnv,
            timeoutSec: 90.0
        )
        appendStepLogs(into: &logs, step: internetConnect)
        if internetConnect.exitCode == 0 {
            emit(onProgress, .connect, .succeeded, "internet")
            return HubRemoteConnectReport(
                ok: true,
                route: .internet,
                summary: "connected_internet",
                logLines: logs,
                reasonCode: nil
            )
        }

        logs.append("[fallback] Install/refresh Mode3 tunnel + connect localhost ...")
        let tunnelInstall = runAxhubctl(
            args: [
                "tunnel",
                "--hub", opts.internetHost,
                "--grpc-port", "\(opts.grpcPort)",
                "--local-port", "\(opts.grpcPort)",
                "--install",
            ],
            options: opts,
            env: customEnv,
            timeoutSec: 90.0
        )
        appendStepLogs(into: &logs, step: tunnelInstall)

        var tunnelArgs: [String] = [
            "connect",
            "--hub", "127.0.0.1",
            "--grpc-port", "\(opts.grpcPort)",
            "--pairing-port", "\(opts.pairingPort)",
            "--timeout-sec", "2",
        ]
        if autoReconnect {
            tunnelArgs += [
                "--auto-reconnect",
                "--max-failures", "3",
                "--max-backoff-sec", "8",
            ]
        }
        let tunnelConnect = runAxhubctl(
            args: tunnelArgs,
            options: opts,
            env: customEnv,
            timeoutSec: 60.0
        )
        appendStepLogs(into: &logs, step: tunnelConnect)
        if tunnelConnect.exitCode == 0 {
            emit(onProgress, .connect, .succeeded, "tunnel")
            return HubRemoteConnectReport(
                ok: true,
                route: .internetTunnel,
                summary: "connected_internet_tunnel",
                logLines: logs,
                reasonCode: nil
            )
        }

        let reason = inferFailureCode(
            from: [tunnelConnect.output, tunnelInstall.output, internetConnect.output, lanConnect.output]
                .joined(separator: "\n"),
            fallback: "connect_failed_after_internet_fallback"
        )
        emit(onProgress, .connect, .failed, reason)
        return HubRemoteConnectReport(
            ok: false,
            route: .none,
            summary: reason,
            logLines: logs,
            reasonCode: reason
        )
    }

    private func preferredConnectHub(
        primaryHubHost: String?,
        options: HubRemoteConnectOptions
    ) -> String {
        if let discovered = nonEmpty(primaryHubHost) {
            return normalizedConnectHostCandidate(discovered)
        }
        if let configured = nonEmpty(options.internetHost) {
            return normalizedConnectHostCandidate(configured)
        }
        let cachedPairing = loadCachedPairingInfo(stateDir: options.stateDir)
        if let cachedHost = nonEmpty(cachedPairing.host), !isLoopbackHost(cachedHost) {
            return normalizedConnectHostCandidate(cachedHost)
        }
        return "auto"
    }

    func detectPorts(
        options rawOptions: HubRemoteConnectOptions,
        candidates rawCandidates: [Int] = [50052, 50053, 50054, 50055, 50056]
    ) async -> HubRemotePortProbeResult {
        let opts = sanitize(rawOptions)
        let customEnv = discoveryEnv(internetHost: opts.internetHost)
        let cachedPairing = loadCachedPairingInfo(stateDir: opts.stateDir)
        var logs: [String] = []

        let normalized = rawCandidates
            .map { max(1, min(65_535, $0)) }
        let candidates = Array(Set(normalized)).sorted()
        if candidates.isEmpty {
            return HubRemotePortProbeResult(
                ok: false,
                pairingPort: opts.pairingPort,
                grpcPort: opts.grpcPort,
                reasonCode: "no_port_candidates",
                candidates: [],
                logLines: ["port probe candidates are empty"]
            )
        }

        var lastOutput = ""
        var discoverUnsupported = false
        if !shouldRequireConfiguredHubHost(options: opts) {
            let lanFallback = await discoverHubOnLAN(
                options: opts,
                pairingPorts: candidates,
                cachedPairing: cachedPairing
            )
            logs.append(contentsOf: lanFallback.logLines)
            if let candidate = lanFallback.candidate {
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: candidate.pairingPort,
                    grpcPort: candidate.grpcPort,
                    reasonCode: nil,
                    candidates: [summary(from: candidate)],
                    logLines: logs
                )
            }
            if let blockedReason = lanFallback.reasonCode {
                return HubRemotePortProbeResult(
                    ok: false,
                    pairingPort: opts.pairingPort,
                    grpcPort: opts.grpcPort,
                    reasonCode: blockedReason,
                    candidates: lanFallback.candidates.map(summary(from:)),
                    logLines: logs
                )
            }
        }

        let probeStateDir = makeEphemeralStateDir(prefix: "xterminal_port_probe")
        var probeOptions = opts
        probeOptions.stateDir = probeStateDir
        for p in candidates {
            let step = runAxhubctl(
                args: [
                    "discover",
                    "--pairing-port", "\(p)",
                    "--timeout-sec", "2",
                ],
                options: probeOptions,
                env: customEnv,
                timeoutSec: 12.0
            )
            appendStepLogs(into: &logs, step: step)
            lastOutput = step.output
            if step.exitCode == 0 {
                let parsedHost = parseStringField(step.output, fieldName: "host")
                if shouldRequireConfiguredHubHost(options: opts),
                   !hostMatchesConfiguredHost(discoveredHost: parsedHost, options: opts) {
                    logs.append("[port-detect] ignore host mismatch (want \(opts.internetHost), got \(parsedHost ?? "unknown"))")
                    continue
                }
                let parsedPair = parsePortField(step.output, fieldName: "pairing_port") ?? p
                let parsedGrpc = parsePortField(step.output, fieldName: "grpc_port") ?? opts.grpcPort
                removeEphemeralStateDir(probeStateDir)
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: parsedPair,
                    grpcPort: parsedGrpc,
                    reasonCode: nil,
                    candidates: [],
                    logLines: logs
                )
            } else if isUnknownCommand(step.output, command: "discover") {
                discoverUnsupported = true
                break
            }
        }
        removeEphemeralStateDir(probeStateDir)

        if discoverUnsupported {
            if let pair = loadCachedPairingInfo(stateDir: opts.stateDir).pairingPort,
               let grpc = loadCachedPairingInfo(stateDir: opts.stateDir).grpcPort {
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: pair,
                    grpcPort: grpc,
                    reasonCode: nil,
                    candidates: [],
                    logLines: logs + ["[port-detect] discover unsupported; using cached pairing/grpc ports."]
                )
            }
            if nonEmpty(opts.internetHost) != nil {
                return HubRemotePortProbeResult(
                    ok: true,
                    pairingPort: opts.pairingPort,
                    grpcPort: opts.grpcPort,
                    reasonCode: nil,
                    candidates: [],
                    logLines: logs + ["[port-detect] discover unsupported; keep configured ports."]
                )
            }
            return HubRemotePortProbeResult(
                ok: false,
                pairingPort: opts.pairingPort,
                grpcPort: opts.grpcPort,
                reasonCode: "discover_unsupported",
                candidates: [],
                logLines: logs
            )
        }

        let reason = inferFailureCode(from: lastOutput, fallback: "port_probe_failed")
        return HubRemotePortProbeResult(
            ok: false,
            pairingPort: opts.pairingPort,
            grpcPort: opts.grpcPort,
            reasonCode: reason,
            candidates: [],
            logLines: logs
        )
    }

    func pinDiscoveredHubCandidate(
        _ candidate: HubDiscoveredHubCandidateSummary,
        options rawOptions: HubRemoteConnectOptions
    ) throws {
        let opts = sanitize(rawOptions)
        try persistDiscoveredPairingInfo(
            host: candidate.host,
            pairingPort: candidate.pairingPort,
            grpcPort: candidate.grpcPort,
            internetHost: nonEmpty(candidate.internetHost) ?? nonEmpty(opts.internetHost),
            hubInstanceID: candidate.hubInstanceID,
            lanDiscoveryName: candidate.lanDiscoveryName,
            options: opts
        )
    }

    func resetLocalPairingState(stateDir: URL?) -> HubRemoteResetResult {
        let base = stateDir ?? defaultStateDir()
        let fm = FileManager.default
        var logs: [String] = []

        let pathsToDelete: [URL] = [
            base.appendingPathComponent("pairing.env"),
            base.appendingPathComponent("hub.env"),
            base.appendingPathComponent("connection.json"),
            base.appendingPathComponent("client_kit", isDirectory: true),
            base.appendingPathComponent("chat.env"),
            base.appendingPathComponent("tunnel.env"),
            base.appendingPathComponent("tunnel_config.env"),
            base.appendingPathComponent("tls", isDirectory: true),
        ]

        for url in pathsToDelete {
            if fm.fileExists(atPath: url.path) {
                do {
                    try fm.removeItem(at: url)
                    logs.append("removed: \(url.path)")
                } catch {
                    logs.append("remove_failed: \(url.path) (\(error.localizedDescription))")
                    return HubRemoteResetResult(
                        ok: false,
                        reasonCode: "reset_failed",
                        logLines: logs
                    )
                }
            } else {
                logs.append("skip_missing: \(url.lastPathComponent)")
            }
        }

        return HubRemoteResetResult(
            ok: true,
            reasonCode: nil,
            logLines: logs
        )
    }

    func fetchRemoteModels(options rawOptions: HubRemoteConnectOptions) -> HubRemoteModelsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let env: [String: String] = [:]

        var list = runAxhubctl(
            args: ["list-models"],
            options: opts,
            env: env,
            timeoutSec: 60.0
        )
        appendStepLogs(into: &logs, step: list)

        if list.exitCode != 0, shouldRetryAfterClientKitInstall(list.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: env,
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                list = runAxhubctl(
                    args: ["list-models"],
                    options: opts,
                    env: env,
                    timeoutSec: 60.0
                )
                appendStepLogs(into: &logs, step: list)
            }
        }

        guard list.exitCode == 0 else {
            let reason = inferFailureCode(from: list.output, fallback: "remote_models_list_failed")
            return HubRemoteModelsResult(
                ok: false,
                models: [],
                reasonCode: reason,
                logLines: logs
            )
        }

        let models = parseListModelsOutput(list.output)
        return HubRemoteModelsResult(
            ok: true,
            models: models,
            reasonCode: nil,
            logLines: logs
        )
    }

    func generateRemoteText(
        options rawOptions: HubRemoteConnectOptions,
        modelId rawModelId: String?,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        taskType: String,
        appId: String?,
        projectId: String?,
        sessionId: String?,
        failClosedOnDowngrade: Bool = false,
        requestId: String?
    ) -> HubRemoteGenerateResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let modelId = rawModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let promptText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptText.isEmpty else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                modelId: nil,
                reasonCode: "prompt_empty",
                logLines: ["prompt is empty for remote generate"]
            )
        }

        let limitedMaxTokens = max(1, min(8192, maxTokens))
        let limitedTemp = max(0, min(2, temperature))
        let limitedTopP = max(0.01, min(1.0, topP))
        let limitedTaskType = nonEmpty(taskType) ?? "assist"
        let limitedAppId = nonEmpty(appId) ?? "x_terminal"
        let limitedProjectId = nonEmpty(projectId) ?? ""
        let limitedSessionId = nonEmpty(sessionId) ?? ""
        let limitedReqId = nonEmpty(requestId) ?? "gen_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6))"

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                modelId: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                modelId: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        var nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        if nodeBin == nil {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
            }
        }
        guard let nodeBin else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                modelId: nil,
                reasonCode: "node_missing",
                logLines: logs + [
                    "missing node runtime for remote generate",
                    "looked for bundled X-Terminal node, client_kit/bin/relflowhub_node, and system node"
                ]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_GEN_REQUEST_ID"] = limitedReqId
        scriptEnv["XTERMINAL_GEN_MODEL_ID"] = modelId
        scriptEnv["XTERMINAL_GEN_TASK_TYPE"] = limitedTaskType
        scriptEnv["XTERMINAL_GEN_APP_ID"] = limitedAppId
        scriptEnv["XTERMINAL_GEN_PROJECT_ID"] = limitedProjectId
        scriptEnv["XTERMINAL_GEN_SESSION_ID"] = limitedSessionId
        scriptEnv["XTERMINAL_GEN_PROMPT_B64"] = Data(prompt.utf8).base64EncodedString()
        scriptEnv["XTERMINAL_GEN_MAX_TOKENS"] = "\(limitedMaxTokens)"
        scriptEnv["XTERMINAL_GEN_TEMPERATURE"] = "\(limitedTemp)"
        scriptEnv["XTERMINAL_GEN_TOP_P"] = "\(limitedTopP)"
        scriptEnv["XTERMINAL_GEN_TIMEOUT_SEC"] = "240"
        scriptEnv["XTERMINAL_GEN_FAIL_CLOSED_ON_DOWNGRADE"] = failClosedOnDowngrade ? "1" : "0"

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteGenerateScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 300.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        func decodeGenerateStep(_ step: StepOutput) -> RemoteGenerateScriptResult? {
            guard let jsonLine = extractTrailingJSONObjectLine(step.output),
                  let data = jsonLine.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(RemoteGenerateScriptResult.self, from: data) else {
                return nil
            }
            return decoded
        }

        func normalizedFailureReason(
            from decoded: RemoteGenerateScriptResult,
            step: StepOutput,
            fallback: String
        ) -> String {
            let rawReason = nonEmpty(decoded.errorCode)
                ?? nonEmpty(decoded.reason)
                ?? nonEmpty(decoded.errorMessage)
            return normalizedRemoteReasonCode(
                rawReason: rawReason,
                stepOutput: step.output,
                fallback: fallback
            )
        }

        func finalizeGenerateStep(_ step: StepOutput) -> HubRemoteGenerateResult {
            guard let decoded = decodeGenerateStep(step) else {
                let reason = inferFailureCode(from: step.output, fallback: "remote_chat_failed")
                return HubRemoteGenerateResult(
                    ok: false,
                    text: "",
                    modelId: nil,
                    reasonCode: reason,
                    logLines: logs
                )
            }

            guard decoded.ok == true else {
                return HubRemoteGenerateResult(
                    ok: false,
                    text: "",
                    modelId: nil,
                    reasonCode: normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_failed"),
                    logLines: logs
                )
            }

            guard let success = Self.successfulRemoteGenerateResult(
                from: decoded,
                fallbackModelId: modelId,
                logLines: logs
            ) else {
                return HubRemoteGenerateResult(
                    ok: false,
                    text: "",
                    reasonCode: normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_empty_output"),
                    logLines: logs
                )
            }

            return success
        }

        guard let decoded = decodeGenerateStep(step) else {
            let reason = inferFailureCode(from: step.output, fallback: "remote_chat_failed")
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                reasonCode: reason,
                logLines: logs
            )
        }

        if decoded.ok != true {
            let reason = normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_failed")
            if reason == "grant_required" {
                let paidModelId = nonEmpty(decoded.modelId) ?? nonEmpty(modelId)
                if let paidModelId {
                    let grant = requestRemotePaidAIGrant(
                        options: opts,
                        modelId: paidModelId,
                        appId: limitedAppId,
                        requestedSeconds: 1800,
                        requestedTokenCap: min(5000, max(1024, limitedMaxTokens * 2)),
                        reason: "x_terminal paid generate \(limitedTaskType)",
                        projectId: limitedProjectId.isEmpty ? nil : limitedProjectId
                    )
                    logs.append(contentsOf: grant.logLines)

                    switch grant.decision {
                    case .approved where grant.ok:
                        step = runScript()
                        appendStepLogs(into: &logs, step: step)
                        return finalizeGenerateStep(step)
                    case .queued:
                        return HubRemoteGenerateResult(
                            ok: false,
                            text: "",
                            reasonCode: "grant_pending",
                            logLines: logs
                        )
                    case .denied:
                        return HubRemoteGenerateResult(
                            ok: false,
                            text: "",
                            reasonCode: grant.reasonCode ?? "grant_denied",
                            logLines: logs
                        )
                    case .failed, .approved:
                        return HubRemoteGenerateResult(
                            ok: false,
                            text: "",
                            reasonCode: grant.reasonCode ?? reason,
                            logLines: logs
                        )
                    }
                }
            }

            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                reasonCode: reason,
                logLines: logs
            )
        }

        guard let success = Self.successfulRemoteGenerateResult(
            from: decoded,
            fallbackModelId: modelId,
            logLines: logs
        ) else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                reasonCode: normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_empty_output"),
                logLines: logs
            )
        }

        return success
    }

    func requestRemoteNetworkGrant(
        options rawOptions: HubRemoteConnectOptions,
        requestedSeconds: Int,
        reason: String?,
        projectId: String? = nil
    ) -> HubRemoteGrantResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for client kit grant request"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_GRANT_CAPABILITY"] = "CAPABILITY_WEB_FETCH"
        scriptEnv["XTERMINAL_GRANT_SECONDS"] = "\(max(30, min(86_400, requestedSeconds)))"
        scriptEnv["XTERMINAL_GRANT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_GRANT_WAIT_SEC"] = "10"
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runGrantScript() -> StepOutput {
            do {
                let script = remoteNetworkGrantScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 28.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runGrantScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runGrantScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteNetworkGrantScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_grant_failed")
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let decisionToken = (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mappedDecision: HubRemoteGrantDecision = {
            switch decisionToken {
            case "approved":
                return .approved
            case "queued":
                return .queued
            case "denied":
                return .denied
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision == .approved || mappedDecision == .queued)
        let rawReasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
        let reasonCode = rawReasonCode.map {
            normalizedRemoteReasonCode(
                rawReason: $0,
                stepOutput: step.output,
                fallback: "remote_grant_failed"
            )
        } ?? (ok ? nil : normalizedRemoteReasonCode(
            rawReason: nil,
            stepOutput: step.output,
            fallback: "remote_grant_failed"
        ))

        let expiresAtSec: Double? = {
            guard let ms = decoded.expiresAtMs, ms > 0 else { return nil }
            return ms / 1000.0
        }()

        return HubRemoteGrantResult(
            ok: ok,
            decision: mappedDecision,
            grantRequestId: nonEmpty(decoded.grantRequestId),
            expiresAtSec: expiresAtSec,
            reasonCode: reasonCode,
            logLines: logs
        )
    }

    func requestRemotePaidAIGrant(
        options rawOptions: HubRemoteConnectOptions,
        modelId rawModelId: String,
        appId rawAppId: String? = nil,
        requestedSeconds: Int,
        requestedTokenCap: Int,
        reason: String?,
        projectId: String? = nil
    ) -> HubRemoteGrantResult {
        let paidModelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paidModelId.isEmpty else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "grant_model_id_missing",
                logLines: ["missing model id for paid AI grant request"]
            )
        }

        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for paid AI grant request"]
            )
        }

        var scriptEnv = merged
        let effectiveAppId = canonicalHubAppID(rawAppId) ?? ""
        if !effectiveAppId.isEmpty {
            scriptEnv["HUB_APP_ID"] = effectiveAppId
        }
        scriptEnv["XTERMINAL_GRANT_CAPABILITY"] = "CAPABILITY_AI_GENERATE_PAID"
        scriptEnv["XTERMINAL_GRANT_MODEL_ID"] = paidModelId
        scriptEnv["XTERMINAL_GRANT_SECONDS"] = "\(max(30, min(86_400, requestedSeconds)))"
        scriptEnv["XTERMINAL_GRANT_TOKEN_CAP"] = "\(max(0, min(5000, requestedTokenCap)))"
        scriptEnv["XTERMINAL_GRANT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_GRANT_WAIT_SEC"] = "10"
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runGrantScript() -> StepOutput {
            do {
                let script = remoteNetworkGrantScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 28.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runGrantScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runGrantScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteNetworkGrantScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_paid_grant_failed")
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let decisionToken = (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mappedDecision: HubRemoteGrantDecision = {
            switch decisionToken {
            case "approved":
                return .approved
            case "queued":
                return .queued
            case "denied":
                return .denied
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision == .approved || mappedDecision == .queued)
        let rawReasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
        let reasonCode = rawReasonCode.map {
            normalizedRemoteReasonCode(
                rawReason: $0,
                stepOutput: step.output,
                fallback: "remote_paid_grant_failed"
            )
        } ?? (ok ? nil : normalizedRemoteReasonCode(
            rawReason: nil,
            stepOutput: step.output,
            fallback: "remote_paid_grant_failed"
        ))

        let expiresAtSec: Double? = {
            guard let ms = decoded.expiresAtMs, ms > 0 else { return nil }
            return ms / 1000.0
        }()

        return HubRemoteGrantResult(
            ok: ok,
            decision: mappedDecision,
            grantRequestId: nonEmpty(decoded.grantRequestId),
            expiresAtSec: expiresAtSec,
            reasonCode: reasonCode,
            logLines: logs
        )
    }

    func requestRemoteWebFetch(
        options rawOptions: HubRemoteConnectOptions,
        url: String,
        timeoutSec: Double,
        maxBytes: Int
    ) -> HubRemoteWebFetchResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let requestURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestURL.isEmpty else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "empty_url",
                reasonCode: "empty_url",
                logLines: ["empty url for web fetch"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "hub_env_missing",
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "client_kit_missing",
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "node_missing",
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote web fetch"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_FETCH_URL"] = requestURL
        scriptEnv["XTERMINAL_FETCH_TIMEOUT_SEC"] = String(max(2.0, min(60.0, timeoutSec)))
        scriptEnv["XTERMINAL_FETCH_MAX_BYTES"] = String(max(1024, min(5_000_000, maxBytes)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runFetchScript() -> StepOutput {
            do {
                let script = remoteWebFetchScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: max(8.0, min(90.0, timeoutSec + 20.0)),
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runFetchScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runFetchScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteWebFetchScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_web_fetch_failed")
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: requestURL,
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: fallback,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (decoded.ok == true ? nil : "remote_web_fetch_failed")
        let message = nonEmpty(decoded.errorMessage)
            ?? nonEmpty(decoded.reason)

        return HubRemoteWebFetchResult(
            ok: decoded.ok ?? false,
            status: decoded.status ?? 0,
            finalURL: nonEmpty(decoded.finalURL) ?? requestURL,
            contentType: nonEmpty(decoded.contentType) ?? "",
            truncated: decoded.truncated ?? false,
            bytes: decoded.bytes ?? 0,
            text: decoded.text ?? "",
            errorMessage: message,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func syncRemoteProjectSnapshot(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteProjectSyncPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let pid = payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "project_id_empty", logLines: ["project_id is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote project sync"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SYNC_PROJECT_ID"] = pid
        scriptEnv["XTERMINAL_SYNC_ROOT_PATH"] = payload.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SYNC_DISPLAY_NAME"] = payload.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SYNC_STATUS_DIGEST"] = payload.statusDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SYNC_LAST_SUMMARY_AT"] = payload.lastSummaryAt.map { String($0) } ?? ""
        scriptEnv["XTERMINAL_SYNC_LAST_EVENT_AT"] = payload.lastEventAt.map { String($0) } ?? ""
        scriptEnv["XTERMINAL_SYNC_UPDATED_AT"] = payload.updatedAt.map { String($0) } ?? String(Date().timeIntervalSince1970)

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteProjectSyncScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_project_sync_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_project_sync_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func appendRemoteProjectConversationTurn(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteProjectConversationPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let pid = payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let threadKey = payload.threadKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestId = payload.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = payload.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantText = payload.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "project_id_empty", logLines: ["conversation project_id is empty"])
        }
        guard !threadKey.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "thread_key_empty", logLines: ["conversation thread_key is empty"])
        }
        guard !requestId.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "request_id_empty", logLines: ["conversation request_id is empty"])
        }
        guard !userText.isEmpty || !assistantText.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "turn_empty", logLines: ["conversation turn payload is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote project conversation append"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_CONV_PROJECT_ID"] = pid
        scriptEnv["XTERMINAL_CONV_THREAD_KEY"] = threadKey
        scriptEnv["XTERMINAL_CONV_REQUEST_ID"] = requestId
        scriptEnv["XTERMINAL_CONV_CREATED_AT_MS"] = String(max(Int64(0), payload.createdAtMs))
        scriptEnv["XTERMINAL_CONV_USER_TEXT"] = userText
        scriptEnv["XTERMINAL_CONV_ASSISTANT_TEXT"] = assistantText

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteProjectConversationAppendScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_project_conversation_append_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_project_conversation_append_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func appendRemoteSupervisorConversationTurn(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteSupervisorConversationPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let threadKey = payload.threadKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestId = payload.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = payload.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantText = payload.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !threadKey.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "thread_key_empty", logLines: ["conversation thread_key is empty"])
        }
        guard !requestId.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "request_id_empty", logLines: ["conversation request_id is empty"])
        }
        guard !userText.isEmpty || !assistantText.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "turn_empty", logLines: ["conversation turn payload is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote supervisor conversation append"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SUPERVISOR_CONV_THREAD_KEY"] = threadKey
        scriptEnv["XTERMINAL_SUPERVISOR_CONV_REQUEST_ID"] = requestId
        scriptEnv["XTERMINAL_SUPERVISOR_CONV_CREATED_AT_MS"] = String(max(Int64(0), payload.createdAtMs))
        scriptEnv["XTERMINAL_SUPERVISOR_CONV_USER_TEXT"] = userText
        scriptEnv["XTERMINAL_SUPERVISOR_CONV_ASSISTANT_TEXT"] = assistantText

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = self.remoteSupervisorConversationAppendScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_supervisor_conversation_append_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_supervisor_conversation_append_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func upsertRemoteProjectCanonicalMemory(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteProjectCanonicalMemoryPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let projectId = payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectId.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "project_id_empty", logLines: ["canonical memory project_id is empty"])
        }

        let items = payload.items.compactMap { raw -> HubRemoteCanonicalMemoryItem? in
            let key = raw.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = raw.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return HubRemoteCanonicalMemoryItem(key: key, value: value)
        }
        guard !items.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "canonical_memory_items_empty", logLines: ["canonical memory payload is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        guard let itemsData = try? JSONEncoder().encode(items) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "canonical_memory_encode_failed", logLines: ["failed to encode canonical memory items"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote project canonical memory upsert"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_PROJECT_MEMORY_PROJECT_ID"] = projectId
        scriptEnv["XTERMINAL_PROJECT_MEMORY_ITEMS_B64"] = itemsData.base64EncodedString()

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteProjectCanonicalMemoryUpsertScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_project_canonical_memory_upsert_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_project_canonical_memory_upsert_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func upsertRemoteDeviceCanonicalMemory(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteDeviceCanonicalMemoryPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let items = payload.items.compactMap { raw -> HubRemoteCanonicalMemoryItem? in
            let key = raw.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = raw.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return HubRemoteCanonicalMemoryItem(key: key, value: value)
        }
        guard !items.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "device_canonical_memory_items_empty", logLines: ["device canonical memory payload is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        guard let itemsData = try? JSONEncoder().encode(items) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "device_canonical_memory_encode_failed", logLines: ["failed to encode device canonical memory items"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote device canonical memory upsert"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_DEVICE_MEMORY_ITEMS_B64"] = itemsData.base64EncodedString()

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteDeviceCanonicalMemoryUpsertScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_device_canonical_memory_upsert_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_device_canonical_memory_upsert_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func pushRemoteNotificationMemory(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteNotificationPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "title_empty", logLines: ["notification title is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote notification"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_NOTIFY_SOURCE"] = payload.source.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_NOTIFY_TITLE"] = title
        scriptEnv["XTERMINAL_NOTIFY_BODY"] = payload.body.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_NOTIFY_DEDUPE"] = payload.dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_NOTIFY_ACTION_URL"] = payload.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_NOTIFY_UNREAD"] = payload.unread ? "1" : "0"

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteNotificationScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_notification_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_notification_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func searchRemoteSkills(
        options rawOptions: HubRemoteConnectOptions,
        query: String,
        sourceFilter: String?,
        projectId: String?,
        limit: Int
    ) -> HubRemoteSkillsSearchResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let boundedLimit = max(1, min(100, limit))

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSkillsSearchResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                results: [],
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                officialChannelStatus: nil,
                logLines: ["hub env or client kit missing for remote skills search"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteSkillsSearchResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                results: [],
                reasonCode: "node_missing",
                officialChannelStatus: nil,
                logLines: ["missing node runtime for remote skills search"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SKILLS_QUERY"] = query.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SKILLS_SOURCE_FILTER"] = sourceFilter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SKILLS_LIMIT"] = String(boundedLimit)
        scriptEnv["XTERMINAL_SKILLS_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSkillsSearchScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSkillsSearchScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_skills_search_failed")
            return HubRemoteSkillsSearchResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                results: [],
                reasonCode: fallback,
                officialChannelStatus: nil,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_skills_search_failed")
        let results = (decoded.results ?? []).compactMap { row -> HubRemoteSkillCatalogEntry? in
            let skillID = nonEmpty(row.skillID) ?? ""
            guard !skillID.isEmpty else { return nil }
            return HubRemoteSkillCatalogEntry(
                skillID: skillID,
                name: nonEmpty(row.name) ?? skillID,
                version: nonEmpty(row.version) ?? "",
                description: nonEmpty(row.description) ?? "",
                publisherID: nonEmpty(row.publisherID) ?? "",
                capabilitiesRequired: row.capabilitiesRequired ?? [],
                sourceID: nonEmpty(row.sourceID) ?? "",
                packageSHA256: nonEmpty(row.packageSHA256) ?? "",
                installHint: nonEmpty(row.installHint) ?? "",
                riskLevel: nonEmpty(row.riskLevel) ?? "low",
                requiresGrant: row.requiresGrant ?? false,
                sideEffectClass: nonEmpty(row.sideEffectClass) ?? ""
            )
        }
        let officialChannelStatus = decoded.officialChannelStatus.map { row in
            HubRemoteOfficialSkillChannelStatus(
                channelID: nonEmpty(row.channelID) ?? "official-stable",
                status: nonEmpty(row.status) ?? "",
                updatedAtMs: max(0, row.updatedAtMs ?? 0),
                lastAttemptAtMs: max(0, row.lastAttemptAtMs ?? 0),
                lastSuccessAtMs: max(0, row.lastSuccessAtMs ?? 0),
                skillCount: max(0, row.skillCount ?? 0),
                errorCode: nonEmpty(row.errorCode) ?? "",
                maintenanceEnabled: row.maintenanceEnabled ?? false,
                maintenanceIntervalMs: max(0, row.maintenanceIntervalMs ?? 0),
                maintenanceLastRunAtMs: max(0, row.maintenanceLastRunAtMs ?? 0),
                maintenanceSourceKind: nonEmpty(row.maintenanceSourceKind) ?? "",
                lastTransitionAtMs: max(0, row.lastTransitionAtMs ?? 0),
                lastTransitionKind: nonEmpty(row.lastTransitionKind) ?? "",
                lastTransitionSummary: nonEmpty(row.lastTransitionSummary) ?? ""
            )
        }

        return HubRemoteSkillsSearchResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            results: results,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            officialChannelStatus: officialChannelStatus,
            logLines: logs
        )
    }

    func setRemoteSkillPin(
        options rawOptions: HubRemoteConnectOptions,
        scope: String,
        skillId: String,
        packageSHA256: String,
        projectId: String?,
        note: String?,
        requestId: String?
    ) -> HubRemoteSkillPinResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSkillId = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard normalizedScope == "global" || normalizedScope == "project" else {
            return HubRemoteSkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "unsupported_skill_pin_scope",
                logLines: ["unsupported skill pin scope: \(normalizedScope)"]
            )
        }
        if normalizedScope == "project", normalizedProjectId.isEmpty {
            return HubRemoteSkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: "",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_project_id",
                logLines: ["project scope skill pin requires project id"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote skill pin"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteSkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote skill pin"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SKILLS_PIN_SCOPE"] = normalizedScope
        scriptEnv["XTERMINAL_SKILLS_PIN_SKILL_ID"] = normalizedSkillId
        scriptEnv["XTERMINAL_SKILLS_PIN_PACKAGE_SHA256"] = normalizedPackageSHA256
        scriptEnv["XTERMINAL_SKILLS_PIN_PROJECT_ID"] = normalizedProjectId
        scriptEnv["XTERMINAL_SKILLS_PIN_NOTE"] = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SKILLS_PIN_REQUEST_ID"] = requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSkillPinScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSkillPinScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_skill_pin_failed")
            return HubRemoteSkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_skill_pin_failed")

        return HubRemoteSkillPinResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            scope: nonEmpty(decoded.scope) ?? normalizedScope,
            userId: nonEmpty(decoded.userId) ?? "",
            projectId: nonEmpty(decoded.projectId) ?? normalizedProjectId,
            skillId: nonEmpty(decoded.skillId) ?? normalizedSkillId,
            packageSHA256: nonEmpty(decoded.packageSHA256) ?? normalizedPackageSHA256,
            previousPackageSHA256: nonEmpty(decoded.previousPackageSHA256) ?? "",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteResolvedSkills(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?
    ) -> HubRemoteResolvedSkillsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteResolvedSkillsResult(
                ok: false,
                source: "hub_runtime_grpc",
                skills: [],
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote resolved skills request"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteResolvedSkillsResult(
                ok: false,
                source: "hub_runtime_grpc",
                skills: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote resolved skills request"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_RESOLVED_SKILLS_PROJECT_ID"] = normalizedProjectId

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteResolvedSkillsScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteResolvedSkillsScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_resolved_skills_failed")
            return HubRemoteResolvedSkillsResult(
                ok: false,
                source: "hub_runtime_grpc",
                skills: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_resolved_skills_failed")
        let skills = (decoded.skills ?? []).compactMap { row -> HubRemoteResolvedSkillEntry? in
            guard let skillRow = row.skill else { return nil }
            let skillID = nonEmpty(skillRow.skillID) ?? ""
            guard !skillID.isEmpty else { return nil }
            let skill = HubRemoteSkillCatalogEntry(
                skillID: skillID,
                name: nonEmpty(skillRow.name) ?? skillID,
                version: nonEmpty(skillRow.version) ?? "",
                description: nonEmpty(skillRow.description) ?? "",
                publisherID: nonEmpty(skillRow.publisherID) ?? "",
                capabilitiesRequired: skillRow.capabilitiesRequired ?? [],
                sourceID: nonEmpty(skillRow.sourceID) ?? "",
                packageSHA256: nonEmpty(skillRow.packageSHA256) ?? "",
                installHint: nonEmpty(skillRow.installHint) ?? "",
                riskLevel: nonEmpty(skillRow.riskLevel) ?? "low",
                requiresGrant: skillRow.requiresGrant ?? false,
                sideEffectClass: nonEmpty(skillRow.sideEffectClass) ?? ""
            )
            return HubRemoteResolvedSkillEntry(
                scope: nonEmpty(row.scope) ?? "",
                skill: skill
            )
        }

        return HubRemoteResolvedSkillsResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            skills: skills,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func stageRemoteAgentImport(
        options rawOptions: HubRemoteConnectOptions,
        importManifestJSON: String,
        findingsJSON: String?,
        scanInputJSON: String?,
        requestedBy: String?,
        note: String?,
        requestId: String?
    ) -> HubRemoteAgentImportStageResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let manifestText = importManifestJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifestText.isEmpty else {
            return HubRemoteAgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: "missing_agent_import_manifest",
                logLines: ["agent import manifest is empty"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteAgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteAgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteAgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote agent import stage"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_AGENT_IMPORT_MANIFEST_JSON"] = manifestText
        scriptEnv["XTERMINAL_AGENT_IMPORT_FINDINGS_JSON"] = findingsJSON ?? ""
        scriptEnv["XTERMINAL_AGENT_IMPORT_SCAN_INPUT_JSON"] = scanInputJSON ?? ""
        scriptEnv["XTERMINAL_AGENT_IMPORT_REQUESTED_BY"] = requestedBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_AGENT_IMPORT_NOTE"] = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_AGENT_IMPORT_REQUEST_ID"] = requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteAgentImportStageScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteAgentImportStageScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_agent_import_stage_failed")
            return HubRemoteAgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_agent_import_stage_failed")

        return HubRemoteAgentImportStageResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            stagingId: nonEmpty(decoded.stagingId),
            status: nonEmpty(decoded.status),
            auditRef: nonEmpty(decoded.auditRef),
            preflightStatus: nonEmpty(decoded.preflightStatus),
            skillId: nonEmpty(decoded.skillId),
            policyScope: nonEmpty(decoded.policyScope),
            findingsCount: max(0, decoded.findingsCount ?? 0),
            vetterStatus: nonEmpty(decoded.vetterStatus),
            vetterCriticalCount: max(0, decoded.vetterCriticalCount ?? 0),
            vetterWarnCount: max(0, decoded.vetterWarnCount ?? 0),
            vetterAuditRef: nonEmpty(decoded.vetterAuditRef),
            recordPath: nonEmpty(decoded.recordPath),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteAgentImportRecord(
        options rawOptions: HubRemoteConnectOptions,
        stagingId: String
    ) -> HubRemoteAgentImportRecordResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedStagingId = stagingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStagingId.isEmpty else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: "missing_agent_staging_id",
                logLines: ["agent import staging id is empty"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote agent import record"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote agent import record"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_AGENT_IMPORT_STAGING_ID"] = normalizedStagingId
        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteAgentImportRecordScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteAgentImportRecordScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_agent_import_record_failed")
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_agent_import_record_failed")

        return HubRemoteAgentImportRecordResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            selector: nonEmpty(decoded.selector),
            stagingId: nonEmpty(decoded.stagingId),
            status: nonEmpty(decoded.status),
            auditRef: nonEmpty(decoded.auditRef),
            schemaVersion: nonEmpty(decoded.schemaVersion),
            skillId: nonEmpty(decoded.skillId),
            projectId: nonEmpty(decoded.projectId),
            recordJSON: nonEmpty(decoded.recordJSON),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteResolvedAgentImportRecord(
        options rawOptions: HubRemoteConnectOptions,
        selector: String,
        skillId: String?,
        projectId: String?
    ) -> HubRemoteAgentImportRecordResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSkillId = skillId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedSelector.isEmpty else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: "missing_agent_import_selector",
                logLines: ["agent import selector is empty"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: normalizedSelector,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote agent import resolve"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: normalizedSelector,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote agent import resolve"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_AGENT_IMPORT_SELECTOR"] = normalizedSelector
        if !normalizedSkillId.isEmpty {
            scriptEnv["XTERMINAL_AGENT_IMPORT_SKILL_ID"] = normalizedSkillId
        }
        if !normalizedProjectId.isEmpty {
            scriptEnv["XTERMINAL_AGENT_IMPORT_PROJECT_ID"] = normalizedProjectId
        }
        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteResolvedAgentImportRecordScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteAgentImportRecordScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_agent_import_record_resolve_failed")
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: normalizedSelector,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_agent_import_record_resolve_failed")

        return HubRemoteAgentImportRecordResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            selector: nonEmpty(decoded.selector) ?? normalizedSelector,
            stagingId: nonEmpty(decoded.stagingId),
            status: nonEmpty(decoded.status),
            auditRef: nonEmpty(decoded.auditRef),
            schemaVersion: nonEmpty(decoded.schemaVersion),
            skillId: nonEmpty(decoded.skillId),
            projectId: nonEmpty(decoded.projectId),
            recordJSON: nonEmpty(decoded.recordJSON),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func uploadRemoteSkillPackage(
        options rawOptions: HubRemoteConnectOptions,
        packageFileURL: URL,
        manifestJSON: String,
        sourceId: String,
        requestId: String?
    ) -> HubRemoteSkillPackageUploadResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let packagePath = packageFileURL.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: packagePath) else {
            return HubRemoteSkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: "skill_package_file_missing",
                logLines: ["missing skill package file: \(packagePath)"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote skill upload"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteSkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote skill upload"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_UPLOAD_SKILL_PACKAGE_PATH"] = packagePath
        scriptEnv["XTERMINAL_UPLOAD_SKILL_MANIFEST_JSON"] = manifestJSON
        scriptEnv["XTERMINAL_UPLOAD_SKILL_SOURCE_ID"] = sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_UPLOAD_SKILL_REQUEST_ID"] = requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSkillPackageUploadScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 60.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSkillPackageUploadScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_skill_package_upload_failed")
            return HubRemoteSkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_skill_package_upload_failed")

        return HubRemoteSkillPackageUploadResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            packageSHA256: nonEmpty(decoded.packageSHA256),
            alreadyPresent: decoded.alreadyPresent ?? false,
            skillId: nonEmpty(decoded.skillId),
            version: nonEmpty(decoded.version),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func promoteRemoteAgentImport(
        options rawOptions: HubRemoteConnectOptions,
        stagingId: String,
        packageSHA256: String,
        note: String?,
        requestId: String?
    ) -> HubRemoteAgentImportPromoteResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedStagingId = stagingId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedStagingId.isEmpty else {
            return HubRemoteAgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: "missing_agent_staging_id",
                logLines: ["agent import staging id is empty"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteAgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote agent import promote"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteAgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote agent import promote"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_AGENT_IMPORT_STAGING_ID"] = normalizedStagingId
        scriptEnv["XTERMINAL_AGENT_IMPORT_PACKAGE_SHA256"] = normalizedPackageSHA256
        scriptEnv["XTERMINAL_AGENT_IMPORT_NOTE"] = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_AGENT_IMPORT_REQUEST_ID"] = requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteAgentImportPromoteScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 30.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteAgentImportPromoteScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_agent_import_promote_failed")
            return HubRemoteAgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_agent_import_promote_failed")

        return HubRemoteAgentImportPromoteResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            stagingId: nonEmpty(decoded.stagingId),
            status: nonEmpty(decoded.status),
            auditRef: nonEmpty(decoded.auditRef),
            packageSHA256: nonEmpty(decoded.packageSHA256),
            scope: nonEmpty(decoded.scope),
            skillId: nonEmpty(decoded.skillId),
            previousPackageSHA256: nonEmpty(decoded.previousPackageSHA256),
            recordPath: nonEmpty(decoded.recordPath),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteMemorySnapshot(
        options rawOptions: HubRemoteConnectOptions,
        mode rawMode: String,
        projectId: String?,
        canonicalLimit: Int = 24,
        workingLimit: Int = 12
    ) -> HubRemoteMemorySnapshotResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let mode = rawMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedMode = mode.isEmpty ? "project" : mode

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote memory snapshot"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_MEM_MODE"] = normalizedMode
        scriptEnv["XTERMINAL_MEM_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_MEM_CANONICAL_LIMIT"] = String(max(1, min(80, canonicalLimit)))
        scriptEnv["XTERMINAL_MEM_WORKING_LIMIT"] = String(max(1, min(80, workingLimit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteMemorySnapshotScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMemorySnapshotScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_memory_snapshot_failed")
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_memory_snapshot_failed")

        return HubRemoteMemorySnapshotResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            canonicalEntries: decoded.canonicalEntries ?? [],
            workingEntries: decoded.workingEntries ?? [],
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteMemoryRetrieval(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubIPCClient.MemoryRetrievalPayload
    ) -> HubRemoteMemoryRetrievalResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMemoryRetrievalResult(
                ok: false,
                schemaVersion: nil,
                requestId: payload.requestId,
                status: nil,
                resolvedScope: nil,
                source: "hub_memory_retrieval_grpc_v1",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "hub_env_missing",
                denyCode: nil,
                results: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0,
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMemoryRetrievalResult(
                ok: false,
                schemaVersion: nil,
                requestId: payload.requestId,
                status: nil,
                resolvedScope: nil,
                source: "hub_memory_retrieval_grpc_v1",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "client_kit_missing",
                denyCode: nil,
                results: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0,
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMemoryRetrievalResult(
                ok: false,
                schemaVersion: nil,
                requestId: payload.requestId,
                status: nil,
                resolvedScope: nil,
                source: "hub_memory_retrieval_grpc_v1",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "node_missing",
                denyCode: nil,
                results: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0,
                logLines: ["missing node runtime for remote memory retrieval"]
            )
        }

        let encodeJSON: ([String]) -> String = { values in
            guard let data = try? JSONEncoder().encode(values),
                  let text = String(data: data, encoding: .utf8) else {
                return "[]"
            }
            return text
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_MEM_RETR_SCHEMA_VERSION"] = payload.schemaVersion
        scriptEnv["XTERMINAL_MEM_RETR_REQUEST_ID"] = payload.requestId
        scriptEnv["XTERMINAL_MEM_RETR_SCOPE"] = payload.scope
        scriptEnv["XTERMINAL_MEM_RETR_REQUESTER_ROLE"] = payload.requesterRole
        scriptEnv["XTERMINAL_MEM_RETR_MODE"] = payload.mode
        scriptEnv["XTERMINAL_MEM_RETR_PROJECT_ID"] = payload.projectId ?? ""
        scriptEnv["XTERMINAL_MEM_RETR_CROSS_PROJECT_TARGET_IDS_JSON"] = encodeJSON(payload.crossProjectTargetIds)
        scriptEnv["XTERMINAL_MEM_RETR_PROJECT_ROOT"] = payload.projectRoot ?? ""
        scriptEnv["XTERMINAL_MEM_RETR_DISPLAY_NAME"] = payload.displayName ?? ""
        scriptEnv["XTERMINAL_MEM_RETR_QUERY"] = payload.query
        scriptEnv["XTERMINAL_MEM_RETR_LATEST_USER"] = payload.latestUser
        scriptEnv["XTERMINAL_MEM_RETR_ALLOWED_LAYERS_JSON"] = encodeJSON(payload.allowedLayers)
        scriptEnv["XTERMINAL_MEM_RETR_RETRIEVAL_KIND"] = payload.retrievalKind
        scriptEnv["XTERMINAL_MEM_RETR_MAX_RESULTS"] = String(max(1, payload.maxResults))
        scriptEnv["XTERMINAL_MEM_RETR_REASON"] = payload.reason ?? ""
        scriptEnv["XTERMINAL_MEM_RETR_REQUIRE_EXPLAINABILITY"] = payload.requireExplainability ? "1" : "0"
        scriptEnv["XTERMINAL_MEM_RETR_REQUESTED_KINDS_JSON"] = encodeJSON(payload.requestedKinds)
        scriptEnv["XTERMINAL_MEM_RETR_EXPLICIT_REFS_JSON"] = encodeJSON(payload.explicitRefs)
        scriptEnv["XTERMINAL_MEM_RETR_MAX_SNIPPETS"] = String(max(1, payload.maxSnippets))
        scriptEnv["XTERMINAL_MEM_RETR_MAX_SNIPPET_CHARS"] = String(max(120, payload.maxSnippetChars))
        scriptEnv["XTERMINAL_MEM_RETR_AUDIT_REF"] = payload.auditRef

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteMemoryRetrievalScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMemoryRetrievalScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_memory_retrieval_failed")
            return HubRemoteMemoryRetrievalResult(
                ok: false,
                schemaVersion: nil,
                requestId: payload.requestId,
                status: nil,
                resolvedScope: nil,
                source: "hub_memory_retrieval_grpc_v1",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: fallback,
                denyCode: nil,
                results: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reasonCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_memory_retrieval_failed")

        return HubRemoteMemoryRetrievalResult(
            ok: decoded.ok ?? false,
            schemaVersion: nonEmpty(decoded.schemaVersion),
            requestId: nonEmpty(decoded.requestId) ?? payload.requestId,
            status: nonEmpty(decoded.status),
            resolvedScope: nonEmpty(decoded.resolvedScope),
            source: nonEmpty(decoded.source) ?? "hub_memory_retrieval_grpc_v1",
            scope: nonEmpty(decoded.scope) ?? payload.scope,
            auditRef: nonEmpty(decoded.auditRef) ?? payload.auditRef,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            denyCode: nonEmpty(decoded.denyCode),
            results: (decoded.results ?? []).map { item in
                HubRemoteMemoryRetrievalItem(
                    ref: nonEmpty(item.ref) ?? "",
                    sourceKind: nonEmpty(item.sourceKind) ?? "memory_doc",
                    summary: nonEmpty(item.summary) ?? "",
                    snippet: nonEmpty(item.snippet) ?? "",
                    score: min(1.0, max(0.0, item.score ?? 0)),
                    redacted: item.redacted ?? false
                )
            },
            truncated: decoded.truncated ?? false,
            budgetUsedChars: max(0, decoded.budgetUsedChars ?? 0),
            truncatedItems: max(0, decoded.truncatedItems ?? 0),
            redactedItems: max(0, decoded.redactedItems ?? 0),
            logLines: logs
        )
    }

    func fetchRemoteSchedulerStatus(
        options rawOptions: HubRemoteConnectOptions,
        includeQueueItems: Bool,
        queueItemsLimit: Int
    ) -> HubRemoteSchedulerStatusResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote scheduler status"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SCHED_INCLUDE_QUEUE_ITEMS"] = includeQueueItems ? "1" : "0"
        scriptEnv["XTERMINAL_SCHED_QUEUE_ITEMS_LIMIT"] = String(max(1, min(500, queueItemsLimit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSchedulerStatusScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSchedulerStatusScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_scheduler_status_failed")
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_scheduler_status_failed")

        let inFlightByScope: [HubRemoteSchedulerScopeCount] = (decoded.inFlightByScope ?? []).compactMap { row in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return HubRemoteSchedulerScopeCount(
                scopeKey: key,
                count: max(0, row.inFlight ?? 0)
            )
        }

        let queuedByScope: [HubRemoteSchedulerScopeCount] = (decoded.queuedByScope ?? []).compactMap { row in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return HubRemoteSchedulerScopeCount(
                scopeKey: key,
                count: max(0, row.queued ?? 0)
            )
        }

        let queueItems: [HubRemoteSchedulerQueueItem] = (decoded.queueItems ?? []).compactMap { row in
            let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
            let scopeKey = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestId.isEmpty, !scopeKey.isEmpty else { return nil }
            return HubRemoteSchedulerQueueItem(
                requestId: requestId,
                scopeKey: scopeKey,
                enqueuedAtMs: max(0, row.enqueuedAtMs ?? 0),
                queuedMs: max(0, row.queuedMs ?? 0)
            )
        }

        return HubRemoteSchedulerStatusResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            inFlightTotal: max(0, decoded.inFlightTotal ?? 0),
            queueDepth: max(0, decoded.queueDepth ?? 0),
            oldestQueuedMs: max(0, decoded.oldestQueuedMs ?? 0),
            inFlightByScope: inFlightByScope,
            queuedByScope: queuedByScope,
            queueItems: queueItems,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteSupervisorBriefProjection(
        options rawOptions: HubRemoteConnectOptions,
        requestId: String,
        projectId: String,
        runId: String?,
        missionId: String?,
        projectionKind: String,
        trigger: String,
        includeTtsScript: Bool,
        includeCardSummary: Bool,
        maxEvidenceRefs: Int
    ) -> HubRemoteSupervisorBriefProjectionResult {
        let normalizedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestId.isEmpty else {
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "request_id_empty",
                logLines: ["supervisor brief projection missing request_id"]
            )
        }
        guard !normalizedProjectId.isEmpty else {
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "project_id_empty",
                logLines: ["supervisor brief projection missing project_id"]
            )
        }

        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote supervisor brief projection"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_REQUEST_ID"] = normalizedRequestId
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_PROJECT_ID"] = normalizedProjectId
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_RUN_ID"] = runId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_MISSION_ID"] = missionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_KIND"] = projectionKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "progress_brief"
            : projectionKind.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_TRIGGER"] = trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "daily_digest"
            : trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_INCLUDE_TTS"] = includeTtsScript ? "1" : "0"
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_INCLUDE_CARD_SUMMARY"] = includeCardSummary ? "1" : "0"
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_MAX_EVIDENCE_REFS"] = String(max(0, min(12, maxEvidenceRefs)))
        scriptEnv["HUB_PROJECT_ID"] = normalizedProjectId

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSupervisorBriefProjectionScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSupervisorBriefProjectionScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_supervisor_brief_projection_failed")
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let projection: HubRemoteSupervisorBriefProjection? = {
            guard let row = decoded.projection else { return nil }
            let projectionId = row.projectionId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectionId.isEmpty else { return nil }
            return HubRemoteSupervisorBriefProjection(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "xhub.supervisor_brief_projection.v1"
                    : row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                projectionId: projectionId,
                projectionKind: row.projectionKind.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                runId: row.runId.trimmingCharacters(in: .whitespacesAndNewlines),
                missionId: row.missionId.trimmingCharacters(in: .whitespacesAndNewlines),
                trigger: row.trigger.trimmingCharacters(in: .whitespacesAndNewlines),
                status: row.status.trimmingCharacters(in: .whitespacesAndNewlines),
                criticalBlocker: row.criticalBlocker.trimmingCharacters(in: .whitespacesAndNewlines),
                topline: row.topline.trimmingCharacters(in: .whitespacesAndNewlines),
                nextBestAction: row.nextBestAction.trimmingCharacters(in: .whitespacesAndNewlines),
                pendingGrantCount: max(0, row.pendingGrantCount ?? 0),
                ttsScript: (row.ttsScript ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                cardSummary: row.cardSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                evidenceRefs: (row.evidenceRefs ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                generatedAtMs: max(0, row.generatedAtMs ?? 0),
                expiresAtMs: max(0, row.expiresAtMs ?? 0),
                auditRef: row.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }()

        let ok = (decoded.ok ?? (projection != nil)) && projection != nil
        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_supervisor_brief_projection_failed")

        return HubRemoteSupervisorBriefProjectionResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_supervisor_grpc",
            projection: projection,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemotePendingGrantRequests(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int
    ) -> HubRemotePendingGrantRequestsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote pending grants"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_PENDING_GRANTS_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANTS_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remotePendingGrantRequestsScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemotePendingGrantRequestsScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_pending_grants_failed")
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_pending_grants_failed")

        let items: [HubRemotePendingGrantItem] = (decoded.items ?? []).compactMap { row in
            let grantRequestId = row.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !grantRequestId.isEmpty else { return nil }
            return HubRemotePendingGrantItem(
                grantRequestId: grantRequestId,
                requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceId: row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                userId: row.userId.trimmingCharacters(in: .whitespacesAndNewlines),
                appId: row.appId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                capability: row.capability.trimmingCharacters(in: .whitespacesAndNewlines),
                modelId: row.modelId.trimmingCharacters(in: .whitespacesAndNewlines),
                reason: row.reason.trimmingCharacters(in: .whitespacesAndNewlines),
                requestedTtlSec: max(0, row.requestedTtlSec ?? 0),
                requestedTokenCap: max(0, row.requestedTokenCap ?? 0),
                status: row.status.trimmingCharacters(in: .whitespacesAndNewlines),
                decision: row.decision.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                decidedAtMs: max(0, row.decidedAtMs ?? 0)
            )
        }

        return HubRemotePendingGrantRequestsResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteSupervisorCandidateReviewQueue(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int
    ) -> HubRemoteSupervisorCandidateReviewQueueResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSupervisorCandidateReviewQueueResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSupervisorCandidateReviewQueueResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSupervisorCandidateReviewQueueResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote supervisor candidate review queue"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = self.remoteSupervisorCandidateReviewQueueScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSupervisorCandidateReviewQueueScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_supervisor_candidate_review_queue_failed")
            return HubRemoteSupervisorCandidateReviewQueueResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_supervisor_candidate_review_queue_failed")

        let items: [HubRemoteSupervisorCandidateReviewQueueItem] = (decoded.items ?? []).compactMap { row in
            let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestId.isEmpty else { return nil }
            return HubRemoteSupervisorCandidateReviewQueueItem(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                reviewId: row.reviewId.trimmingCharacters(in: .whitespacesAndNewlines),
                requestId: requestId,
                evidenceRef: row.evidenceRef.trimmingCharacters(in: .whitespacesAndNewlines),
                reviewState: row.reviewState.trimmingCharacters(in: .whitespacesAndNewlines),
                durablePromotionState: row.durablePromotionState.trimmingCharacters(in: .whitespacesAndNewlines),
                promotionBoundary: row.promotionBoundary.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceId: row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                userId: row.userId.trimmingCharacters(in: .whitespacesAndNewlines),
                appId: row.appId.trimmingCharacters(in: .whitespacesAndNewlines),
                threadId: row.threadId.trimmingCharacters(in: .whitespacesAndNewlines),
                threadKey: row.threadKey.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectIds: row.projectIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                scopes: row.scopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                recordTypes: row.recordTypes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                auditRefs: row.auditRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                idempotencyKeys: row.idempotencyKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                candidateCount: max(0, row.candidateCount ?? 0),
                summaryLine: row.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines),
                mirrorTarget: row.mirrorTarget.trimmingCharacters(in: .whitespacesAndNewlines),
                localStoreRole: row.localStoreRole.trimmingCharacters(in: .whitespacesAndNewlines),
                carrierKind: row.carrierKind.trimmingCharacters(in: .whitespacesAndNewlines),
                carrierSchemaVersion: row.carrierSchemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                pendingChangeId: row.pendingChangeId.trimmingCharacters(in: .whitespacesAndNewlines),
                pendingChangeStatus: row.pendingChangeStatus.trimmingCharacters(in: .whitespacesAndNewlines),
                editSessionId: row.editSessionId.trimmingCharacters(in: .whitespacesAndNewlines),
                docId: row.docId.trimmingCharacters(in: .whitespacesAndNewlines),
                writebackRef: row.writebackRef.trimmingCharacters(in: .whitespacesAndNewlines),
                stageCreatedAtMs: max(0, row.stageCreatedAtMs ?? 0),
                stageUpdatedAtMs: max(0, row.stageUpdatedAtMs ?? 0),
                latestEmittedAtMs: max(0, row.latestEmittedAtMs ?? 0),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                updatedAtMs: max(0, row.updatedAtMs ?? 0)
            )
        }

        return HubRemoteSupervisorCandidateReviewQueueResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteConnectorIngressReceipts(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int
    ) -> HubRemoteConnectorIngressReceiptsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteConnectorIngressReceiptsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteConnectorIngressReceiptsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteConnectorIngressReceiptsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote connector ingress receipts"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_CONNECTOR_INGRESS_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_CONNECTOR_INGRESS_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteConnectorIngressReceiptsScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteConnectorIngressReceiptsScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_connector_ingress_receipts_failed")
            return HubRemoteConnectorIngressReceiptsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_connector_ingress_receipts_failed")

        let items: [HubRemoteConnectorIngressReceipt] = (decoded.items ?? []).compactMap { row in
            let receiptId = row.receiptId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !receiptId.isEmpty else { return nil }
            return HubRemoteConnectorIngressReceipt(
                receiptId: receiptId,
                requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                connector: row.connector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                targetId: row.targetId.trimmingCharacters(in: .whitespacesAndNewlines),
                ingressType: row.ingressType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                channelScope: row.channelScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                sourceId: row.sourceId.trimmingCharacters(in: .whitespacesAndNewlines),
                messageId: row.messageId.trimmingCharacters(in: .whitespacesAndNewlines),
                dedupeKey: row.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                receivedAtMs: max(0, row.receivedAtMs ?? 0),
                eventSequence: Swift.max(Int64(0), row.eventSequence ?? 0),
                deliveryState: row.deliveryState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                runtimeState: row.runtimeState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        }

        return HubRemoteConnectorIngressReceiptsResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteRuntimeSurfaceOverrides(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int
    ) -> HubRemoteRuntimeSurfaceOverridesResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote runtime surface overrides"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_RUNTIME_SURFACE_OVERRIDE_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_RUNTIME_SURFACE_OVERRIDE_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteRuntimeSurfaceOverridesScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteRuntimeSurfaceOverridesScriptResult.self, from: data) else {
            let fallback = inferFailureCode(
                from: step.output,
                fallback: HubRemoteRuntimeSurfaceCompatContract.failureReasonCode
            )
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : HubRemoteRuntimeSurfaceCompatContract.failureReasonCode)

        let items: [HubRemoteRuntimeSurfaceOverrideItem] = (decoded.items ?? []).compactMap { row in
            let projectId = row.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawMode = row.overrideMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !projectId.isEmpty,
                  let overrideMode = AXProjectRuntimeSurfaceHubOverrideMode(rawValue: rawMode) else {
                return nil
            }
            return HubRemoteRuntimeSurfaceOverrideItem(
                projectId: projectId,
                overrideMode: overrideMode,
                updatedAtMs: max(0, row.updatedAtMs ?? 0),
                reason: row.reason.trimmingCharacters(in: .whitespacesAndNewlines),
                auditRef: row.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return HubRemoteRuntimeSurfaceOverridesResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    @available(*, deprecated, message: "Use fetchRemoteRuntimeSurfaceOverrides(options:projectId:limit:)")
    func fetchRemoteAutonomyPolicyOverrides(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int
    ) -> HubRemoteAutonomyPolicyOverridesResult {
        fetchRemoteRuntimeSurfaceOverrides(
            options: rawOptions,
            projectId: projectId,
            limit: limit
        )
    }

    func approveRemotePendingGrantRequest(
        options rawOptions: HubRemoteConnectOptions,
        grantRequestId: String,
        projectId: String?,
        ttlSec: Int?,
        tokenCap: Int?,
        note: String?
    ) -> HubRemotePendingGrantActionResult {
        performRemotePendingGrantAction(
            options: rawOptions,
            action: "approve",
            grantRequestId: grantRequestId,
            projectId: projectId,
            ttlSec: ttlSec,
            tokenCap: tokenCap,
            note: note,
            reason: nil
        )
    }

    func denyRemotePendingGrantRequest(
        options rawOptions: HubRemoteConnectOptions,
        grantRequestId: String,
        projectId: String?,
        reason: String?
    ) -> HubRemotePendingGrantActionResult {
        performRemotePendingGrantAction(
            options: rawOptions,
            action: "deny",
            grantRequestId: grantRequestId,
            projectId: projectId,
            ttlSec: nil,
            tokenCap: nil,
            note: nil,
            reason: reason
        )
    }

    func stageRemoteSupervisorCandidateReview(
        options rawOptions: HubRemoteConnectOptions,
        candidateRequestId: String,
        projectId: String?
    ) -> HubRemoteSupervisorCandidateReviewStageResult {
        let normalizedCandidateRequestId = candidateRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCandidateRequestId.isEmpty else {
            return HubRemoteSupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: nil,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: "candidate_request_id_empty",
                logLines: ["stage supervisor candidate review missing candidate_request_id"]
            )
        }

        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: normalizedCandidateRequestId,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: normalizedCandidateRequestId,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: normalizedCandidateRequestId,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote supervisor candidate review stage"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_REQUEST_ID"] = normalizedCandidateRequestId
        scriptEnv["XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = self.remoteSupervisorCandidateReviewStageScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSupervisorCandidateReviewStageScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_supervisor_candidate_review_stage_failed")
            return HubRemoteSupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: normalizedCandidateRequestId,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let staged = decoded.staged ?? false
        let idempotent = decoded.idempotent ?? false
        let ok = decoded.ok ?? (staged || idempotent)
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_supervisor_candidate_review_stage_failed")

        return HubRemoteSupervisorCandidateReviewStageResult(
            ok: ok,
            staged: staged,
            idempotent: idempotent,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            reviewState: nonEmpty(decoded.reviewState) ?? "",
            durablePromotionState: nonEmpty(decoded.durablePromotionState) ?? "",
            promotionBoundary: nonEmpty(decoded.promotionBoundary) ?? "",
            candidateRequestId: nonEmpty(decoded.candidateRequestId) ?? normalizedCandidateRequestId,
            evidenceRef: nonEmpty(decoded.evidenceRef),
            editSessionId: nonEmpty(decoded.editSessionId),
            pendingChangeId: nonEmpty(decoded.pendingChangeId),
            docId: nonEmpty(decoded.docId),
            baseVersion: nonEmpty(decoded.baseVersion),
            workingVersion: nonEmpty(decoded.workingVersion),
            sessionRevision: Int64(decoded.sessionRevision ?? 0),
            status: nonEmpty(decoded.status),
            markdown: decoded.markdown,
            createdAtMs: max(0, decoded.createdAtMs ?? 0),
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            expiresAtMs: max(0, decoded.expiresAtMs ?? 0),
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteSecretVaultItems(
        options rawOptions: HubRemoteConnectOptions,
        scope: String?,
        namePrefix: String?,
        limit: Int
    ) -> HubRemoteSecretVaultItemsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSecretVaultItemsResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSecretVaultItemsResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSecretVaultItemsResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote secret vault list"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SECRET_VAULT_SCOPE"] = scope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_NAME_PREFIX"] = namePrefix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSecretVaultListScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSecretVaultItemsScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_secret_vault_list_failed")
            return HubRemoteSecretVaultItemsResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_secret_vault_list_failed")

        let items = (decoded.items ?? []).compactMap { row -> HubRemoteSecretVaultItem? in
            let itemId = row.itemId.trimmingCharacters(in: .whitespacesAndNewlines)
            let itemScope = row.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let itemName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !itemId.isEmpty, !itemScope.isEmpty, !itemName.isEmpty else { return nil }
            return HubRemoteSecretVaultItem(
                itemId: itemId,
                scope: itemScope,
                name: itemName,
                sensitivity: row.sensitivity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                updatedAtMs: max(0, row.updatedAtMs ?? 0)
            )
        }

        return HubRemoteSecretVaultItemsResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func createRemoteSecretVaultItem(
        options rawOptions: HubRemoteConnectOptions,
        scope: String,
        name: String,
        plaintext: String,
        sensitivity: String,
        projectId: String?,
        displayName: String?,
        reason: String?
    ) -> HubRemoteSecretVaultCreateResult {
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPlaintext = plaintext.trimmingCharacters(in: .newlines)
        guard !normalizedScope.isEmpty, !normalizedName.isEmpty, !normalizedPlaintext.isEmpty else {
            return HubRemoteSecretVaultCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "invalid_request",
                logLines: ["secret vault create missing scope/name/plaintext"]
            )
        }

        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSecretVaultCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSecretVaultCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSecretVaultCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote secret vault create"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SECRET_VAULT_SCOPE"] = normalizedScope
        scriptEnv["XTERMINAL_SECRET_VAULT_NAME"] = normalizedName
        scriptEnv["XTERMINAL_SECRET_VAULT_PLAINTEXT_B64"] = Data(normalizedPlaintext.utf8).base64EncodedString()
        scriptEnv["XTERMINAL_SECRET_VAULT_SENSITIVITY"] = sensitivity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        scriptEnv["XTERMINAL_SECRET_VAULT_DISPLAY_NAME"] = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSecretVaultCreateScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSecretVaultCreateScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_secret_vault_create_failed")
            return HubRemoteSecretVaultCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_secret_vault_create_failed")

        let item: HubRemoteSecretVaultItem? = {
            guard let row = decoded.item else { return nil }
            let itemId = row.itemId.trimmingCharacters(in: .whitespacesAndNewlines)
            let itemScope = row.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let itemName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !itemId.isEmpty, !itemScope.isEmpty, !itemName.isEmpty else { return nil }
            return HubRemoteSecretVaultItem(
                itemId: itemId,
                scope: itemScope,
                name: itemName,
                sensitivity: row.sensitivity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                updatedAtMs: max(0, row.updatedAtMs ?? 0)
            )
        }()

        let ok = (decoded.ok ?? (item != nil)) && item != nil

        return HubRemoteSecretVaultCreateResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            item: item,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func beginRemoteSecretVaultUse(
        options rawOptions: HubRemoteConnectOptions,
        itemId: String?,
        scope: String?,
        name: String?,
        projectId: String?,
        purpose: String,
        target: String?,
        ttlMs: Int
    ) -> HubRemoteSecretVaultUseResult {
        let normalizedItemId = itemId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedScope = scope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPurpose.isEmpty,
              (normalizedItemId?.isEmpty == false || ((normalizedScope?.isEmpty == false) && (normalizedName?.isEmpty == false))) else {
            return HubRemoteSecretVaultUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: normalizedItemId,
                expiresAtMs: nil,
                reasonCode: "invalid_request",
                logLines: ["secret vault begin use missing item reference or purpose"]
            )
        }

        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSecretVaultUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: normalizedItemId,
                expiresAtMs: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSecretVaultUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: normalizedItemId,
                expiresAtMs: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSecretVaultUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: normalizedItemId,
                expiresAtMs: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote secret vault use"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SECRET_VAULT_ITEM_ID"] = normalizedItemId ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_SCOPE"] = normalizedScope ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_NAME"] = normalizedName ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_USE_PURPOSE"] = normalizedPurpose
        scriptEnv["XTERMINAL_SECRET_VAULT_USE_TARGET"] = target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_USE_TTL_MS"] = String(max(1_000, min(600_000, ttlMs)))
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSecretVaultBeginUseScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSecretVaultUseScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_secret_vault_use_failed")
            return HubRemoteSecretVaultUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: normalizedItemId,
                expiresAtMs: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_secret_vault_use_failed")

        let ok = decoded.ok ?? false
        return HubRemoteSecretVaultUseResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            leaseId: nonEmpty(decoded.leaseId),
            useToken: nonEmpty(decoded.useToken),
            itemId: nonEmpty(decoded.itemId) ?? normalizedItemId,
            expiresAtMs: decoded.expiresAtMs.map { max(0, $0) },
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func redeemRemoteSecretVaultUse(
        options rawOptions: HubRemoteConnectOptions,
        useToken: String,
        projectId: String?
    ) -> HubRemoteSecretVaultRedeemResult {
        let normalizedUseToken = useToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUseToken.isEmpty else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "invalid_request",
                logLines: ["secret vault redeem missing use token"]
            )
        }

        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote secret vault redeem"]
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_secret_vault_redeem_\(UUID().uuidString)", isDirectory: false)
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SECRET_VAULT_USE_TOKEN"] = normalizedUseToken
        scriptEnv["XTERMINAL_SECRET_VAULT_REDEEM_OUTPUT"] = outputURL.path
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSecretVaultRedeemScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSecretVaultRedeemScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_secret_vault_redeem_failed")
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_secret_vault_redeem_failed")
        let ok = decoded.ok ?? false
        guard ok else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
                leaseId: nonEmpty(decoded.leaseId),
                itemId: nonEmpty(decoded.itemId),
                plaintext: nil,
                reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
                logLines: logs
            )
        }

        guard let plaintextData = try? Data(contentsOf: outputURL),
              let plaintext = String(data: plaintextData, encoding: .utf8),
              !plaintext.isEmpty else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
                leaseId: nonEmpty(decoded.leaseId),
                itemId: nonEmpty(decoded.itemId),
                plaintext: nil,
                reasonCode: "secret_vault_plaintext_missing",
                logLines: logs
            )
        }

        return HubRemoteSecretVaultRedeemResult(
            ok: true,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            leaseId: nonEmpty(decoded.leaseId),
            itemId: nonEmpty(decoded.itemId),
            plaintext: plaintext,
            reasonCode: nil,
            logLines: logs
        )
    }

    func fetchRemoteVoiceWakeProfile(
        options rawOptions: HubRemoteConnectOptions,
        desiredWakeMode: VoiceWakeMode
    ) -> VoiceWakeProfileSyncResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"],
                syncedAtMs: nil
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"],
                syncedAtMs: nil
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote voice wake profile fetch"],
                syncedAtMs: nil
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_VOICE_WAKE_DESIRED_MODE"] = desiredWakeMode.rawValue

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteVoiceWakeProfileGetScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteVoiceWakeProfileScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_voice_wake_profile_fetch_failed")
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: fallback,
                logLines: logs,
                syncedAtMs: nil
            )
        }

        let profile: VoiceWakeProfile? = {
            guard let row = decoded.profile else { return nil }
            let sanitized = VoiceWakeProfile(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? VoiceWakeProfile.currentSchemaVersion
                    : row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                profileID: row.profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "default"
                    : row.profileID.trimmingCharacters(in: .whitespacesAndNewlines),
                triggerWords: row.triggerWords,
                updatedAtMs: max(0, Int64(row.updatedAtMs ?? 0)),
                scope: .pairedDeviceGroup,
                source: .hubPairingSync,
                wakeMode: desiredWakeMode,
                requiresPairingReady: row.requiresPairingReady ?? true,
                auditRef: nonEmpty(row.auditRef)
            ).sanitized()
            return sanitized.isValid ? sanitized : nil
        }()

        let ok = (decoded.ok ?? (profile != nil)) && profile != nil
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_voice_wake_profile_fetch_failed")

        return VoiceWakeProfileSyncResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            profile: profile,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs,
            syncedAtMs: profile?.updatedAtMs
        )
    }

    func setRemoteVoiceWakeProfile(
        options rawOptions: HubRemoteConnectOptions,
        profile: VoiceWakeProfile
    ) -> VoiceWakeProfileSyncResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        guard let payloadData = try? JSONEncoder().encode(profile.sanitized()) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "voice_wake_profile_encode_failed",
                logLines: ["failed to encode voice wake profile payload"],
                syncedAtMs: nil
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"],
                syncedAtMs: nil
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"],
                syncedAtMs: nil
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote voice wake profile set"],
                syncedAtMs: nil
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_VOICE_WAKE_PROFILE_JSON_B64"] = payloadData.base64EncodedString()

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteVoiceWakeProfileSetScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteVoiceWakeProfileScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_voice_wake_profile_set_failed")
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: fallback,
                logLines: logs,
                syncedAtMs: nil
            )
        }

        let syncedProfile: VoiceWakeProfile? = {
            guard let row = decoded.profile else { return nil }
            let wakeMode = VoiceWakeMode(rawValue: row.wakeMode.trimmingCharacters(in: .whitespacesAndNewlines)) ?? profile.wakeMode
            let sanitized = VoiceWakeProfile(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? VoiceWakeProfile.currentSchemaVersion
                    : row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                profileID: row.profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "default"
                    : row.profileID.trimmingCharacters(in: .whitespacesAndNewlines),
                triggerWords: row.triggerWords,
                updatedAtMs: max(0, Int64(row.updatedAtMs ?? 0)),
                scope: .pairedDeviceGroup,
                source: .hubPairingSync,
                wakeMode: wakeMode,
                requiresPairingReady: row.requiresPairingReady ?? true,
                auditRef: nonEmpty(row.auditRef)
            ).sanitized()
            return sanitized.isValid ? sanitized : nil
        }()

        let ok = (decoded.ok ?? (syncedProfile != nil)) && syncedProfile != nil
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_voice_wake_profile_set_failed")

        return VoiceWakeProfileSyncResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            profile: syncedProfile,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs,
            syncedAtMs: syncedProfile?.updatedAtMs
        )
    }

    func issueRemoteVoiceGrantChallenge(
        options rawOptions: HubRemoteConnectOptions,
        requestId: String,
        projectId: String?,
        templateId: String,
        actionDigest: String,
        scopeDigest: String,
        amountDigest: String?,
        challengeCode: String?,
        riskLevel: String,
        boundDeviceId: String?,
        mobileTerminalId: String?,
        allowVoiceOnly: Bool,
        requiresMobileConfirm: Bool,
        ttlMs: Int
    ) -> HubRemoteVoiceGrantChallengeResult {
        let normalizedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestId.isEmpty else {
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "request_id_empty",
                logLines: ["voice grant challenge missing request_id"]
            )
        }

        let normalizedTemplateId = templateId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedActionDigest = actionDigest.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedScopeDigest = scopeDigest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTemplateId.isEmpty, !normalizedActionDigest.isEmpty, !normalizedScopeDigest.isEmpty else {
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "invalid_request",
                logLines: ["voice grant challenge missing template/action/scope digest"]
            )
        }

        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote voice grant challenge"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_REQUEST_ID"] = normalizedRequestId
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_TEMPLATE_ID"] = normalizedTemplateId
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_ACTION_DIGEST"] = normalizedActionDigest
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_SCOPE_DIGEST"] = normalizedScopeDigest
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_AMOUNT_DIGEST"] = amountDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_CODE"] = challengeCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_RISK_LEVEL"] = riskLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_BOUND_DEVICE_ID"] = boundDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_MOBILE_TERMINAL_ID"] = mobileTerminalId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_ALLOW_VOICE_ONLY"] = allowVoiceOnly ? "1" : "0"
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_REQUIRES_MOBILE_CONFIRM"] = requiresMobileConfirm ? "1" : "0"
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_TTL_MS"] = String(max(10_000, min(600_000, ttlMs)))
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteVoiceGrantChallengeScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteVoiceGrantChallengeScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_voice_grant_challenge_failed")
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let challenge: HubRemoteVoiceGrantChallenge? = {
            guard let row = decoded.challenge else { return nil }
            let challengeId = row.challengeId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !challengeId.isEmpty else { return nil }
            return HubRemoteVoiceGrantChallenge(
                challengeId: challengeId,
                templateId: row.templateId.trimmingCharacters(in: .whitespacesAndNewlines),
                actionDigest: row.actionDigest.trimmingCharacters(in: .whitespacesAndNewlines),
                scopeDigest: row.scopeDigest.trimmingCharacters(in: .whitespacesAndNewlines),
                amountDigest: row.amountDigest.trimmingCharacters(in: .whitespacesAndNewlines),
                challengeCode: row.challengeCode.trimmingCharacters(in: .whitespacesAndNewlines),
                riskLevel: row.riskLevel.trimmingCharacters(in: .whitespacesAndNewlines),
                requiresMobileConfirm: row.requiresMobileConfirm ?? false,
                allowVoiceOnly: row.allowVoiceOnly ?? false,
                boundDeviceId: row.boundDeviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                mobileTerminalId: row.mobileTerminalId.trimmingCharacters(in: .whitespacesAndNewlines),
                issuedAtMs: max(0, row.issuedAtMs ?? 0),
                expiresAtMs: max(0, row.expiresAtMs ?? 0)
            )
        }()

        let ok = (decoded.ok ?? (challenge != nil)) && challenge != nil
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_voice_grant_challenge_failed")

        return HubRemoteVoiceGrantChallengeResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            challenge: challenge,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func verifyRemoteVoiceGrantResponse(
        options rawOptions: HubRemoteConnectOptions,
        requestId: String,
        projectId: String?,
        challengeId: String,
        challengeCode: String?,
        transcript: String?,
        transcriptHash: String?,
        semanticMatchScore: Double?,
        parsedActionDigest: String?,
        parsedScopeDigest: String?,
        parsedAmountDigest: String?,
        verifyNonce: String,
        boundDeviceId: String?,
        mobileConfirmed: Bool
    ) -> HubRemoteVoiceGrantVerificationResult {
        let normalizedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedChallengeId = challengeId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVerifyNonce = verifyNonce.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestId.isEmpty else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: nil,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "request_id_empty",
                logLines: ["voice grant verify missing request_id"]
            )
        }
        guard !normalizedChallengeId.isEmpty else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: nil,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "challenge_id_empty",
                logLines: ["voice grant verify missing challenge_id"]
            )
        }
        guard !normalizedVerifyNonce.isEmpty else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "verify_nonce_empty",
                logLines: ["voice grant verify missing verify_nonce"]
            )
        }

        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote voice grant verify"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_VOICE_VERIFY_REQUEST_ID"] = normalizedRequestId
        scriptEnv["XTERMINAL_VOICE_VERIFY_CHALLENGE_ID"] = normalizedChallengeId
        scriptEnv["XTERMINAL_VOICE_VERIFY_CHALLENGE_CODE"] = challengeCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_TRANSCRIPT"] = transcript ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_TRANSCRIPT_HASH"] = transcriptHash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let semanticMatchScore, semanticMatchScore.isFinite {
            scriptEnv["XTERMINAL_VOICE_VERIFY_SEMANTIC_MATCH_SCORE"] = String(semanticMatchScore)
        } else {
            scriptEnv["XTERMINAL_VOICE_VERIFY_SEMANTIC_MATCH_SCORE"] = ""
        }
        scriptEnv["XTERMINAL_VOICE_VERIFY_PARSED_ACTION_DIGEST"] = parsedActionDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_PARSED_SCOPE_DIGEST"] = parsedScopeDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_PARSED_AMOUNT_DIGEST"] = parsedAmountDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_NONCE"] = normalizedVerifyNonce
        scriptEnv["XTERMINAL_VOICE_VERIFY_BOUND_DEVICE_ID"] = boundDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_MOBILE_CONFIRMED"] = mobileConfirmed ? "1" : "0"
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteVoiceGrantVerifyScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteVoiceGrantVerificationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_voice_grant_verify_failed")
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let mappedDecision: HubRemoteVoiceGrantVerificationDecision = {
            switch (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "allow":
                return .allow
            case "deny":
                return .deny
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision != .failed)
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_voice_grant_verify_failed")

        return HubRemoteVoiceGrantVerificationResult(
            ok: ok,
            verified: decoded.verified ?? false,
            decision: mappedDecision,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            denyCode: nonEmpty(decoded.denyCode),
            challengeId: nonEmpty(decoded.challengeId) ?? normalizedChallengeId,
            transcriptHash: nonEmpty(decoded.transcriptHash),
            semanticMatchScore: decoded.semanticMatchScore ?? 0,
            challengeMatch: decoded.challengeMatch ?? false,
            deviceBindingOK: decoded.deviceBindingOk ?? false,
            mobileConfirmed: decoded.mobileConfirmed ?? false,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    private func performRemotePendingGrantAction(
        options rawOptions: HubRemoteConnectOptions,
        action rawAction: String,
        grantRequestId: String,
        projectId: String?,
        ttlSec: Int?,
        tokenCap: Int?,
        note: String?,
        reason: String?
    ) -> HubRemotePendingGrantActionResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let action = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard action == "approve" || action == "deny" else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "invalid_action",
                logLines: ["invalid pending grant action: \(rawAction)"]
            )
        }

        let grantId = grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty",
                logLines: ["pending grant action missing grant_request_id"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote pending grant action"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_PENDING_GRANT_ACTION"] = action
        scriptEnv["XTERMINAL_PENDING_GRANT_ID"] = grantId
        scriptEnv["XTERMINAL_PENDING_GRANT_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        scriptEnv["XTERMINAL_PENDING_GRANT_TTL_SEC"] = ttlSec.map { String(max(10, min(86_400, $0))) } ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANT_TOKEN_CAP"] = tokenCap.map { String(max(0, $0)) } ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANT_NOTE"] = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remotePendingGrantActionScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemotePendingGrantActionScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_pending_grant_action_failed")
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let decisionToken = (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mappedDecision: HubRemotePendingGrantActionDecision = {
            switch decisionToken {
            case "approved":
                return .approved
            case "denied":
                return .denied
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision == .approved || mappedDecision == .denied)
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_pending_grant_action_failed")

        return HubRemotePendingGrantActionResult(
            ok: ok,
            decision: mappedDecision,
            grantRequestId: nonEmpty(decoded.grantRequestId) ?? grantId,
            grantId: nonEmpty(decoded.grantId),
            expiresAtMs: decoded.expiresAtMs,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    // MARK: - Helpers

    private struct StepOutput {
        var exitCode: Int32
        var output: String
        var command: String
    }

    private struct RemoteGenerateScriptResult: Codable {
        var ok: Bool?
        var text: String?
        var modelId: String?
        var requestedModelId: String?
        var actualModelId: String?
        var runtimeProvider: String?
        var executionPath: String?
        var fallbackReasonCode: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case ok
            case text
            case modelId = "model_id"
            case requestedModelId = "requested_model_id"
            case actualModelId = "actual_model_id"
            case runtimeProvider = "runtime_provider"
            case executionPath = "execution_path"
            case fallbackReasonCode = "fallback_reason_code"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    private static func successfulRemoteGenerateResult(
        from decoded: RemoteGenerateScriptResult,
        fallbackModelId: String?,
        logLines: [String]
    ) -> HubRemoteGenerateResult? {
        func cleaned(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        let text = decoded.text ?? ""
        guard !text.isEmpty else { return nil }
        return HubRemoteGenerateResult(
            ok: true,
            text: text,
            modelId: cleaned(decoded.modelId) ?? cleaned(fallbackModelId),
            requestedModelId: cleaned(decoded.requestedModelId) ?? cleaned(fallbackModelId),
            actualModelId: cleaned(decoded.actualModelId) ?? cleaned(decoded.modelId) ?? cleaned(fallbackModelId),
            runtimeProvider: cleaned(decoded.runtimeProvider),
            executionPath: cleaned(decoded.executionPath),
            fallbackReasonCode: cleaned(decoded.fallbackReasonCode),
            promptTokens: decoded.promptTokens,
            completionTokens: decoded.completionTokens,
            reasonCode: nil,
            logLines: logLines
        )
    }

    nonisolated static func remoteGenerateResultForTesting(
        jsonLine: String,
        requestedModelId: String? = nil
    ) -> HubRemoteGenerateResult? {
        guard let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteGenerateScriptResult.self, from: data),
              decoded.ok == true else {
            return nil
        }
        return successfulRemoteGenerateResult(
            from: decoded,
            fallbackModelId: requestedModelId,
            logLines: []
        )
    }

    nonisolated static func remoteSupervisorCandidateReviewQueueResultForTesting(
        jsonLine: String
    ) -> HubRemoteSupervisorCandidateReviewQueueResult? {
        guard let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSupervisorCandidateReviewQueueScriptResult.self, from: data),
              decoded.ok == true else {
            return nil
        }

        let items = (decoded.items ?? []).compactMap { row -> HubRemoteSupervisorCandidateReviewQueueItem? in
            let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestId.isEmpty else { return nil }
            return HubRemoteSupervisorCandidateReviewQueueItem(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                reviewId: row.reviewId.trimmingCharacters(in: .whitespacesAndNewlines),
                requestId: requestId,
                evidenceRef: row.evidenceRef.trimmingCharacters(in: .whitespacesAndNewlines),
                reviewState: row.reviewState.trimmingCharacters(in: .whitespacesAndNewlines),
                durablePromotionState: row.durablePromotionState.trimmingCharacters(in: .whitespacesAndNewlines),
                promotionBoundary: row.promotionBoundary.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceId: row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                userId: row.userId.trimmingCharacters(in: .whitespacesAndNewlines),
                appId: row.appId.trimmingCharacters(in: .whitespacesAndNewlines),
                threadId: row.threadId.trimmingCharacters(in: .whitespacesAndNewlines),
                threadKey: row.threadKey.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectIds: row.projectIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                scopes: row.scopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                recordTypes: row.recordTypes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                auditRefs: row.auditRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                idempotencyKeys: row.idempotencyKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                candidateCount: max(0, row.candidateCount ?? 0),
                summaryLine: row.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines),
                mirrorTarget: row.mirrorTarget.trimmingCharacters(in: .whitespacesAndNewlines),
                localStoreRole: row.localStoreRole.trimmingCharacters(in: .whitespacesAndNewlines),
                carrierKind: row.carrierKind.trimmingCharacters(in: .whitespacesAndNewlines),
                carrierSchemaVersion: row.carrierSchemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                pendingChangeId: row.pendingChangeId.trimmingCharacters(in: .whitespacesAndNewlines),
                pendingChangeStatus: row.pendingChangeStatus.trimmingCharacters(in: .whitespacesAndNewlines),
                editSessionId: row.editSessionId.trimmingCharacters(in: .whitespacesAndNewlines),
                docId: row.docId.trimmingCharacters(in: .whitespacesAndNewlines),
                writebackRef: row.writebackRef.trimmingCharacters(in: .whitespacesAndNewlines),
                stageCreatedAtMs: max(0, row.stageCreatedAtMs ?? 0),
                stageUpdatedAtMs: max(0, row.stageUpdatedAtMs ?? 0),
                latestEmittedAtMs: max(0, row.latestEmittedAtMs ?? 0),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                updatedAtMs: max(0, row.updatedAtMs ?? 0)
            )
        }

        return HubRemoteSupervisorCandidateReviewQueueResult(
            ok: true,
            source: (decoded.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: nil,
            logLines: []
        )
    }

    nonisolated static func remoteSupervisorCandidateReviewStageResultForTesting(
        jsonLine: String
    ) -> HubRemoteSupervisorCandidateReviewStageResult? {
        guard let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteSupervisorCandidateReviewStageScriptResult.self, from: data),
              decoded.ok == true else {
            return nil
        }

        return HubRemoteSupervisorCandidateReviewStageResult(
            ok: true,
            staged: decoded.staged ?? false,
            idempotent: decoded.idempotent ?? false,
            source: (decoded.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            reviewState: (decoded.reviewState ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            durablePromotionState: (decoded.durablePromotionState ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            promotionBoundary: (decoded.promotionBoundary ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            candidateRequestId: decoded.candidateRequestId?.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceRef: decoded.evidenceRef?.trimmingCharacters(in: .whitespacesAndNewlines),
            editSessionId: decoded.editSessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
            pendingChangeId: decoded.pendingChangeId?.trimmingCharacters(in: .whitespacesAndNewlines),
            docId: decoded.docId?.trimmingCharacters(in: .whitespacesAndNewlines),
            baseVersion: decoded.baseVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
            workingVersion: decoded.workingVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionRevision: Int64(decoded.sessionRevision ?? 0),
            status: decoded.status?.trimmingCharacters(in: .whitespacesAndNewlines),
            markdown: decoded.markdown,
            createdAtMs: max(0, decoded.createdAtMs ?? 0),
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            expiresAtMs: max(0, decoded.expiresAtMs ?? 0),
            reasonCode: nil,
            logLines: []
        )
    }

    nonisolated static func remoteLongtermMarkdownReviewResultForTesting(
        jsonLine: String
    ) -> HubRemoteLongtermMarkdownReviewResult? {
        guard let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteLongtermMarkdownReviewScriptResult.self, from: data),
              decoded.ok == true else {
            return nil
        }

        return HubRemoteLongtermMarkdownReviewResult(
            ok: true,
            source: (decoded.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pendingChangeId: decoded.pendingChangeId?.trimmingCharacters(in: .whitespacesAndNewlines),
            editSessionId: decoded.editSessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
            docId: decoded.docId?.trimmingCharacters(in: .whitespacesAndNewlines),
            status: decoded.status?.trimmingCharacters(in: .whitespacesAndNewlines),
            reviewDecision: decoded.reviewDecision?.trimmingCharacters(in: .whitespacesAndNewlines),
            policyDecision: decoded.policyDecision?.trimmingCharacters(in: .whitespacesAndNewlines),
            findingsJSON: decoded.findingsJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
            redactedCount: max(0, decoded.redactedCount ?? 0),
            reviewedAtMs: max(0, decoded.reviewedAtMs ?? 0),
            approvedAtMs: max(0, decoded.approvedAtMs ?? 0),
            markdown: decoded.markdown,
            autoRejected: decoded.autoRejected ?? false,
            reasonCode: nil,
            logLines: []
        )
    }

    nonisolated static func remoteLongtermMarkdownWritebackResultForTesting(
        jsonLine: String
    ) -> HubRemoteLongtermMarkdownWritebackResult? {
        guard let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteLongtermMarkdownWritebackScriptResult.self, from: data),
              decoded.ok == true else {
            return nil
        }

        return HubRemoteLongtermMarkdownWritebackResult(
            ok: true,
            source: (decoded.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pendingChangeId: decoded.pendingChangeId?.trimmingCharacters(in: .whitespacesAndNewlines),
            status: decoded.status?.trimmingCharacters(in: .whitespacesAndNewlines),
            candidateId: decoded.candidateId?.trimmingCharacters(in: .whitespacesAndNewlines),
            queueStatus: decoded.queueStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
            writtenAtMs: max(0, decoded.writtenAtMs ?? 0),
            docId: decoded.docId?.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceVersion: decoded.sourceVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
            changeLogId: decoded.changeLogId?.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceRef: decoded.evidenceRef?.trimmingCharacters(in: .whitespacesAndNewlines),
            reasonCode: nil,
            logLines: []
        )
    }

    nonisolated static func normalizedRemoteReasonCodeForTesting(
        _ rawReason: String?,
        stepOutput: String = "",
        fallback: String = "remote_chat_failed"
    ) -> String {
        normalizedRemoteReasonCode(
            rawReason: rawReason,
            stepOutput: stepOutput,
            fallback: fallback
        )
    }

    nonisolated static func inferredReusableInternetHostForTesting(
        _ host: String?,
        hubInstanceID: String? = nil,
        lanDiscoveryName: String? = nil
    ) -> String? {
        inferredReusableInternetHostValue(
            host,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )
    }

    private struct RemoteNetworkGrantScriptResult: Codable {
        var ok: Bool?
        var decision: String?
        var grantRequestId: String?
        var expiresAtMs: Double?
        var reason: String?
        var queued: Bool?
        var autoApproved: Bool?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case decision
            case grantRequestId = "grant_request_id"
            case expiresAtMs = "expires_at_ms"
            case reason
            case queued
            case autoApproved = "auto_approved"
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteWebFetchScriptResult: Codable {
        var ok: Bool?
        var status: Int?
        var finalURL: String?
        var contentType: String?
        var truncated: Bool?
        var bytes: Int?
        var text: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case status
            case finalURL = "final_url"
            case contentType = "content_type"
            case truncated
            case bytes
            case text
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteMutationScriptResult: Codable {
        var ok: Bool?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSkillCatalogEntryScriptResult: Codable {
        var skillID: String?
        var name: String?
        var version: String?
        var description: String?
        var publisherID: String?
        var capabilitiesRequired: [String]?
        var sourceID: String?
        var packageSHA256: String?
        var installHint: String?
        var riskLevel: String?
        var requiresGrant: Bool?
        var sideEffectClass: String?

        enum CodingKeys: String, CodingKey {
            case skillID = "skill_id"
            case name
            case version
            case description
            case publisherID = "publisher_id"
            case capabilitiesRequired = "capabilities_required"
            case sourceID = "source_id"
            case packageSHA256 = "package_sha256"
            case installHint = "install_hint"
            case riskLevel = "risk_level"
            case requiresGrant = "requires_grant"
            case sideEffectClass = "side_effect_class"
        }
    }

    private struct RemoteSkillsSearchScriptResult: Codable {
        struct OfficialSkillChannelStatus: Codable {
            var channelID: String?
            var status: String?
            var updatedAtMs: Int64?
            var lastAttemptAtMs: Int64?
            var lastSuccessAtMs: Int64?
            var skillCount: Int?
            var errorCode: String?
            var maintenanceEnabled: Bool?
            var maintenanceIntervalMs: Int64?
            var maintenanceLastRunAtMs: Int64?
            var maintenanceSourceKind: String?
            var lastTransitionAtMs: Int64?
            var lastTransitionKind: String?
            var lastTransitionSummary: String?

            enum CodingKeys: String, CodingKey {
                case channelID = "channel_id"
                case status
                case updatedAtMs = "updated_at_ms"
                case lastAttemptAtMs = "last_attempt_at_ms"
                case lastSuccessAtMs = "last_success_at_ms"
                case skillCount = "skill_count"
                case errorCode = "error_code"
                case maintenanceEnabled = "maintenance_enabled"
                case maintenanceIntervalMs = "maintenance_interval_ms"
                case maintenanceLastRunAtMs = "maintenance_last_run_at_ms"
                case maintenanceSourceKind = "maintenance_source_kind"
                case lastTransitionAtMs = "last_transition_at_ms"
                case lastTransitionKind = "last_transition_kind"
                case lastTransitionSummary = "last_transition_summary"
            }
        }

        var ok: Bool?
        var source: String?
        var updatedAtMs: Int64?
        var results: [RemoteSkillCatalogEntryScriptResult]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?
        var officialChannelStatus: OfficialSkillChannelStatus?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case results
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
            case officialChannelStatus = "official_channel_status"
        }
    }

    private struct RemoteSkillPinScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var scope: String?
        var userId: String?
        var projectId: String?
        var skillId: String?
        var packageSHA256: String?
        var previousPackageSHA256: String?
        var updatedAtMs: Int64?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case scope
            case userId = "user_id"
            case projectId = "project_id"
            case skillId = "skill_id"
            case packageSHA256 = "package_sha256"
            case previousPackageSHA256 = "previous_package_sha256"
            case updatedAtMs = "updated_at_ms"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteResolvedSkillEntryScriptResult: Codable {
        var scope: String?
        var skill: RemoteSkillCatalogEntryScriptResult?
    }

    private struct RemoteResolvedSkillsScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var skills: [RemoteResolvedSkillEntryScriptResult]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case skills
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteAgentImportStageScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var stagingId: String?
        var status: String?
        var auditRef: String?
        var preflightStatus: String?
        var skillId: String?
        var policyScope: String?
        var findingsCount: Int?
        var vetterStatus: String?
        var vetterCriticalCount: Int?
        var vetterWarnCount: Int?
        var vetterAuditRef: String?
        var recordPath: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case stagingId = "staging_id"
            case status
            case auditRef = "audit_ref"
            case preflightStatus = "preflight_status"
            case skillId = "skill_id"
            case policyScope = "policy_scope"
            case findingsCount = "findings_count"
            case vetterStatus = "vetter_status"
            case vetterCriticalCount = "vetter_critical_count"
            case vetterWarnCount = "vetter_warn_count"
            case vetterAuditRef = "vetter_audit_ref"
            case recordPath = "record_path"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteAgentImportRecordScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var selector: String?
        var stagingId: String?
        var status: String?
        var auditRef: String?
        var schemaVersion: String?
        var skillId: String?
        var projectId: String?
        var recordJSON: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case selector
            case stagingId = "staging_id"
            case status
            case auditRef = "audit_ref"
            case schemaVersion = "schema_version"
            case skillId = "skill_id"
            case projectId = "project_id"
            case recordJSON = "record_json"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSkillPackageUploadScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var packageSHA256: String?
        var alreadyPresent: Bool?
        var skillId: String?
        var version: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case packageSHA256 = "package_sha256"
            case alreadyPresent = "already_present"
            case skillId = "skill_id"
            case version
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteAgentImportPromoteScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var stagingId: String?
        var status: String?
        var auditRef: String?
        var packageSHA256: String?
        var scope: String?
        var skillId: String?
        var previousPackageSHA256: String?
        var recordPath: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case stagingId = "staging_id"
            case status
            case auditRef = "audit_ref"
            case packageSHA256 = "package_sha256"
            case scope
            case skillId = "skill_id"
            case previousPackageSHA256 = "previous_package_sha256"
            case recordPath = "record_path"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteMemorySnapshotScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var canonicalEntries: [String]?
        var workingEntries: [String]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case canonicalEntries = "canonical_entries"
            case workingEntries = "working_entries"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteMemoryRetrievalScriptItem: Codable {
        var ref: String?
        var sourceKind: String?
        var summary: String?
        var snippet: String?
        var score: Double?
        var redacted: Bool?

        enum CodingKeys: String, CodingKey {
            case ref
            case sourceKind = "source_kind"
            case summary
            case snippet
            case score
            case redacted
        }
    }

    private struct RemoteMemoryRetrievalScriptResult: Codable {
        var ok: Bool?
        var schemaVersion: String?
        var requestId: String?
        var status: String?
        var resolvedScope: String?
        var source: String?
        var scope: String?
        var auditRef: String?
        var reasonCode: String?
        var denyCode: String?
        var results: [RemoteMemoryRetrievalScriptItem]?
        var truncated: Bool?
        var budgetUsedChars: Int?
        var truncatedItems: Int?
        var redactedItems: Int?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case schemaVersion = "schema_version"
            case requestId = "request_id"
            case status
            case resolvedScope = "resolved_scope"
            case source
            case scope
            case auditRef = "audit_ref"
            case reasonCode = "reason_code"
            case denyCode = "deny_code"
            case results
            case truncated
            case budgetUsedChars = "budget_used_chars"
            case truncatedItems = "truncated_items"
            case redactedItems = "redacted_items"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSchedulerScopeInFlightRow: Codable {
        var scopeKey: String
        var inFlight: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case inFlight = "in_flight"
        }
    }

    private struct RemoteSchedulerScopeQueuedRow: Codable {
        var scopeKey: String
        var queued: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case queued
        }
    }

    private struct RemoteSchedulerQueueItemRow: Codable {
        var requestId: String
        var scopeKey: String
        var enqueuedAtMs: Double?
        var queuedMs: Int?

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case scopeKey = "scope_key"
            case enqueuedAtMs = "enqueued_at_ms"
            case queuedMs = "queued_ms"
        }
    }

    private struct RemoteSchedulerStatusScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var inFlightTotal: Int?
        var queueDepth: Int?
        var oldestQueuedMs: Int?
        var inFlightByScope: [RemoteSchedulerScopeInFlightRow]?
        var queuedByScope: [RemoteSchedulerScopeQueuedRow]?
        var queueItems: [RemoteSchedulerQueueItemRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case inFlightTotal = "in_flight_total"
            case queueDepth = "queue_depth"
            case oldestQueuedMs = "oldest_queued_ms"
            case inFlightByScope = "in_flight_by_scope"
            case queuedByScope = "queued_by_scope"
            case queueItems = "queue_items"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemotePendingGrantItemRow: Codable {
        var grantRequestId: String
        var requestId: String
        var deviceId: String
        var userId: String
        var appId: String
        var projectId: String
        var capability: String
        var modelId: String
        var reason: String
        var requestedTtlSec: Int?
        var requestedTokenCap: Int?
        var status: String
        var decision: String
        var createdAtMs: Double?
        var decidedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case grantRequestId = "grant_request_id"
            case requestId = "request_id"
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case projectId = "project_id"
            case capability
            case modelId = "model_id"
            case reason
            case requestedTtlSec = "requested_ttl_sec"
            case requestedTokenCap = "requested_token_cap"
            case status
            case decision
            case createdAtMs = "created_at_ms"
            case decidedAtMs = "decided_at_ms"
        }
    }

    private struct RemotePendingGrantRequestsScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemotePendingGrantItemRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSupervisorCandidateReviewQueueItemRow: Codable {
        var schemaVersion: String
        var reviewId: String
        var requestId: String
        var evidenceRef: String
        var reviewState: String
        var durablePromotionState: String
        var promotionBoundary: String
        var deviceId: String
        var userId: String
        var appId: String
        var threadId: String
        var threadKey: String
        var projectId: String
        var projectIds: [String]
        var scopes: [String]
        var recordTypes: [String]
        var auditRefs: [String]
        var idempotencyKeys: [String]
        var candidateCount: Int?
        var summaryLine: String
        var mirrorTarget: String
        var localStoreRole: String
        var carrierKind: String
        var carrierSchemaVersion: String
        var pendingChangeId: String
        var pendingChangeStatus: String
        var editSessionId: String
        var docId: String
        var writebackRef: String
        var stageCreatedAtMs: Double?
        var stageUpdatedAtMs: Double?
        var latestEmittedAtMs: Double?
        var createdAtMs: Double?
        var updatedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case reviewId = "review_id"
            case requestId = "request_id"
            case evidenceRef = "evidence_ref"
            case reviewState = "review_state"
            case durablePromotionState = "durable_promotion_state"
            case promotionBoundary = "promotion_boundary"
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case threadId = "thread_id"
            case threadKey = "thread_key"
            case projectId = "project_id"
            case projectIds = "project_ids"
            case scopes
            case recordTypes = "record_types"
            case auditRefs = "audit_refs"
            case idempotencyKeys = "idempotency_keys"
            case candidateCount = "candidate_count"
            case summaryLine = "summary_line"
            case mirrorTarget = "mirror_target"
            case localStoreRole = "local_store_role"
            case carrierKind = "carrier_kind"
            case carrierSchemaVersion = "carrier_schema_version"
            case pendingChangeId = "pending_change_id"
            case pendingChangeStatus = "pending_change_status"
            case editSessionId = "edit_session_id"
            case docId = "doc_id"
            case writebackRef = "writeback_ref"
            case stageCreatedAtMs = "stage_created_at_ms"
            case stageUpdatedAtMs = "stage_updated_at_ms"
            case latestEmittedAtMs = "latest_emitted_at_ms"
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
        }
    }

    private struct RemoteSupervisorCandidateReviewQueueScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemoteSupervisorCandidateReviewQueueItemRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSupervisorBriefProjectionRow: Codable {
        var schemaVersion: String
        var projectionId: String
        var projectionKind: String
        var projectId: String
        var runId: String
        var missionId: String
        var trigger: String
        var status: String
        var criticalBlocker: String
        var topline: String
        var nextBestAction: String
        var pendingGrantCount: Int?
        var ttsScript: [String]?
        var cardSummary: String
        var evidenceRefs: [String]?
        var generatedAtMs: Double?
        var expiresAtMs: Double?
        var auditRef: String

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case projectionId = "projection_id"
            case projectionKind = "projection_kind"
            case projectId = "project_id"
            case runId = "run_id"
            case missionId = "mission_id"
            case trigger
            case status
            case criticalBlocker = "critical_blocker"
            case topline
            case nextBestAction = "next_best_action"
            case pendingGrantCount = "pending_grant_count"
            case ttsScript = "tts_script"
            case cardSummary = "card_summary"
            case evidenceRefs = "evidence_refs"
            case generatedAtMs = "generated_at_ms"
            case expiresAtMs = "expires_at_ms"
            case auditRef = "audit_ref"
        }
    }

    private struct RemoteSupervisorBriefProjectionScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var projection: RemoteSupervisorBriefProjectionRow?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case projection
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteConnectorIngressReceiptRow: Codable {
        var receiptId: String
        var requestId: String
        var projectId: String
        var connector: String
        var targetId: String
        var ingressType: String
        var channelScope: String
        var sourceId: String
        var messageId: String
        var dedupeKey: String
        var receivedAtMs: Double?
        var eventSequence: Int64?
        var deliveryState: String
        var runtimeState: String

        enum CodingKeys: String, CodingKey {
            case receiptId = "receipt_id"
            case requestId = "request_id"
            case projectId = "project_id"
            case connector
            case targetId = "target_id"
            case ingressType = "ingress_type"
            case channelScope = "channel_scope"
            case sourceId = "source_id"
            case messageId = "message_id"
            case dedupeKey = "dedupe_key"
            case receivedAtMs = "received_at_ms"
            case eventSequence = "event_sequence"
            case deliveryState = "delivery_state"
            case runtimeState = "runtime_state"
        }
    }

    private struct RemoteConnectorIngressReceiptsScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemoteConnectorIngressReceiptRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteRuntimeSurfaceOverrideRow: Codable {
        var projectId: String
        var overrideMode: String
        var updatedAtMs: Double?
        var reason: String
        var auditRef: String

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case overrideMode = "override_mode"
            case updatedAtMs = "updated_at_ms"
            case reason
            case auditRef = "audit_ref"
        }
    }

    private struct RemoteRuntimeSurfaceOverridesScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemoteRuntimeSurfaceOverrideRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSecretVaultItemRow: Codable {
        var itemId: String
        var scope: String
        var name: String
        var sensitivity: String
        var createdAtMs: Double?
        var updatedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case scope
            case name
            case sensitivity
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
        }
    }

    private struct RemoteSecretVaultItemsScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemoteSecretVaultItemRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSecretVaultCreateScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var item: RemoteSecretVaultItemRow?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case item
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSecretVaultUseScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var leaseId: String?
        var useToken: String?
        var itemId: String?
        var expiresAtMs: Double?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case leaseId = "lease_id"
            case useToken = "use_token"
            case itemId = "item_id"
            case expiresAtMs = "expires_at_ms"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSecretVaultRedeemScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var leaseId: String?
        var itemId: String?
        var plaintextBytes: Double?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case leaseId = "lease_id"
            case itemId = "item_id"
            case plaintextBytes = "plaintext_bytes"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemotePendingGrantActionScriptResult: Codable {
        var ok: Bool?
        var decision: String?
        var grantRequestId: String?
        var grantId: String?
        var expiresAtMs: Double?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case decision
            case grantRequestId = "grant_request_id"
            case grantId = "grant_id"
            case expiresAtMs = "expires_at_ms"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteSupervisorCandidateReviewStageScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var staged: Bool?
        var idempotent: Bool?
        var reviewState: String?
        var durablePromotionState: String?
        var promotionBoundary: String?
        var candidateRequestId: String?
        var evidenceRef: String?
        var editSessionId: String?
        var pendingChangeId: String?
        var docId: String?
        var baseVersion: String?
        var workingVersion: String?
        var sessionRevision: Double?
        var status: String?
        var markdown: String?
        var createdAtMs: Double?
        var updatedAtMs: Double?
        var expiresAtMs: Double?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case staged
            case idempotent
            case reviewState = "review_state"
            case durablePromotionState = "durable_promotion_state"
            case promotionBoundary = "promotion_boundary"
            case candidateRequestId = "candidate_request_id"
            case evidenceRef = "evidence_ref"
            case editSessionId = "edit_session_id"
            case pendingChangeId = "pending_change_id"
            case docId = "doc_id"
            case baseVersion = "base_version"
            case workingVersion = "working_version"
            case sessionRevision = "session_revision"
            case status
            case markdown
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
            case expiresAtMs = "expires_at_ms"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteLongtermMarkdownReviewScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var pendingChangeId: String?
        var editSessionId: String?
        var docId: String?
        var status: String?
        var reviewDecision: String?
        var policyDecision: String?
        var findingsJSON: String?
        var redactedCount: Int?
        var reviewedAtMs: Double?
        var approvedAtMs: Double?
        var markdown: String?
        var autoRejected: Bool?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case pendingChangeId = "pending_change_id"
            case editSessionId = "edit_session_id"
            case docId = "doc_id"
            case status
            case reviewDecision = "review_decision"
            case policyDecision = "policy_decision"
            case findingsJSON = "findings_json"
            case redactedCount = "redacted_count"
            case reviewedAtMs = "reviewed_at_ms"
            case approvedAtMs = "approved_at_ms"
            case markdown
            case autoRejected = "auto_rejected"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteLongtermMarkdownWritebackScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var pendingChangeId: String?
        var status: String?
        var candidateId: String?
        var queueStatus: String?
        var writtenAtMs: Double?
        var docId: String?
        var sourceVersion: String?
        var changeLogId: String?
        var evidenceRef: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case pendingChangeId = "pending_change_id"
            case status
            case candidateId = "candidate_id"
            case queueStatus = "queue_status"
            case writtenAtMs = "written_at_ms"
            case docId = "doc_id"
            case sourceVersion = "source_version"
            case changeLogId = "change_log_id"
            case evidenceRef = "evidence_ref"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteVoiceWakeProfileRow: Codable {
        var schemaVersion: String
        var profileID: String
        var triggerWords: [String]
        var updatedAtMs: Double?
        var wakeMode: String
        var requiresPairingReady: Bool?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case profileID = "profile_id"
            case triggerWords = "trigger_words"
            case updatedAtMs = "updated_at_ms"
            case wakeMode = "wake_mode"
            case requiresPairingReady = "requires_pairing_ready"
            case auditRef = "audit_ref"
        }
    }

    private struct RemoteVoiceWakeProfileScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var profile: RemoteVoiceWakeProfileRow?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case profile
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteVoiceGrantChallengeRow: Codable {
        var challengeId: String
        var templateId: String
        var actionDigest: String
        var scopeDigest: String
        var amountDigest: String
        var challengeCode: String
        var riskLevel: String
        var requiresMobileConfirm: Bool?
        var allowVoiceOnly: Bool?
        var boundDeviceId: String
        var mobileTerminalId: String
        var issuedAtMs: Double?
        var expiresAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case challengeId = "challenge_id"
            case templateId = "template_id"
            case actionDigest = "action_digest"
            case scopeDigest = "scope_digest"
            case amountDigest = "amount_digest"
            case challengeCode = "challenge_code"
            case riskLevel = "risk_level"
            case requiresMobileConfirm = "requires_mobile_confirm"
            case allowVoiceOnly = "allow_voice_only"
            case boundDeviceId = "bound_device_id"
            case mobileTerminalId = "mobile_terminal_id"
            case issuedAtMs = "issued_at_ms"
            case expiresAtMs = "expires_at_ms"
        }
    }

    private struct RemoteVoiceGrantChallengeScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var challenge: RemoteVoiceGrantChallengeRow?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case challenge
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private struct RemoteVoiceGrantVerificationScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var verified: Bool?
        var decision: String?
        var denyCode: String?
        var challengeId: String?
        var transcriptHash: String?
        var semanticMatchScore: Double?
        var challengeMatch: Bool?
        var deviceBindingOk: Bool?
        var mobileConfirmed: Bool?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case verified
            case decision
            case denyCode = "deny_code"
            case challengeId = "challenge_id"
            case transcriptHash = "transcript_hash"
            case semanticMatchScore = "semantic_match_score"
            case challengeMatch = "challenge_match"
            case deviceBindingOk = "device_binding_ok"
            case mobileConfirmed = "mobile_confirmed"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    private func sanitize(_ options: HubRemoteConnectOptions) -> HubRemoteConnectOptions {
        var out = options
        out.grpcPort = max(1, min(65_535, options.grpcPort))
        out.pairingPort = max(1, min(65_535, options.pairingPort))
        let device = options.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        out.deviceName = device.isEmpty ? Host.current().localizedName ?? "X-Terminal" : device
        out.internetHost = options.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        out.axhubctlPath = options.axhubctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
        out.stateDir = options.stateDir ?? defaultStateDir()
        return out
    }

    private func appendStepLogs(into logs: inout [String], step: StepOutput) {
        logs.append("$ \(step.command)")
        if !step.output.isEmpty {
            logs.append(step.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        logs.append("(exit=\(step.exitCode))")
    }

    private func runLegacyBootstrapFlow(
        options opts: HubRemoteConnectOptions,
        hubHost: String,
        grpcPort: Int,
        preferredPairingPort: Int,
        env customEnv: [String: String],
        logs: inout [String]
    ) -> (ok: Bool, pairingPort: Int, reasonCode: String?) {
        let candidates = orderedPairingPortCandidates(preferredPairingPort)
        var lastFailureText = ""

        for p in candidates {
            logs.append("[bootstrap-fallback] try pairing_port=\(p)")
            let knock = runAxhubctl(
                args: [
                    "knock",
                    "--hub", hubHost,
                    "--pairing-port", "\(p)",
                    "--grpc-port", "\(grpcPort)",
                    "--device-name", opts.deviceName,
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 90.0
            )
            appendStepLogs(into: &logs, step: knock)
            if knock.exitCode != 0 {
                lastFailureText = knock.output
                continue
            }

            let wait = runAxhubctl(
                args: [
                    "wait",
                    "--hub", hubHost,
                    "--pairing-port", "\(p)",
                    "--grpc-port", "\(grpcPort)",
                    "--timeout-sec", "900",
                    "--interval-sec", "2",
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 1_300.0
            )
            appendStepLogs(into: &logs, step: wait)
            if wait.exitCode != 0 {
                lastFailureText = wait.output
                continue
            }

            // Best-effort: if old bootstrap path is bypassed, still try fetching client kit now.
            let install = runAxhubctl(
                args: [
                    "install-client",
                    "--hub", hubHost,
                    "--pairing-port", "\(p)",
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode != 0 {
                logs.append("[bootstrap-fallback] install-client failed (best-effort); continue with pairing.")
            }

            return (true, p, nil)
        }

        return (false, preferredPairingPort, inferFailureCode(from: lastFailureText, fallback: "bootstrap_failed"))
    }

    private func orderedPairingPortCandidates(_ preferred: Int) -> [Int] {
        var out: [Int] = []
        for p in [preferred] + Array(50052...50056) {
            let clamped = max(1, min(65_535, p))
            if !out.contains(clamped) {
                out.append(clamped)
            }
        }
        return out
    }

    private func shouldFallbackLegacyBootstrap(_ output: String) -> Bool {
        let text = output.lowercased()
        if text.contains("permission denied") {
            return true
        }
        if text.contains("unknown command: bootstrap") {
            return true
        }
        if text.contains("request failed: curl")
            || text.contains("empty reply from server")
            || text.contains("connection refused")
            || text.contains("failed to connect") {
            return true
        }
        return false
    }

    private func legacyConnectWithListModels(
        options opts: HubRemoteConnectOptions,
        env customEnv: [String: String],
        logs: inout [String],
        onProgress: (@Sendable (HubRemoteProgressEvent) -> Void)?
    ) -> HubRemoteConnectReport {
        logs.append("[fallback] axhubctl missing connect; legacy verify via list-models.")
        var list = runAxhubctl(
            args: ["list-models"],
            options: opts,
            env: customEnv,
            timeoutSec: 60.0
        )
        appendStepLogs(into: &logs, step: list)

        if list.exitCode != 0, shouldRetryAfterClientKitInstall(list.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: customEnv,
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                list = runAxhubctl(
                    args: ["list-models"],
                    options: opts,
                    env: customEnv,
                    timeoutSec: 60.0
                )
                appendStepLogs(into: &logs, step: list)
            }
        }

        if list.exitCode == 0 {
            let route: HubRemoteRoute = shouldRequireConfiguredHubHost(options: opts) ? .internet : .lan
            emit(onProgress, .connect, .succeeded, "legacy_list_models")
            return HubRemoteConnectReport(
                ok: true,
                route: route,
                summary: "connected_legacy_list_models",
                logLines: logs,
                reasonCode: nil
            )
        }

        let reason = inferFailureCode(from: list.output, fallback: "legacy_connect_failed")
        emit(onProgress, .connect, .failed, reason)
        return HubRemoteConnectReport(
            ok: false,
            route: .none,
            summary: reason,
            logLines: logs,
            reasonCode: reason
        )
    }

    private func runAxhubctl(
        args: [String],
        options: HubRemoteConnectOptions,
        env: [String: String],
        timeoutSec: Double
    ) -> StepOutput {
        let resolved = resolveAxhubctlExecutable(override: options.axhubctlPath)
        var commandDisplay = ""
        var result: ProcessResult

        do {
            switch resolved {
            case .direct(let path):
                commandDisplay = ([path] + args).joined(separator: " ")
                result = try ProcessCapture.run(
                    path,
                    args,
                    cwd: nil,
                    timeoutSec: timeoutSec,
                    env: mergedAxhubEnv(options: options, extra: env)
                )
            case .bashScript(let path):
                commandDisplay = (["/bin/bash", path] + args).joined(separator: " ")
                result = try ProcessCapture.run(
                    "/bin/bash",
                    [path] + args,
                    cwd: nil,
                    timeoutSec: timeoutSec,
                    env: mergedAxhubEnv(options: options, extra: env)
                )
            case .viaEnv:
                commandDisplay = (["axhubctl"] + args).joined(separator: " ")
                result = try ProcessCapture.run(
                    "/usr/bin/env",
                    ["axhubctl"] + args,
                    cwd: nil,
                    timeoutSec: timeoutSec,
                    env: mergedAxhubEnv(options: options, extra: env)
                )
            }
        } catch {
            return StepOutput(
                exitCode: 127,
                output: String(describing: error),
                command: commandDisplay.isEmpty ? ("axhubctl " + args.joined(separator: " ")) : commandDisplay
            )
        }

        return StepOutput(exitCode: result.exitCode, output: result.combined, command: commandDisplay)
    }

    private func resolveNodeExecutable(clientKitBaseDir: URL, env: [String: String]) -> String? {
        let fm = FileManager.default
        if let override = nonEmpty(env["AXHUBCTL_NODE_BIN"]), fm.isExecutableFile(atPath: override) {
            return override
        }

        if let bundled = preferredNodeBinPath(), fm.isExecutableFile(atPath: bundled) {
            return bundled
        }

        let kitNode = clientKitBaseDir.appendingPathComponent("bin/relflowhub_node").path
        if fm.isExecutableFile(atPath: kitNode) {
            return kitNode
        }

        let systemCandidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        for c in systemCandidates where fm.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    private func extractTrailingJSONObjectLine(_ text: String) -> String? {
        for raw in text.components(separatedBy: .newlines).reversed() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("{"), line.hasSuffix("}") {
                return line
            }
        }
        return nil
    }

    private func readEnvExports(from fileURL: URL) -> [String: String] {
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
            let lhs = String(candidate[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = String(candidate[candidate.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lhs.isEmpty else { continue }
            out[lhs] = unquoteShellValue(rhs)
        }
        return out
    }

    private func remoteGenerateScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const asText = (v) => (v == null ? '' : String(v));
const safe = (v) => asText(v).trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  const projectOverride = safe(process.env.XTERMINAL_GEN_PROJECT_ID || '');
  const sessionOverride = safe(process.env.XTERMINAL_GEN_SESSION_ID || '');
  const appOverride = safe(process.env.XTERMINAL_GEN_APP_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: appOverride || safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectOverride || safe(process.env.HUB_PROJECT_ID || ''),
    session_id: sessionOverride || safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function listModels(modelsClient, md, client) {
  return await new Promise((resolve, reject) => {
    modelsClient.ListModels({ client }, md, (err, out) => {
      if (err) reject(err);
      else resolve(Array.isArray(out?.models) ? out.models : []);
    });
  });
}

function normalizeWantedModelId(models, wantedModelId) {
  const wanted = safe(wantedModelId);
  if (!wanted) return '';

  const all = Array.isArray(models) ? models : [];
  const exact = all.find((m) => safe(m?.model_id || '').toLowerCase() === wanted.toLowerCase());
  if (exact) {
    return safe(exact?.model_id || '');
  }

  if (wanted.includes('/')) {
    return wanted;
  }

  const needle = wanted.toLowerCase();
  const suffixMatches = all.filter((m) => {
    const id = safe(m?.model_id || '').toLowerCase();
    if (!id) return false;
    return id === needle || id.endsWith(`/${needle}`);
  });
  if (suffixMatches.length === 1) {
    return safe(suffixMatches[0]?.model_id || '');
  }

  return wanted;
}

function selectModelId(models, wantedModelId) {
  const wanted = normalizeWantedModelId(models, wantedModelId);
  if (wanted) return wanted;
  const available = models.filter((m) => safe(m?.visibility) === 'MODEL_VISIBILITY_AVAILABLE');
  if (available.length > 0) {
    const id = safe(available[0]?.model_id || '');
    if (id) return id;
  }
  for (const m of models) {
    const id = safe(m?.model_id || '');
    if (id) return id;
  }
  return '';
}

function modelById(models, modelId) {
  const wanted = safe(modelId);
  if (!wanted) return null;
  const all = Array.isArray(models) ? models : [];
  const exact = all.find((m) => safe(m?.model_id || '').toLowerCase() === wanted.toLowerCase());
  if (exact) return exact;

  const normalized = normalizeWantedModelId(all, wanted);
  if (!normalized) return null;
  return all.find((m) => safe(m?.model_id || '').toLowerCase() === normalized.toLowerCase()) || null;
}

function modelIdsEquivalent(lhs, rhs) {
  const left = safe(lhs).toLowerCase();
  const right = safe(rhs).toLowerCase();
  if (!left || !right) return false;
  if (left === right) return true;

  const leftBase = left.includes('/') ? left.split('/').pop() : left;
  const rightBase = right.includes('/') ? right.split('/').pop() : right;
  return !!leftBase && leftBase === rightBase;
}

function isPaidModel(model) {
  const kind = safe(model?.kind || '');
  return kind === 'MODEL_KIND_PAID_ONLINE' || kind === '2';
}

function isLocalModel(model) {
  const kind = safe(model?.kind || '');
  if (kind === 'MODEL_KIND_LOCAL_OFFLINE' || kind === '1') return true;
  const backend = safe(model?.backend || '').toLowerCase();
  return backend === 'mlx';
}

function buildExecutionDescriptor(models, requestedModelId, actualModelId) {
  const requested = safe(requestedModelId);
  const actual = safe(actualModelId || requestedModelId);
  const requestedMeta = modelById(models, requested);
  const actualMeta = modelById(models, actual);
  const requestedPaid = isPaidModel(requestedMeta);
  const actualPaid = isPaidModel(actualMeta);
  const actualLocal = isLocalModel(actualMeta);

  if (!requestedPaid) {
    return {
      requested_model_id: requested,
      actual_model_id: actual,
      runtime_provider: 'Hub (Local)',
      execution_path: 'local_runtime',
      fallback_reason_code: '',
    };
  }

  if (requested && actual && !modelIdsEquivalent(requested, actual) && (actualLocal || !actualPaid)) {
    return {
      requested_model_id: requested,
      actual_model_id: actual,
      runtime_provider: 'Hub (Local)',
      execution_path: 'hub_downgraded_to_local',
      fallback_reason_code: 'downgrade_to_local',
    };
  }

  return {
    requested_model_id: requested,
    actual_model_id: actual,
    runtime_provider: 'Hub (Remote)',
    execution_path: 'remote_model',
    fallback_reason_code: '',
  };
}

async function generateOnce(aiClient, md, req, timeoutMs) {
  const stream = aiClient.Generate(req, md);
  return await new Promise((resolve, reject) => {
    let assistantText = '';
    let doneObj = null;
    let errObj = null;

    const timer = setTimeout(() => {
      try { stream.cancel(); } catch {}
      reject(new Error('remote_generate_timeout'));
    }, Math.max(4000, timeoutMs));

    stream.on('data', (ev) => {
      const which = safe(ev?.ev || '');
      const start = ev?.start || (which === 'start' ? ev?.start : null);
      const delta = ev?.delta || (which === 'delta' ? ev?.delta : null);
      const done = ev?.done || (which === 'done' ? ev?.done : null);
      const err = ev?.error || (which === 'error' ? ev?.error : null);

      if (start && safe(start.model_id || '')) {
        req.model_id = safe(start.model_id || req.model_id || '');
      }
      if (delta && typeof delta.text === 'string' && delta.text) {
        assistantText += delta.text;
      }
      if (done) doneObj = done;
      if (err) errObj = err;
    });

    stream.on('end', () => {
      clearTimeout(timer);
      resolve({ assistantText, done: doneObj, error: errObj, model_id: safe(req.model_id || '') });
    });
    stream.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

async function main() {
  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubAI) {
    throw new Error('hub_ai_missing');
  }

  const { creds, options } = await makeClientCreds();
  const aiClient = new proto.HubAI(addr, creds, options);
  const modelsClient = proto?.HubModels ? new proto.HubModels(addr, creds, options) : null;
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const reqId = safe(process.env.XTERMINAL_GEN_REQUEST_ID || `gen_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`);
  const wantedModelId = safe(process.env.XTERMINAL_GEN_MODEL_ID || '');
  const promptB64 = asText(process.env.XTERMINAL_GEN_PROMPT_B64 || '');
  const promptText = promptB64 ? Buffer.from(promptB64, 'base64').toString('utf8') : '';
  if (!safe(promptText)) {
    throw new Error('prompt_empty');
  }

  let models = [];
  let modelId = wantedModelId;
  if (modelsClient) {
    try {
      models = await listModels(modelsClient, md, client);
      modelId = selectModelId(models, wantedModelId);
    } catch {
      models = [];
      modelId = wantedModelId;
    }
  }
  if (!modelId) {
    throw new Error('no_model_routed');
  }

  const maxTokensRaw = Number.parseInt(safe(process.env.XTERMINAL_GEN_MAX_TOKENS || '768'), 10);
  const temperatureRaw = Number.parseFloat(safe(process.env.XTERMINAL_GEN_TEMPERATURE || '0.2'));
  const topPRaw = Number.parseFloat(safe(process.env.XTERMINAL_GEN_TOP_P || '0.95'));
  const timeoutSecRaw = Number.parseFloat(safe(process.env.XTERMINAL_GEN_TIMEOUT_SEC || '240'));
  const failClosedOnDowngrade = safe(process.env.XTERMINAL_GEN_FAIL_CLOSED_ON_DOWNGRADE || '') === '1';

  const req = {
    request_id: reqId,
    client,
    model_id: modelId,
    messages: [{ role: 'user', content: promptText }],
    max_tokens: Math.max(1, Math.min(8192, Number.isFinite(maxTokensRaw) ? maxTokensRaw : 768)),
    temperature: Math.max(0, Math.min(2, Number.isFinite(temperatureRaw) ? temperatureRaw : 0.2)),
    top_p: Math.max(0.01, Math.min(1, Number.isFinite(topPRaw) ? topPRaw : 0.95)),
    stream: true,
    created_at_ms: Date.now(),
    fail_closed_on_downgrade: failClosedOnDowngrade,
  };

  const streamResult = await generateOnce(
    aiClient,
    md,
    req,
    Math.max(8, Math.min(600, Number.isFinite(timeoutSecRaw) ? timeoutSecRaw : 240)) * 1000
  );

  const errPayload = streamResult?.error?.error || streamResult?.error || null;
  if (errPayload) {
    const code = safe(errPayload.code || '');
    const message = safe(errPayload.message || '');
    out({
      ok: false,
      text: '',
      model_id: streamResult?.model_id || modelId,
      reason: code || message || 'remote_chat_failed',
      error_code: code || message || 'remote_chat_failed',
      error_message: message || code || 'remote_chat_failed',
    });
    return;
  }

  const done = streamResult?.done || null;
  if (done && done.ok === false) {
    const reason = safe(done.reason || 'remote_chat_failed') || 'remote_chat_failed';
    out({
      ok: false,
      text: '',
      model_id: streamResult?.model_id || modelId,
      reason,
      error_code: reason,
      error_message: reason,
    });
    return;
  }

  const usage = done?.usage && typeof done.usage === 'object' ? done.usage : {};
  const promptTokens = Number(usage.prompt_tokens || 0) || 0;
  const completionTokens = Number(usage.completion_tokens || 0) || 0;
  const totalTokens = Number(usage.total_tokens || 0) || (promptTokens + completionTokens);
  const actualModelId = safe(streamResult?.model_id || modelId);
  const execution = buildExecutionDescriptor(models, modelId, actualModelId);

  out({
    ok: done ? done.ok !== false : true,
    text: asText(streamResult?.assistantText || ''),
    model_id: actualModelId || modelId,
    requested_model_id: execution.requested_model_id,
    actual_model_id: execution.actual_model_id,
    runtime_provider: execution.runtime_provider,
    execution_path: execution.execution_path,
    fallback_reason_code: execution.fallback_reason_code,
    reason: safe(done?.reason || 'eos') || 'eos',
    prompt_tokens: promptTokens,
    completion_tokens: completionTokens,
    total_tokens: totalTokens,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    text: '',
    reason: msg || 'remote_chat_failed',
    error_code: msg || 'remote_chat_failed',
    error_message: msg || 'remote_chat_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteNetworkGrantScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function requestGrant(grantsClient, md, req) {
  return await new Promise((resolve, reject) => {
    grantsClient.RequestGrant(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function waitGrantDecision(eventsClient, md, client, grantId, waitMs) {
  return await new Promise((resolve) => {
    let done = false;
    const finish = (payload) => {
      if (done) return;
      done = true;
      try { stream.cancel(); } catch {}
      clearTimeout(timer);
      resolve(payload || null);
    };

    const stream = eventsClient.Subscribe(
      {
        client,
        scopes: ['grants', 'requests'],
        last_event_id: '',
      },
      md
    );

    const timer = setTimeout(() => finish(null), Math.max(1000, waitMs));

    stream.on('data', (ev) => {
      const which = safe(ev?.ev || '');
      if (which !== 'grant_decision') return;
      const gd = ev?.grant_decision || null;
      const gid = safe(gd?.grant_request_id || '');
      if (!gid || gid !== grantId) return;
      finish({
        decision: safe(gd?.decision || ''),
        deny_reason: safe(gd?.deny_reason || ''),
      });
    });
    stream.on('error', () => finish(null));
    stream.on('end', () => finish(null));
  });
}

async function main() {
  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubGrants) {
    throw new Error('hub_grants_missing');
  }

  const { creds, options } = await makeClientCreds();
  const grantsClient = new proto.HubGrants(addr, creds, options);
  const eventsClient = proto?.HubEvents ? new proto.HubEvents(addr, creds, options) : null;
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const capability = safe(process.env.XTERMINAL_GRANT_CAPABILITY || 'CAPABILITY_WEB_FETCH');
  const reqId = `grant_${capability.toLowerCase()}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const reqSecondsRaw = Number.parseInt(safe(process.env.XTERMINAL_GRANT_SECONDS || '900'), 10);
  const reqSeconds = Math.max(30, Math.min(86400, Number.isFinite(reqSecondsRaw) ? reqSecondsRaw : 900));
  const waitSecRaw = Number.parseInt(safe(process.env.XTERMINAL_GRANT_WAIT_SEC || '10'), 10);
  const waitSec = Math.max(0, Math.min(60, Number.isFinite(waitSecRaw) ? waitSecRaw : 10));
  const requestedTokenCapRaw = Number.parseInt(safe(process.env.XTERMINAL_GRANT_TOKEN_CAP || '0'), 10);
  const requestedTokenCap = Math.max(0, Math.min(5000, Number.isFinite(requestedTokenCapRaw) ? requestedTokenCapRaw : 0));
  const modelId = safe(process.env.XTERMINAL_GRANT_MODEL_ID || '');
  const reason = safe(process.env.XTERMINAL_GRANT_REASON || 'x_terminal need_network');

  if (capability === 'CAPABILITY_AI_GENERATE_PAID' && !modelId) {
    throw new Error('grant_model_id_missing');
  }

  const resp = await requestGrant(grantsClient, md, {
    request_id: reqId,
    client,
    capability,
    model_id: modelId,
    reason,
    requested_ttl_sec: reqSeconds,
    requested_token_cap: requestedTokenCap,
    created_at_ms: Date.now(),
  });

  const decisionRaw = safe(resp?.decision || '');
  const grantRequestId = safe(resp?.grant_request_id || reqId);
  const expiresAtMs = Number(resp?.expires_at_ms || 0) || 0;
  const denyReason = safe(resp?.deny_reason || '');

  if (decisionRaw === 'GRANT_DECISION_APPROVED') {
    out({
      ok: true,
      decision: 'approved',
      grant_request_id: grantRequestId,
      expires_at_ms: expiresAtMs,
      queued: false,
      auto_approved: true,
    });
    return;
  }

  if (decisionRaw === 'GRANT_DECISION_DENIED' || decisionRaw === 'GRANT_DECISION_REJECTED') {
    out({
      ok: false,
      decision: 'denied',
      grant_request_id: grantRequestId,
      expires_at_ms: expiresAtMs,
      reason: denyReason || 'grant_denied',
      queued: false,
      auto_approved: false,
      error_code: denyReason || 'grant_denied',
    });
    return;
  }

  if (decisionRaw === 'GRANT_DECISION_QUEUED' && waitSec > 0 && eventsClient) {
    const decided = await waitGrantDecision(eventsClient, md, client, grantRequestId, waitSec * 1000);
    const d = safe(decided?.decision || '');
    if (d === 'GRANT_DECISION_APPROVED') {
      out({
        ok: true,
        decision: 'approved',
        grant_request_id: grantRequestId,
        expires_at_ms: expiresAtMs,
        queued: false,
        auto_approved: false,
      });
      return;
    }
    if (d === 'GRANT_DECISION_DENIED' || d === 'GRANT_DECISION_REJECTED') {
      const deny = safe(decided?.deny_reason || 'grant_denied');
      out({
        ok: false,
        decision: 'denied',
        grant_request_id: grantRequestId,
        expires_at_ms: expiresAtMs,
        reason: deny,
        queued: false,
        auto_approved: false,
        error_code: deny,
      });
      return;
    }
  }

  out({
    ok: true,
    decision: 'queued',
    grant_request_id: grantRequestId,
    expires_at_ms: expiresAtMs,
    queued: true,
    auto_approved: false,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    decision: 'failed',
    error_code: msg || 'remote_grant_failed',
    error_message: msg || 'remote_grant_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteWebFetchScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function fetchOnce(webClient, md, req) {
  return await new Promise((resolve, reject) => {
    const stream = webClient.Fetch(req, md);
    let doneObj = null;
    const chunks = [];

    stream.on('data', (ev) => {
      const which = safe(ev?.ev || '');
      const chunk = ev?.chunk || (which === 'chunk' ? ev?.chunk : null);
      const done = ev?.done || (which === 'done' ? ev?.done : null);
      if (chunk?.data) {
        chunks.push(Buffer.from(chunk.data));
      }
      if (done) {
        doneObj = done;
      }
    });

    stream.on('end', () => resolve({ done: doneObj, chunks }));
    stream.on('error', (e) => reject(e));
  });
}

async function main() {
  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const fetchURL = safe(process.env.XTERMINAL_FETCH_URL || '');
  if (!fetchURL) {
    throw new Error('empty_url');
  }

  const timeoutRaw = Number.parseFloat(safe(process.env.XTERMINAL_FETCH_TIMEOUT_SEC || '12'));
  const timeoutSec = Math.max(2, Math.min(60, Number.isFinite(timeoutRaw) ? timeoutRaw : 12));
  const maxBytesRaw = Number.parseInt(safe(process.env.XTERMINAL_FETCH_MAX_BYTES || '1000000'), 10);
  const maxBytes = Math.max(1024, Math.min(5000000, Number.isFinite(maxBytesRaw) ? maxBytesRaw : 1000000));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubWeb) {
    throw new Error('hub_web_missing');
  }

  const { creds, options } = await makeClientCreds();
  const webClient = new proto.HubWeb(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const req = {
    request_id: `web_fetch_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    client,
    url: fetchURL,
    method: 'GET',
    headers: {},
    timeout_sec: Math.floor(timeoutSec),
    max_bytes: Math.floor(maxBytes),
    created_at_ms: Date.now(),
    stream: false,
  };

  const resp = await fetchOnce(webClient, md, req);
  const done = resp?.done || null;
  const chunks = Array.isArray(resp?.chunks) ? resp.chunks : [];
  if (!done) {
    throw new Error('web_fetch_no_done_event');
  }

  let text = safe(done?.text || '');
  if (!text && chunks.length > 0) {
    try {
      text = Buffer.concat(chunks).toString('utf8');
    } catch {
      text = '';
    }
  }

  const errCode = safe(done?.error?.code || '');
  const errMessage = safe(done?.error?.message || '');

  out({
    ok: !!done?.ok,
    status: Number(done?.status || 0),
    final_url: safe(done?.final_url || fetchURL),
    content_type: safe(done?.content_type || ''),
    truncated: !!done?.truncated,
    bytes: Number(done?.bytes || 0),
    text,
    reason: errCode || errMessage || '',
    error_code: errCode || '',
    error_message: errMessage || '',
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    status: 0,
    final_url: safe(process.env.XTERMINAL_FETCH_URL || ''),
    content_type: '',
    truncated: false,
    bytes: 0,
    text: '',
    reason: msg || 'remote_web_fetch_failed',
    error_code: msg || 'remote_web_fetch_failed',
    error_message: msg || 'remote_web_fetch_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteProjectSyncScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  const projectId = safe(process.env.XTERMINAL_SYNC_PROJECT_ID || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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

async function upsert(memoryClient, md, client, key, value) {
  return await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client,
        scope: 'project',
        thread_id: '',
        key,
        value,
        pinned: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const client = reqClientFromEnv();
  if (!safe(client.project_id)) throw new Error('project_id_empty');

  const payload = {
    project_id: safe(process.env.XTERMINAL_SYNC_PROJECT_ID || ''),
    root_path: safe(process.env.XTERMINAL_SYNC_ROOT_PATH || ''),
    display_name: safe(process.env.XTERMINAL_SYNC_DISPLAY_NAME || ''),
    status_digest: safe(process.env.XTERMINAL_SYNC_STATUS_DIGEST || ''),
    last_summary_at: Number.parseFloat(safe(process.env.XTERMINAL_SYNC_LAST_SUMMARY_AT || '0')) || 0,
    last_event_at: Number.parseFloat(safe(process.env.XTERMINAL_SYNC_LAST_EVENT_AT || '0')) || 0,
    updated_at: Number.parseFloat(safe(process.env.XTERMINAL_SYNC_UPDATED_AT || `${Date.now() / 1000}`)) || (Date.now() / 1000),
  };

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();
  const key = 'xterminal.project.snapshot';
  const value = JSON.stringify(payload);
  await upsert(memoryClient, md, client, key, value);

  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({ ok: false, error_code: msg || 'remote_project_sync_failed', error_message: msg || 'remote_project_sync_failed' });
  process.exit(1);
});
"""#
    }

    private func remoteNotificationScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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

async function getOrCreateThread(memoryClient, md, client, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client, thread_key: threadKey }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
  return resp?.thread || null;
}

async function appendTurns(memoryClient, md, client, threadId, content) {
  return await new Promise((resolve, reject) => {
    memoryClient.AppendTurns(
      {
        request_id: `xterminal_notify_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        client,
        thread_id: threadId,
        messages: [{ role: 'assistant', content }],
        created_at_ms: Date.now(),
        allow_private: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function upsertLast(memoryClient, md, client, value) {
  return await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client,
        scope: 'device',
        thread_id: '',
        key: 'xterminal.notification.last',
        value,
        pinned: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();

  const source = safe(process.env.XTERMINAL_NOTIFY_SOURCE || 'X-Terminal');
  const title = safe(process.env.XTERMINAL_NOTIFY_TITLE || '');
  const body = safe(process.env.XTERMINAL_NOTIFY_BODY || '');
  if (!title) throw new Error('title_empty');
  const dedupe = safe(process.env.XTERMINAL_NOTIFY_DEDUPE || '');
  const action = safe(process.env.XTERMINAL_NOTIFY_ACTION_URL || '');
  const unread = ['1', 'true', 'yes'].includes(safe(process.env.XTERMINAL_NOTIFY_UNREAD || '').toLowerCase());

  const payload = {
    source,
    title,
    body,
    dedupe_key: dedupe || null,
    action_url: action || null,
    unread,
    created_at: Date.now(),
  };
  const line = `[Notification] ${title}\n${body || '(no body)'}\nsource=${source}${action ? `\naction=${action}` : ''}${dedupe ? `\ndedupe=${dedupe}` : ''}`;

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  const th = await getOrCreateThread(memoryClient, md, client, 'xterminal_notifications');
  const threadId = safe(th?.thread_id || '');
  if (!threadId) throw new Error('thread_missing');

  await appendTurns(memoryClient, md, client, threadId, line);
  await upsertLast(memoryClient, md, client, JSON.stringify(payload));
  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({ ok: false, error_code: msg || 'remote_notification_failed', error_message: msg || 'remote_notification_failed' });
  process.exit(1);
});
"""#
    }

    private func remoteSkillsSearchScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = projectIdOverride === undefined || projectIdOverride === null
    ? safe(process.env.HUB_PROJECT_ID || '')
    : safe(projectIdOverride);
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const query = safe(process.env.XTERMINAL_SKILLS_QUERY || '');
  const sourceFilter = safe(process.env.XTERMINAL_SKILLS_SOURCE_FILTER || '');
  const limit = Number.parseInt(safe(process.env.XTERMINAL_SKILLS_LIMIT || '20'), 10) || 20;
  const projectId = safe(process.env.XTERMINAL_SKILLS_PROJECT_ID || '');

  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv(projectId);

  const resp = await new Promise((resolve, reject) => {
    skillsClient.SearchSkills(
      {
        client,
        query,
        source_filter: sourceFilter,
        limit,
      },
      md,
      (err, result) => {
        if (err) reject(err);
        else resolve(result || {});
      }
    );
  });

  const results = Array.isArray(resp?.results) ? resp.results : [];
  const officialChannelStatus = resp?.official_channel_status && typeof resp.official_channel_status === 'object'
    ? {
      channel_id: safe(resp.official_channel_status.channel_id || ''),
      status: safe(resp.official_channel_status.status || ''),
      updated_at_ms: Number(resp.official_channel_status.updated_at_ms || 0),
      last_attempt_at_ms: Number(resp.official_channel_status.last_attempt_at_ms || 0),
      last_success_at_ms: Number(resp.official_channel_status.last_success_at_ms || 0),
      skill_count: Number(resp.official_channel_status.skill_count || 0),
      error_code: safe(resp.official_channel_status.error_code || ''),
      maintenance_enabled: !!resp.official_channel_status.maintenance_enabled,
      maintenance_interval_ms: Number(resp.official_channel_status.maintenance_interval_ms || 0),
      maintenance_last_run_at_ms: Number(resp.official_channel_status.maintenance_last_run_at_ms || 0),
      maintenance_source_kind: safe(resp.official_channel_status.maintenance_source_kind || ''),
      last_transition_at_ms: Number(resp.official_channel_status.last_transition_at_ms || 0),
      last_transition_kind: safe(resp.official_channel_status.last_transition_kind || ''),
      last_transition_summary: safe(resp.official_channel_status.last_transition_summary || ''),
    }
    : null;
  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: Number(resp?.updated_at_ms || 0),
    results: results.map((row) => ({
      skill_id: safe(row?.skill_id || ''),
      name: safe(row?.name || ''),
      version: safe(row?.version || ''),
      description: safe(row?.description || ''),
      publisher_id: safe(row?.publisher_id || ''),
      capabilities_required: Array.isArray(row?.capabilities_required) ? row.capabilities_required.map((item) => safe(item)).filter(Boolean) : [],
      source_id: safe(row?.source_id || ''),
      package_sha256: safe(row?.package_sha256 || ''),
      install_hint: safe(row?.install_hint || ''),
      risk_level: safe(row?.risk_level || ''),
      requires_grant: !!row?.requires_grant,
      side_effect_class: safe(row?.side_effect_class || ''),
    })),
    official_channel_status: officialChannelStatus,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    results: [],
    reason: msg || 'remote_skills_search_failed',
    error_code: msg || 'remote_skills_search_failed',
    error_message: msg || 'remote_skills_search_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteSkillPinScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = projectIdOverride === undefined || projectIdOverride === null
    ? safe(process.env.HUB_PROJECT_ID || '')
    : safe(projectIdOverride);
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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

function protoScope(scope) {
  if (scope === 'global') return 'SKILL_PIN_SCOPE_GLOBAL';
  if (scope === 'project') return 'SKILL_PIN_SCOPE_PROJECT';
  throw new Error('unsupported_skill_pin_scope');
}

function normalizedScope(scope) {
  if (scope === 'SKILL_PIN_SCOPE_GLOBAL') return 'global';
  if (scope === 'SKILL_PIN_SCOPE_PROJECT') return 'project';
  return safe(scope).toLowerCase();
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const scope = safe(process.env.XTERMINAL_SKILLS_PIN_SCOPE || '').toLowerCase();
  const skillId = safe(process.env.XTERMINAL_SKILLS_PIN_SKILL_ID || '');
  const packageSha = safe(process.env.XTERMINAL_SKILLS_PIN_PACKAGE_SHA256 || '').toLowerCase();
  const projectId = scope === 'project'
    ? safe(process.env.XTERMINAL_SKILLS_PIN_PROJECT_ID || '')
    : '';
  const note = safe(process.env.XTERMINAL_SKILLS_PIN_NOTE || '');
  const requestId = safe(process.env.XTERMINAL_SKILLS_PIN_REQUEST_ID || '');
  if (!skillId) throw new Error('missing_skill_id');
  if (!packageSha) throw new Error('missing_package_sha256');

  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv(projectId);

  const resp = await new Promise((resolve, reject) => {
    skillsClient.SetSkillPin(
      {
        client,
        request_id: requestId,
        scope: protoScope(scope),
        skill_id: skillId,
        package_sha256: packageSha,
        note,
        created_at_ms: Date.now(),
      },
      md,
      (err, result) => {
        if (err) reject(err);
        else resolve(result || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    scope: normalizedScope(resp?.scope || scope),
    user_id: safe(resp?.user_id || ''),
    project_id: safe(resp?.project_id || projectId),
    skill_id: safe(resp?.skill_id || skillId),
    package_sha256: safe(resp?.package_sha256 || packageSha),
    previous_package_sha256: safe(resp?.previous_package_sha256 || ''),
    updated_at_ms: Number(resp?.updated_at_ms || 0),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    scope: safe(process.env.XTERMINAL_SKILLS_PIN_SCOPE || ''),
    user_id: '',
    project_id: safe(process.env.XTERMINAL_SKILLS_PIN_PROJECT_ID || ''),
    skill_id: safe(process.env.XTERMINAL_SKILLS_PIN_SKILL_ID || ''),
    package_sha256: safe(process.env.XTERMINAL_SKILLS_PIN_PACKAGE_SHA256 || ''),
    previous_package_sha256: '',
    updated_at_ms: 0,
    reason: msg || 'remote_skill_pin_failed',
    error_code: msg || 'remote_skill_pin_failed',
    error_message: msg || 'remote_skill_pin_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteResolvedSkillsScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = projectIdOverride === undefined || projectIdOverride === null
    ? safe(process.env.HUB_PROJECT_ID || '')
    : safe(projectIdOverride);
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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

function normalizedScope(scope) {
  if (scope === 'SKILL_PIN_SCOPE_GLOBAL') return 'global';
  if (scope === 'SKILL_PIN_SCOPE_PROJECT') return 'project';
  return safe(scope).toLowerCase();
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const projectId = safe(process.env.XTERMINAL_RESOLVED_SKILLS_PROJECT_ID || '');

  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv(projectId);

  const resp = await new Promise((resolve, reject) => {
    skillsClient.ListResolvedSkills(
      { client },
      md,
      (err, result) => {
        if (err) reject(err);
        else resolve(result || {});
      }
    );
  });

  const skills = Array.isArray(resp?.skills) ? resp.skills : [];
  out({
    ok: true,
    source: 'hub_runtime_grpc',
    skills: skills.map((row) => ({
      scope: normalizedScope(row?.scope || ''),
      skill: {
        skill_id: safe(row?.skill?.skill_id || ''),
        name: safe(row?.skill?.name || ''),
        version: safe(row?.skill?.version || ''),
        description: safe(row?.skill?.description || ''),
        publisher_id: safe(row?.skill?.publisher_id || ''),
        capabilities_required: Array.isArray(row?.skill?.capabilities_required) ? row.skill.capabilities_required.map((item) => safe(item)).filter(Boolean) : [],
        source_id: safe(row?.skill?.source_id || ''),
        package_sha256: safe(row?.skill?.package_sha256 || ''),
        install_hint: safe(row?.skill?.install_hint || ''),
        risk_level: safe(row?.skill?.risk_level || ''),
        requires_grant: !!row?.skill?.requires_grant,
        side_effect_class: safe(row?.skill?.side_effect_class || ''),
      },
    })),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    skills: [],
    reason: msg || 'remote_resolved_skills_failed',
    error_code: msg || 'remote_resolved_skills_failed',
    error_message: msg || 'remote_resolved_skills_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteAgentImportStageScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();

  const importManifestJson = safe(process.env.XTERMINAL_AGENT_IMPORT_MANIFEST_JSON || '');
  if (!importManifestJson) throw new Error('missing_agent_import_manifest');
  const findingsJson = safe(process.env.XTERMINAL_AGENT_IMPORT_FINDINGS_JSON || '');
  const scanInputJson = safe(process.env.XTERMINAL_AGENT_IMPORT_SCAN_INPUT_JSON || '');
  const requestedBy = safe(process.env.XTERMINAL_AGENT_IMPORT_REQUESTED_BY || '');
  const note = safe(process.env.XTERMINAL_AGENT_IMPORT_NOTE || '');
  const requestId = safe(process.env.XTERMINAL_AGENT_IMPORT_REQUEST_ID || '');

  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  if (typeof skillsClient.StageAgentImport !== 'function') {
    throw new Error('hub_agent_import_unimplemented');
  }

  const resp = await new Promise((resolve, reject) => {
    skillsClient.StageAgentImport(
      {
        client,
        request_id: requestId,
        import_manifest_json: importManifestJson,
        findings_json: findingsJson,
        scan_input_json: scanInputJson,
        requested_by: requestedBy,
        note,
        created_at_ms: Date.now(),
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    staging_id: safe(resp?.staging_id || ''),
    status: safe(resp?.status || ''),
    audit_ref: safe(resp?.audit_ref || ''),
    preflight_status: safe(resp?.preflight_status || ''),
    skill_id: safe(resp?.skill_id || ''),
    policy_scope: safe(resp?.policy_scope || ''),
    findings_count: Number(resp?.findings_count || 0),
    vetter_status: safe(resp?.vetter_status || ''),
    vetter_critical_count: Number(resp?.vetter_critical_count || 0),
    vetter_warn_count: Number(resp?.vetter_warn_count || 0),
    vetter_audit_ref: safe(resp?.vetter_audit_ref || ''),
    record_path: safe(resp?.record_path || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('hub_agent_import_unimplemented') || lower.includes('unimplemented')
    ? 'hub_agent_import_unimplemented'
    : (msg || 'remote_agent_import_stage_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteAgentImportRecordScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
  const stagingId = safe(process.env.XTERMINAL_AGENT_IMPORT_STAGING_ID || '');
  if (!stagingId) throw new Error('missing_agent_staging_id');
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();

  const resp = await new Promise((resolve, reject) => {
    skillsClient.GetAgentImportRecord(
      {
        client,
        staging_id: stagingId,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    staging_id: safe(resp?.staging_id || ''),
    status: safe(resp?.status || ''),
    audit_ref: safe(resp?.audit_ref || ''),
    schema_version: safe(resp?.schema_version || ''),
    skill_id: safe(resp?.skill_id || ''),
    record_json: safe(resp?.record_json || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    reason: msg || 'remote_agent_import_record_failed',
    error_code: msg || 'remote_agent_import_record_failed',
    error_message: msg || 'remote_agent_import_record_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteResolvedAgentImportRecordScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
  const selector = safe(process.env.XTERMINAL_AGENT_IMPORT_SELECTOR || '');
  const skillId = safe(process.env.XTERMINAL_AGENT_IMPORT_SKILL_ID || '');
  const projectId = safe(process.env.XTERMINAL_AGENT_IMPORT_PROJECT_ID || '');
  if (!selector) throw new Error('missing_agent_import_selector');
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();

  const resp = await new Promise((resolve, reject) => {
    skillsClient.ResolveAgentImportRecord(
      {
        client,
        selector,
        skill_id: skillId,
        project_id: projectId,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    selector: safe(resp?.selector || ''),
    staging_id: safe(resp?.staging_id || ''),
    status: safe(resp?.status || ''),
    audit_ref: safe(resp?.audit_ref || ''),
    schema_version: safe(resp?.schema_version || ''),
    skill_id: safe(resp?.skill_id || ''),
    project_id: safe(resp?.project_id || ''),
    record_json: safe(resp?.record_json || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    selector: safe(process.env.XTERMINAL_AGENT_IMPORT_SELECTOR || ''),
    reason: msg || 'remote_agent_import_record_resolve_failed',
    error_code: msg || 'remote_agent_import_record_resolve_failed',
    error_message: msg || 'remote_agent_import_record_resolve_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteSkillPackageUploadScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
  const packagePath = safe(process.env.XTERMINAL_UPLOAD_SKILL_PACKAGE_PATH || '');
  const manifestJSON = safe(process.env.XTERMINAL_UPLOAD_SKILL_MANIFEST_JSON || '');
  const sourceId = safe(process.env.XTERMINAL_UPLOAD_SKILL_SOURCE_ID || 'local:xt-import');
  const requestId = safe(process.env.XTERMINAL_UPLOAD_SKILL_REQUEST_ID || '');
  if (!packagePath) throw new Error('missing_package_path');
  if (!manifestJSON) throw new Error('missing_manifest_json');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  const packageBytes = fs.readFileSync(packagePath);

  const resp = await new Promise((resolve, reject) => {
    skillsClient.UploadSkillPackage(
      {
        client,
        request_id: requestId,
        source_id: sourceId,
        package_bytes: packageBytes,
        manifest_json: manifestJSON,
        created_at_ms: Date.now(),
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    package_sha256: safe(resp?.package_sha256 || ''),
    already_present: !!resp?.already_present,
    skill_id: safe(resp?.skill?.skill_id || ''),
    version: safe(resp?.skill?.version || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    reason: msg || 'remote_skill_package_upload_failed',
    error_code: msg || 'remote_skill_package_upload_failed',
    error_message: msg || 'remote_skill_package_upload_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteAgentImportPromoteScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
  const stagingId = safe(process.env.XTERMINAL_AGENT_IMPORT_STAGING_ID || '');
  const packageSHA256 = safe(process.env.XTERMINAL_AGENT_IMPORT_PACKAGE_SHA256 || '');
  const note = safe(process.env.XTERMINAL_AGENT_IMPORT_NOTE || '');
  const requestId = safe(process.env.XTERMINAL_AGENT_IMPORT_REQUEST_ID || '');
  if (!stagingId) throw new Error('missing_agent_staging_id');
  if (!packageSHA256) throw new Error('missing_package_sha256');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();

  const resp = await new Promise((resolve, reject) => {
    skillsClient.PromoteAgentImport(
      {
        client,
        request_id: requestId,
        staging_id: stagingId,
        package_sha256: packageSHA256,
        note,
        created_at_ms: Date.now(),
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    staging_id: safe(resp?.staging_id || ''),
    status: safe(resp?.status || ''),
    audit_ref: safe(resp?.audit_ref || ''),
    package_sha256: safe(resp?.package_sha256 || ''),
    scope: safe(resp?.scope || ''),
    skill_id: safe(resp?.skill_id || ''),
    previous_package_sha256: safe(resp?.previous_package_sha256 || ''),
    record_path: safe(resp?.record_path || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    reason: msg || 'remote_agent_import_promote_failed',
    error_code: msg || 'remote_agent_import_promote_failed',
    error_message: msg || 'remote_agent_import_promote_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteProjectConversationAppendScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = safe(projectIdOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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

async function getOrCreateThread(memoryClient, md, client, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client, thread_key: threadKey }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
  return resp?.thread || null;
}

async function appendTurns(memoryClient, md, client, threadId, requestId, createdAtMs, userText, assistantText) {
  const messages = [];
  if (userText) messages.push({ role: 'user', content: userText });
  if (assistantText) messages.push({ role: 'assistant', content: assistantText });
  if (messages.length === 0) throw new Error('turn_empty');

  return await new Promise((resolve, reject) => {
    memoryClient.AppendTurns(
      {
        request_id: requestId,
        client,
        thread_id: threadId,
        messages,
        created_at_ms: createdAtMs,
        allow_private: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_CONV_PROJECT_ID || '');
  const threadKey = safe(process.env.XTERMINAL_CONV_THREAD_KEY || '');
  const requestId = safe(process.env.XTERMINAL_CONV_REQUEST_ID || '');
  const userText = safe(process.env.XTERMINAL_CONV_USER_TEXT || '');
  const assistantText = safe(process.env.XTERMINAL_CONV_ASSISTANT_TEXT || '');
  const createdAtMsRaw = Number.parseInt(safe(process.env.XTERMINAL_CONV_CREATED_AT_MS || `${Date.now()}`), 10);
  const createdAtMs = Number.isFinite(createdAtMsRaw) ? createdAtMsRaw : Date.now();

  if (!projectId) throw new Error('project_id_empty');
  if (!threadKey) throw new Error('thread_key_empty');
  if (!requestId) throw new Error('request_id_empty');
  if (!userText && !assistantText) throw new Error('turn_empty');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv(projectId);

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  const th = await getOrCreateThread(memoryClient, md, client, threadKey);
  const threadId = safe(th?.thread_id || '');
  if (!threadId) throw new Error('thread_missing');

  await appendTurns(memoryClient, md, client, threadId, requestId, createdAtMs, userText, assistantText);
  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({ ok: false, error_code: msg || 'remote_project_conversation_append_failed', error_message: msg || 'remote_project_conversation_append_failed' });
  process.exit(1);
});
"""#
    }

    private func remoteSupervisorConversationAppendScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: '',
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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

async function getOrCreateThread(memoryClient, md, client, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client, thread_key: threadKey }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
  return resp?.thread || null;
}

async function appendTurns(memoryClient, md, client, threadId, requestId, createdAtMs, userText, assistantText) {
  const messages = [];
  if (userText) messages.push({ role: 'user', content: userText });
  if (assistantText) messages.push({ role: 'assistant', content: assistantText });
  if (messages.length === 0) throw new Error('turn_empty');

  return await new Promise((resolve, reject) => {
    memoryClient.AppendTurns(
      {
        request_id: requestId,
        client,
        thread_id: threadId,
        messages,
        created_at_ms: createdAtMs,
        allow_private: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const threadKey = safe(process.env.XTERMINAL_SUPERVISOR_CONV_THREAD_KEY || '');
  const requestId = safe(process.env.XTERMINAL_SUPERVISOR_CONV_REQUEST_ID || '');
  const userText = safe(process.env.XTERMINAL_SUPERVISOR_CONV_USER_TEXT || '');
  const assistantText = safe(process.env.XTERMINAL_SUPERVISOR_CONV_ASSISTANT_TEXT || '');
  const createdAtMsRaw = Number.parseInt(safe(process.env.XTERMINAL_SUPERVISOR_CONV_CREATED_AT_MS || `${Date.now()}`), 10);
  const createdAtMs = Number.isFinite(createdAtMsRaw) ? createdAtMsRaw : Date.now();

  if (!threadKey) throw new Error('thread_key_empty');
  if (!requestId) throw new Error('request_id_empty');
  if (!userText && !assistantText) throw new Error('turn_empty');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  const th = await getOrCreateThread(memoryClient, md, client, threadKey);
  const threadId = safe(th?.thread_id || '');
  if (!threadId) throw new Error('thread_missing');

  await appendTurns(memoryClient, md, client, threadId, requestId, createdAtMs, userText, assistantText);
  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({ ok: false, error_code: msg || 'remote_supervisor_conversation_append_failed', error_message: msg || 'remote_supervisor_conversation_append_failed' });
  process.exit(1);
});
"""#
    }

    private func remoteProjectCanonicalMemoryUpsertScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = safe(projectIdOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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

async function upsert(memoryClient, md, client, key, value) {
  return await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client,
        scope: 'project',
        thread_id: '',
        key,
        value,
        pinned: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_PROJECT_MEMORY_PROJECT_ID || process.env.HUB_PROJECT_ID || '');
  if (!projectId) throw new Error('project_id_empty');

  const encoded = safe(process.env.XTERMINAL_PROJECT_MEMORY_ITEMS_B64 || '');
  if (!encoded) throw new Error('project_memory_items_missing');

  let items = [];
  try {
    items = JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'));
  } catch {
    throw new Error('project_memory_items_invalid');
  }
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error('project_memory_items_empty');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const client = reqClientFromEnv(projectId);
  if (!safe(client.project_id)) throw new Error('project_id_empty');

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  for (const row of items) {
    const key = safe(row?.key || '');
    const value = safe(row?.value || '');
    if (!key || !value) continue;
    await upsert(memoryClient, md, client, key, value);
  }

  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    error_code: msg || 'remote_project_canonical_memory_upsert_failed',
    error_message: msg || 'remote_project_canonical_memory_upsert_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteDeviceCanonicalMemoryUpsertScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: '',
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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

async function upsert(memoryClient, md, client, key, value) {
  return await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client,
        scope: 'device',
        thread_id: '',
        key,
        value,
        pinned: false,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
}

async function main() {
  const encoded = safe(process.env.XTERMINAL_DEVICE_MEMORY_ITEMS_B64 || '');
  if (!encoded) throw new Error('device_canonical_memory_items_missing');

  let items = [];
  try {
    items = JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'));
  } catch {
    throw new Error('device_canonical_memory_items_invalid');
  }
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error('device_canonical_memory_items_empty');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  for (const row of items) {
    const key = safe(row?.key || '');
    const value = safe(row?.value || '');
    if (!key || !value) continue;
    await upsert(memoryClient, md, client, key, value);
  }

  out({ ok: true });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    error_code: msg || 'remote_device_canonical_memory_upsert_failed',
    error_message: msg || 'remote_device_canonical_memory_upsert_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteMemorySnapshotScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = safe(projectIdOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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

async function listCanonical(memoryClient, md, client, scope, limit) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.ListCanonicalMemory(
      {
        client,
        scope,
        thread_id: '',
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
  return Array.isArray(resp?.items) ? resp.items : [];
}

async function getOrCreateThread(memoryClient, md, client, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client, thread_key: threadKey }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
  return resp?.thread || null;
}

async function getWorkingSet(memoryClient, md, client, threadId, limit) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetWorkingSet(
      {
        client,
        thread_id: threadId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });
  return Array.isArray(resp?.messages) ? resp.messages : [];
}

function clipText(v, n = 360) {
  const s = safe(v);
  if (!s) return '';
  if (s.length <= n) return s;
  return `${s.slice(0, n)}…`;
}

async function main() {
  const mode = safe(process.env.XTERMINAL_MEM_MODE || 'project').toLowerCase();
  const projectId = safe(process.env.XTERMINAL_MEM_PROJECT_ID || '');
  const canonicalLimitRaw = Number.parseInt(safe(process.env.XTERMINAL_MEM_CANONICAL_LIMIT || '24'), 10);
  const workingLimitRaw = Number.parseInt(safe(process.env.XTERMINAL_MEM_WORKING_LIMIT || '12'), 10);
  const canonicalLimit = Math.max(1, Math.min(80, Number.isFinite(canonicalLimitRaw) ? canonicalLimitRaw : 24));
  const workingLimit = Math.max(1, Math.min(80, Number.isFinite(workingLimitRaw) ? workingLimitRaw : 12));

  const scope = mode === 'project' ? 'project' : 'device';
  const client = reqClientFromEnv(mode === 'project' ? projectId : '');
  if (scope === 'project' && !safe(client.project_id)) {
    throw new Error('project_id_empty');
  }

  const threadKey = scope === 'project'
    ? `xterminal_project_${safe(client.project_id)}`
    : 'xterminal_supervisor_device';

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();

  const canonicalItems = await listCanonical(memoryClient, md, client, scope, canonicalLimit);
  const canonicalEntries = canonicalItems
    .map((it) => {
      const key = safe(it?.key || '');
      const value = clipText(it?.value || '', 460);
      if (!key || !value) return '';
      return `${key} = ${value}`;
    })
    .filter(Boolean);

  const th = await getOrCreateThread(memoryClient, md, client, threadKey);
  const threadId = safe(th?.thread_id || '');
  let workingEntries = [];
  if (threadId) {
    const ws = await getWorkingSet(memoryClient, md, client, threadId, workingLimit);
    workingEntries = ws
      .map((m) => {
        const role = safe(m?.role || 'assistant');
        const content = clipText(m?.content || '', 420);
        if (!content) return '';
        return `${role}: ${content}`;
      })
      .filter(Boolean);
  }

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    canonical_entries: canonicalEntries,
    working_entries: workingEntries,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    canonical_entries: [],
    working_entries: [],
    reason: msg || 'remote_memory_snapshot_failed',
    error_code: msg || 'remote_memory_snapshot_failed',
    error_message: msg || 'remote_memory_snapshot_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remoteMemoryRetrievalScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = projectIdOverride === undefined || projectIdOverride === null
    ? safe(process.env.HUB_PROJECT_ID || '')
    : safe(projectIdOverride);
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

function parseJsonList(raw) {
  const text = safe(raw);
  if (!text) return [];
  try {
    const decoded = JSON.parse(text);
    if (!Array.isArray(decoded)) return [];
    return decoded.map((item) => safe(item)).filter(Boolean);
  } catch {
    return [];
  }
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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

async function retrieveMemory(memoryClient, md, payload) {
  return await new Promise((resolve, reject) => {
    memoryClient.RetrieveMemory(payload, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;

  const projectId = safe(process.env.XTERMINAL_MEM_RETR_PROJECT_ID || process.env.HUB_PROJECT_ID || '');
  const client = reqClientFromEnv(projectId);
  const payload = {
    schema_version: safe(process.env.XTERMINAL_MEM_RETR_SCHEMA_VERSION || 'xt.memory_retrieval_request.v1'),
    request_id: safe(process.env.XTERMINAL_MEM_RETR_REQUEST_ID || ''),
    client,
    scope: safe(process.env.XTERMINAL_MEM_RETR_SCOPE || 'current_project'),
    requester_role: safe(process.env.XTERMINAL_MEM_RETR_REQUESTER_ROLE || 'chat'),
    mode: safe(process.env.XTERMINAL_MEM_RETR_MODE || 'project_chat'),
    project_id: projectId,
    cross_project_target_ids: parseJsonList(process.env.XTERMINAL_MEM_RETR_CROSS_PROJECT_TARGET_IDS_JSON || '[]'),
    project_root: safe(process.env.XTERMINAL_MEM_RETR_PROJECT_ROOT || ''),
    display_name: safe(process.env.XTERMINAL_MEM_RETR_DISPLAY_NAME || ''),
    query: safe(process.env.XTERMINAL_MEM_RETR_QUERY || ''),
    latest_user: safe(process.env.XTERMINAL_MEM_RETR_LATEST_USER || ''),
    allowed_layers: parseJsonList(process.env.XTERMINAL_MEM_RETR_ALLOWED_LAYERS_JSON || '[]'),
    retrieval_kind: safe(process.env.XTERMINAL_MEM_RETR_RETRIEVAL_KIND || ''),
    max_results: Number.parseInt(safe(process.env.XTERMINAL_MEM_RETR_MAX_RESULTS || '3'), 10) || 3,
    reason: safe(process.env.XTERMINAL_MEM_RETR_REASON || ''),
    require_explainability: ['1', 'true', 'yes'].includes(safe(process.env.XTERMINAL_MEM_RETR_REQUIRE_EXPLAINABILITY || '').toLowerCase()),
    requested_kinds: parseJsonList(process.env.XTERMINAL_MEM_RETR_REQUESTED_KINDS_JSON || '[]'),
    explicit_refs: parseJsonList(process.env.XTERMINAL_MEM_RETR_EXPLICIT_REFS_JSON || '[]'),
    max_snippets: Number.parseInt(safe(process.env.XTERMINAL_MEM_RETR_MAX_SNIPPETS || '3'), 10) || 3,
    max_snippet_chars: Number.parseInt(safe(process.env.XTERMINAL_MEM_RETR_MAX_SNIPPET_CHARS || '420'), 10) || 420,
    audit_ref: safe(process.env.XTERMINAL_MEM_RETR_AUDIT_REF || ''),
  };

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();
  const response = await retrieveMemory(memoryClient, md, payload);

  out({
    ok: true,
    ...response,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    schema_version: 'xt.memory_retrieval_result.v1',
    request_id: safe(process.env.XTERMINAL_MEM_RETR_REQUEST_ID || ''),
    status: '',
    resolved_scope: safe(process.env.XTERMINAL_MEM_RETR_SCOPE || 'current_project'),
    source: 'hub_memory_retrieval_grpc_v1',
    scope: safe(process.env.XTERMINAL_MEM_RETR_SCOPE || 'current_project'),
    audit_ref: safe(process.env.XTERMINAL_MEM_RETR_AUDIT_REF || ''),
    reason: msg || 'remote_memory_retrieval_failed',
    reason_code: msg || 'remote_memory_retrieval_failed',
    deny_code: '',
    results: [],
    truncated: false,
    budget_used_chars: 0,
    truncated_items: 0,
    redacted_items: 0,
    error_code: msg || 'remote_memory_retrieval_failed',
    error_message: msg || 'remote_memory_retrieval_failed',
  });
  process.exit(1);
});
"""#
    }

    private func remotePendingGrantRequestsScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_PENDING_GRANTS_PROJECT_ID || '');
  const limitRaw = Number.parseInt(safe(process.env.XTERMINAL_PENDING_GRANTS_LIMIT || '200'), 10);
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient.GetPendingGrantRequests(
      {
        client,
        project_id: projectId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        grant_request_id: safe(it?.grant_request_id || ''),
        request_id: safe(it?.request_id || ''),
        device_id: safe(it?.client?.device_id || ''),
        user_id: safe(it?.client?.user_id || ''),
        app_id: safe(it?.client?.app_id || ''),
        project_id: safe(it?.client?.project_id || ''),
        capability: safe(it?.capability || ''),
        model_id: safe(it?.model_id || ''),
        reason: safe(it?.reason || ''),
        requested_ttl_sec: asInt(it?.requested_ttl_sec || 0),
        requested_token_cap: asInt(it?.requested_token_cap || 0),
        status: safe(it?.status || ''),
        decision: safe(it?.decision || ''),
        created_at_ms: asMs(it?.created_at_ms || 0),
        decided_at_ms: asMs(it?.decided_at_ms || 0),
      })).filter((it) => it.grant_request_id)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || 'remote_pending_grants_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteSupervisorCandidateReviewQueueScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asList(v) {
  return Array.isArray(v) ? v.map((item) => safe(item)).filter(Boolean) : [];
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_PROJECT_ID || '');
  const limitRaw = Number.parseInt(safe(process.env.XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_LIMIT || '200'), 10);
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient.GetSupervisorCandidateReviewQueue(
      {
        client,
        project_id: projectId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        schema_version: safe(it?.schema_version || ''),
        review_id: safe(it?.review_id || ''),
        request_id: safe(it?.request_id || ''),
        evidence_ref: safe(it?.evidence_ref || ''),
        review_state: safe(it?.review_state || ''),
        durable_promotion_state: safe(it?.durable_promotion_state || ''),
        promotion_boundary: safe(it?.promotion_boundary || ''),
        device_id: safe(it?.device_id || ''),
        user_id: safe(it?.user_id || ''),
        app_id: safe(it?.app_id || ''),
        thread_id: safe(it?.thread_id || ''),
        thread_key: safe(it?.thread_key || ''),
        project_id: safe(it?.project_id || ''),
        project_ids: asList(it?.project_ids),
        scopes: asList(it?.scopes),
        record_types: asList(it?.record_types),
        audit_refs: asList(it?.audit_refs),
        idempotency_keys: asList(it?.idempotency_keys),
        candidate_count: asInt(it?.candidate_count || 0),
        summary_line: safe(it?.summary_line || ''),
        mirror_target: safe(it?.mirror_target || ''),
        local_store_role: safe(it?.local_store_role || ''),
        carrier_kind: safe(it?.carrier_kind || ''),
        carrier_schema_version: safe(it?.carrier_schema_version || ''),
        pending_change_id: safe(it?.pending_change_id || ''),
        pending_change_status: safe(it?.pending_change_status || ''),
        edit_session_id: safe(it?.edit_session_id || ''),
        doc_id: safe(it?.doc_id || ''),
        writeback_ref: safe(it?.writeback_ref || ''),
        stage_created_at_ms: asMs(it?.stage_created_at_ms || 0),
        stage_updated_at_ms: asMs(it?.stage_updated_at_ms || 0),
        latest_emitted_at_ms: asMs(it?.latest_emitted_at_ms || 0),
        created_at_ms: asMs(it?.created_at_ms || 0),
        updated_at_ms: asMs(it?.updated_at_ms || 0),
      })).filter((it) => it.request_id)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || 'remote_supervisor_candidate_review_queue_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteConnectorIngressReceiptsScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const projectId = safe(process.env.XTERMINAL_CONNECTOR_INGRESS_PROJECT_ID || '');
  const limitRaw = Number.parseInt(safe(process.env.XTERMINAL_CONNECTOR_INGRESS_LIMIT || '200'), 10);
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient.GetConnectorIngressReceipts(
      {
        client,
        project_id: projectId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        receipt_id: safe(it?.receipt_id || ''),
        request_id: safe(it?.request_id || ''),
        project_id: safe(it?.project_id || ''),
        connector: safe(it?.connector || ''),
        target_id: safe(it?.target_id || ''),
        ingress_type: safe(it?.ingress_type || ''),
        channel_scope: safe(it?.channel_scope || ''),
        source_id: safe(it?.source_id || ''),
        message_id: safe(it?.message_id || ''),
        dedupe_key: safe(it?.dedupe_key || ''),
        received_at_ms: asMs(it?.received_at_ms || 0),
        event_sequence: asMs(it?.event_sequence || 0),
        delivery_state: safe(it?.delivery_state || ''),
        runtime_state: safe(it?.runtime_state || ''),
      })).filter((it) => it.receipt_id)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || 'remote_connector_ingress_receipts_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteRuntimeSurfaceOverridesScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const projectId = safe(
    process.env.XTERMINAL_RUNTIME_SURFACE_OVERRIDE_PROJECT_ID
      || process.env.\#(HubRemoteRuntimeSurfaceCompatContract.legacyProjectIdEnv)
      || ''
  );
  const limitRaw = Number.parseInt(
    safe(
      process.env.XTERMINAL_RUNTIME_SURFACE_OVERRIDE_LIMIT
        || process.env.\#(HubRemoteRuntimeSurfaceCompatContract.legacyLimitEnv)
        || '200'
    ),
    10
  );
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient[\#(String(reflecting: HubRemoteRuntimeSurfaceCompatContract.grpcMethod))](
      {
        client,
        project_id: projectId,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        project_id: safe(it?.project_id || ''),
        override_mode: safe(it?.override_mode || '').toLowerCase(),
        updated_at_ms: asMs(it?.updated_at_ms || 0),
        reason: safe(it?.reason || ''),
        audit_ref: safe(it?.audit_ref || ''),
      })).filter((it) => it.project_id && it.override_mode)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || '\#(HubRemoteRuntimeSurfaceCompatContract.failureReasonCode)');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    @available(*, deprecated, message: "Use remoteRuntimeSurfaceOverridesScriptSource()")
    private func remoteAutonomyPolicyOverridesScriptSource() -> String {
        remoteRuntimeSurfaceOverridesScriptSource()
    }

    private func remotePendingGrantActionScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function callApprove(runtimeClient, md, req) {
  return await new Promise((resolve, reject) => {
    runtimeClient.ApprovePendingGrantRequest(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function callDeny(runtimeClient, md, req) {
  return await new Promise((resolve, reject) => {
    runtimeClient.DenyPendingGrantRequest(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });
}

async function main() {
  const action = safe(process.env.XTERMINAL_PENDING_GRANT_ACTION || '').toLowerCase();
  if (action !== 'approve' && action !== 'deny') throw new Error('invalid_action');

  const grantRequestId = safe(process.env.XTERMINAL_PENDING_GRANT_ID || '');
  if (!grantRequestId) throw new Error('grant_request_id_empty');

  const projectId = safe(process.env.XTERMINAL_PENDING_GRANT_PROJECT_ID || '');
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv(projectId);
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  if (action === 'approve') {
    const ttlRaw = Number.parseInt(safe(process.env.XTERMINAL_PENDING_GRANT_TTL_SEC || ''), 10);
    const tokenCapRaw = Number.parseInt(safe(process.env.XTERMINAL_PENDING_GRANT_TOKEN_CAP || ''), 10);
    const note = safe(process.env.XTERMINAL_PENDING_GRANT_NOTE || '');
    const req = {
      client,
      grant_request_id: grantRequestId,
      ttl_sec: Number.isFinite(ttlRaw) && ttlRaw > 0 ? Math.max(10, Math.min(86400, ttlRaw)) : 0,
      token_cap: Number.isFinite(tokenCapRaw) && tokenCapRaw > 0 ? Math.max(0, tokenCapRaw) : 0,
      note,
    };
    const resp = await callApprove(runtimeClient, md, req);
    out({
      ok: true,
      decision: 'approved',
      grant_request_id: safe(resp?.grant_request_id || grantRequestId),
      grant_id: safe(resp?.grant?.grant_id || ''),
      expires_at_ms: asMs(resp?.grant?.expires_at_ms || 0),
    });
    return;
  }

  const reason = safe(process.env.XTERMINAL_PENDING_GRANT_REASON || '');
  const resp = await callDeny(runtimeClient, md, {
    client,
    grant_request_id: grantRequestId,
    reason,
  });
  out({
    ok: true,
    decision: 'denied',
    grant_request_id: safe(resp?.grant_request_id || grantRequestId),
    grant_id: '',
    expires_at_ms: 0,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_runtime_unimplemented'
    : (msg || 'remote_pending_grant_action_failed');
  out({
    ok: false,
    decision: 'failed',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteSupervisorCandidateReviewStageScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const candidateRequestId = safe(process.env.XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_REQUEST_ID || '');
  if (!candidateRequestId) throw new Error('candidate_request_id_empty');

  const projectId = safe(process.env.XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_PROJECT_ID || '');
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv(projectId);
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    memoryClient.StageSupervisorCandidateReview(
      {
        client,
        candidate_request_id: candidateRequestId,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    staged: !!resp?.staged,
    idempotent: !!resp?.idempotent,
    review_state: safe(resp?.review_state || ''),
    durable_promotion_state: safe(resp?.durable_promotion_state || ''),
    promotion_boundary: safe(resp?.promotion_boundary || ''),
    candidate_request_id: safe(resp?.candidate_request_id || candidateRequestId),
    evidence_ref: safe(resp?.evidence_ref || ''),
    edit_session_id: safe(resp?.edit_session_id || ''),
    pending_change_id: safe(resp?.pending_change_id || ''),
    doc_id: safe(resp?.doc_id || ''),
    base_version: safe(resp?.base_version || ''),
    working_version: safe(resp?.working_version || ''),
    session_revision: asInt(resp?.session_revision || 0),
    status: safe(resp?.status || ''),
    markdown: typeof resp?.markdown === 'string' ? resp.markdown : '',
    created_at_ms: asMs(resp?.created_at_ms || 0),
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    expires_at_ms: asMs(resp?.expires_at_ms || 0),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_memory_unimplemented'
    : (msg || 'remote_supervisor_candidate_review_stage_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    staged: false,
    idempotent: false,
    review_state: '',
    durable_promotion_state: '',
    promotion_boundary: '',
    candidate_request_id: '',
    evidence_ref: '',
    edit_session_id: '',
    pending_change_id: '',
    doc_id: '',
    base_version: '',
    working_version: '',
    session_revision: 0,
    status: '',
    markdown: '',
    created_at_ms: 0,
    updated_at_ms: 0,
    expires_at_ms: 0,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteVoiceWakeProfileGetScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const desiredWakeMode = safe(process.env.XTERMINAL_VOICE_WAKE_DESIRED_MODE || 'wake_phrase') || 'wake_phrase';

  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetVoiceWakeProfile(
      {
        client,
        desired_wake_mode: desiredWakeMode,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const profile = resp?.profile || {};
  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    profile: {
      schema_version: safe(profile?.schema_version || ''),
      profile_id: safe(profile?.profile_id || 'default'),
      trigger_words: Array.isArray(profile?.trigger_words) ? profile.trigger_words.map((item) => safe(item)).filter(Boolean) : [],
      updated_at_ms: asMs(profile?.updated_at_ms || 0),
      wake_mode: safe(profile?.wake_mode || desiredWakeMode),
      requires_pairing_ready: !!profile?.requires_pairing_ready,
      audit_ref: safe(profile?.audit_ref || ''),
    },
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_memory_unimplemented'
    : (msg || 'remote_voice_wake_profile_fetch_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteVoiceWakeProfileSetScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function decodeProfileFromEnv() {
  const encoded = safe(process.env.XTERMINAL_VOICE_WAKE_PROFILE_JSON_B64 || '');
  if (!encoded) {
    throw new Error('voice_wake_profile_payload_missing');
  }
  const json = Buffer.from(encoded, 'base64').toString('utf8');
  const parsed = JSON.parse(json);
  return {
    schema_version: safe(parsed?.schema_version || ''),
    profile_id: safe(parsed?.profile_id || 'default'),
    trigger_words: Array.isArray(parsed?.trigger_words) ? parsed.trigger_words.map((item) => safe(item)).filter(Boolean) : [],
    updated_at_ms: asMs(parsed?.updated_at_ms || 0),
    scope: safe(parsed?.scope || ''),
    source: safe(parsed?.source || ''),
    wake_mode: safe(parsed?.wake_mode || 'wake_phrase'),
    requires_pairing_ready: !!parsed?.requires_pairing_ready,
    audit_ref: safe(parsed?.audit_ref || ''),
  };
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const profile = decodeProfileFromEnv();

  const resp = await new Promise((resolve, reject) => {
    memoryClient.SetVoiceWakeProfile(
      {
        client,
        profile,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const synced = resp?.profile || {};
  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    profile: {
      schema_version: safe(synced?.schema_version || ''),
      profile_id: safe(synced?.profile_id || profile.profile_id || 'default'),
      trigger_words: Array.isArray(synced?.trigger_words) ? synced.trigger_words.map((item) => safe(item)).filter(Boolean) : [],
      updated_at_ms: asMs(synced?.updated_at_ms || 0),
      wake_mode: safe(synced?.wake_mode || profile.wake_mode || 'wake_phrase'),
      requires_pairing_ready: !!synced?.requires_pairing_ready,
      audit_ref: safe(synced?.audit_ref || profile.audit_ref || ''),
    },
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_memory_unimplemented'
    : (msg || 'remote_voice_wake_profile_set_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteVoiceGrantChallengeScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function parseBool(v, fallback = false) {
  const raw = safe(v).toLowerCase();
  if (!raw) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(raw)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(raw)) return false;
  return fallback;
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const requestId = safe(process.env.XTERMINAL_VOICE_CHALLENGE_REQUEST_ID || '');
  const templateId = safe(process.env.XTERMINAL_VOICE_CHALLENGE_TEMPLATE_ID || '');
  const actionDigest = safe(process.env.XTERMINAL_VOICE_CHALLENGE_ACTION_DIGEST || '');
  const scopeDigest = safe(process.env.XTERMINAL_VOICE_CHALLENGE_SCOPE_DIGEST || '');
  if (!requestId || !templateId || !actionDigest || !scopeDigest) {
    throw new Error('invalid_request');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);

  const ttlRaw = Number.parseInt(safe(process.env.XTERMINAL_VOICE_CHALLENGE_TTL_MS || '120000'), 10);
  const resp = await new Promise((resolve, reject) => {
    memoryClient.IssueVoiceGrantChallenge(
      {
        request_id: requestId,
        client,
        template_id: templateId,
        action_digest: actionDigest,
        scope_digest: scopeDigest,
        amount_digest: safe(process.env.XTERMINAL_VOICE_CHALLENGE_AMOUNT_DIGEST || ''),
        challenge_code: safe(process.env.XTERMINAL_VOICE_CHALLENGE_CODE || ''),
        risk_level: safe(process.env.XTERMINAL_VOICE_CHALLENGE_RISK_LEVEL || 'high'),
        bound_device_id: safe(process.env.XTERMINAL_VOICE_CHALLENGE_BOUND_DEVICE_ID || ''),
        mobile_terminal_id: safe(process.env.XTERMINAL_VOICE_CHALLENGE_MOBILE_TERMINAL_ID || ''),
        allow_voice_only: parseBool(process.env.XTERMINAL_VOICE_CHALLENGE_ALLOW_VOICE_ONLY || '', false),
        requires_mobile_confirm: parseBool(process.env.XTERMINAL_VOICE_CHALLENGE_REQUIRES_MOBILE_CONFIRM || '', true),
        ttl_ms: Number.isFinite(ttlRaw) ? Math.max(10000, Math.min(600000, ttlRaw)) : 120000,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const challenge = resp?.challenge || null;
  const challengeId = safe(challenge?.challenge_id || '');
  if (!challengeId) {
    out({
      ok: false,
      source: 'hub_memory_v1_grpc',
      reason: 'voice_grant_challenge_missing',
      error_code: 'voice_grant_challenge_missing',
      error_message: 'voice_grant_challenge_missing',
    });
    process.exit(1);
    return;
  }

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    challenge: {
      challenge_id: challengeId,
      template_id: safe(challenge?.template_id || ''),
      action_digest: safe(challenge?.action_digest || ''),
      scope_digest: safe(challenge?.scope_digest || ''),
      amount_digest: safe(challenge?.amount_digest || ''),
      challenge_code: safe(challenge?.challenge_code || ''),
      risk_level: safe(challenge?.risk_level || 'high'),
      requires_mobile_confirm: !!challenge?.requires_mobile_confirm,
      allow_voice_only: !!challenge?.allow_voice_only,
      bound_device_id: safe(challenge?.bound_device_id || ''),
      mobile_terminal_id: safe(challenge?.mobile_terminal_id || ''),
      issued_at_ms: asMs(challenge?.issued_at_ms || 0),
      expires_at_ms: asMs(challenge?.expires_at_ms || 0),
    },
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_memory_unimplemented'
    : (msg || 'remote_voice_grant_challenge_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteVoiceGrantVerifyScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function parseBool(v, fallback = false) {
  const raw = safe(v).toLowerCase();
  if (!raw) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(raw)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(raw)) return false;
  return fallback;
}

function parseScore(v) {
  const n = Number(safe(v || ''));
  if (!Number.isFinite(n)) return 0;
  return n;
}

async function main() {
  const requestId = safe(process.env.XTERMINAL_VOICE_VERIFY_REQUEST_ID || '');
  const challengeId = safe(process.env.XTERMINAL_VOICE_VERIFY_CHALLENGE_ID || '');
  const verifyNonce = safe(process.env.XTERMINAL_VOICE_VERIFY_NONCE || '');
  if (!requestId || !challengeId || !verifyNonce) {
    throw new Error('invalid_request');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    memoryClient.VerifyVoiceGrantResponse(
      {
        request_id: requestId,
        client,
        challenge_id: challengeId,
        challenge_code: safe(process.env.XTERMINAL_VOICE_VERIFY_CHALLENGE_CODE || ''),
        transcript: String(process.env.XTERMINAL_VOICE_VERIFY_TRANSCRIPT || ''),
        transcript_hash: safe(process.env.XTERMINAL_VOICE_VERIFY_TRANSCRIPT_HASH || ''),
        semantic_match_score: parseScore(process.env.XTERMINAL_VOICE_VERIFY_SEMANTIC_MATCH_SCORE || ''),
        parsed_action_digest: safe(process.env.XTERMINAL_VOICE_VERIFY_PARSED_ACTION_DIGEST || ''),
        parsed_scope_digest: safe(process.env.XTERMINAL_VOICE_VERIFY_PARSED_SCOPE_DIGEST || ''),
        parsed_amount_digest: safe(process.env.XTERMINAL_VOICE_VERIFY_PARSED_AMOUNT_DIGEST || ''),
        verify_nonce: verifyNonce,
        bound_device_id: safe(process.env.XTERMINAL_VOICE_VERIFY_BOUND_DEVICE_ID || ''),
        mobile_confirmed: parseBool(process.env.XTERMINAL_VOICE_VERIFY_MOBILE_CONFIRMED || '', false),
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    verified: !!resp?.verified,
    decision: safe(resp?.decision || (resp?.verified ? 'allow' : 'deny')),
    deny_code: safe(resp?.deny_code || ''),
    challenge_id: safe(resp?.challenge_id || challengeId),
    transcript_hash: safe(resp?.transcript_hash || ''),
    semantic_match_score: Number(resp?.semantic_match_score || 0),
    challenge_match: !!resp?.challenge_match,
    device_binding_ok: !!resp?.device_binding_ok,
    mobile_confirmed: !!resp?.mobile_confirmed,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_memory_unimplemented'
    : (msg || 'remote_voice_grant_verify_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    verified: false,
    decision: 'failed',
    deny_code: '',
    challenge_id: '',
    transcript_hash: '',
    semantic_match_score: 0,
    challenge_match: false,
    device_binding_ok: false,
    mobile_confirmed: false,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteSecretVaultListScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  if (typeof memoryClient.ListSecretVaultItems !== 'function') {
    throw new Error('hub_secret_vault_unimplemented');
  }

  const scope = safe(process.env.XTERMINAL_SECRET_VAULT_SCOPE || '');
  const namePrefix = safe(process.env.XTERMINAL_SECRET_VAULT_NAME_PREFIX || '');
  const limitRaw = Number.parseInt(safe(process.env.XTERMINAL_SECRET_VAULT_LIMIT || '200'), 10);
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const resp = await new Promise((resolve, reject) => {
    memoryClient.ListSecretVaultItems(
      {
        client,
        scope,
        name_prefix: namePrefix,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        item_id: safe(it?.item_id || it?.id || ''),
        scope: safe(it?.scope || '').toLowerCase(),
        name: safe(it?.name || ''),
        sensitivity: safe(it?.sensitivity || 'secret').toLowerCase(),
        created_at_ms: asMs(it?.created_at_ms || 0),
        updated_at_ms: asMs(it?.updated_at_ms || 0),
      })).filter((it) => it.item_id && it.scope && it.name)
    : [];

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('hub_secret_vault_unimplemented') || lower.includes('unimplemented')
    ? 'hub_secret_vault_unimplemented'
    : (msg || 'remote_secret_vault_list_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteSecretVaultCreateScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const scope = safe(process.env.XTERMINAL_SECRET_VAULT_SCOPE || '').toLowerCase();
  const name = safe(process.env.XTERMINAL_SECRET_VAULT_NAME || '');
  const plaintextB64 = safe(process.env.XTERMINAL_SECRET_VAULT_PLAINTEXT_B64 || '');
  if (!scope || !name || !plaintextB64) {
    throw new Error('invalid_request');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  if (typeof memoryClient.CreateSecretVaultItem !== 'function') {
    throw new Error('hub_secret_vault_unimplemented');
  }

  const req = {
    client,
    scope,
    name,
    plaintext_b64: plaintextB64,
    plaintext_bytes: Buffer.from(plaintextB64, 'base64'),
    sensitivity: safe(process.env.XTERMINAL_SECRET_VAULT_SENSITIVITY || 'secret').toLowerCase(),
    display_name: safe(process.env.XTERMINAL_SECRET_VAULT_DISPLAY_NAME || ''),
    reason: safe(process.env.XTERMINAL_SECRET_VAULT_REASON || ''),
  };

  const resp = await new Promise((resolve, reject) => {
    memoryClient.CreateSecretVaultItem(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });

  const item = resp?.item || resp?.secret_vault_item || {};
  const itemId = safe(item?.item_id || item?.id || '');
  if (!itemId) {
    out({
      ok: false,
      source: 'hub_memory_v1_grpc',
      reason: 'secret_vault_item_missing',
      error_code: 'secret_vault_item_missing',
      error_message: 'secret_vault_item_missing',
    });
    process.exit(1);
    return;
  }

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    item: {
      item_id: itemId,
      scope: safe(item?.scope || scope).toLowerCase(),
      name: safe(item?.name || name),
      sensitivity: safe(item?.sensitivity || 'secret').toLowerCase(),
      created_at_ms: asMs(item?.created_at_ms || 0),
      updated_at_ms: asMs(item?.updated_at_ms || 0),
    },
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('hub_secret_vault_unimplemented') || lower.includes('unimplemented')
    ? 'hub_secret_vault_unimplemented'
    : (msg || 'remote_secret_vault_create_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteSecretVaultBeginUseScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const itemId = safe(process.env.XTERMINAL_SECRET_VAULT_ITEM_ID || '');
  const scope = safe(process.env.XTERMINAL_SECRET_VAULT_SCOPE || '').toLowerCase();
  const name = safe(process.env.XTERMINAL_SECRET_VAULT_NAME || '');
  const purpose = safe(process.env.XTERMINAL_SECRET_VAULT_USE_PURPOSE || '');
  if (!purpose || (!itemId && !(scope && name))) {
    throw new Error('invalid_request');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  if (typeof memoryClient.BeginSecretVaultUse !== 'function') {
    throw new Error('hub_secret_vault_unimplemented');
  }

  const ttlRaw = Number.parseInt(safe(process.env.XTERMINAL_SECRET_VAULT_USE_TTL_MS || '60000'), 10);
  const req = {
    client,
    item_id: itemId,
    scope,
    name,
    purpose,
    target: safe(process.env.XTERMINAL_SECRET_VAULT_USE_TARGET || ''),
    ttl_ms: Number.isFinite(ttlRaw) ? Math.max(1000, Math.min(600000, ttlRaw)) : 60000,
  };

  const resp = await new Promise((resolve, reject) => {
    memoryClient.BeginSecretVaultUse(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    lease_id: safe(resp?.lease_id || resp?.lease?.lease_id || ''),
    use_token: safe(resp?.use_token || resp?.lease?.use_token || ''),
    item_id: safe(resp?.item_id || itemId),
    expires_at_ms: asMs(resp?.expires_at_ms || resp?.lease?.expires_at_ms || 0),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('hub_secret_vault_unimplemented') || lower.includes('unimplemented')
    ? 'hub_secret_vault_unimplemented'
    : (msg || 'remote_secret_vault_use_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    lease_id: '',
    use_token: '',
    item_id: '',
    expires_at_ms: 0,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteSecretVaultRedeemScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function writePlaintext(outputPath, buffer) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, buffer, { mode: 0o600 });
}

async function main() {
  const useToken = safe(process.env.XTERMINAL_SECRET_VAULT_USE_TOKEN || '');
  const outputPath = safe(process.env.XTERMINAL_SECRET_VAULT_REDEEM_OUTPUT || '');
  if (!useToken || !outputPath) {
    throw new Error('invalid_request');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  if (typeof memoryClient.RedeemSecretVaultUse !== 'function') {
    throw new Error('hub_secret_vault_unimplemented');
  }

  const req = {
    client,
    use_token: useToken,
  };

  const resp = await new Promise((resolve, reject) => {
    memoryClient.RedeemSecretVaultUse(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });

  let plaintextBuffer = Buffer.alloc(0);
  if (Buffer.isBuffer(resp?.plaintext_bytes)) {
    plaintextBuffer = Buffer.from(resp.plaintext_bytes);
  } else if (resp?.plaintext_bytes != null && typeof resp.plaintext_bytes === 'object' && typeof resp.plaintext_bytes.length === 'number') {
    plaintextBuffer = Buffer.from(resp.plaintext_bytes);
  }
  if (!plaintextBuffer.length) {
    throw new Error('secret_vault_plaintext_missing');
  }

  writePlaintext(outputPath, plaintextBuffer);
  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    lease_id: safe(resp?.lease_id || resp?.lease?.lease_id || ''),
    item_id: safe(resp?.item_id || resp?.item?.item_id || ''),
    plaintext_bytes: plaintextBuffer.length,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('hub_secret_vault_unimplemented') || lower.includes('unimplemented')
    ? 'hub_secret_vault_unimplemented'
    : (msg || 'remote_secret_vault_redeem_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    lease_id: '',
    item_id: '',
    plaintext_bytes: 0,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteSchedulerStatusScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

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
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const includeQueueItems = ['1', 'true', 'yes', 'on'].includes(safe(process.env.XTERMINAL_SCHED_INCLUDE_QUEUE_ITEMS || '1').toLowerCase());
  const queueItemsLimitRaw = Number.parseInt(safe(process.env.XTERMINAL_SCHED_QUEUE_ITEMS_LIMIT || '80'), 10);
  const queueItemsLimit = Math.max(1, Math.min(500, Number.isFinite(queueItemsLimitRaw) ? queueItemsLimitRaw : 80));

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubRuntime) throw new Error('hub_runtime_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = new proto.HubRuntime(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    runtimeClient.GetSchedulerStatus(
      {
        client,
        include_queue_items: includeQueueItems,
        queue_items_limit: queueItemsLimit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const paid = resp?.paid_ai || {};
  const inFlightByScope = Array.isArray(paid?.in_flight_by_scope)
    ? paid.in_flight_by_scope.map((it) => ({
        scope_key: safe(it?.scope_key || ''),
        in_flight: asInt(it?.in_flight || 0),
      })).filter((it) => it.scope_key)
    : [];
  const queuedByScope = Array.isArray(paid?.queued_by_scope)
    ? paid.queued_by_scope.map((it) => ({
        scope_key: safe(it?.scope_key || ''),
        queued: asInt(it?.queued || 0),
      })).filter((it) => it.scope_key)
    : [];
  const queueItems = Array.isArray(paid?.queue_items)
    ? paid.queue_items.map((it) => ({
        request_id: safe(it?.request_id || ''),
        scope_key: safe(it?.scope_key || ''),
        enqueued_at_ms: asMs(it?.enqueued_at_ms || 0),
        queued_ms: asMs(it?.queued_ms || 0),
      })).filter((it) => it.request_id && it.scope_key)
    : [];

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: asMs(paid?.updated_at_ms || 0),
    in_flight_total: asInt(paid?.in_flight_total || 0),
    queue_depth: asInt(paid?.queue_depth || 0),
    oldest_queued_ms: asMs(paid?.oldest_queued_ms || 0),
    in_flight_by_scope: inFlightByScope,
    queued_by_scope: queuedByScope,
    queue_items: queueItems,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented') ? 'hub_runtime_unimplemented' : (msg || 'remote_scheduler_status_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    in_flight_total: 0,
    queue_depth: 0,
    oldest_queued_ms: 0,
    in_flight_by_scope: [],
    queued_by_scope: [],
    queue_items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func remoteSupervisorBriefProjectionScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
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
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
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
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asBool(v, fallback = false) {
  const token = safe(v).toLowerCase();
  if (!token) return fallback;
  if (token === '1' || token === 'true' || token === 'yes' || token === 'on') return true;
  if (token === '0' || token === 'false' || token === 'no' || token === 'off') return false;
  return fallback;
}

async function main() {
  const requestId = safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_REQUEST_ID || '');
  const projectId = safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_PROJECT_ID || '');
  if (!requestId) throw new Error('request_id_empty');
  if (!projectId) throw new Error('project_id_empty');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSupervisor && !proto?.HubRuntime) throw new Error('hub_supervisor_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv(projectId);
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const runtimeClient = proto?.HubRuntime ? new proto.HubRuntime(addr, creds, options) : null;
  const supervisorClient = (() => {
    if (runtimeClient && typeof runtimeClient.GetSupervisorBriefProjection === 'function') return runtimeClient;
    if (proto?.HubSupervisor) return new proto.HubSupervisor(addr, creds, options);
    throw new Error('hub_supervisor_missing');
  })();

  const request = {
    request_id: requestId,
    client,
    project_id: projectId,
    run_id: safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_RUN_ID || ''),
    mission_id: safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_MISSION_ID || ''),
    projection_kind: safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_KIND || 'progress_brief') || 'progress_brief',
    trigger: safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_TRIGGER || 'daily_digest') || 'daily_digest',
    include_tts_script: asBool(process.env.XTERMINAL_SUPERVISOR_BRIEF_INCLUDE_TTS || '1', true),
    include_card_summary: asBool(process.env.XTERMINAL_SUPERVISOR_BRIEF_INCLUDE_CARD_SUMMARY || '0', false),
    max_evidence_refs: Math.max(0, Math.min(12, Number.parseInt(safe(process.env.XTERMINAL_SUPERVISOR_BRIEF_MAX_EVIDENCE_REFS || '4'), 10) || 4)),
  };

  const resp = await new Promise((resolve, reject) => {
    supervisorClient.GetSupervisorBriefProjection(
      request,
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const projection = resp?.projection
    ? {
        schema_version: safe(resp.projection?.schema_version || 'xhub.supervisor_brief_projection.v1'),
        projection_id: safe(resp.projection?.projection_id || ''),
        projection_kind: safe(resp.projection?.projection_kind || ''),
        project_id: safe(resp.projection?.project_id || ''),
        run_id: safe(resp.projection?.run_id || ''),
        mission_id: safe(resp.projection?.mission_id || ''),
        trigger: safe(resp.projection?.trigger || ''),
        status: safe(resp.projection?.status || ''),
        critical_blocker: safe(resp.projection?.critical_blocker || ''),
        topline: safe(resp.projection?.topline || ''),
        next_best_action: safe(resp.projection?.next_best_action || ''),
        pending_grant_count: asInt(resp.projection?.pending_grant_count || 0),
        tts_script: Array.isArray(resp.projection?.tts_script)
          ? resp.projection.tts_script.map((item) => safe(item)).filter(Boolean)
          : [],
        card_summary: safe(resp.projection?.card_summary || ''),
        evidence_refs: Array.isArray(resp.projection?.evidence_refs)
          ? resp.projection.evidence_refs.map((item) => safe(item)).filter(Boolean)
          : [],
        generated_at_ms: asMs(resp.projection?.generated_at_ms || 0),
        expires_at_ms: asMs(resp.projection?.expires_at_ms || 0),
        audit_ref: safe(resp.projection?.audit_ref || ''),
      }
    : null;

  const denyCode = safe(resp?.deny_code || '');
  out({
    ok: resp?.ok === true,
    source: 'hub_supervisor_grpc',
    projection,
    reason: denyCode || '',
    error_code: denyCode || '',
    error_message: denyCode || '',
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_supervisor_unimplemented'
    : (msg || 'remote_supervisor_brief_projection_failed');
  out({
    ok: false,
    source: 'hub_supervisor_grpc',
    projection: null,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    private func emit(
        _ callback: (@Sendable (HubRemoteProgressEvent) -> Void)?,
        _ phase: HubRemoteProgressPhase,
        _ state: HubRemoteProgressState,
        _ detail: String?
    ) {
        callback?(HubRemoteProgressEvent(phase: phase, state: state, detail: detail))
    }

    private func normalizedRemoteReasonCode(
        rawReason: String?,
        stepOutput: String,
        fallback: String
    ) -> String {
        Self.normalizedRemoteReasonCode(
            rawReason: rawReason,
            stepOutput: stepOutput,
            fallback: fallback
        )
    }

    private nonisolated static func normalizedRemoteReasonCode(
        rawReason: String?,
        stepOutput: String,
        fallback: String
    ) -> String {
        let trimmedRaw = rawReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let sanitized = sanitizedReasonToken(trimmedRaw),
           isCanonicalReasonToken(trimmedRaw) {
            if sanitized == "14_unavailable" {
                return "grpc_unavailable"
            }
            return sanitized
        }

        if !trimmedRaw.isEmpty {
            let inferredFromRaw = inferFailureCodeFromText(trimmedRaw, fallback: fallback)
            if inferredFromRaw != fallback || stepOutput.isEmpty {
                return inferredFromRaw
            }
        }

        return inferFailureCodeFromText(stepOutput, fallback: fallback)
    }

    private nonisolated static func sanitizedReasonToken(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        var token = trimmed
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        while token.contains("__") {
            token = token.replacingOccurrences(of: "__", with: "_")
        }
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return token.isEmpty ? nil : token
    }

    private nonisolated static func isCanonicalReasonToken(_ raw: String) -> Bool {
        guard !raw.isEmpty, raw.count <= 80 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return raw.rangeOfCharacter(from: allowed.inverted) == nil
    }

    private func inferFailureCode(from output: String, fallback: String) -> String {
        Self.inferFailureCodeFromText(output, fallback: fallback)
    }

    private nonisolated static func inferFailureCodeFromText(_ output: String, fallback: String) -> String {
        let text = output.lowercased()
        if text.isEmpty { return fallback }
        if text.contains("alert certificate required")
            || text.contains("tlsv13 alert certificate required")
            || text.contains("peer did not return a certificate")
            || text.contains("client certificate required")
            || text.contains("certificate required") {
            return "mtls_client_certificate_required"
        }
        if let done = extractRegexGroup(in: text, pattern: #"(?m)^\[done\].*reason=([a-z0-9_.-]+)\s*$"#) {
            return done.replacingOccurrences(of: "-", with: "_")
        }
        if let errCode = extractRegexGroup(in: text, pattern: #"(?m)^\[error\]\s*([a-z0-9_.-]+)\s*:"#) {
            return errCode.replacingOccurrences(of: "-", with: "_")
        }
        if let fromParens = extractParenReason(in: text, prefix: "connect failed (") {
            return fromParens
        }
        if text.contains("bridge_disabled") { return "bridge_disabled" }
        if text.contains("bridge_unavailable") { return "bridge_unavailable" }
        if text.contains("remote_model_not_found") { return "remote_model_not_found" }
        if text.contains("api_key_missing") { return "api_key_missing" }
        if text.contains("base_url_invalid") { return "base_url_invalid" }
        if text.contains("grant_required") { return "grant_required" }
        if text.contains("permission_denied") { return "forbidden" }
        if text.contains("node_runtime_killed") || text.contains("node runtime killed") {
            return "node_runtime_killed"
        }
        if text.contains("permission denied") { return "permission_denied" }
        if text.contains("unknown command: discover") { return "discover_unsupported" }
        if text.contains("unknown command: connect") { return "connect_unsupported" }
        if text.contains("source_ip_not_allowed") || text.contains("source ip may not be allowed") {
            return "source_ip_not_allowed"
        }
        if text.contains("grpc_unavailable") { return "grpc_unavailable" }
        if text.contains("14 unavailable") || text.contains("14_unavailable") {
            return "grpc_unavailable"
        }
        if text.contains("no connection established") {
            return "grpc_unavailable"
        }
        if text.contains("failed to connect to all addresses") {
            return "grpc_unavailable"
        }
        if text.contains("killed: 9")
            || text.contains("(exit=137)")
            || text.contains("(exit=134)")
            || text.contains("(exit=139)") {
            return "node_runtime_killed"
        }
        if text.contains("discovery_failed") { return "discovery_failed" }
        if text.contains("pairing_health_failed") { return "pairing_health_failed" }
        if text.contains("grpc_probe_failed") { return "grpc_probe_failed" }
        if text.contains("missing_pairing_secret") { return "missing_pairing_secret" }
        if text.contains("unauthenticated") { return "unauthenticated" }
        if text.contains("forbidden") || text.contains(" 403") { return "forbidden" }
        if text.contains("certificate") || text.contains("tls") { return "tls_error" }
        if text.contains("timeout") { return "timeout" }
        if text.contains("couldn't connect to server") || text.contains("failed to connect to") {
            return "hub_unreachable"
        }
        if text.contains("connection refused") { return "connection_refused" }
        if text.contains("network is unreachable") { return "network_unreachable" }
        if text.contains("doesn't exist") || text.contains("doesn’t exist") { return "file_not_found" }
        if text.contains("nscocoaerrordomain code=4") { return "file_not_found" }
        if text.contains("not found") { return "not_found" }
        if text.contains("client kit not installed") || text.contains("axhub_client_kit_not_found") {
            return "client_kit_missing"
        }
        return fallback
    }

    private func shouldRetryAfterClientKitInstall(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("client kit not installed")
            || text.contains("axhub_client_kit_not_found")
            || text.contains("client kit not available")
            || text.contains("killed: 9")
            || text.contains("missing node")
    }

    private func isUnknownCommand(_ output: String, command: String) -> Bool {
        output.lowercased().contains("unknown command: \(command.lowercased())")
    }

    private func parseListModelsOutput(_ output: String) -> [HubModel] {
        var rows: [HubModel] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("- ") else { continue }
            let payload = String(trimmed.dropFirst(2))
            let fields = payload.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard fields.count >= 2 else { continue }
            let name = fields[0]
            let modelId = fields[1]
            if modelId.isEmpty { continue }
            let kind = fields.count > 2 ? fields[2] : ""
            let backend = fields.count > 3 ? fields[3] : "unknown"
            let visibility = fields.count > 4 ? fields[4] : ""

            var roles: [String] = ["general"]
            let kindUpper = kind.uppercased()
            if kindUpper.contains("PAID") {
                roles.append("paid")
            } else if kindUpper.contains("LOCAL") {
                roles.append("local")
            }

            let noteParts = [kind, visibility]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            rows.append(
                HubModel(
                    id: modelId,
                    name: name.isEmpty ? modelId : name,
                    backend: backend.isEmpty ? "unknown" : backend,
                    quant: "",
                    contextLength: 8192,
                    paramsB: 0,
                    roles: roles,
                    // ListModels entries from paired Hub are directly routable in remote mode.
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: nil,
                    note: noteParts.isEmpty ? nil : noteParts.joined(separator: " | ")
                )
            )
        }
        return rows
    }

    private func extractChatAssistantText(_ output: String) -> String {
        let rawLines = output.components(separatedBy: .newlines)
        var content: [String] = []
        var started = false

        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if started {
                    content.append("")
                }
                continue
            }

            if line.hasPrefix("Hub connected:")
                || line.hasPrefix("Using model:")
                || line.hasPrefix("Memory:")
                || line.hasPrefix("Usage:")
                || line.hasPrefix("Tips (interactive):")
                || line.hasPrefix("Next:")
                || line.hasPrefix("chat failed:")
                || line.hasPrefix("[grant]")
                || line.hasPrefix("[models]")
                || line.hasPrefix("[quota]")
                || line.hasPrefix("[killswitch]")
                || line.hasPrefix("[req]")
                || line.hasPrefix("[error]")
                || line.hasPrefix("[done]") {
                continue
            }

            started = true
            content.append(raw)
        }

        return content
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractParenReason(_ lowerText: String, prefix: String) -> String? {
        Self.extractParenReason(in: lowerText, prefix: prefix)
    }

    private nonisolated static func extractParenReason(in lowerText: String, prefix: String) -> String? {
        guard let start = lowerText.range(of: prefix) else { return nil }
        let tail = lowerText[start.upperBound...]
        guard let close = tail.firstIndex(of: ")") else { return nil }
        let raw = String(tail[..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = raw.replacingOccurrences(of: " ", with: "_")
        return cleaned.isEmpty ? nil : cleaned
    }

    private func extractRegexGroup(_ text: String, pattern: String) -> String? {
        Self.extractRegexGroup(in: text, pattern: pattern)
    }

    private nonisolated static func extractRegexGroup(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2 else { return nil }
        let g = m.range(at: 1)
        guard g.location != NSNotFound, g.length > 0 else { return nil }
        let out = ns.substring(with: g).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    private func parsePortField(_ output: String, fieldName: String) -> Int? {
        let pattern = "(?m)^\\s*" + NSRegularExpression.escapedPattern(for: fieldName) + "\\s*:\\s*([0-9]{1,5})\\s*$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = output as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: output, options: [], range: range), m.numberOfRanges > 1 else {
            return nil
        }
        let s = ns.substring(with: m.range(at: 1))
        return Int(s)
    }

    private func parseStringField(_ output: String, fieldName: String) -> String? {
        let pattern = "(?m)^\\s*" + NSRegularExpression.escapedPattern(for: fieldName) + "\\s*:\\s*(.+?)\\s*$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = output as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: output, options: [], range: range), m.numberOfRanges > 1 else {
            return nil
        }
        let s = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func hasInstalledClientKit(stateDir: URL?) -> Bool {
        let base = stateDir ?? defaultStateDir()
        let marker = base
            .appendingPathComponent("client_kit", isDirectory: true)
            .appendingPathComponent("hub_grpc_server", isDirectory: true)
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent("list_models_client.js", isDirectory: false)
        return FileManager.default.fileExists(atPath: marker.path)
    }

    private func connectRepairHosts(
        primaryHubHost: String?,
        options: HubRemoteConnectOptions
    ) -> [String] {
        var out: [String] = []
        func append(_ raw: String?) {
            guard let raw = nonEmpty(raw) else { return }
            let host = normalizedConnectHostCandidate(raw)
            guard !host.isEmpty, !out.contains(host) else { return }
            out.append(host)
        }

        append(primaryHubHost)
        append(options.internetHost)

        let cached = loadCachedPairingInfo(stateDir: options.stateDir)
        append(cached.host)
        append(cached.internetHost)

        if out.isEmpty || out.contains(where: { isCurrentMachineHost($0) }) || out.contains("127.0.0.1") {
            append("127.0.0.1")
        }
        return out
    }

    private func maybeInstallClientKit(
        options opts: HubRemoteConnectOptions,
        hosts: [String],
        env customEnv: [String: String],
        logs: inout [String]
    ) -> Bool {
        guard !hosts.isEmpty else { return false }
        for host in hosts {
            let install = runAxhubctl(
                args: [
                    "install-client",
                    "--hub", host,
                    "--pairing-port", "\(opts.pairingPort)",
                ],
                options: opts,
                env: customEnv,
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                return true
            }
        }
        return false
    }

    private func normalizedConnectHostCandidate(_ host: String) -> String {
        isCurrentMachineHost(host) ? "127.0.0.1" : host
    }

    private func preferredBootstrapHub(
        discoveredHubHost: String?,
        options: HubRemoteConnectOptions
    ) -> String {
        if let discoveredHubHost, !discoveredHubHost.isEmpty {
            return normalizedConnectHostCandidate(discoveredHubHost)
        }
        let internetHost = options.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !internetHost.isEmpty {
            return normalizedConnectHostCandidate(internetHost)
        }
        return "127.0.0.1"
    }

    private func shouldRequireConfiguredHubHost(options: HubRemoteConnectOptions) -> Bool {
        let configured = options.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if configured.isEmpty { return false }
        if isCurrentMachineHost(configured) { return false }
        return !isLoopbackHost(configured)
    }

    private func hostMatchesConfiguredHost(discoveredHost: String?, options: HubRemoteConnectOptions) -> Bool {
        let configured = normalizeHost(options.internetHost)
        guard !configured.isEmpty else { return true }
        guard let discoveredHost else { return false }
        if isCurrentMachineHost(configured), isCurrentMachineHost(discoveredHost) {
            return true
        }
        return normalizeHost(discoveredHost) == configured
    }

    private func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isLoopbackHost(_ host: String) -> Bool {
        let n = normalizeHost(host)
        return n == "localhost" || n == "127.0.0.1"
    }

    private func isCurrentMachineHost(_ host: String) -> Bool {
        let normalized = normalizeHost(host)
        if normalized.isEmpty { return false }
        if isLoopbackHost(normalized) { return true }
        return Self.currentMachineIPv4Hosts().contains(normalized)
    }

    private func makeEphemeralStateDir(prefix: String) -> URL? {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            return tmp
        } catch {
            return nil
        }
    }

    private func removeEphemeralStateDir(_ dir: URL?) {
        guard let dir else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    private func discoverHubOnLAN(
        options: HubRemoteConnectOptions,
        pairingPorts: [Int],
        cachedPairing: HubCachedPairingInfo
    ) async -> HubLANDiscoveryAttempt {
        if shouldRequireConfiguredHubHost(options: options) {
            return HubLANDiscoveryAttempt(candidate: nil, reasonCode: nil, candidates: [], logLines: [])
        }

        let bonjourResult = await discoverHubViaBonjour(
            options: options,
            cachedPairing: cachedPairing
        )
        if bonjourResult.candidate != nil || bonjourResult.reasonCode != nil {
            return bonjourResult
        }

        let plan = Self.buildLANDiscoveryScanPlan()
        guard !plan.hosts.isEmpty else {
            return HubLANDiscoveryAttempt(
                candidate: nil,
                reasonCode: nil,
                candidates: [],
                logLines: ["[lan-discover] no active IPv4 subnets available for fallback scan."]
            )
        }

        let prioritizedHosts = prioritizeLANHosts(plan.hosts, preferredHosts: [
            cachedPairing.host,
            options.internetHost
        ])

        let portCandidates = Array(Set(pairingPorts.map { max(1, min(65_535, $0)) })).sorted()
        let summary = plan.networkSummaries.isEmpty
            ? "unknown"
            : plan.networkSummaries.joined(separator: ", ")
        var logs = [
            "[lan-discover] fallback subnet scan: networks=\(summary) hosts=\(prioritizedHosts.count)"
        ]

        for pairingPort in portCandidates {
            let matches = await Self.collectLANDiscoveryMatches(
                hosts: prioritizedHosts,
                pairingPort: pairingPort,
                timeoutSec: 0.35
            )
            let resolved = resolveDiscoveryCandidate(
                matches.map {
                    HubLANDiscoveryCandidate(
                        host: $0.host,
                        pairingPort: $0.pairingPort,
                        grpcPort: $0.grpcPort,
                        internetHost: $0.internetHost,
                        hubInstanceID: $0.hubInstanceID,
                        lanDiscoveryName: $0.lanDiscoveryName,
                        logLines: []
                    )
                },
                cachedPairing: cachedPairing,
                configuredInternetHost: nonEmpty(options.internetHost),
                source: "lan-discover",
                ambiguousReasonCode: "lan_multiple_hubs_ambiguous"
            )
            logs.append(contentsOf: resolved.logLines)
            if let candidate = resolved.candidate {
                let discoveredInternetHost = nonEmpty(candidate.internetHost)
                    ?? nonEmpty(cachedPairing.internetHost)
                do {
                    try persistDiscoveredPairingInfo(
                        host: candidate.host,
                        pairingPort: candidate.pairingPort,
                        grpcPort: candidate.grpcPort,
                        internetHost: discoveredInternetHost,
                        hubInstanceID: candidate.hubInstanceID,
                        lanDiscoveryName: candidate.lanDiscoveryName,
                        options: options
                    )
                    logs.append("[lan-discover] cached host=\(candidate.host) pairing=\(candidate.pairingPort) grpc=\(candidate.grpcPort)")
                } catch {
                    logs.append("[lan-discover] cache_write_failed: \(error.localizedDescription)")
                }
                return HubLANDiscoveryAttempt(
                    candidate: HubLANDiscoveryCandidate(
                        host: candidate.host,
                        pairingPort: candidate.pairingPort,
                        grpcPort: candidate.grpcPort,
                        internetHost: discoveredInternetHost,
                        hubInstanceID: candidate.hubInstanceID,
                        lanDiscoveryName: candidate.lanDiscoveryName,
                        logLines: logs
                    ),
                    reasonCode: nil,
                    candidates: [candidate],
                    logLines: logs
                )
            }
            if let reasonCode = resolved.reasonCode {
                return HubLANDiscoveryAttempt(candidate: nil, reasonCode: reasonCode, candidates: resolved.candidates, logLines: logs)
            }
        }

        logs.append("[lan-discover] no Hub responded on scanned subnets.")
        return HubLANDiscoveryAttempt(candidate: nil, reasonCode: nil, candidates: [], logLines: logs)
    }

    private func discoverHubViaBonjour(
        options: HubRemoteConnectOptions,
        cachedPairing: HubCachedPairingInfo
    ) async -> HubLANDiscoveryAttempt {
        let outcome = await HubBonjourDiscovery.discover(timeoutSec: 1.6)
        let resolved = resolveDiscoveryCandidate(
            outcome.candidates.map {
                HubLANDiscoveryCandidate(
                    host: $0.host,
                    pairingPort: $0.pairingPort,
                    grpcPort: $0.grpcPort,
                    internetHost: $0.internetHost,
                    hubInstanceID: $0.hubInstanceID,
                    lanDiscoveryName: $0.lanDiscoveryName,
                    logLines: []
                )
            },
            cachedPairing: cachedPairing,
            configuredInternetHost: nonEmpty(options.internetHost),
            source: "bonjour-discover",
            ambiguousReasonCode: "bonjour_multiple_hubs_ambiguous"
        )

        guard let candidate = resolved.candidate else {
            return HubLANDiscoveryAttempt(
                candidate: nil,
                reasonCode: resolved.reasonCode,
                candidates: resolved.candidates,
                logLines: resolved.logLines
            )
        }

        let discoveredInternetHost = nonEmpty(candidate.internetHost)
            ?? nonEmpty(cachedPairing.internetHost)
        var logs = resolved.logLines
        do {
            try persistDiscoveredPairingInfo(
                host: candidate.host,
                pairingPort: candidate.pairingPort,
                grpcPort: candidate.grpcPort,
                internetHost: discoveredInternetHost,
                hubInstanceID: candidate.hubInstanceID,
                lanDiscoveryName: candidate.lanDiscoveryName,
                options: options
            )
            logs.append("[bonjour-discover] cached host=\(candidate.host) pairing=\(candidate.pairingPort) grpc=\(candidate.grpcPort)")
        } catch {
            logs.append("[bonjour-discover] cache_write_failed: \(error.localizedDescription)")
        }

        return HubLANDiscoveryAttempt(
            candidate: HubLANDiscoveryCandidate(
                host: candidate.host,
                pairingPort: candidate.pairingPort,
                grpcPort: candidate.grpcPort,
                internetHost: discoveredInternetHost,
                hubInstanceID: candidate.hubInstanceID,
                lanDiscoveryName: candidate.lanDiscoveryName,
                logLines: logs
            ),
            reasonCode: nil,
            candidates: [candidate],
            logLines: logs
        )
    }

    private func resolveDiscoveryCandidate(
        _ rawCandidates: [HubLANDiscoveryCandidate],
        cachedPairing: HubCachedPairingInfo,
        configuredInternetHost: String?,
        source: String,
        ambiguousReasonCode: String
    ) -> HubLANDiscoveryAttempt {
        let candidates = deduplicatedDiscoveryCandidates(rawCandidates)
        guard !candidates.isEmpty else {
            return HubLANDiscoveryAttempt(candidate: nil, reasonCode: nil, candidates: [], logLines: [])
        }

        if candidates.count == 1, let candidate = candidates.first {
            return HubLANDiscoveryAttempt(
                candidate: candidate,
                reasonCode: nil,
                candidates: candidates,
                logLines: ["[\(source)] selected \(describeDiscoveryCandidate(candidate))"]
            )
        }

        if let pinnedHubInstanceID = normalizedDiscoveryToken(cachedPairing.hubInstanceID) {
            let matches = candidates.filter {
                normalizedDiscoveryToken($0.hubInstanceID) == pinnedHubInstanceID
            }
            if matches.count == 1, let match = matches.first {
                return HubLANDiscoveryAttempt(
                    candidate: match,
                    reasonCode: nil,
                    candidates: candidates,
                    logLines: ["[\(source)] selected cached hub identity=\(pinnedHubInstanceID) -> \(describeDiscoveryCandidate(match))"]
                )
            }
        }

        let pinnedInternetHosts = [
            normalizedHostToken(configuredInternetHost),
            normalizedHostToken(cachedPairing.internetHost),
        ].compactMap { $0 }

        for pinnedInternetHost in pinnedInternetHosts {
            let matches = candidates.filter {
                normalizedHostToken($0.internetHost) == pinnedInternetHost
            }
            if matches.count == 1, let match = matches.first {
                return HubLANDiscoveryAttempt(
                    candidate: match,
                    reasonCode: nil,
                    candidates: candidates,
                    logLines: ["[\(source)] selected pinned internet host=\(pinnedInternetHost) -> \(describeDiscoveryCandidate(match))"]
                )
            }
        }

        let rendered = candidates
            .map { describeDiscoveryCandidate($0) }
            .joined(separator: " | ")
        return HubLANDiscoveryAttempt(
            candidate: nil,
            reasonCode: ambiguousReasonCode,
            candidates: candidates,
            logLines: ["[\(source)] multiple hubs discovered; refusing auto-select. candidates=\(rendered)"]
        )
    }

    private func summary(from candidate: HubLANDiscoveryCandidate) -> HubDiscoveredHubCandidateSummary {
        HubDiscoveredHubCandidateSummary(
            host: candidate.host,
            pairingPort: candidate.pairingPort,
            grpcPort: candidate.grpcPort,
            internetHost: candidate.internetHost,
            hubInstanceID: candidate.hubInstanceID,
            lanDiscoveryName: candidate.lanDiscoveryName
        )
    }

    private func deduplicatedDiscoveryCandidates(
        _ rawCandidates: [HubLANDiscoveryCandidate]
    ) -> [HubLANDiscoveryCandidate] {
        var mergedByKey: [String: HubLANDiscoveryCandidate] = [:]
        var orderedKeys: [String] = []

        for candidate in rawCandidates {
            let key = discoveryCandidateKey(candidate)
            if let existing = mergedByKey[key] {
                mergedByKey[key] = richerDiscoveryCandidate(existing, candidate)
            } else {
                mergedByKey[key] = candidate
                orderedKeys.append(key)
            }
        }

        return orderedKeys.compactMap { mergedByKey[$0] }
    }

    private func discoveryCandidateKey(_ candidate: HubLANDiscoveryCandidate) -> String {
        if let hubInstanceID = normalizedDiscoveryToken(candidate.hubInstanceID) {
            return "id:\(hubInstanceID)"
        }
        return [
            normalizedHostToken(candidate.host) ?? "",
            String(candidate.pairingPort),
            String(candidate.grpcPort),
            normalizedHostToken(candidate.internetHost) ?? "",
        ].joined(separator: "|")
    }

    private func richerDiscoveryCandidate(
        _ lhs: HubLANDiscoveryCandidate,
        _ rhs: HubLANDiscoveryCandidate
    ) -> HubLANDiscoveryCandidate {
        discoveryCandidateScore(lhs) >= discoveryCandidateScore(rhs) ? lhs : rhs
    }

    private func discoveryCandidateScore(_ candidate: HubLANDiscoveryCandidate) -> Int {
        var score = 0
        if nonEmpty(candidate.internetHost) != nil { score += 4 }
        if nonEmpty(candidate.hubInstanceID) != nil { score += 3 }
        if nonEmpty(candidate.lanDiscoveryName) != nil { score += 2 }
        if !candidate.logLines.isEmpty { score += 1 }
        return score
    }

    private func describeDiscoveryCandidate(_ candidate: HubLANDiscoveryCandidate) -> String {
        let service = nonEmpty(candidate.lanDiscoveryName)
            ?? nonEmpty(candidate.hubInstanceID)
            ?? candidate.host
        let internet = nonEmpty(candidate.internetHost) ?? "-"
        return "service=\(service) host=\(candidate.host) pairing=\(candidate.pairingPort) grpc=\(candidate.grpcPort) internet=\(internet)"
    }

    private func normalizedDiscoveryToken(_ raw: String?) -> String? {
        nonEmpty(raw)?.lowercased()
    }

    private func normalizedHostToken(_ raw: String?) -> String? {
        guard let value = nonEmpty(raw)?.lowercased() else { return nil }
        if value.hasSuffix(".") {
            return String(value.dropLast())
        }
        return value
    }

    private func prioritizeLANHosts(
        _ hosts: [String],
        preferredHosts: [String?]
    ) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        func appendHost(_ raw: String?) {
            guard let raw else { return }
            let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return }
            guard !isLoopbackHost(host) else { return }
            guard seen.insert(normalizeHost(host)).inserted else { return }
            ordered.append(host)
        }

        for host in preferredHosts {
            appendHost(host)
        }
        for host in hosts {
            appendHost(host)
        }
        return ordered
    }

    private func persistDiscoveredPairingInfo(
        host: String,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String?,
        hubInstanceID: String?,
        lanDiscoveryName: String?,
        options: HubRemoteConnectOptions
    ) throws {
        let base = options.stateDir ?? defaultStateDir()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let pairingEnv = base.appendingPathComponent("pairing.env")
        let appID = canonicalHubAppID(readEnvValue(from: pairingEnv, key: "AXHUB_APP_ID")) ?? "x_terminal"
        let deviceName = nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_DEVICE_NAME"))
            ?? nonEmpty(options.deviceName)
            ?? "X-Terminal"
        let pairingRequestID = readEnvValue(from: pairingEnv, key: "AXHUB_PAIRING_REQUEST_ID") ?? ""
        let pairingSecret = readEnvValue(from: pairingEnv, key: "AXHUB_PAIRING_SECRET") ?? ""
        let preservedInternetHost = nonEmpty(internetHost)
            ?? nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_INTERNET_HOST"))
            ?? ""
        let preservedHubInstanceID = nonEmpty(hubInstanceID)
            ?? nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_HUB_INSTANCE_ID"))
            ?? ""
        let preservedLanDiscoveryName = nonEmpty(lanDiscoveryName)
            ?? nonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_LAN_DISCOVERY_NAME"))
            ?? ""

        let contents = [
            "AXHUB_HUB_HOST=\(shellSingleQuoted(host))",
            "AXHUB_PAIRING_PORT=\(shellSingleQuoted(String(pairingPort)))",
            "AXHUB_GRPC_PORT=\(shellSingleQuoted(String(grpcPort)))",
            "AXHUB_APP_ID=\(shellSingleQuoted(appID))",
            "AXHUB_DEVICE_NAME=\(shellSingleQuoted(deviceName))",
            "AXHUB_PAIRING_REQUEST_ID=\(shellSingleQuoted(pairingRequestID))",
            "AXHUB_PAIRING_SECRET=\(shellSingleQuoted(pairingSecret))",
            "AXHUB_INTERNET_HOST=\(shellSingleQuoted(preservedInternetHost))",
            "AXHUB_HUB_INSTANCE_ID=\(shellSingleQuoted(preservedHubInstanceID))",
            "AXHUB_LAN_DISCOVERY_NAME=\(shellSingleQuoted(preservedLanDiscoveryName))",
        ].joined(separator: "\n") + "\n"

        try contents.write(to: pairingEnv, atomically: true, encoding: .utf8)
    }

    private nonisolated static func buildLANDiscoveryScanPlan() -> HubLANDiscoveryScanPlan {
        var discoveredHosts: [String] = []
        var seenHosts: Set<String> = []
        var networkSummaries: [String] = []
        var seenNetworks: Set<String> = []

        var cursor: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&cursor) == 0, let first = cursor else {
            return HubLANDiscoveryScanPlan(hosts: [], networkSummaries: [])
        }
        defer { freeifaddrs(cursor) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = current {
            defer { current = pointer.pointee.ifa_next }

            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, let netmask = entry.ifa_netmask else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard netmask.pointee.sa_family == UInt8(AF_INET) else { continue }

            let flags = Int32(entry.ifa_flags)
            guard (flags & IFF_UP) != 0 else { continue }
            guard (flags & IFF_LOOPBACK) == 0 else { continue }

            guard let addressValue = ipv4UInt32(from: addr),
                  let maskValue = ipv4UInt32(from: netmask),
                  maskValue != 0 else {
                continue
            }

            var prefixLength = maskValue.nonzeroBitCount
            var effectiveMask = maskValue
            if prefixLength < 24 {
                prefixLength = 24
                effectiveMask = 0xFF_FF_FF_00
            }
            if prefixLength > 30 { continue }

            let network = addressValue & effectiveMask
            let broadcast = network | ~effectiveMask
            guard broadcast > network + 1 else { continue }

            let networkSummary = "\(ipv4String(network))/\(prefixLength)"
            if seenNetworks.insert(networkSummary).inserted {
                networkSummaries.append(networkSummary)
            }

            func appendHost(_ rawValue: UInt32) {
                guard rawValue > network, rawValue < broadcast else { return }
                guard rawValue != addressValue else { return }
                let host = ipv4String(rawValue)
                let key = host.lowercased()
                guard seenHosts.insert(key).inserted else { return }
                discoveredHosts.append(host)
            }

            appendHost(network &+ 1)
            var candidate = network &+ 1
            while candidate < broadcast {
                appendHost(candidate)
                candidate &+= 1
            }
        }

        return HubLANDiscoveryScanPlan(
            hosts: discoveredHosts,
            networkSummaries: networkSummaries
        )
    }

    private nonisolated static func collectLANDiscoveryMatches(
        hosts: [String],
        pairingPort: Int,
        timeoutSec: TimeInterval
    ) async -> [HubLANDiscoveryProbeMatch] {
        await withTaskGroup(of: HubLANDiscoveryProbeMatch?.self) { group in
            for host in hosts {
                group.addTask {
                    await probeLANPairingEndpoint(
                        host: host,
                        pairingPort: pairingPort,
                        timeoutSec: timeoutSec
                    )
                }
            }

            var matches: [HubLANDiscoveryProbeMatch] = []
            for await result in group {
                if let result {
                    matches.append(result)
                }
            }
            return matches
        }
    }

    private nonisolated static func probeLANPairingEndpoint(
        host: String,
        pairingPort: Int,
        timeoutSec: TimeInterval
    ) async -> HubLANDiscoveryProbeMatch? {
        guard let url = URL(string: "http://\(host):\(pairingPort)/pairing/discovery") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSec
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return nil
            }
            let payload = try JSONDecoder().decode(HubPairingDiscoveryPayload.self, from: data)
            guard payload.matchesPairingService else { return nil }

            let matchedHost = normalizedTrimmed(payload.hubHostHint) ?? host
            return HubLANDiscoveryProbeMatch(
                host: matchedHost,
                pairingPort: payload.pairingPort ?? pairingPort,
                grpcPort: payload.grpcPort ?? 50051,
                internetHost: normalizedTrimmed(payload.internetHostHint),
                hubInstanceID: normalizedTrimmed(payload.hubInstanceID),
                lanDiscoveryName: normalizedTrimmed(payload.lanDiscoveryName)
            )
        } catch {
            return nil
        }
    }

    private nonisolated static func ipv4UInt32(from sockaddrPointer: UnsafeMutablePointer<sockaddr>) -> UInt32? {
        guard sockaddrPointer.pointee.sa_family == UInt8(AF_INET) else { return nil }
        return sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
            UInt32(bigEndian: pointer.pointee.sin_addr.s_addr)
        }
    }

    private nonisolated static func ipv4String(_ address: UInt32) -> String {
        [
            String((address >> 24) & 0xFF),
            String((address >> 16) & 0xFF),
            String((address >> 8) & 0xFF),
            String(address & 0xFF),
        ].joined(separator: ".")
    }

    private nonisolated static func currentMachineIPv4Hosts() -> Set<String> {
        var hosts: Set<String> = ["127.0.0.1", "localhost"]
        var cursor: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&cursor) == 0, let first = cursor else {
            return hosts
        }
        defer { freeifaddrs(cursor) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = current {
            defer { current = pointer.pointee.ifa_next }
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard let addressValue = ipv4UInt32(from: addr) else { continue }
            hosts.insert(ipv4String(addressValue).lowercased())
        }
        return hosts
    }

    private nonisolated static func normalizedTrimmed(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private enum ExecutableRef {
        case direct(String)
        case bashScript(String)
        case viaEnv
    }

    private func stagedBundledExecutable(named fileName: String) -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let sourceURL = resourceURL.appendingPathComponent(fileName, isDirectory: false)
        return stageBundledExecutableIfNeeded(sourceURL: sourceURL)
    }

    private func stageBundledExecutableIfNeeded(sourceURL: URL) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { return nil }

        let stagedDir = HubBundledToolSupport.toolSupportBinDirectory(
            applicationSupportBase: HubBundledToolSupport.defaultApplicationSupportBase(fileManager: fm)
        )
        do {
            try fm.createDirectory(at: stagedDir, withIntermediateDirectories: true)
        } catch {
            return sourceURL.path
        }

        let stagedURL = stagedDir.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
        if shouldRefreshStagedExecutable(sourceURL: sourceURL, stagedURL: stagedURL, fileManager: fm) {
            do {
                if fm.fileExists(atPath: stagedURL.path) {
                    try fm.removeItem(at: stagedURL)
                }
                try fm.copyItem(at: sourceURL, to: stagedURL)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedURL.path)
            } catch {
                return sourceURL.path
            }
        }

        return stagedURL.path
    }

    private func shouldRefreshStagedExecutable(
        sourceURL: URL,
        stagedURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: stagedURL.path) else { return true }
        guard
            let sourceAttrs = try? fileManager.attributesOfItem(atPath: sourceURL.path),
            let stagedAttrs = try? fileManager.attributesOfItem(atPath: stagedURL.path)
        else {
            return true
        }

        let sourceSize = sourceAttrs[.size] as? NSNumber
        let stagedSize = stagedAttrs[.size] as? NSNumber
        if sourceSize != stagedSize {
            return true
        }

        let sourceModified = sourceAttrs[.modificationDate] as? Date
        let stagedModified = stagedAttrs[.modificationDate] as? Date
        if let sourceModified, let stagedModified {
            return sourceModified > stagedModified
        }
        return false
    }

    private func resolveAxhubctlExecutable(override: String) -> ExecutableRef {
        let fm = FileManager.default

        if !override.isEmpty {
            let p = expandTilde(override)
            if fm.fileExists(atPath: p) {
                let best = preferredAxhubctlPath(primary: p)
                return fm.isExecutableFile(atPath: best) ? .direct(best) : .bashScript(best)
            }
        }

        if let bundled = bundledAxhubctlCandidate() {
            return fm.isExecutableFile(atPath: bundled) ? .direct(bundled) : .bashScript(bundled)
        }

        let directCandidates = HubBundledToolSupport.defaultAxhubctlFallbackCandidates(
            homeDirectory: fm.homeDirectoryForCurrentUser
        )

        for p in directCandidates {
            let e = expandTilde(p)
            if fm.fileExists(atPath: e) {
                let best = preferredAxhubctlPath(primary: e)
                return fm.isExecutableFile(atPath: best) ? .direct(best) : .bashScript(best)
            }
        }

        if let repo = repoRelativeAxhubctlCandidate(), fm.fileExists(atPath: repo) {
            let best = preferredAxhubctlPath(primary: repo)
            return fm.isExecutableFile(atPath: best) ? .direct(best) : .bashScript(best)
        }

        return .viaEnv
    }

    private func bundledAxhubctlCandidate() -> String? {
        guard let staged = stagedBundledExecutable(named: "axhubctl") else { return nil }
        return FileManager.default.fileExists(atPath: staged) ? staged : nil
    }

    private func preferredAxhubctlPath(primary: String) -> String {
        guard !supportsModernAxhubctlCommands(at: primary),
              let bundled = bundledAxhubctlCandidate(),
              supportsModernAxhubctlCommands(at: bundled) else {
            return primary
        }
        return bundled
    }

    private func supportsModernAxhubctlCommands(at path: String) -> Bool {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return true
        }
        let lower = text.lowercased()
        return lower.contains("  discover)") && lower.contains("  connect)")
    }

    private func repoRelativeAxhubctlCandidate() -> String? {
        let fm = FileManager.default
        var url = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            let c1 = url
                .appendingPathComponent("x-hub/grpc-server/hub_grpc_server/assets/axhubctl")
                .path
            if fm.fileExists(atPath: c1) { return c1 }

            let c2 = url
                .appendingPathComponent("x-hub-system/x-hub/grpc-server/hub_grpc_server/assets/axhubctl")
                .path
            if fm.fileExists(atPath: c2) { return c2 }

            let c3 = url
                .appendingPathComponent("hub_grpc_server/assets/axhubctl")
                .path
            if fm.fileExists(atPath: c3) { return c3 }

            url.deleteLastPathComponent()
        }
        return nil
    }

    private func discoveryEnv(internetHost: String) -> [String: String] {
        let host = internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        var hints = ["127.0.0.1", "localhost"]
        if !host.isEmpty {
            hints.insert(host, at: 0)
        }
        return ["HUB_DISCOVERY_HINTS": hints.joined(separator: ",")]
    }

    private func mergedAxhubEnv(
        options: HubRemoteConnectOptions,
        extra: [String: String]
    ) -> [String: String] {
        var out = extra
        if let d = options.stateDir {
            out["AXHUBCTL_STATE_DIR"] = d.path
        }
        if out["AXHUBCTL_PREFER_BUNDLED_NODE"] == nil {
            out["AXHUBCTL_PREFER_BUNDLED_NODE"] = "0"
        }
        if out["AXHUBCTL_NODE_BIN"] == nil, let node = preferredNodeBinPath() {
            out["AXHUBCTL_NODE_BIN"] = node
        }
        if let appID = canonicalHubAppID(out["HUB_APP_ID"]) {
            out["HUB_APP_ID"] = appID
        }
        return out
    }

    private func preferredNodeBinPath() -> String? {
        let fm = FileManager.default
        if let stagedNode = stagedBundledExecutable(named: "relflowhub_node"),
           fm.isExecutableFile(atPath: stagedNode) {
            return stagedNode
        }
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        for c in candidates where fm.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    private func defaultStateDir() -> URL {
        XTProcessPaths.defaultAxhubStateDir()
    }

    private func loadCachedPairingInfo(stateDir: URL?) -> HubCachedPairingInfo {
        let base = stateDir ?? defaultStateDir()
        let pairingEnv = base.appendingPathComponent("pairing.env")
        let hubEnv = base.appendingPathComponent("hub.env")

        let hostFromPairing = readEnvValue(from: pairingEnv, key: "AXHUB_HUB_HOST")
        let internetHostFromPairing = readEnvValue(from: pairingEnv, key: "AXHUB_INTERNET_HOST")
        let hubInstanceID = readEnvValue(from: pairingEnv, key: "AXHUB_HUB_INSTANCE_ID")
        let lanDiscoveryName = readEnvValue(from: pairingEnv, key: "AXHUB_LAN_DISCOVERY_NAME")
        let pairingPort = normalizePort(readEnvValue(from: pairingEnv, key: "AXHUB_PAIRING_PORT"))
        let grpcFromPairing = normalizePort(readEnvValue(from: pairingEnv, key: "AXHUB_GRPC_PORT"))

        let host = nonEmpty(hostFromPairing) ?? nonEmpty(readEnvValue(from: hubEnv, key: "HUB_HOST"))
        let internetHost = nonEmpty(internetHostFromPairing) ?? inferredReusableInternetHost(
            host,
            hubInstanceID: nonEmpty(hubInstanceID),
            lanDiscoveryName: nonEmpty(lanDiscoveryName)
        )
        let grpcPort = grpcFromPairing ?? normalizePort(readEnvValue(from: hubEnv, key: "HUB_PORT"))

        return HubCachedPairingInfo(
            host: host,
            internetHost: internetHost,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            hubInstanceID: nonEmpty(hubInstanceID),
            lanDiscoveryName: nonEmpty(lanDiscoveryName)
        )
    }

    private func expandTilde(_ text: String) -> String {
        NSString(string: text).expandingTildeInPath
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizePort(_ raw: String?) -> Int? {
        guard let value = nonEmpty(raw), let p = Int(value), (1...65_535).contains(p) else {
            return nil
        }
        return p
    }

    private func inferredReusableInternetHost(
        _ host: String?,
        hubInstanceID: String? = nil,
        lanDiscoveryName: String? = nil
    ) -> String? {
        Self.inferredReusableInternetHostValue(
            host,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )
    }

    private static func inferredReusableInternetHostValue(
        _ host: String?,
        hubInstanceID: String? = nil,
        lanDiscoveryName: String? = nil
    ) -> String? {
        func trimmedNonEmpty(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        guard let host = trimmedNonEmpty(host) else { return nil }
        let lowered = host.lowercased()
        if lowered == "localhost" || lowered == "127.0.0.1" || lowered.hasSuffix(".local") {
            return nil
        }
        if isPrivateIPv4Host(lowered) {
            return nil
        }
        if isIPv4Host(lowered),
           trimmedNonEmpty(hubInstanceID) != nil || trimmedNonEmpty(lanDiscoveryName) != nil {
            return nil
        }
        return host
    }

    private static func isIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { (0...255).contains($0) }
    }

    private static func isPrivateIPv4Host(_ host: String) -> Bool {
        guard isIPv4Host(host) else { return false }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        let a = octets[0]
        let b = octets[1]
        if a == 10 { return true }
        if a == 127 { return true }
        if a == 169, b == 254 { return true }
        if a == 172, b >= 16, b <= 31 { return true }
        if a == 192, b == 168 { return true }
        return false
    }

    private func readEnvValue(from fileURL: URL, key: String) -> String? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            var candidate = trimmed
            if candidate.hasPrefix("export ") {
                candidate = String(candidate.dropFirst("export ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let eq = candidate.firstIndex(of: "=") else { continue }
            let lhs = String(candidate[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard lhs == key else { continue }
            let rhs = String(candidate[candidate.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return unquoteShellValue(rhs)
        }
        return nil
    }

    private func unquoteShellValue(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private func shellSingleQuoted(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
