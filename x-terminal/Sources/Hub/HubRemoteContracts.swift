import Foundation

enum HubRemoteRoute: String, Codable, Sendable {
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
    var inviteToken: String
    var inviteAlias: String
    var inviteInstanceID: String
    var axhubctlPath: String
    var configuredEndpointIsAuthoritative: Bool
    var stateDir: URL?

    init(
        grpcPort: Int,
        pairingPort: Int,
        deviceName: String,
        internetHost: String,
        inviteToken: String = "",
        inviteAlias: String = "",
        inviteInstanceID: String = "",
        axhubctlPath: String,
        configuredEndpointIsAuthoritative: Bool = false,
        stateDir: URL?
    ) {
        self.grpcPort = grpcPort
        self.pairingPort = pairingPort
        self.deviceName = deviceName
        self.internetHost = internetHost
        self.inviteToken = inviteToken
        self.inviteAlias = inviteAlias
        self.inviteInstanceID = inviteInstanceID
        self.axhubctlPath = axhubctlPath
        self.configuredEndpointIsAuthoritative = configuredEndpointIsAuthoritative
        self.stateDir = stateDir
    }
}

struct HubRemoteConnectReport: Sendable {
    var ok: Bool
    var route: HubRemoteRoute
    var summary: String
    var logLines: [String]
    var reasonCode: String?
    var completedFreshPairing: Bool
    var selectedRoute: XTHubRouteCandidate?
    var attemptedRoutes: [XTHubRouteCandidate]
    var handoffReason: String?
    var cooldownApplied: Bool

    var logText: String {
        logLines.joined(separator: "\n")
    }

    init(
        ok: Bool,
        route: HubRemoteRoute,
        summary: String,
        logLines: [String],
        reasonCode: String?,
        completedFreshPairing: Bool = false,
        selectedRoute: XTHubRouteCandidate? = nil,
        attemptedRoutes: [XTHubRouteCandidate] = [],
        handoffReason: String? = nil,
        cooldownApplied: Bool = false
    ) {
        self.ok = ok
        self.route = route
        self.summary = summary
        self.logLines = logLines
        self.reasonCode = reasonCode
        self.completedFreshPairing = completedFreshPairing
        self.selectedRoute = selectedRoute
        self.attemptedRoutes = attemptedRoutes
        self.handoffReason = handoffReason
        self.cooldownApplied = cooldownApplied
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

enum HubRemoteBootstrapDisposition: Sendable {
    case connectOnly
    case freshPairingApproved
    case reusedExistingProfile
    case refreshedExistingProfile
}

enum HubRemoteConnectAttemptOutcome: Sendable {
    case succeeded(HubRemoteConnectReport)
    case legacy(HubRemoteConnectReport)
    case failed(String)
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
    var pairingProfileEpoch: Int? = nil
    var routePackVersion: String? = nil

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

struct HubPairingDiscoveryPayload: Decodable, Sendable {
    var ok: Bool?
    var service: String?
    var hubHostHint: String?
    var pairingPort: Int?
    var grpcPort: Int?
    var internetHostHint: String?
    var hubInstanceID: String?
    var lanDiscoveryName: String?
    var pairingProfileEpoch: Int?
    var routePackVersion: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case service
        case hubHostHint = "hub_host_hint"
        case pairingPort = "pairing_port"
        case grpcPort = "grpc_port"
        case internetHostHint = "internet_host_hint"
        case hubInstanceID = "hub_instance_id"
        case lanDiscoveryName = "lan_discovery_name"
        case pairingProfileEpoch = "pairing_profile_epoch"
        case routePackVersion = "route_pack_version"
    }

    var matchesPairingService: Bool {
        if ok == true { return true }
        let normalizedService = (service ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedService.contains("pair")
    }
}

struct HubLANDiscoveryCandidate: Sendable {
    var host: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String?
    var hubInstanceID: String?
    var lanDiscoveryName: String?
    var pairingProfileEpoch: Int? = nil
    var routePackVersion: String? = nil
    var logLines: [String]
}

struct HubLANDiscoveryProbeMatch: Sendable {
    var host: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String?
    var hubInstanceID: String?
    var lanDiscoveryName: String?
    var pairingProfileEpoch: Int? = nil
    var routePackVersion: String? = nil
}

struct HubLANDiscoveryProbeOutcome: Sendable {
    var match: HubLANDiscoveryProbeMatch?
    var localNetworkAccessDenied: Bool
}

struct HubLANDiscoveryProbeCollection: Sendable {
    var matches: [HubLANDiscoveryProbeMatch]
    var localNetworkAccessDenied: Bool
}

struct HubLANDiscoveryMultiPortProbeCollection: Sendable {
    var matchesByPort: [Int: [HubLANDiscoveryProbeMatch]]
    var localNetworkAccessDenied: Bool
}

struct HubCachedPairingInfo: Sendable {
    var host: String?
    var internetHost: String?
    var pairingPort: Int?
    var grpcPort: Int?
    var hubInstanceID: String?
    var lanDiscoveryName: String?
    var pairingProfileEpoch: Int? = nil
    var routePackVersion: String? = nil
}

struct HubCachedPairingLoadResult: Sendable {
    var pairing: HubCachedPairingInfo
    var logLines: [String]
}

struct HubLANDiscoveryAttempt: Sendable {
    var candidate: HubLANDiscoveryCandidate?
    var reasonCode: String?
    var candidates: [HubLANDiscoveryCandidate]
    var logLines: [String]
}

struct HubLANDiscoveryScanPlan: Sendable {
    var hosts: [String]
    var networkSummaries: [String]
}

struct HubLANDiscoveryCIDR: Sendable {
    var network: UInt32
    var broadcast: UInt32
    var prefixLength: Int
}

struct PairingMetadataRepairBlock: Sendable {
    var reasonCode: String
    var detailLine: String
}

struct HubRemoteResetResult: Sendable {
    var ok: Bool
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemotePaidAccessSnapshot: Equatable, Sendable {
    var trustProfilePresent: Bool
    var paidModelPolicyMode: String?
    var dailyTokenLimit: Int
    var singleRequestTokenLimit: Int
}

struct HubRemoteModelsResult: Sendable {
    var ok: Bool
    var models: [HubModel]
    var paidAccessSnapshot: HubRemotePaidAccessSnapshot?
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

func canonicalHubAppID(_ raw: String?) -> String? {
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
    var auditRef: String? = nil
    var denyCode: String? = nil
    var promptTokens: Int? = nil
    var completionTokens: Int? = nil
    var memoryPromptProjection: HubMemoryPromptProjectionSnapshot? = nil
    var grantDecision: HubRemoteGrantDecision? = nil
    var grantRequestId: String? = nil
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
    var messages: [XTProjectConversationMirrorMessage] = []
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
    var source: String = "hub_runtime_grpc"
    var auditRefs: [String] = []
    var evidenceRefs: [String] = []
    var writebackRefs: [String] = []
    var updatedAtMs: Int64? = nil
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

struct HubRemoteSkillManifestResult: Sendable {
    var ok: Bool
    var source: String
    var packageSHA256: String
    var manifestJSON: String
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSkillPackageDownloadResult: Sendable {
    var ok: Bool
    var source: String
    var packageSHA256: String
    var data: Data
    var reasonCode: String?
    var logLines: [String]

    var logText: String {
        logLines.joined(separator: "\n")
    }
}

struct HubRemoteSkillRunnerGateResult: Sendable {
    var ok: Bool
    var source: String
    var skillId: String
    var packageSHA256: String
    var toolName: String
    var decision: String
    var toolRequestId: String
    var grantId: String
    var executionId: String
    var denyCode: String?
    var resultJSON: String
    var executedAtMs: Int64
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
    var roleTurnMessages: [XTProjectConversationMirrorMessage] = []
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

enum HubRemoteRuntimeSurfaceCompatContract {
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

struct HubRemoteSupervisorRouteGovernanceComponent: Sendable {
    var key: AXProjectGovernanceRuntimeReadinessComponentKey
    var state: AXProjectGovernanceRuntimeReadinessComponentState
    var denyCode: String
    var summaryLine: String
    var missingReasonCodes: [String]
}

struct HubRemoteSupervisorRouteGovernanceRuntimeReadiness: Sendable {
    var schemaVersion: String
    var source: String
    var governanceSurface: String
    var context: String
    var configured: Bool
    var state: AXProjectGovernanceRuntimeReadinessState
    var runtimeReady: Bool
    var projectId: String
    var blockers: [String]
    var blockedComponentKeys: [AXProjectGovernanceRuntimeReadinessComponentKey]
    var missingReasonCodes: [String]
    var summaryLine: String
    var missingSummaryLine: String
    var components: [HubRemoteSupervisorRouteGovernanceComponent]
}

struct HubRemoteSupervisorRouteDecision: Sendable {
    var schemaVersion: String
    var routeId: String
    var requestId: String
    var projectId: String
    var runId: String
    var missionId: String
    var decision: String
    var riskTier: String
    var preferredDeviceId: String
    var resolvedDeviceId: String
    var runnerId: String
    var xtOnline: Bool
    var runnerRequired: Bool
    var sameProjectScope: Bool
    var requiresGrant: Bool
    var grantScope: String
    var denyCode: String
    var updatedAtMs: Double
    var auditRef: String
}

struct HubRemoteSupervisorRouteDecisionResult: Sendable {
    var ok: Bool
    var source: String
    var route: HubRemoteSupervisorRouteDecision?
    var governanceRuntimeReadiness: HubRemoteSupervisorRouteGovernanceRuntimeReadiness?
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

func hubInviteTokenArgs(_ options: HubRemoteConnectOptions) -> [String] {
    let token = options.inviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return [] }
    return ["--invite-token", token]
}
