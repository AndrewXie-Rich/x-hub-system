import Foundation
import Darwin

enum HubIPCClient {
    private enum RuntimeSurfaceOverrideCompatContract {
        static let snapshotFilename = "autonomy_policy_overrides_status.json"
        static let fileSource = "hub_autonomy_policy_overrides_file"
    }

    private static let remoteMemorySnapshotCache = HubRemoteMemorySnapshotCache(ttlSeconds: 15.0)
    private static let remoteRuntimeSurfaceOverrideCacheTTLSeconds: TimeInterval = 20.0
    private static var remoteRuntimeSurfaceOverrideCache = HubRemoteRuntimeSurfaceOverrideCache(
        ttlSeconds: remoteRuntimeSurfaceOverrideCacheTTLSeconds
    )
    private static let testingOverrideLock = NSLock()
    private static let runtimeSurfaceFetchLock = NSLock()
    private static var inFlightRuntimeSurfaceOverrideFetches: [HubRemoteRuntimeSurfaceOverrideCache.Key: Task<RuntimeSurfaceOverridesSnapshot?, Never>] = [:]
    private struct TestingOverrideScopeKey: Hashable {
        let task: UnsafeCurrentTask
    }
    private static var agentImportStageOverrideForTesting: (@Sendable (AgentImportStageRequestPayload) async -> AgentImportStageResult)?
    private static var agentImportRecordOverrideForTesting: (@Sendable (AgentImportRecordLookupPayload) async -> AgentImportRecordResult)?
    private static var skillPackageUploadOverrideForTesting: (@Sendable (SkillPackageUploadRequestPayload) async -> SkillPackageUploadResult)?
    private static var agentImportPromoteOverrideForTesting: (@Sendable (AgentImportPromoteRequestPayload) async -> AgentImportPromoteResult)?
    private static var skillPinOverrideForTesting: (@Sendable (SkillPinRequestPayload) async -> SkillPinResult)?
    private static var resolvedSkillsOverrideForTesting: (@Sendable (String?) async -> ResolvedSkillsResult)?
    private static var skillManifestOverrideForTesting: (@Sendable (String) async -> SkillManifestResult)?
    private static var secretUseOverrideForTesting: (@Sendable (SecretUseRequestPayload) async -> SecretUseResult)?
    private static var secretRedeemOverrideForTesting: (@Sendable (SecretRedeemRequestPayload) async -> SecretRedeemResult)?
    private static var localTaskExecutionOverrideForTesting: (@Sendable (LocalTaskRequestPayload, Double) -> LocalTaskResult)?
    private static var routeDecisionOverrideForTesting: (@Sendable () async -> HubRouteDecision)?
    private static var scopedRouteDecisionOverridesForTesting: [TestingOverrideScopeKey: (@Sendable () async -> HubRouteDecision)] = [:]
    private static var memoryContextResolutionOverrideForTesting: (@Sendable (XTMemoryRouteDecision, XTMemoryUseMode, Double) async -> MemoryContextResolutionResult)?
    private static var scopedMemoryContextResolutionOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (XTMemoryRouteDecision, XTMemoryUseMode, Double) async -> MemoryContextResolutionResult)] = [:]
    private static var memoryRetrievalOverrideForTesting: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    private static var scopedMemoryRetrievalOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)] = [:]
    private static var localMemoryRetrievalIPCOverrideForTesting: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    private static var scopedLocalMemoryRetrievalIPCOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)] = [:]
    private static var remoteMemorySnapshotOverrideForTesting: (@Sendable (XTMemoryUseMode, String?, Bool, Double) async -> HubRemoteMemorySnapshotResult)?
    private static var scopedRemoteMemorySnapshotOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (XTMemoryUseMode, String?, Bool, Double) async -> HubRemoteMemorySnapshotResult)] = [:]
    private static var voiceGrantChallengeOverrideForTesting: (@Sendable (VoiceGrantChallengeRequestPayload) async -> VoiceGrantChallengeResult)?
    private static var scopedVoiceGrantChallengeOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (VoiceGrantChallengeRequestPayload) async -> VoiceGrantChallengeResult)] = [:]
    private static var voiceGrantVerificationOverrideForTesting: (@Sendable (VoiceGrantVerificationPayload) async -> VoiceGrantVerificationResult)?
    private static var scopedVoiceGrantVerificationOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (VoiceGrantVerificationPayload) async -> VoiceGrantVerificationResult)] = [:]
    private static var remoteMemoryRetrievalOverrideForTesting: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    private static var scopedRemoteMemoryRetrievalOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)] = [:]
    private static var remoteRuntimeSurfaceOverridesOverrideForTesting: (@Sendable (String?, Int, Double) async -> HubRemoteRuntimeSurfaceOverridesResult)?
    private static var scopedRemoteRuntimeSurfaceOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (String?, Int, Double) async -> HubRemoteRuntimeSurfaceOverridesResult)] = [:]
    private static var supervisorRemoteContinuityOverrideForTesting: (@Sendable (Bool) async -> SupervisorRemoteContinuityResult)?
    private static var scopedSupervisorRemoteContinuityOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (Bool) async -> SupervisorRemoteContinuityResult)] = [:]
    private static var supervisorConversationAppendOverrideForTesting: (@Sendable (HubRemoteSupervisorConversationPayload) async -> Bool)?
    private static var scopedSupervisorConversationAppendOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (HubRemoteSupervisorConversationPayload) async -> Bool)] = [:]
    private static var supervisorRouteDecisionOverrideForTesting: (@Sendable (SupervisorRouteDecisionRequestPayload) async -> SupervisorRouteDecisionResult)?
    private static var scopedSupervisorRouteDecisionOverridesForTesting: [TestingOverrideScopeKey: (@Sendable (SupervisorRouteDecisionRequestPayload) async -> SupervisorRouteDecisionResult)] = [:]
    private static var eventWriteOverrideForTesting: (@Sendable (Data, URL, URL) throws -> Void)?
    private static let voiceTTSReadinessCacheLock = NSLock()
    private static let voiceTTSReadinessCacheTTL: TimeInterval = 1.0
    private static var voiceTTSReadinessCache: [String: CachedVoiceTTSReadiness] = [:]
    private static let canonicalMemorySyncStatusCacheLock = NSLock()
    private static var canonicalMemorySyncStatusCache: CachedCanonicalMemorySyncStatus?

    private static func withTestingOverrideLock<T>(_ body: () -> T) -> T {
        testingOverrideLock.lock()
        defer { testingOverrideLock.unlock() }
        return body()
    }

    private static func currentTestingOverrideScopeKey() -> TestingOverrideScopeKey? {
        var scopeKey: TestingOverrideScopeKey?
        withUnsafeCurrentTask { task in
            if let task {
                scopeKey = TestingOverrideScopeKey(task: task)
            }
        }
        return scopeKey
    }

    private static func testingOverride<T>(
        fallback: T?,
        scoped: [TestingOverrideScopeKey: T]
    ) -> T? {
        if let scopeKey = currentTestingOverrideScopeKey(),
           let override = scoped[scopeKey] {
            return override
        }
        return fallback
    }

    private static func setTestingOverride<T>(
        _ override: T?,
        fallback: inout T?,
        scoped: inout [TestingOverrideScopeKey: T]
    ) {
        if let scopeKey = currentTestingOverrideScopeKey() {
            if let override {
                scoped[scopeKey] = override
            } else {
                scoped.removeValue(forKey: scopeKey)
            }
            return
        }
        fallback = override
    }

    private static func resetTestingOverride<T>(
        fallback: inout T?,
        scoped: inout [TestingOverrideScopeKey: T]
    ) {
        if let scopeKey = currentTestingOverrideScopeKey() {
            scoped.removeValue(forKey: scopeKey)
            return
        }
        fallback = nil
    }

    private struct CachedVoiceTTSReadiness {
        var result: VoiceTTSReadinessResult
        var expiresAt: TimeInterval
    }

    private struct CachedCanonicalMemorySyncStatus {
        var urlPath: String
        var fileSize: UInt64
        var modificationTime: TimeInterval
        var snapshot: CanonicalMemorySyncStatusSnapshot
    }

    struct RuntimeSurfaceOverrideItem: Equatable, Sendable {
        var projectId: String
        var overrideMode: AXProjectRuntimeSurfaceHubOverrideMode
        var updatedAtMs: Int64
        var reason: String
        var auditRef: String
    }

    struct RuntimeSurfaceOverridesSnapshot: Equatable, Sendable {
        var source: String
        var updatedAtMs: Int64
        var items: [RuntimeSurfaceOverrideItem]
    }

    @available(*, deprecated, message: "Use RuntimeSurfaceOverrideItem")
    typealias AutonomyPolicyOverrideItem = RuntimeSurfaceOverrideItem

    @available(*, deprecated, message: "Use RuntimeSurfaceOverridesSnapshot")
    typealias AutonomyPolicyOverridesSnapshot = RuntimeSurfaceOverridesSnapshot

    struct SupervisorRemoteContinuityResult: Equatable, Sendable {
        var ok: Bool
        var source: String
        var workingEntries: [String]
        var cacheHit: Bool
        var reasonCode: String?
        var remoteSnapshotCacheScope: String? = nil
        var remoteSnapshotCachedAtMs: Int64? = nil
        var remoteSnapshotAgeMs: Int? = nil
        var remoteSnapshotTTLRemainingMs: Int? = nil
        var remoteSnapshotCachePosture: String? = nil
        var remoteSnapshotInvalidationReason: String? = nil
    }

    struct AgentImportStageResult: Codable, Equatable, Sendable {
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
            case reasonCode = "reason_code"
        }
    }

    struct AgentImportStageRequestPayload: Equatable, Sendable {
        var importManifestJSON: String
        var findingsJSON: String?
        var scanInputJSON: String?
        var requestedBy: String?
        var note: String?
        var requestId: String?
    }

    struct AgentImportRecordLookupPayload: Equatable, Sendable {
        var stagingId: String?
        var selector: String?
        var skillId: String?
        var projectId: String?
    }

    struct AgentImportRecordResult: Codable, Equatable, Sendable {
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
            case reasonCode = "reason_code"
        }
    }

    struct SkillPackageUploadResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var packageSHA256: String?
        var alreadyPresent: Bool
        var skillId: String?
        var version: String?
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case packageSHA256 = "package_sha256"
            case alreadyPresent = "already_present"
            case skillId = "skill_id"
            case version
            case reasonCode = "reason_code"
        }
    }

    struct SkillPackageUploadRequestPayload: Equatable, Sendable {
        var packageFileURL: URL
        var manifestJSON: String
        var sourceId: String
        var requestId: String?
    }

    struct AgentImportPromoteResult: Codable, Equatable, Sendable {
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
            case reasonCode = "reason_code"
        }
    }

    struct AgentImportPromoteRequestPayload: Equatable, Sendable {
        var stagingId: String
        var packageSHA256: String
        var note: String?
        var requestId: String?
    }

    struct SkillCatalogEntry: Codable, Equatable, Sendable, Identifiable {
        var skillID: String
        var name: String
        var version: String
        var description: String
        var publisherID: String
        var capabilitiesRequired: [String]
        var sourceID: String
        var packageSHA256: String
        var installHint: String
        var riskLevel: String = "low"
        var requiresGrant: Bool = false
        var sideEffectClass: String = ""

        init(
            skillID: String,
            name: String,
            version: String,
            description: String,
            publisherID: String,
            capabilitiesRequired: [String],
            sourceID: String,
            packageSHA256: String,
            installHint: String,
            riskLevel: String = "low",
            requiresGrant: Bool = false,
            sideEffectClass: String = ""
        ) {
            self.skillID = skillID
            self.name = name
            self.version = version
            self.description = description
            self.publisherID = publisherID
            self.capabilitiesRequired = capabilitiesRequired
            self.sourceID = sourceID
            self.packageSHA256 = packageSHA256
            self.installHint = installHint
            self.riskLevel = riskLevel
            self.requiresGrant = requiresGrant
            self.sideEffectClass = sideEffectClass
        }

        var id: String { "\(skillID)::\(version)::\(sourceID)::\(packageSHA256)" }

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

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            skillID = try container.decode(String.self, forKey: .skillID)
            name = try container.decode(String.self, forKey: .name)
            version = try container.decode(String.self, forKey: .version)
            description = try container.decode(String.self, forKey: .description)
            publisherID = try container.decode(String.self, forKey: .publisherID)
            capabilitiesRequired = try container.decodeIfPresent([String].self, forKey: .capabilitiesRequired) ?? []
            sourceID = try container.decode(String.self, forKey: .sourceID)
            packageSHA256 = try container.decodeIfPresent(String.self, forKey: .packageSHA256) ?? ""
            installHint = try container.decodeIfPresent(String.self, forKey: .installHint) ?? ""
            riskLevel = try container.decodeIfPresent(String.self, forKey: .riskLevel) ?? "low"
            requiresGrant = try container.decodeIfPresent(Bool.self, forKey: .requiresGrant) ?? false
            sideEffectClass = try container.decodeIfPresent(String.self, forKey: .sideEffectClass) ?? ""
        }
    }

    struct OfficialSkillChannelStatus: Codable, Equatable, Sendable {
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

        init(
            channelID: String,
            status: String,
            updatedAtMs: Int64,
            lastAttemptAtMs: Int64,
            lastSuccessAtMs: Int64,
            skillCount: Int,
            errorCode: String,
            maintenanceEnabled: Bool,
            maintenanceIntervalMs: Int64,
            maintenanceLastRunAtMs: Int64,
            maintenanceSourceKind: String,
            lastTransitionAtMs: Int64,
            lastTransitionKind: String,
            lastTransitionSummary: String
        ) {
            self.channelID = channelID
            self.status = status
            self.updatedAtMs = updatedAtMs
            self.lastAttemptAtMs = lastAttemptAtMs
            self.lastSuccessAtMs = lastSuccessAtMs
            self.skillCount = skillCount
            self.errorCode = errorCode
            self.maintenanceEnabled = maintenanceEnabled
            self.maintenanceIntervalMs = maintenanceIntervalMs
            self.maintenanceLastRunAtMs = maintenanceLastRunAtMs
            self.maintenanceSourceKind = maintenanceSourceKind
            self.lastTransitionAtMs = lastTransitionAtMs
            self.lastTransitionKind = lastTransitionKind
            self.lastTransitionSummary = lastTransitionSummary
        }
    }

    struct SkillsSearchResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var updatedAtMs: Int64
        var results: [SkillCatalogEntry]
        var reasonCode: String?
        var officialChannelStatus: OfficialSkillChannelStatus? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case results
            case reasonCode = "reason_code"
            case officialChannelStatus = "official_channel_status"
        }
    }

    struct SkillPinRequestPayload: Equatable, Sendable {
        var scope: String
        var skillId: String
        var packageSHA256: String
        var projectId: String?
        var note: String?
        var requestId: String?
    }

    struct SkillPinResult: Codable, Equatable, Sendable {
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
            case reasonCode = "reason_code"
        }
    }

    struct ResolvedSkillEntry: Codable, Equatable, Sendable, Identifiable {
        var scope: String
        var skill: SkillCatalogEntry

        var id: String { "\(scope)::\(skill.id)" }
    }

    struct ResolvedSkillsResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var skills: [ResolvedSkillEntry]
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case skills
            case reasonCode = "reason_code"
        }
    }

    struct SkillManifestResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var packageSHA256: String
        var manifestJSON: String
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case packageSHA256 = "package_sha256"
            case manifestJSON = "manifest_json"
            case reasonCode = "reason_code"
        }
    }

    struct SecretVaultItem: Codable, Equatable, Sendable, Identifiable {
        var itemId: String
        var scope: String
        var name: String
        var sensitivity: String
        var createdAtMs: Int64
        var updatedAtMs: Int64

        var id: String { itemId }

        enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case scope
            case name
            case sensitivity
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
        }
    }

    struct SecretVaultSnapshot: Codable, Equatable, Sendable {
        var source: String
        var updatedAtMs: Int64
        var items: [SecretVaultItem]

        enum CodingKeys: String, CodingKey {
            case source
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    struct SecretCreateRequestPayload: Codable, Equatable, Sendable {
        var scope: String
        var name: String
        var plaintext: String
        var sensitivity: String
        var projectId: String?
        var displayName: String?
        var reason: String?

        enum CodingKeys: String, CodingKey {
            case scope
            case name
            case plaintext
            case sensitivity
            case projectId = "project_id"
            case displayName = "display_name"
            case reason
        }
    }

    struct SecretCreateResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var item: SecretVaultItem?
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case item
            case reasonCode = "reason_code"
        }
    }

    struct SecretVaultListRequestPayload: Codable, Equatable, Sendable {
        var scope: String?
        var namePrefix: String?
        var projectId: String?
        var limit: Int

        enum CodingKeys: String, CodingKey {
            case scope
            case namePrefix = "name_prefix"
            case projectId = "project_id"
            case limit
        }
    }

    struct SecretUseRequestPayload: Codable, Equatable, Sendable {
        var itemId: String?
        var scope: String?
        var name: String?
        var projectId: String?
        var purpose: String
        var target: String?
        var ttlMs: Int

        enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case scope
            case name
            case projectId = "project_id"
            case purpose
            case target
            case ttlMs = "ttl_ms"
        }
    }

    struct SecretUseResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var leaseId: String?
        var useToken: String?
        var itemId: String?
        var expiresAtMs: Int64?
        var reasonCode: String?
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case leaseId = "lease_id"
            case useToken = "use_token"
            case itemId = "item_id"
            case expiresAtMs = "expires_at_ms"
            case reasonCode = "reason_code"
            case detail
        }
    }

    struct SecretRedeemRequestPayload: Codable, Equatable, Sendable {
        var useToken: String
        var projectId: String?

        enum CodingKeys: String, CodingKey {
            case useToken = "use_token"
            case projectId = "project_id"
        }
    }

    struct SecretRedeemResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var leaseId: String?
        var itemId: String?
        var plaintext: String?
        var reasonCode: String?
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case leaseId = "lease_id"
            case itemId = "item_id"
            case plaintext
            case reasonCode = "reason_code"
            case detail
        }
    }

    struct ProjectSyncPayload: Codable {
        var projectId: String
        var rootPath: String
        var displayName: String
        var statusDigest: String?
        var lastSummaryAt: Double?
        var lastEventAt: Double?
        var updatedAt: Double?

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case rootPath = "root_path"
            case displayName = "display_name"
            case statusDigest = "status_digest"
            case lastSummaryAt = "last_summary_at"
            case lastEventAt = "last_event_at"
            case updatedAt = "updated_at"
        }
    }

    struct IPCRequest: Codable {
        var type: String
        var reqId: String
        var project: ProjectSyncPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case project
        }
    }

    struct ProjectCanonicalMemoryItemPayload: Codable {
        var key: String
        var value: String
    }

    struct ProjectCanonicalMemoryPayload: Codable {
        var projectId: String
        var projectRoot: String?
        var displayName: String?
        var updatedAt: Double?
        var items: [ProjectCanonicalMemoryItemPayload]

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case projectRoot = "project_root"
            case displayName = "display_name"
            case updatedAt = "updated_at"
            case items
        }
    }

    struct ProjectCanonicalMemoryIPCRequest: Codable {
        var type: String
        var reqId: String
        var projectCanonicalMemory: ProjectCanonicalMemoryPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case projectCanonicalMemory = "project_canonical_memory"
        }
    }

    struct DeviceCanonicalMemoryPayload: Codable {
        var supervisorId: String
        var displayName: String?
        var updatedAt: Double?
        var items: [ProjectCanonicalMemoryItemPayload]

        enum CodingKeys: String, CodingKey {
            case supervisorId = "supervisor_id"
            case displayName = "display_name"
            case updatedAt = "updated_at"
            case items
        }
    }

    struct DeviceCanonicalMemoryIPCRequest: Codable {
        var type: String
        var reqId: String
        var deviceCanonicalMemory: DeviceCanonicalMemoryPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case deviceCanonicalMemory = "device_canonical_memory"
        }
    }

    struct CanonicalMemorySyncStatusItem: Codable, Equatable, Sendable, Identifiable {
        var scopeKind: String
        var scopeId: String
        var displayName: String
        var source: String
        var ok: Bool
        var updatedAtMs: Int64
        var reasonCode: String?
        var detail: String?
        var deliveryState: String?
        var auditRefs: [String]?
        var evidenceRefs: [String]?
        var writebackRefs: [String]?

        var id: String { "\(scopeKind)::\(scopeId)" }
        var primaryAuditRef: String? { auditRefs?.first }
        var primaryEvidenceRef: String? { evidenceRefs?.first }
        var primaryWritebackRef: String? { writebackRefs?.first }

        init(
            scopeKind: String,
            scopeId: String,
            displayName: String,
            source: String,
            ok: Bool,
            updatedAtMs: Int64,
            reasonCode: String? = nil,
            detail: String? = nil,
            deliveryState: String? = nil,
            auditRefs: [String]? = nil,
            evidenceRefs: [String]? = nil,
            writebackRefs: [String]? = nil
        ) {
            self.scopeKind = scopeKind
            self.scopeId = scopeId
            self.displayName = displayName
            self.source = source
            self.ok = ok
            self.updatedAtMs = updatedAtMs
            self.reasonCode = reasonCode
            self.detail = detail
            self.deliveryState = deliveryState
            self.auditRefs = auditRefs
            self.evidenceRefs = evidenceRefs
            self.writebackRefs = writebackRefs
        }

        enum CodingKeys: String, CodingKey {
            case scopeKind = "scope_kind"
            case scopeId = "scope_id"
            case displayName = "display_name"
            case source
            case ok
            case updatedAtMs = "updated_at_ms"
            case reasonCode = "reason_code"
            case detail
            case deliveryState = "delivery_state"
            case auditRefs = "audit_refs"
            case evidenceRefs = "evidence_refs"
            case writebackRefs = "writeback_refs"
        }
    }

    struct CanonicalMemorySyncStatusSnapshot: Codable, Equatable, Sendable {
        var schemaVersion: String
        var updatedAtMs: Int64
        var items: [CanonicalMemorySyncStatusItem]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    struct AckIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
        }
    }

    struct NetworkRequestPayload: Codable {
        var id: String
        var source: String
        var projectId: String?
        var rootPath: String?
        var displayName: String?
        var reason: String?
        var requestedSeconds: Int
        var createdAt: Double

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case projectId = "project_id"
            case rootPath = "root_path"
            case displayName = "display_name"
            case reason
            case requestedSeconds = "requested_seconds"
            case createdAt = "created_at"
        }
    }

    struct NetworkIPCRequest: Codable {
        var type: String
        var reqId: String
        var network: NetworkRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case network
        }
    }

    struct NetworkIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
        }
    }

    struct NotificationPayload: Codable {
        var id: String
        var source: String
        var title: String
        var body: String
        var createdAt: Double
        var dedupeKey: String?
        var actionURL: String?
        var unread: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case title
            case body
            case createdAt = "created_at"
            case dedupeKey = "dedupe_key"
            case actionURL = "action_url"
            case unread
        }
    }

    struct NotificationIPCRequest: Codable {
        var type: String
        var reqId: String
        var notification: NotificationPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case notification
        }
    }

    struct NotificationDismissPayload: Codable {
        var id: String?
        var dedupeKey: String?

        enum CodingKeys: String, CodingKey {
            case id
            case dedupeKey = "dedupe_key"
        }
    }

    struct NotificationDismissIPCRequest: Codable {
        var type: String
        var reqId: String
        var notificationDismiss: NotificationDismissPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case notificationDismiss = "notification_dismiss"
        }
    }

    struct SupervisorIncidentAuditPayload: Codable {
        var incidentId: String
        var laneId: String
        var taskId: String
        var projectId: String?
        var incidentCode: String
        var eventType: String
        var denyCode: String
        var proposedAction: String
        var severity: String
        var category: String
        var detectedAtMs: Int64
        var handledAtMs: Int64?
        var takeoverLatencyMs: Int64?
        var auditRef: String
        var detail: String?
        var status: String
        var source: String?

        enum CodingKeys: String, CodingKey {
            case incidentId = "incident_id"
            case laneId = "lane_id"
            case taskId = "task_id"
            case projectId = "project_id"
            case incidentCode = "incident_code"
            case eventType = "event_type"
            case denyCode = "deny_code"
            case proposedAction = "proposed_action"
            case severity
            case category
            case detectedAtMs = "detected_at_ms"
            case handledAtMs = "handled_at_ms"
            case takeoverLatencyMs = "takeover_latency_ms"
            case auditRef = "audit_ref"
            case detail
            case status
            case source
        }
    }

    struct SupervisorIncidentAuditIPCRequest: Codable {
        var type: String
        var reqId: String
        var supervisorIncident: SupervisorIncidentAuditPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case supervisorIncident = "supervisor_incident"
        }
    }

    struct SupervisorProjectActionAuditPayload: Codable {
        var eventId: String
        var projectId: String
        var projectName: String
        var eventType: String
        var severity: String
        var actionTitle: String
        var actionSummary: String
        var whyItMatters: String
        var nextAction: String
        var occurredAtMs: Int64
        var deliveryChannel: String
        var deliveryStatus: String
        var jurisdictionRole: String?
        var grantedScope: String?
        var auditRef: String
        var source: String?

        enum CodingKeys: String, CodingKey {
            case eventId = "event_id"
            case projectId = "project_id"
            case projectName = "project_name"
            case eventType = "event_type"
            case severity
            case actionTitle = "action_title"
            case actionSummary = "action_summary"
            case whyItMatters = "why_it_matters"
            case nextAction = "next_action"
            case occurredAtMs = "occurred_at_ms"
            case deliveryChannel = "delivery_channel"
            case deliveryStatus = "delivery_status"
            case jurisdictionRole = "jurisdiction_role"
            case grantedScope = "granted_scope"
            case auditRef = "audit_ref"
            case source
        }
    }

    struct SupervisorProjectActionAuditIPCRequest: Codable {
        var type: String
        var reqId: String
        var supervisorProjectAction: SupervisorProjectActionAuditPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case supervisorProjectAction = "supervisor_project_action"
        }
    }

    struct MemoryContextBudgets: Codable, Equatable {
        var totalTokens: Int?
        var l0Tokens: Int?
        var l1Tokens: Int?
        var l2Tokens: Int?
        var l3Tokens: Int?
        var l4Tokens: Int?

        enum CodingKeys: String, CodingKey {
            case totalTokens = "total_tokens"
            case l0Tokens = "l0_tokens"
            case l1Tokens = "l1_tokens"
            case l2Tokens = "l2_tokens"
            case l3Tokens = "l3_tokens"
            case l4Tokens = "l4_tokens"
        }
    }

    struct MemoryContextPayload: Codable {
        var mode: String?
        var projectId: String?
        var projectRoot: String?
        var displayName: String?
        var latestUser: String
        var reviewLevelHint: String?
        var constitutionHint: String?
        var dialogueWindowText: String?
        var portfolioBriefText: String?
        var focusedProjectAnchorPackText: String?
        var longtermOutlineText: String?
        var deltaFeedText: String?
        var conflictSetText: String?
        var contextRefsText: String?
        var evidencePackText: String?
        var canonicalText: String?
        var observationsText: String?
        var workingSetText: String?
        var rawEvidenceText: String?
        var servingProfile: String? = nil
        var budgets: MemoryContextBudgets?

        init(
            mode: String? = nil,
            projectId: String? = nil,
            projectRoot: String? = nil,
            displayName: String? = nil,
            latestUser: String,
            reviewLevelHint: String? = nil,
            constitutionHint: String? = nil,
            dialogueWindowText: String? = nil,
            portfolioBriefText: String? = nil,
            focusedProjectAnchorPackText: String? = nil,
            longtermOutlineText: String? = nil,
            deltaFeedText: String? = nil,
            conflictSetText: String? = nil,
            contextRefsText: String? = nil,
            evidencePackText: String? = nil,
            canonicalText: String? = nil,
            observationsText: String? = nil,
            workingSetText: String? = nil,
            rawEvidenceText: String? = nil,
            servingProfile: String? = nil,
            budgets: MemoryContextBudgets? = nil
        ) {
            self.mode = mode
            self.projectId = projectId
            self.projectRoot = projectRoot
            self.displayName = displayName
            self.latestUser = latestUser
            self.reviewLevelHint = reviewLevelHint
            self.constitutionHint = constitutionHint
            self.dialogueWindowText = dialogueWindowText
            self.portfolioBriefText = portfolioBriefText
            self.focusedProjectAnchorPackText = focusedProjectAnchorPackText
            self.longtermOutlineText = longtermOutlineText
            self.deltaFeedText = deltaFeedText
            self.conflictSetText = conflictSetText
            self.contextRefsText = contextRefsText
            self.evidencePackText = evidencePackText
            self.canonicalText = canonicalText
            self.observationsText = observationsText
            self.workingSetText = workingSetText
            self.rawEvidenceText = rawEvidenceText
            self.servingProfile = servingProfile
            self.budgets = budgets
        }

        enum CodingKeys: String, CodingKey {
            case mode
            case projectId = "project_id"
            case projectRoot = "project_root"
            case displayName = "display_name"
            case latestUser = "latest_user"
            case reviewLevelHint = "review_level_hint"
            case constitutionHint = "constitution_hint"
            case dialogueWindowText = "dialogue_window_text"
            case portfolioBriefText = "portfolio_brief_text"
            case focusedProjectAnchorPackText = "focused_project_anchor_pack_text"
            case longtermOutlineText = "longterm_outline_text"
            case deltaFeedText = "delta_feed_text"
            case conflictSetText = "conflict_set_text"
            case contextRefsText = "context_refs_text"
            case evidencePackText = "evidence_pack_text"
            case canonicalText = "canonical_text"
            case observationsText = "observations_text"
            case workingSetText = "working_set_text"
            case rawEvidenceText = "raw_evidence_text"
            case servingProfile = "serving_profile"
            case budgets
        }
    }

    struct MemoryRetrievalResultItem: Codable, Equatable, Sendable {
        var ref: String
        var sourceKind: String
        var summary: String
        var snippet: String
        var score: Double
        var redacted: Bool

        enum CodingKeys: String, CodingKey {
            case ref
            case sourceKind = "source_kind"
            case summary
            case snippet
            case score
            case redacted
        }
    }

    struct MemoryRetrievalPayload: Codable, Equatable {
        var schemaVersion: String
        var requestId: String
        var scope: String
        var requesterRole: String
        var mode: String
        var projectId: String?
        var crossProjectTargetIds: [String]
        var projectRoot: String?
        var displayName: String?
        var query: String
        var latestUser: String
        var allowedLayers: [String]
        var retrievalKind: String
        var maxResults: Int
        var reason: String?
        var requireExplainability: Bool
        var requestedKinds: [String]
        var explicitRefs: [String]
        var maxSnippets: Int
        var maxSnippetChars: Int
        var auditRef: String

        init(
            schemaVersion: String = "xt.memory_retrieval_request.v1",
            requestId: String,
            scope: String,
            requesterRole: String,
            mode: String,
            projectId: String?,
            crossProjectTargetIds: [String] = [],
            projectRoot: String?,
            displayName: String?,
            query: String,
            latestUser: String,
            allowedLayers: [String],
            retrievalKind: String,
            maxResults: Int,
            reason: String?,
            requireExplainability: Bool = true,
            requestedKinds: [String],
            explicitRefs: [String],
            maxSnippets: Int,
            maxSnippetChars: Int,
            auditRef: String
        ) {
            self.schemaVersion = schemaVersion
            self.requestId = requestId
            self.scope = scope
            self.requesterRole = requesterRole
            self.mode = mode
            self.projectId = projectId
            self.crossProjectTargetIds = crossProjectTargetIds
            self.projectRoot = projectRoot
            self.displayName = displayName
            self.query = query
            self.latestUser = latestUser
            self.allowedLayers = allowedLayers
            self.retrievalKind = retrievalKind
            self.maxResults = maxResults
            self.reason = reason
            self.requireExplainability = requireExplainability
            self.requestedKinds = requestedKinds
            self.explicitRefs = explicitRefs
            self.maxSnippets = maxSnippets
            self.maxSnippetChars = maxSnippetChars
            self.auditRef = auditRef
        }

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case requestId = "request_id"
            case scope
            case requesterRole = "requester_role"
            case mode
            case projectId = "project_id"
            case crossProjectTargetIds = "cross_project_target_ids"
            case projectRoot = "project_root"
            case displayName = "display_name"
            case query
            case latestUser = "latest_user"
            case allowedLayers = "allowed_layers"
            case retrievalKind = "retrieval_kind"
            case maxResults = "max_results"
            case reason
            case requireExplainability = "require_explainability"
            case requestedKinds = "requested_kinds"
            case explicitRefs = "explicit_refs"
            case maxSnippets = "max_snippets"
            case maxSnippetChars = "max_snippet_chars"
            case auditRef = "audit_ref"
        }
    }

    struct MemoryContextIPCRequest: Codable {
        var type: String
        var reqId: String
        var memoryContext: MemoryContextPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case memoryContext = "memory_context"
        }
    }

    struct MemoryRetrievalSnippet: Codable, Equatable, Sendable {
        var snippetId: String
        var sourceKind: String
        var title: String
        var ref: String
        var text: String
        var score: Int
        var truncated: Bool

        enum CodingKeys: String, CodingKey {
            case snippetId = "snippet_id"
            case sourceKind = "source_kind"
            case title
            case ref
            case text
            case score
            case truncated
        }
    }

    struct MemoryRetrievalIPCRequest: Codable {
        var type: String
        var reqId: String
        var memoryRetrieval: MemoryRetrievalPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case memoryRetrieval = "memory_retrieval"
        }
    }

    struct MemoryContextLayerUsage: Codable, Equatable {
        var layer: String
        var usedTokens: Int
        var budgetTokens: Int

        enum CodingKeys: String, CodingKey {
            case layer
            case usedTokens = "used_tokens"
            case budgetTokens = "budget_tokens"
        }
    }

    struct MemoryContextResponsePayload: Codable, Equatable {
        var text: String
        var source: String
        var resolvedMode: String?
        var requestedProfile: String?
        var resolvedProfile: String?
        var attemptedProfiles: [String]?
        var progressiveUpgradeCount: Int?
        var longtermMode: String?
        var retrievalAvailable: Bool?
        var fulltextNotLoaded: Bool?
        var freshness: String?
        var cacheHit: Bool?
        var remoteSnapshotCacheScope: String?
        var remoteSnapshotCachedAtMs: Int64?
        var remoteSnapshotAgeMs: Int?
        var remoteSnapshotTTLRemainingMs: Int?
        var remoteSnapshotCachePosture: String?
        var remoteSnapshotInvalidationReason: String?
        var denyCode: String?
        var downgradeCode: String?
        var budgetTotalTokens: Int
        var usedTotalTokens: Int
        var layerUsage: [MemoryContextLayerUsage]
        var truncatedLayers: [String]
        var redactedItems: Int
        var privateDrops: Int

        init(
            text: String,
            source: String,
            resolvedMode: String? = nil,
            requestedProfile: String? = nil,
            resolvedProfile: String? = nil,
            attemptedProfiles: [String]? = nil,
            progressiveUpgradeCount: Int? = nil,
            longtermMode: String? = nil,
            retrievalAvailable: Bool? = nil,
            fulltextNotLoaded: Bool? = nil,
            freshness: String? = nil,
            cacheHit: Bool? = nil,
            remoteSnapshotCacheScope: String? = nil,
            remoteSnapshotCachedAtMs: Int64? = nil,
            remoteSnapshotAgeMs: Int? = nil,
            remoteSnapshotTTLRemainingMs: Int? = nil,
            remoteSnapshotCachePosture: String? = nil,
            remoteSnapshotInvalidationReason: String? = nil,
            denyCode: String? = nil,
            downgradeCode: String? = nil,
            budgetTotalTokens: Int,
            usedTotalTokens: Int,
            layerUsage: [MemoryContextLayerUsage],
            truncatedLayers: [String],
            redactedItems: Int,
            privateDrops: Int
        ) {
            self.text = text
            self.source = source
            self.resolvedMode = resolvedMode
            self.requestedProfile = requestedProfile
            self.resolvedProfile = resolvedProfile
            self.attemptedProfiles = attemptedProfiles
            self.progressiveUpgradeCount = progressiveUpgradeCount
            self.longtermMode = longtermMode
            self.retrievalAvailable = retrievalAvailable
            self.fulltextNotLoaded = fulltextNotLoaded
            self.freshness = freshness
            self.cacheHit = cacheHit
            self.remoteSnapshotCacheScope = remoteSnapshotCacheScope
            self.remoteSnapshotCachedAtMs = remoteSnapshotCachedAtMs
            self.remoteSnapshotAgeMs = remoteSnapshotAgeMs
            self.remoteSnapshotTTLRemainingMs = remoteSnapshotTTLRemainingMs
            self.remoteSnapshotCachePosture = remoteSnapshotCachePosture
            self.remoteSnapshotInvalidationReason = remoteSnapshotInvalidationReason
            self.denyCode = denyCode
            self.downgradeCode = downgradeCode
            self.budgetTotalTokens = budgetTotalTokens
            self.usedTotalTokens = usedTotalTokens
            self.layerUsage = layerUsage
            self.truncatedLayers = truncatedLayers
            self.redactedItems = redactedItems
            self.privateDrops = privateDrops
        }

        enum CodingKeys: String, CodingKey {
            case text
            case source
            case resolvedMode = "resolved_mode"
            case requestedProfile = "requested_profile"
            case resolvedProfile = "resolved_profile"
            case attemptedProfiles = "attempted_profiles"
            case progressiveUpgradeCount = "progressive_upgrade_count"
            case longtermMode = "longterm_mode"
            case retrievalAvailable = "retrieval_available"
            case fulltextNotLoaded = "fulltext_not_loaded"
            case freshness
            case cacheHit = "cache_hit"
            case remoteSnapshotCacheScope = "remote_snapshot_cache_scope"
            case remoteSnapshotCachedAtMs = "remote_snapshot_cached_at_ms"
            case remoteSnapshotAgeMs = "remote_snapshot_age_ms"
            case remoteSnapshotTTLRemainingMs = "remote_snapshot_ttl_remaining_ms"
            case remoteSnapshotCachePosture = "remote_snapshot_cache_posture"
            case remoteSnapshotInvalidationReason = "remote_snapshot_invalidation_reason"
            case denyCode = "deny_code"
            case downgradeCode = "downgrade_code"
            case budgetTotalTokens = "budget_total_tokens"
            case usedTotalTokens = "used_total_tokens"
            case layerUsage = "layer_usage"
            case truncatedLayers = "truncated_layers"
            case redactedItems = "redacted_items"
            case privateDrops = "private_drops"
        }
    }

    struct MemoryRetrievalResponsePayload: Codable, Equatable, Sendable {
        var schemaVersion: String?
        var requestId: String?
        var status: String?
        var resolvedScope: String?
        var source: String
        var scope: String
        var auditRef: String
        var reasonCode: String?
        var detail: String?
        var denyCode: String?
        var results: [MemoryRetrievalResultItem]?
        var snippets: [MemoryRetrievalSnippet]
        var truncated: Bool?
        var budgetUsedChars: Int?
        var truncatedItems: Int
        var redactedItems: Int

        init(
            schemaVersion: String? = nil,
            requestId: String? = nil,
            status: String? = nil,
            resolvedScope: String? = nil,
            source: String,
            scope: String,
            auditRef: String,
            reasonCode: String? = nil,
            detail: String? = nil,
            denyCode: String? = nil,
            results: [MemoryRetrievalResultItem]? = nil,
            snippets: [MemoryRetrievalSnippet],
            truncated: Bool? = nil,
            budgetUsedChars: Int? = nil,
            truncatedItems: Int,
            redactedItems: Int
        ) {
            self.schemaVersion = schemaVersion
            self.requestId = requestId
            self.status = status
            self.resolvedScope = resolvedScope
            self.source = source
            self.scope = scope
            self.auditRef = auditRef
            self.reasonCode = reasonCode
            self.detail = detail
            self.denyCode = denyCode
            self.results = results
            self.snippets = snippets
            self.truncated = truncated
            self.budgetUsedChars = budgetUsedChars
            self.truncatedItems = truncatedItems
            self.redactedItems = redactedItems
        }

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case requestId = "request_id"
            case status
            case resolvedScope = "resolved_scope"
            case source
            case scope
            case auditRef = "audit_ref"
            case reasonCode = "reason_code"
            case detail
            case denyCode = "deny_code"
            case results
            case snippets
            case truncated
            case budgetUsedChars = "budget_used_chars"
            case truncatedItems = "truncated_items"
            case redactedItems = "redacted_items"
        }
    }

    struct MemoryContextResolutionResult {
        var response: MemoryContextResponsePayload?
        var source: String
        var resolvedMode: XTMemoryUseMode
        var requestedProfile: String?
        var attemptedProfiles: [String]
        var freshness: String
        var cacheHit: Bool
        var remoteSnapshotCacheScope: String? = nil
        var remoteSnapshotCachedAtMs: Int64? = nil
        var remoteSnapshotAgeMs: Int? = nil
        var remoteSnapshotTTLRemainingMs: Int? = nil
        var remoteSnapshotCachePosture: String? = nil
        var remoteSnapshotInvalidationReason: String? = nil
        var denyCode: String?
        var downgradeCode: String?
        var reasonCode: String?
        var detail: String? = nil
    }

    struct MemoryContextIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var memoryContext: MemoryContextResponsePayload?
        var memoryRetrieval: MemoryRetrievalResponsePayload?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case memoryContext = "memory_context"
            case memoryRetrieval = "memory_retrieval"
        }
    }

    struct VoiceWakeProfileRequestPayload: Codable, Equatable {
        var desiredWakeMode: String

        enum CodingKeys: String, CodingKey {
            case desiredWakeMode = "desired_wake_mode"
        }
    }

    struct VoiceWakeProfileGetIPCRequest: Codable {
        var type: String
        var reqId: String
        var voiceWakeProfileRequest: VoiceWakeProfileRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case voiceWakeProfileRequest = "voice_wake_profile_request"
        }
    }

    struct VoiceWakeProfileSetIPCRequest: Codable {
        var type: String
        var reqId: String
        var voiceWakeProfile: VoiceWakeProfile

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case voiceWakeProfile = "voice_wake_profile"
        }
    }

    struct VoiceWakeProfileIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var voiceWakeProfile: VoiceWakeProfile?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case voiceWakeProfile = "voice_wake_profile"
        }
    }

    struct VoiceTTSReadinessRequestPayload: Codable, Equatable, Sendable {
        var preferredModelId: String

        enum CodingKeys: String, CodingKey {
            case preferredModelId = "preferred_model_id"
        }
    }

    struct VoiceTTSReadinessIPCRequest: Codable {
        var type: String
        var reqId: String
        var voiceTTSReadiness: VoiceTTSReadinessRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case voiceTTSReadiness = "voice_tts_readiness"
        }
    }

    struct VoiceTTSReadinessResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var provider: String?
        var modelId: String?
        var reasonCode: String?
        var detail: String?

        init(
            ok: Bool,
            source: String,
            provider: String? = nil,
            modelId: String? = nil,
            reasonCode: String? = nil,
            detail: String? = nil
        ) {
            self.ok = ok
            self.source = source
            self.provider = provider
            self.modelId = modelId
            self.reasonCode = reasonCode
            self.detail = detail
        }

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case provider
            case modelId = "model_id"
            case reasonCode = "reason_code"
            case detail
        }
    }

    struct VoiceTTSReadinessIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var voiceTTSReadiness: VoiceTTSReadinessResult?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case voiceTTSReadiness = "voice_tts_readiness"
        }
    }

    struct VoiceTTSRequestPayload: Codable, Equatable, Sendable {
        var preferredModelId: String
        var text: String
        var localeIdentifier: String?
        var voiceColor: String?
        var speechRate: Double?

        enum CodingKeys: String, CodingKey {
            case preferredModelId = "preferred_model_id"
            case text
            case localeIdentifier = "locale_identifier"
            case voiceColor = "voice_color"
            case speechRate = "speech_rate"
        }
    }

    struct VoiceTTSIPCRequest: Codable {
        var type: String
        var reqId: String
        var voiceTTS: VoiceTTSRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case voiceTTS = "voice_tts"
        }
    }

    struct VoiceTTSAudit: Codable, Equatable, Sendable {
        var schemaVersion: String
        var ok: Bool
        var taskKind: String
        var requestId: String
        var capability: String
        var provider: String
        var requestedModelId: String
        var modelId: String
        var resolvedModelId: String
        var routeSource: String
        var sourceKind: String
        var outputRefKind: String
        var engineName: String
        var speakerId: String
        var nativeTTSUsed: Bool?
        var fallbackUsed: Bool
        var fallbackMode: String
        var fallbackReasonCode: String
        var denyCode: String
        var rawDenyCode: String
        var locale: String
        var voiceColor: String
        var speechRate: Double

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ok
            case taskKind = "task_kind"
            case requestId = "request_id"
            case capability
            case provider
            case requestedModelId = "requested_model_id"
            case modelId = "model_id"
            case resolvedModelId = "resolved_model_id"
            case routeSource = "route_source"
            case sourceKind = "source_kind"
            case outputRefKind = "output_ref_kind"
            case engineName = "engine_name"
            case speakerId = "speaker_id"
            case nativeTTSUsed = "native_tts_used"
            case fallbackUsed = "fallback_used"
            case fallbackMode = "fallback_mode"
            case fallbackReasonCode = "fallback_reason_code"
            case denyCode = "deny_code"
            case rawDenyCode = "raw_deny_code"
            case locale
            case voiceColor = "voice_color"
            case speechRate = "speech_rate"
        }
    }

    struct VoiceTTSResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var provider: String?
        var modelId: String?
        var taskKind: String?
        var audioFilePath: String?
        var audioFormat: String?
        var voiceName: String?
        var engineName: String?
        var speakerId: String?
        var deviceBackend: String?
        var nativeTTSUsed: Bool?
        var fallbackMode: String?
        var fallbackReasonCode: String?
        var reasonCode: String?
        var runtimeReasonCode: String?
        var error: String?
        var detail: String?
        var ttsAudit: VoiceTTSAudit?
        var ttsAuditLine: String?

        init(
            ok: Bool,
            source: String,
            provider: String? = nil,
            modelId: String? = nil,
            taskKind: String? = nil,
            audioFilePath: String? = nil,
            audioFormat: String? = nil,
            voiceName: String? = nil,
            engineName: String? = nil,
            speakerId: String? = nil,
            deviceBackend: String? = nil,
            nativeTTSUsed: Bool? = nil,
            fallbackMode: String? = nil,
            fallbackReasonCode: String? = nil,
            reasonCode: String? = nil,
            runtimeReasonCode: String? = nil,
            error: String? = nil,
            detail: String? = nil,
            ttsAudit: VoiceTTSAudit? = nil,
            ttsAuditLine: String? = nil
        ) {
            self.ok = ok
            self.source = source
            self.provider = provider
            self.modelId = modelId
            self.taskKind = taskKind
            self.audioFilePath = audioFilePath
            self.audioFormat = audioFormat
            self.voiceName = voiceName
            self.engineName = engineName
            self.speakerId = speakerId
            self.deviceBackend = deviceBackend
            self.nativeTTSUsed = nativeTTSUsed
            self.fallbackMode = fallbackMode
            self.fallbackReasonCode = fallbackReasonCode
            self.reasonCode = reasonCode
            self.runtimeReasonCode = runtimeReasonCode
            self.error = error
            self.detail = detail
            self.ttsAudit = ttsAudit
            self.ttsAuditLine = ttsAuditLine
        }

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case provider
            case modelId = "model_id"
            case taskKind = "task_kind"
            case audioFilePath = "audio_file_path"
            case audioFormat = "audio_format"
            case voiceName = "voice_name"
            case engineName = "engine_name"
            case speakerId = "speaker_id"
            case deviceBackend = "device_backend"
            case nativeTTSUsed = "native_tts_used"
            case fallbackMode = "fallback_mode"
            case fallbackReasonCode = "fallback_reason_code"
            case reasonCode = "reason_code"
            case runtimeReasonCode = "runtime_reason_code"
            case error
            case detail
            case ttsAudit = "tts_audit"
            case ttsAuditLine = "tts_audit_line"
        }
    }

    struct VoiceTTSIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var voiceTTS: VoiceTTSResult?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case voiceTTS = "voice_tts"
        }
    }

    struct LocalTaskRequestPayload: Codable, Equatable, Sendable {
        var schemaVersion: String
        var taskKind: String
        var modelId: String
        var deviceId: String?
        var timeoutSec: Double?
        var parameters: [String: JSONValue]

        init(
            schemaVersion: String = "xhub.local_task_ipc.v1",
            taskKind: String,
            modelId: String,
            deviceId: String? = nil,
            timeoutSec: Double? = nil,
            parameters: [String: JSONValue] = [:]
        ) {
            self.schemaVersion = schemaVersion
            self.taskKind = taskKind
            self.modelId = modelId
            self.deviceId = deviceId
            self.timeoutSec = timeoutSec
            self.parameters = parameters
        }

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case taskKind = "task_kind"
            case modelId = "model_id"
            case deviceId = "device_id"
            case timeoutSec = "timeout_sec"
            case parameters
        }
    }

    struct LocalTaskIPCRequest: Codable {
        var type: String
        var reqId: String
        var localTask: LocalTaskRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case localTask = "local_task"
        }
    }

    struct LocalTaskResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var runtimeSource: String?
        var provider: String?
        var modelId: String?
        var taskKind: String?
        var reasonCode: String?
        var runtimeReasonCode: String?
        var error: String?
        var detail: String?
        var payload: [String: JSONValue]

        init(
            ok: Bool,
            source: String,
            runtimeSource: String? = nil,
            provider: String? = nil,
            modelId: String? = nil,
            taskKind: String? = nil,
            reasonCode: String? = nil,
            runtimeReasonCode: String? = nil,
            error: String? = nil,
            detail: String? = nil,
            payload: [String: JSONValue] = [:]
        ) {
            self.ok = ok
            self.source = source
            self.runtimeSource = runtimeSource
            self.provider = provider
            self.modelId = modelId
            self.taskKind = taskKind
            self.reasonCode = reasonCode
            self.runtimeReasonCode = runtimeReasonCode
            self.error = error
            self.detail = detail
            self.payload = payload
        }

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case runtimeSource = "runtime_source"
            case provider
            case modelId = "model_id"
            case taskKind = "task_kind"
            case reasonCode = "reason_code"
            case runtimeReasonCode = "runtime_reason_code"
            case error
            case detail
            case payload
        }
    }

    struct LocalTaskIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var localTask: LocalTaskResult?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case localTask = "local_task"
        }
    }

    struct SecretVaultCreateIPCRequest: Codable {
        var type: String
        var reqId: String
        var secretVaultCreate: SecretCreateRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case secretVaultCreate = "secret_vault_create"
        }
    }

    struct SecretVaultListIPCRequest: Codable {
        var type: String
        var reqId: String
        var secretVaultList: SecretVaultListRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case secretVaultList = "secret_vault_list"
        }
    }

    struct SecretVaultBeginUseIPCRequest: Codable {
        var type: String
        var reqId: String
        var secretVaultUse: SecretUseRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case secretVaultUse = "secret_vault_use"
        }
    }

    struct SecretVaultRedeemIPCRequest: Codable {
        var type: String
        var reqId: String
        var secretVaultRedeem: SecretRedeemRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case secretVaultRedeem = "secret_vault_redeem"
        }
    }

    struct SecretVaultCreateIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var secretVaultItem: SecretVaultItem?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case secretVaultItem = "secret_vault_item"
        }
    }

    struct SecretVaultListIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var secretVaultSnapshot: SecretVaultSnapshot?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case secretVaultSnapshot = "secret_vault_snapshot"
        }
    }

    struct SecretVaultUseIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var secretVaultUse: SecretUseResult?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case secretVaultUse = "secret_vault_use"
        }
    }

    struct SecretVaultRedeemIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var secretVaultRedeem: SecretRedeemResult?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case secretVaultRedeem = "secret_vault_redeem"
        }
    }

    struct SchedulerScopeCount: Codable, Equatable {
        var scopeKey: String
        var count: Int
    }

    struct SchedulerQueueItem: Codable, Equatable {
        var requestId: String
        var scopeKey: String
        var enqueuedAtMs: Double
        var queuedMs: Int
    }

    struct SchedulerStatusSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var inFlightTotal: Int
        var queueDepth: Int
        var oldestQueuedMs: Int
        var inFlightByScope: [SchedulerScopeCount]
        var queuedByScope: [SchedulerScopeCount]
        var queueItems: [SchedulerQueueItem]
    }

    struct PendingGrantItem: Codable, Equatable, Identifiable {
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

        var id: String { grantRequestId }
    }

    struct PendingGrantSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [PendingGrantItem]
    }

    struct SupervisorCandidateReviewItem: Codable, Equatable, Identifiable {
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

        var id: String { reviewId.isEmpty ? requestId : reviewId }

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

    struct SupervisorCandidateReviewSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [SupervisorCandidateReviewItem]
    }

    struct ConnectorIngressReceipt: Codable, Equatable, Identifiable {
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

        var id: String { receiptId }
    }

    struct ConnectorIngressSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [ConnectorIngressReceipt]
    }

    struct SupervisorBriefProjectionRequestPayload: Codable, Equatable {
        var requestId: String
        var projectId: String
        var runId: String?
        var missionId: String?
        var projectionKind: String
        var trigger: String
        var includeTtsScript: Bool
        var includeCardSummary: Bool
        var maxEvidenceRefs: Int

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case projectId = "project_id"
            case runId = "run_id"
            case missionId = "mission_id"
            case projectionKind = "projection_kind"
            case trigger
            case includeTtsScript = "include_tts_script"
            case includeCardSummary = "include_card_summary"
            case maxEvidenceRefs = "max_evidence_refs"
        }
    }

    struct SupervisorBriefProjectionSnapshot: Codable, Equatable, Identifiable {
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

        var id: String { projectionId }

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

    struct SupervisorBriefProjectionResult: Codable, Equatable {
        var ok: Bool
        var source: String
        var projection: SupervisorBriefProjectionSnapshot?
        var reasonCode: String?
    }

    struct SupervisorRouteDecisionRequestPayload: Codable, Equatable {
        var requestId: String
        var projectId: String
        var runId: String?
        var missionId: String?
        var surfaceType: String
        var trustLevel: String
        var normalizedIntentType: String
        var preferredDeviceId: String?
        var requireXT: Bool
        var requireRunner: Bool
        var actorRef: String?
        var conversationId: String?
        var threadKey: String?

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case projectId = "project_id"
            case runId = "run_id"
            case missionId = "mission_id"
            case surfaceType = "surface_type"
            case trustLevel = "trust_level"
            case normalizedIntentType = "normalized_intent_type"
            case preferredDeviceId = "preferred_device_id"
            case requireXT = "require_xt"
            case requireRunner = "require_runner"
            case actorRef = "actor_ref"
            case conversationId = "conversation_id"
            case threadKey = "thread_key"
        }
    }

    struct SupervisorRouteGovernanceComponentSnapshot: Codable, Equatable {
        var key: AXProjectGovernanceRuntimeReadinessComponentKey
        var state: AXProjectGovernanceRuntimeReadinessComponentState
        var denyCode: String
        var summaryLine: String
        var missingReasonCodes: [String]
    }

    struct SupervisorRouteGovernanceRuntimeReadinessSnapshot: Codable, Equatable {
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
        var components: [SupervisorRouteGovernanceComponentSnapshot]
    }

    struct SupervisorRouteDecisionSnapshot: Codable, Equatable {
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

    struct SupervisorRouteDecisionResult: Codable, Equatable {
        var ok: Bool
        var source: String
        var route: SupervisorRouteDecisionSnapshot?
        var governanceRuntimeReadiness: SupervisorRouteGovernanceRuntimeReadinessSnapshot?
        var reasonCode: String?
    }

    struct OperatorChannelXTCommandItem: Codable, Equatable, Identifiable {
        var commandId: String
        var requestId: String
        var actionName: String
        var bindingId: String
        var routeId: String
        var scopeType: String
        var scopeId: String
        var projectId: String
        var provider: String
        var accountId: String
        var conversationId: String
        var threadKey: String
        var actorRef: String
        var resolvedDeviceId: String
        var preferredDeviceId: String
        var note: String
        var createdAtMs: Double
        var auditRef: String

        var id: String { commandId }

        enum CodingKeys: String, CodingKey {
            case commandId = "command_id"
            case requestId = "request_id"
            case actionName = "action_name"
            case bindingId = "binding_id"
            case routeId = "route_id"
            case scopeType = "scope_type"
            case scopeId = "scope_id"
            case projectId = "project_id"
            case provider
            case accountId = "account_id"
            case conversationId = "conversation_id"
            case threadKey = "thread_key"
            case actorRef = "actor_ref"
            case resolvedDeviceId = "resolved_device_id"
            case preferredDeviceId = "preferred_device_id"
            case note
            case createdAtMs = "created_at_ms"
            case auditRef = "audit_ref"
        }
    }

    struct OperatorChannelXTCommandSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [OperatorChannelXTCommandItem]
    }

    struct OperatorChannelXTCommandResultItem: Codable, Equatable, Identifiable {
        var commandId: String
        var requestId: String
        var actionName: String
        var projectId: String
        var resolvedDeviceId: String
        var status: String
        var denyCode: String
        var detail: String
        var runId: String
        var createdAtMs: Double
        var completedAtMs: Double
        var auditRef: String

        var id: String { commandId }

        enum CodingKeys: String, CodingKey {
            case commandId = "command_id"
            case requestId = "request_id"
            case actionName = "action_name"
            case projectId = "project_id"
            case resolvedDeviceId = "resolved_device_id"
            case status
            case denyCode = "deny_code"
            case detail
            case runId = "run_id"
            case createdAtMs = "created_at_ms"
            case completedAtMs = "completed_at_ms"
            case auditRef = "audit_ref"
        }
    }

    struct OperatorChannelXTCommandResultSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [OperatorChannelXTCommandResultItem]
    }

    enum PendingGrantActionDecision: String {
        case approved
        case denied
        case failed
    }

    struct PendingGrantActionResult {
        var ok: Bool
        var decision: PendingGrantActionDecision
        var source: String
        var grantRequestId: String?
        var grantId: String?
        var expiresAtMs: Double?
        var reasonCode: String?
    }

    struct SupervisorCandidateReviewStageResult {
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
    }

    struct VoiceGrantChallengeRequestPayload: Codable, Equatable {
        var requestId: String
        var projectId: String?
        var templateId: String
        var actionDigest: String
        var scopeDigest: String
        var amountDigest: String?
        var challengeCode: String?
        var riskLevel: String
        var boundDeviceId: String?
        var mobileTerminalId: String?
        var allowVoiceOnly: Bool
        var requiresMobileConfirm: Bool
        var ttlMs: Int

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case projectId = "project_id"
            case templateId = "template_id"
            case actionDigest = "action_digest"
            case scopeDigest = "scope_digest"
            case amountDigest = "amount_digest"
            case challengeCode = "challenge_code"
            case riskLevel = "risk_level"
            case boundDeviceId = "bound_device_id"
            case mobileTerminalId = "mobile_terminal_id"
            case allowVoiceOnly = "allow_voice_only"
            case requiresMobileConfirm = "requires_mobile_confirm"
            case ttlMs = "ttl_ms"
        }
    }

    struct VoiceGrantChallengeSnapshot: Codable, Equatable, Identifiable {
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

        var id: String { challengeId }

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

    struct VoiceGrantChallengeResult: Codable, Equatable {
        var ok: Bool
        var source: String
        var challenge: VoiceGrantChallengeSnapshot?
        var reasonCode: String?
    }

    struct VoiceGrantVerificationPayload: Codable, Equatable {
        var requestId: String
        var projectId: String?
        var challengeId: String
        var challengeCode: String?
        var transcript: String?
        var transcriptHash: String?
        var semanticMatchScore: Double?
        var parsedActionDigest: String?
        var parsedScopeDigest: String?
        var parsedAmountDigest: String?
        var verifyNonce: String
        var boundDeviceId: String?
        var mobileConfirmed: Bool

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case projectId = "project_id"
            case challengeId = "challenge_id"
            case challengeCode = "challenge_code"
            case transcript
            case transcriptHash = "transcript_hash"
            case semanticMatchScore = "semantic_match_score"
            case parsedActionDigest = "parsed_action_digest"
            case parsedScopeDigest = "parsed_scope_digest"
            case parsedAmountDigest = "parsed_amount_digest"
            case verifyNonce = "verify_nonce"
            case boundDeviceId = "bound_device_id"
            case mobileConfirmed = "mobile_confirmed"
        }
    }

    enum VoiceGrantVerificationDecision: String, Codable {
        case allow
        case deny
        case failed
    }

    struct VoiceGrantVerificationResult: Codable, Equatable {
        var ok: Bool
        var verified: Bool
        var decision: VoiceGrantVerificationDecision
        var source: String
        var denyCode: String?
        var challengeId: String?
        var transcriptHash: String?
        var semanticMatchScore: Double
        var challengeMatch: Bool
        var deviceBindingOK: Bool
        var mobileConfirmed: Bool
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case verified
            case decision
            case source
            case denyCode = "deny_code"
            case challengeId = "challenge_id"
            case transcriptHash = "transcript_hash"
            case semanticMatchScore = "semantic_match_score"
            case challengeMatch = "challenge_match"
            case deviceBindingOK = "device_binding_ok"
            case mobileConfirmed = "mobile_confirmed"
            case reasonCode = "reason_code"
        }
    }

    struct NetworkRequestTicket: Equatable {
        var reqId: String
        var baseDir: URL
    }

    private struct LocalIPCTransport {
        var mode: String
        var ipcURL: URL
        var baseDir: URL
    }

    private struct IPCEventWriteStatus {
        var requestQueued: Bool?
        var requestError: String
    }

    private struct CanonicalMemorySyncDispatchResult {
        var ok: Bool
        var source: String
        var deliveryState: String? = nil
        var auditRefs: [String] = []
        var evidenceRefs: [String] = []
        var writebackRefs: [String] = []
        var reasonCode: String? = nil
        var detail: String? = nil
    }

    private struct LocalMemoryContextIPCResult {
        var response: MemoryContextResponsePayload?
        var reasonCode: String?
        var detail: String?
    }

    private struct NetworkIPCDispatchResult {
        var ticket: NetworkRequestTicket
        var ack: NetworkIPCResponse?
        var source: String
        var reasonCode: String? = nil
        var detail: String? = nil
    }

    enum NetworkAccessState: String {
        case enabled
        case autoApproved
        case queued
        case denied
        case failed
    }

    struct NetworkAccessResult {
        var state: NetworkAccessState
        var source: String
        var reasonCode: String?
        var remainingSeconds: Int?
        var grantRequestId: String?
        var detail: String? = nil
    }

    private static func currentRouteDecision() async -> HubRouteDecision {
        if let override = routeDecisionOverride() {
            return await override()
        }
        let mode = HubAIClient.transportMode()
        let hasRemote = HubPairingCoordinator.hasHubEnvFast(stateDir: nil)
        return HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: hasRemote)
    }

    private static func localIPCTransport(ttl: Double = 3.0) -> LocalIPCTransport? {
        guard let st = HubConnector.readHubStatusIfAny(ttl: ttl) else { return nil }
        let mode = (st.ipcMode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ipcPath = (st.ipcPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mode.isEmpty, !ipcPath.isEmpty else { return nil }

        let ipcURL: URL
        switch mode {
        case "file":
            ipcURL = URL(fileURLWithPath: ipcPath, isDirectory: true)
        case "socket":
            ipcURL = URL(fileURLWithPath: ipcPath, isDirectory: false)
        default:
            return nil
        }

        return LocalIPCTransport(
            mode: mode,
            ipcURL: ipcURL,
            baseDir: URL(fileURLWithPath: st.baseDir, isDirectory: true)
        )
    }

    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        var totalWritten = 0
        return data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return false }
            while totalWritten < data.count {
                let written = Darwin.write(fd, base.advanced(by: totalWritten), data.count - totalWritten)
                if written <= 0 { return false }
                totalWritten += written
            }
            return true
        }
    }

    private static func summarized(_ error: Error) -> String {
        "\(type(of: error)):\(error.localizedDescription)"
    }

    private static func sendSocketRequest<Request: Encodable, Response: Decodable>(
        _ request: Request,
        socketURL: URL,
        timeoutSec: Double = 2.0
    ) -> Response? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(socketURL.path.utf8) + [0]
        guard bytes.count <= maxLen else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: maxLen) { buf in
                for index in 0..<bytes.count {
                    buf[index] = bytes[index]
                }
            }
        }

        var socketAddr = addr
        let connectRC = withUnsafePointer(to: &socketAddr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectRC == 0 else { return nil }

        let clampedTimeout = max(0.2, min(4.0, timeoutSec))
        var timeout = timeval(
            tv_sec: Int(clampedTimeout.rounded(.down)),
            tv_usec: __darwin_suseconds_t((clampedTimeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        )
        withUnsafePointer(to: &timeout) { ptr in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }

        guard let encoded = try? JSONEncoder().encode(request) else { return nil }
        var payload = encoded
        payload.append(0x0A)
        guard writeAll(payload, to: fd) else { return nil }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > 262_144 { return nil }
            if buffer.contains(0x0A) { break }
        }

        guard let lineEnd = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = buffer.prefix(upTo: lineEnd)
        return try? JSONDecoder().decode(Response.self, from: line)
    }

    static func isLocalHubVoicePackPlaybackAvailable(preferredModelID: String) -> Bool {
        let normalizedPreferredModelID = preferredModelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPreferredModelID.isEmpty else { return false }
        guard let model = localModelStateSnapshot()?.models.first(where: {
            $0.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedPreferredModelID
        }) else {
            return false
        }
        guard model.isEligibleHubVoicePackModel else { return false }
        guard let transport = localIPCTransport(ttl: 3.0) else { return false }
        guard transport.mode == "file" || transport.mode == "socket" else { return false }

        let cacheKey = "\(transport.baseDir.path.lowercased())::\(normalizedPreferredModelID)"
        if let cached = Self.cachedVoiceTTSReadiness(for: cacheKey) {
            return cached.ok
        }

        let result = requestVoiceTTSReadinessViaLocalIPC(
            preferredModelID: model.id,
            timeoutSec: 0.8
        )
        Self.storeVoiceTTSReadiness(result, for: cacheKey)
        return result.ok
    }

    static func synthesizeVoiceViaLocalHub(
        preferredModelID: String,
        text: String,
        localeIdentifier: String?,
        voiceColor: String?,
        speechRate: Double?,
        timeoutSec: Double = 3.0
    ) -> VoiceTTSResult {
        let payload = VoiceTTSRequestPayload(
            preferredModelId: preferredModelID,
            text: text,
            localeIdentifier: normalized(localeIdentifier),
            voiceColor: normalized(voiceColor),
            speechRate: speechRate
        )
        return requestVoiceTTSSynthesisViaLocalIPC(payload, timeoutSec: timeoutSec)
    }

    static func executeLocalTaskViaLocalHub(
        taskKind: String,
        modelID: String,
        parameters: [String: JSONValue],
        deviceID: String? = nil,
        timeoutSec: Double = 5.0
    ) -> LocalTaskResult {
        let payload = LocalTaskRequestPayload(
            taskKind: taskKind,
            modelId: modelID,
            deviceId: normalized(deviceID),
            timeoutSec: timeoutSec,
            parameters: parameters
        )
        return requestLocalTaskExecutionViaLocalIPC(payload, timeoutSec: timeoutSec)
    }

    static func fetchVoiceWakeProfile(
        desiredWakeMode: VoiceWakeMode
    ) async -> VoiceWakeProfileSyncResult {
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteVoiceWakeProfile(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                desiredWakeMode: desiredWakeMode
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return remote
            }
        }

        if routeDecision.requiresRemote {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                ),
                logLines: ["voice wake profile fetch requires remote route"],
                syncedAtMs: nil
            )
        }

        return await fetchVoiceWakeProfileViaLocalIPC(desiredWakeMode: desiredWakeMode)
    }

    static func setVoiceWakeProfile(
        _ profile: VoiceWakeProfile
    ) async -> VoiceWakeProfileSyncResult {
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.setRemoteVoiceWakeProfile(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                profile: profile
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return remote
            }
        }

        if routeDecision.requiresRemote {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                ),
                logLines: ["voice wake profile set requires remote route"],
                syncedAtMs: nil
            )
        }

        return await setVoiceWakeProfileViaLocalIPC(profile)
    }

    static func syncProject(_ entry: AXProjectEntry) {
        let payload = ProjectSyncPayload(
            projectId: entry.projectId,
            rootPath: entry.rootPath,
            displayName: entry.displayName,
            statusDigest: entry.statusDigest,
            lastSummaryAt: entry.lastSummaryAt,
            lastEventAt: entry.lastEventAt,
            updatedAt: Date().timeIntervalSince1970
        )

        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await syncProjectViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await syncProjectViaPreferredRoute(payload: payload, allowFileFallback: true)
            }
        case .fileIPC:
            _ = writeProjectSyncViaFileIPC(payload)
        }
    }

    static func appendProjectConversationTurn(
        ctx: AXProjectContext,
        userText: String,
        assistantText: String,
        createdAt: Double,
        config: AXProjectConfig?
    ) async -> Bool {
        guard XTProjectMemoryGovernance.prefersHubMemory(config) else { return false }

        let mirroredMessages = XTProjectConversationMirror.messages(
            userText: userText,
            assistantText: assistantText
        )
        guard !mirroredMessages.isEmpty else { return false }

        let routeDecision = await currentRouteDecision()
        guard routeDecision.preferRemote else { return false }

        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let payload = HubRemoteProjectConversationPayload(
            projectId: projectId,
            threadKey: XTProjectConversationMirror.projectThreadKey(projectId: projectId),
            requestId: XTProjectConversationMirror.requestID(projectId: projectId, createdAt: createdAt),
            createdAtMs: XTProjectConversationMirror.createdAtMs(createdAt),
            userText: mirroredMessages.first(where: { $0.role == "user" })?.content ?? "",
            assistantText: mirroredMessages.first(where: { $0.role == "assistant" })?.content ?? ""
        )

        let remote = await HubPairingCoordinator.shared.appendRemoteProjectConversationTurn(
            options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
            payload: payload
        )
        if remote.ok {
            await invalidateProjectRemoteMemorySnapshotCache(
                projectId: projectId,
                reason: .newTurnAppend
            )
        }
        return remote.ok
    }

    static func appendSupervisorConversationTurn(
        userText: String,
        assistantText: String,
        createdAt: Double
    ) async -> Bool {
        if let override = supervisorConversationAppendOverride() {
            guard let normalizedTurn = XTSupervisorConversationMirror.normalizedTurn(
                userText: userText,
                assistantText: assistantText
            ) else {
                return false
            }
            let payload = HubRemoteSupervisorConversationPayload(
                threadKey: XTSupervisorConversationMirror.threadKey,
                requestId: XTSupervisorConversationMirror.requestID(createdAt: createdAt),
                createdAtMs: XTSupervisorConversationMirror.createdAtMs(createdAt),
                userText: normalizedTurn.userText,
                assistantText: normalizedTurn.assistantText
            )
            return await override(payload)
        }

        guard let normalizedTurn = XTSupervisorConversationMirror.normalizedTurn(
            userText: userText,
            assistantText: assistantText
        ) else {
            return false
        }

        let routeDecision = await currentRouteDecision()
        guard routeDecision.preferRemote else { return false }

        let payload = HubRemoteSupervisorConversationPayload(
            threadKey: XTSupervisorConversationMirror.threadKey,
            requestId: XTSupervisorConversationMirror.requestID(createdAt: createdAt),
            createdAtMs: XTSupervisorConversationMirror.createdAtMs(createdAt),
            userText: normalizedTurn.userText,
            assistantText: normalizedTurn.assistantText
        )

        let remote = await HubPairingCoordinator.shared.appendRemoteSupervisorConversationTurn(
            options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
            payload: payload
        )
        if remote.ok {
            await invalidateSupervisorMemoryCache(reason: .newTurnAppend)
        }
        return remote.ok
    }

    static func requestSupervisorRemoteContinuity(
        bypassCache: Bool = false,
        timeoutSec: Double = 0.9
    ) async -> SupervisorRemoteContinuityResult {
        if let override = supervisorRemoteContinuityOverride() {
            return await override(bypassCache)
        }

        let routeDecision = await currentRouteDecision()
        guard routeDecision.preferRemote else {
            return SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: routeDecision.remoteUnavailableReasonCode ?? "remote_route_not_preferred"
            )
        }

        let remote = await fetchRemoteMemorySnapshot(
            mode: .supervisorOrchestration,
            projectId: nil,
            bypassCache: bypassCache,
            timeoutSec: timeoutSec
        )
        return SupervisorRemoteContinuityResult(
            ok: remote.snapshot.ok,
            source: remote.snapshot.ok ? "hub_thread" : remote.snapshot.source,
            workingEntries: remote.snapshot.ok ? remote.snapshot.workingEntries : [],
            cacheHit: remote.cacheHit,
            reasonCode: remote.snapshot.reasonCode,
            remoteSnapshotCacheScope: remote.cacheMetadata?.scope,
            remoteSnapshotCachedAtMs: remote.cacheMetadata?.storedAtMs,
            remoteSnapshotAgeMs: remote.cacheMetadata?.ageMs,
            remoteSnapshotTTLRemainingMs: remote.cacheMetadata?.ttlRemainingMs,
            remoteSnapshotCachePosture: remote.cacheMetadata?.cachePosture.rawValue,
            remoteSnapshotInvalidationReason: remote.cacheMetadata?.invalidationReason?.rawValue
        )
    }

    static func syncProjectCanonicalMemory(
        ctx: AXProjectContext,
        memory: AXMemory,
        config: AXProjectConfig?
    ) {
        guard XTProjectMemoryGovernance.prefersHubMemory(config) else { return }

        let projectDisplayName = AXProjectRegistryStore.displayName(
            forRoot: ctx.root,
            preferredDisplayName: memory.projectName
        )
        let payload = ProjectCanonicalMemoryPayload(
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectRoot: ctx.root.path,
            displayName: projectDisplayName,
            updatedAt: memory.updatedAt,
            items: XTProjectCanonicalMemorySync.items(
                memory: memory,
                preferredProjectName: projectDisplayName
            ).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.items.isEmpty else { return }

        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let result = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: result
                )
            }
        case .auto:
            Task {
                let result = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: true
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: result
                )
            }
        case .fileIPC:
            let result = writeProjectCanonicalMemoryViaLocalIPC(payload)
            recordCanonicalMemorySyncStatus(
                scopeKind: "project",
                scopeId: payload.projectId,
                displayName: payload.displayName,
                result: result
            )
            if result.ok {
                Task {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        }
    }

    static func syncSupervisorProjectCapsule(_ capsule: SupervisorProjectCapsule) {
        let payload = ProjectCanonicalMemoryPayload(
            projectId: capsule.projectId,
            projectRoot: nil,
            displayName: capsule.projectName,
            updatedAt: Double(capsule.updatedAtMs) / 1000.0,
            items: SupervisorProjectCapsuleCanonicalSync.items(capsule: capsule).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !payload.items.isEmpty else { return }

        let localResult = writeProjectCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        case .auto:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        case .fileIPC:
            recordCanonicalMemorySyncStatus(
                scopeKind: "project",
                scopeId: payload.projectId,
                displayName: payload.displayName,
                result: localResult
            )
            if localResult.ok {
                Task {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        }
    }

    static func syncSupervisorProjectWorkflow(_ snapshot: SupervisorProjectWorkflowSnapshot) {
        let payload = ProjectCanonicalMemoryPayload(
            projectId: snapshot.projectId,
            projectRoot: nil,
            displayName: snapshot.projectName,
            updatedAt: Double(snapshot.updatedAtMs) / 1000.0,
            items: SupervisorProjectWorkflowCanonicalSync.items(snapshot: snapshot).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !payload.items.isEmpty else { return }

        let localResult = writeProjectCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        case .auto:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        case .fileIPC:
            recordCanonicalMemorySyncStatus(
                scopeKind: "project",
                scopeId: payload.projectId,
                displayName: payload.displayName,
                result: localResult
            )
            if localResult.ok {
                Task {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        }
    }

    static func syncSupervisorProjectHeartbeat(_ record: SupervisorProjectHeartbeatCanonicalRecord) {
        let payload = ProjectCanonicalMemoryPayload(
            projectId: record.projectId,
            projectRoot: nil,
            displayName: record.projectName,
            updatedAt: Double(record.updatedAtMs) / 1000.0,
            items: SupervisorProjectHeartbeatCanonicalSync.items(record: record).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !payload.items.isEmpty else { return }

        let localResult = writeProjectCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        case .auto:
            Task {
                let remoteResult = await syncProjectCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "project",
                    scopeId: payload.projectId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        case .fileIPC:
            recordCanonicalMemorySyncStatus(
                scopeKind: "project",
                scopeId: payload.projectId,
                displayName: payload.displayName,
                result: localResult
            )
            if localResult.ok {
                Task {
                    await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                }
            }
        }
    }

    static func syncSupervisorPortfolioSnapshot(
        _ snapshot: SupervisorPortfolioSnapshot,
        supervisorId: String = defaultSupervisorCanonicalID(),
        displayName: String? = nil
    ) {
        let normalizedSupervisorId = supervisorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSupervisorId.isEmpty else { return }

        let payload = DeviceCanonicalMemoryPayload(
            supervisorId: normalizedSupervisorId,
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: snapshot.updatedAt,
            items: SupervisorPortfolioSnapshotCanonicalSync.items(
                snapshot: snapshot,
                supervisorId: normalizedSupervisorId
            ).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.items.isEmpty else { return }

        let localResult = writeDeviceCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let remoteResult = await syncDeviceCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "device",
                    scopeId: payload.supervisorId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateSupervisorMemoryCache(reason: .reviewGuidanceCarryForwardChanged)
                }
            }
        case .auto:
            Task {
                let remoteResult = await syncDeviceCanonicalMemoryViaPreferredRoute(
                    payload: payload,
                    allowFileFallback: false
                )
                let finalResult = mergedCanonicalMemorySyncResult(
                    primary: remoteResult,
                    secondary: localResult
                )
                recordCanonicalMemorySyncStatus(
                    scopeKind: "device",
                    scopeId: payload.supervisorId,
                    displayName: payload.displayName,
                    result: finalResult
                )
                if finalResult.ok {
                    await invalidateSupervisorMemoryCache(reason: .reviewGuidanceCarryForwardChanged)
                }
            }
        case .fileIPC:
            recordCanonicalMemorySyncStatus(
                scopeKind: "device",
                scopeId: payload.supervisorId,
                displayName: payload.displayName,
                result: localResult
            )
            if localResult.ok {
                Task {
                    await invalidateSupervisorMemoryCache(reason: .reviewGuidanceCarryForwardChanged)
                }
            }
        }
    }

    static func requestNetworkAccess(root: URL, seconds: Int, reason: String?) async -> NetworkAccessResult {
        let bridge = HubBridgeClient.status()
        if bridge.enabled {
            let remaining = Int(max(0, bridge.enabledUntil - Date().timeIntervalSince1970))
            return NetworkAccessResult(
                state: .enabled,
                source: "bridge",
                reasonCode: nil,
                remainingSeconds: remaining,
                grantRequestId: nil
            )
        }

        let routeDecision = await currentRouteDecision()
        let requestedSeconds = max(30, min(86_400, seconds))
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        if routeDecision.preferRemote {
            let grant = await HubPairingCoordinator.shared.requestRemoteNetworkGrant(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestedSeconds: requestedSeconds,
                reason: reason,
                projectId: projectId
            )
            let grantId = normalized(grant.grantRequestId)
            let reasonCode = normalizedReasonCode(grant.reasonCode, fallback: grant.ok ? nil : "grant_failed")

            if grant.ok {
                switch grant.decision {
                case .approved:
                    let bridgeAfterGrant = await waitForBridgeEnabled(timeoutSec: 4.2)
                    if bridgeAfterGrant.enabled {
                        let remaining = Int(max(0, bridgeAfterGrant.enabledUntil - Date().timeIntervalSince1970))
                        await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                        return NetworkAccessResult(
                            state: .autoApproved,
                            source: "grpc",
                            reasonCode: "auto_approved",
                            remainingSeconds: remaining,
                            grantRequestId: grantId
                        )
                    }
                    await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                    return NetworkAccessResult(
                        state: .autoApproved,
                        source: "grpc",
                        reasonCode: "bridge_starting",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .queued:
                    await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                    return NetworkAccessResult(
                        state: .queued,
                        source: "grpc",
                        reasonCode: reasonCode ?? "queued",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .denied:
                    await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                    return NetworkAccessResult(
                        state: .denied,
                        source: "grpc",
                        reasonCode: reasonCode ?? "denied",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .failed:
                    if routeDecision.allowFileFallback,
                       HubRouteStateMachine.shouldFallbackToFile(afterRemoteReasonCode: reasonCode) {
                        break
                    }
                    return NetworkAccessResult(
                        state: networkFailureState(reasonCode: reasonCode),
                        source: "grpc",
                        reasonCode: reasonCode ?? "grant_failed",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )
                }
            }

            if !routeDecision.allowFileFallback {
                return NetworkAccessResult(
                    state: networkFailureState(reasonCode: reasonCode),
                    source: "grpc",
                    reasonCode: reasonCode ?? "grant_failed",
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }
        } else if routeDecision.requiresRemote {
            return NetworkAccessResult(
                state: .failed,
                source: "grpc",
                reasonCode: routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing",
                remainingSeconds: nil,
                grantRequestId: nil
            )
        }

        let dispatch = requestNetworkViaLocalIPC(root: root, seconds: requestedSeconds, reason: reason)
        guard let dispatch else {
            return NetworkAccessResult(
                state: .failed,
                source: "local_ipc",
                reasonCode: "hub_not_connected",
                remainingSeconds: nil,
                grantRequestId: nil
            )
        }

        if let dispatchReason = dispatch.reasonCode {
            return NetworkAccessResult(
                state: networkFailureState(reasonCode: dispatchReason),
                source: dispatch.source,
                reasonCode: dispatchReason,
                remainingSeconds: nil,
                grantRequestId: dispatch.ticket.reqId,
                detail: dispatch.detail
            )
        }

        let ack: NetworkIPCResponse?
        if let existingAck = dispatch.ack {
            ack = existingAck
        } else {
            ack = await pollNetworkResponse(
                baseDir: dispatch.ticket.baseDir,
                reqId: dispatch.ticket.reqId,
                timeoutSec: 2.6
            )
        }
        if let ack {
            let grantId = normalized(ack.id) ?? dispatch.ticket.reqId
            if !ack.ok {
                let reasonCode = normalizedReasonCode(ack.error, fallback: "denied") ?? "denied"
                return NetworkAccessResult(
                    state: networkFailureState(reasonCode: reasonCode),
                    source: dispatch.source,
                    reasonCode: reasonCode,
                    remainingSeconds: nil,
                    grantRequestId: grantId,
                    detail: normalized(ack.error)
                )
            }

            let reasonCode = normalizedReasonCode(ack.error, fallback: nil)
            if reasonCode == "auto_approved" {
                let bridgeAfterGrant = await waitForBridgeEnabled(timeoutSec: 4.2)
                if bridgeAfterGrant.enabled {
                    let remaining = Int(max(0, bridgeAfterGrant.enabledUntil - Date().timeIntervalSince1970))
                    await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                    return NetworkAccessResult(
                        state: .autoApproved,
                        source: dispatch.source,
                        reasonCode: "auto_approved",
                        remainingSeconds: remaining,
                        grantRequestId: grantId
                    )
                }
                await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                return NetworkAccessResult(
                    state: .autoApproved,
                    source: dispatch.source,
                    reasonCode: "bridge_starting",
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }

            if reasonCode == "denied" || reasonCode == "forbidden" {
                await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                return NetworkAccessResult(
                    state: .denied,
                    source: dispatch.source,
                    reasonCode: reasonCode,
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }

            await noteRemoteMemoryGrantStateChanged(projectId: projectId)
            return NetworkAccessResult(
                state: .queued,
                source: dispatch.source,
                reasonCode: reasonCode ?? "queued",
                remainingSeconds: nil,
                grantRequestId: grantId
            )
        }

        if dispatch.source == "file_ipc" {
            let bridgeAfterFileRequest = HubBridgeClient.status()
            if bridgeAfterFileRequest.enabled {
                let remaining = Int(max(0, bridgeAfterFileRequest.enabledUntil - Date().timeIntervalSince1970))
                await noteRemoteMemoryGrantStateChanged(projectId: projectId)
                return NetworkAccessResult(
                    state: .enabled,
                    source: "bridge",
                    reasonCode: nil,
                    remainingSeconds: remaining,
                    grantRequestId: dispatch.ticket.reqId
                )
            }
        }

        await noteRemoteMemoryGrantStateChanged(projectId: projectId)
        return NetworkAccessResult(
            state: .queued,
            source: dispatch.source,
            reasonCode: "ack_timeout",
            remainingSeconds: nil,
            grantRequestId: dispatch.ticket.reqId
        )
    }

    private static func requestNetworkViaLocalIPC(root: URL, seconds: Int, reason: String?) -> NetworkIPCDispatchResult? {
        guard let transport = localIPCTransport(ttl: 3.0) else { return nil }
        let reqId = UUID().uuidString
        let rootPath = AXProjectRegistryStore.normalizedRootPath(root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let displayName = AXProjectRegistryStore.displayName(forRoot: root)

        let payload = NetworkRequestPayload(
            id: reqId,
            source: "x_terminal",
            projectId: projectId,
            rootPath: rootPath,
            displayName: displayName,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines),
            requestedSeconds: max(10, seconds),
            createdAt: Date().timeIntervalSince1970
        )
        let req = NetworkIPCRequest(type: "need_network", reqId: reqId, network: payload)
        let ticket = NetworkRequestTicket(reqId: reqId, baseDir: transport.baseDir)

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return NetworkIPCDispatchResult(
                    ticket: ticket,
                    ack: nil,
                    source: "file_ipc",
                    reasonCode: "network_request_encode_failed",
                    detail: summarized(error)
                )
            }
            let writeStatus = writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_net",
                tmpPrefix: ".xterminal_net",
                in: transport.ipcURL
            )
            if writeStatus.requestQueued == true {
                return NetworkIPCDispatchResult(ticket: ticket, ack: nil, source: "file_ipc")
            }
            return NetworkIPCDispatchResult(
                ticket: ticket,
                ack: nil,
                source: "file_ipc",
                reasonCode: "network_request_write_failed",
                detail: normalized(writeStatus.requestError)
            )
        case "socket":
            guard let ack: NetworkIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return NetworkIPCDispatchResult(
                    ticket: ticket,
                    ack: nil,
                    source: "socket_ipc",
                    reasonCode: "socket_request_failed",
                    detail: "need_network socket request failed"
                )
            }
            return NetworkIPCDispatchResult(ticket: ticket, ack: ack, source: "socket_ipc")
        default:
            return NetworkIPCDispatchResult(
                ticket: ticket,
                ack: nil,
                source: "local_ipc",
                reasonCode: "unsupported_ipc_mode",
                detail: "need_network local IPC mode unsupported"
            )
        }
    }

    @discardableResult
    private static func syncProjectViaPreferredRoute(
        payload: ProjectSyncPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.syncRemoteProjectSnapshot(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteProjectSyncPayload(
                    projectId: payload.projectId,
                    rootPath: payload.rootPath,
                    displayName: payload.displayName,
                    statusDigest: payload.statusDigest,
                    lastSummaryAt: payload.lastSummaryAt,
                    lastEventAt: payload.lastEventAt,
                    updatedAt: payload.updatedAt
                )
            )
            if remote.ok {
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeProjectSyncViaFileIPC(payload)
    }

    @discardableResult
    private static func syncProjectCanonicalMemoryViaPreferredRoute(
        payload: ProjectCanonicalMemoryPayload,
        allowFileFallback: Bool
    ) async -> CanonicalMemorySyncDispatchResult {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.upsertRemoteProjectCanonicalMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteProjectCanonicalMemoryPayload(
                    projectId: payload.projectId,
                    items: payload.items.map { item in
                        HubRemoteCanonicalMemoryItem(key: item.key, value: item.value)
                    }
                )
            )
            if remote.ok {
                await invalidateProjectRemoteMemorySnapshotCache(
                    projectId: payload.projectId,
                    reason: .projectCanonicalSave
                )
                return CanonicalMemorySyncDispatchResult(
                    ok: true,
                    source: normalized(remote.source) ?? "grpc",
                    deliveryState: "delivered_remote",
                    auditRefs: remote.auditRefs,
                    evidenceRefs: remote.evidenceRefs,
                    writebackRefs: remote.writebackRefs,
                    detail: normalized(remote.logText)
                )
            }
            if !allowFileFallback {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: normalized(remote.source) ?? "grpc",
                    deliveryState: "remote_delivery_failed",
                    auditRefs: remote.auditRefs,
                    evidenceRefs: remote.evidenceRefs,
                    writebackRefs: remote.writebackRefs,
                    reasonCode: normalizedReasonCode(
                        remote.reasonCode,
                        fallback: "project_canonical_memory_remote_failed"
                    ),
                    detail: normalized(remote.logText)
                )
            }
        } else if !allowFileFallback {
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "grpc",
                reasonCode: "hub_not_connected",
                detail: "project canonical memory remote route unavailable"
            )
        }

        let localResult = writeProjectCanonicalMemoryViaLocalIPC(payload)
        if localResult.ok {
            await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
        }
        return localResult
    }

    private static func writeProjectSyncViaFileIPC(_ payload: ProjectSyncPayload) -> Bool {
        guard let dir = fileIPCEventsDir() else { return false }
        let reqId = UUID().uuidString
        let req = IPCRequest(type: "project_sync", reqId: reqId, project: payload)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { return false }
        return writeEvent(data: data, reqId: reqId, filePrefix: "xterminal", tmpPrefix: ".xterminal", in: dir)
    }

    private static func writeProjectCanonicalMemoryViaLocalIPC(
        _ payload: ProjectCanonicalMemoryPayload
    ) -> CanonicalMemorySyncDispatchResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "local_ipc",
                deliveryState: "local_ipc_unavailable",
                reasonCode: "project_canonical_memory_local_ipc_unavailable",
                detail: "project canonical memory local IPC unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = ProjectCanonicalMemoryIPCRequest(
            type: "project_canonical_memory",
            reqId: reqId,
            projectCanonicalMemory: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(req) else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "file_ipc",
                    deliveryState: "local_file_ipc_encode_failed",
                    reasonCode: "project_canonical_memory_encode_failed",
                    detail: "project canonical memory request encoding failed"
                )
            }
            let writeStatus = writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_project_memory",
                tmpPrefix: ".xterminal_project_memory",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "file_ipc",
                    deliveryState: "local_file_ipc_write_failed",
                    reasonCode: "project_canonical_memory_write_failed",
                    detail: normalized(writeStatus.requestError)
                )
            }
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: "file_ipc",
                deliveryState: "queued_local_file_ipc"
            )
        case "socket":
            guard let ack: AckIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "socket_ipc",
                    deliveryState: "local_socket_ipc_request_failed",
                    reasonCode: "socket_request_failed",
                    detail: "project canonical memory socket request failed"
                )
            }
            guard ack.ok else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "socket_ipc",
                    deliveryState: "local_socket_ipc_rejected",
                    reasonCode: normalizedReasonCode(
                        ack.error,
                        fallback: "project_canonical_memory_ipc_rejected"
                    ),
                    detail: normalized(ack.error)
                )
            }
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: "socket_ipc",
                deliveryState: "accepted_local_socket_ipc"
            )
        default:
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "local_ipc",
                deliveryState: "local_ipc_mode_unsupported",
                reasonCode: "unsupported_ipc_mode",
                detail: "project canonical memory local IPC mode unsupported"
            )
        }
    }

    @discardableResult
    private static func syncDeviceCanonicalMemoryViaPreferredRoute(
        payload: DeviceCanonicalMemoryPayload,
        allowFileFallback: Bool
    ) async -> CanonicalMemorySyncDispatchResult {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.upsertRemoteDeviceCanonicalMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteDeviceCanonicalMemoryPayload(
                    items: payload.items.map { item in
                        HubRemoteCanonicalMemoryItem(key: item.key, value: item.value)
                    }
                )
            )
            if remote.ok {
                await invalidateSupervisorMemoryCache(reason: .reviewGuidanceCarryForwardChanged)
                return CanonicalMemorySyncDispatchResult(
                    ok: true,
                    source: normalized(remote.source) ?? "grpc",
                    deliveryState: "delivered_remote",
                    auditRefs: remote.auditRefs,
                    evidenceRefs: remote.evidenceRefs,
                    writebackRefs: remote.writebackRefs,
                    detail: normalized(remote.logText)
                )
            }
            if !allowFileFallback {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: normalized(remote.source) ?? "grpc",
                    deliveryState: "remote_delivery_failed",
                    auditRefs: remote.auditRefs,
                    evidenceRefs: remote.evidenceRefs,
                    writebackRefs: remote.writebackRefs,
                    reasonCode: normalizedReasonCode(
                        remote.reasonCode,
                        fallback: "device_canonical_memory_remote_failed"
                    ),
                    detail: normalized(remote.logText)
                )
            }
        } else if !allowFileFallback {
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "grpc",
                reasonCode: "hub_not_connected",
                detail: "device canonical memory remote route unavailable"
            )
        }

        let localResult = writeDeviceCanonicalMemoryViaLocalIPC(payload)
        if localResult.ok {
            await invalidateSupervisorMemoryCache(reason: .reviewGuidanceCarryForwardChanged)
        }
        return localResult
    }

    private static func writeDeviceCanonicalMemoryViaLocalIPC(
        _ payload: DeviceCanonicalMemoryPayload
    ) -> CanonicalMemorySyncDispatchResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "local_ipc",
                deliveryState: "local_ipc_unavailable",
                reasonCode: "device_canonical_memory_local_ipc_unavailable",
                detail: "device canonical memory local IPC unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = DeviceCanonicalMemoryIPCRequest(
            type: "device_canonical_memory",
            reqId: reqId,
            deviceCanonicalMemory: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(req) else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "file_ipc",
                    deliveryState: "local_file_ipc_encode_failed",
                    reasonCode: "device_canonical_memory_encode_failed",
                    detail: "device canonical memory request encoding failed"
                )
            }
            let writeStatus = writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_device_memory",
                tmpPrefix: ".xterminal_device_memory",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "file_ipc",
                    deliveryState: "local_file_ipc_write_failed",
                    reasonCode: "device_canonical_memory_write_failed",
                    detail: normalized(writeStatus.requestError)
                )
            }
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: "file_ipc",
                deliveryState: "queued_local_file_ipc"
            )
        case "socket":
            guard let ack: AckIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "socket_ipc",
                    deliveryState: "local_socket_ipc_request_failed",
                    reasonCode: "socket_request_failed",
                    detail: "device canonical memory socket request failed"
                )
            }
            guard ack.ok else {
                return CanonicalMemorySyncDispatchResult(
                    ok: false,
                    source: "socket_ipc",
                    deliveryState: "local_socket_ipc_rejected",
                    reasonCode: normalizedReasonCode(
                        ack.error,
                        fallback: "device_canonical_memory_ipc_rejected"
                    ),
                    detail: normalized(ack.error)
                )
            }
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: "socket_ipc",
                deliveryState: "accepted_local_socket_ipc"
            )
        default:
            return CanonicalMemorySyncDispatchResult(
                ok: false,
                source: "local_ipc",
                deliveryState: "local_ipc_mode_unsupported",
                reasonCode: "unsupported_ipc_mode",
                detail: "device canonical memory local IPC mode unsupported"
            )
        }
    }

    static func invalidateProjectRemoteMemorySnapshotCache(
        projectId: String?,
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) async {
        await remoteMemorySnapshotCache.invalidate(projectId: projectId, reason: reason)
    }

    static func invalidateSupervisorRemoteMemorySnapshotCache(
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) async {
        await remoteMemorySnapshotCache.invalidate(
            key: HubRemoteMemorySnapshotCache.Key(
                mode: XTMemoryUseMode.supervisorOrchestration.rawValue,
                projectId: nil
            ),
            reason: reason
        )
    }

    private static func invalidateSupervisorMemoryCache(
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) async {
        await invalidateSupervisorRemoteMemorySnapshotCache(reason: reason)
    }

    static func noteRemoteMemoryGrantStateChanged(
        projectId: String?
    ) async {
        await noteSupervisorRemoteMemoryGrantStateChanged()
        await noteProjectRemoteMemoryGrantStateChanged(projectId: projectId)
    }

    static func refreshProjectRemoteMemorySnapshotCache(projectId: String?) async {
        await invalidateProjectRemoteMemorySnapshotCache(projectId: projectId, reason: .manualRefresh)
    }

    static func refreshSupervisorRemoteMemorySnapshotCache() async {
        await invalidateSupervisorRemoteMemorySnapshotCache(reason: .manualRefresh)
    }

    static func noteProjectRemoteMemoryGrantStateChanged(projectId: String?) async {
        await invalidateProjectRemoteMemorySnapshotCache(projectId: projectId, reason: .grantStateChanged)
    }

    static func noteProjectRemoteMemoryRouteOrModelPreferenceChanged(projectId: String?) async {
        await invalidateProjectRemoteMemorySnapshotCache(
            projectId: projectId,
            reason: .routeOrModelPreferenceChanged
        )
    }

    static func noteProjectRemoteMemoryHeartbeatAnomalyEscalated(projectId: String?) async {
        await invalidateProjectRemoteMemorySnapshotCache(
            projectId: projectId,
            reason: .heartbeatAnomalyEscalated
        )
    }

    static func noteSupervisorRemoteMemoryGrantStateChanged() async {
        await invalidateSupervisorRemoteMemorySnapshotCache(reason: .grantStateChanged)
    }

    static func noteSupervisorRemoteMemoryRouteOrModelPreferenceChanged() async {
        await invalidateSupervisorRemoteMemorySnapshotCache(reason: .routeOrModelPreferenceChanged)
    }

    static func noteSupervisorRemoteMemoryHeartbeatAnomalyEscalated() async {
        await invalidateSupervisorRemoteMemorySnapshotCache(reason: .heartbeatAnomalyEscalated)
    }

    static func defaultSupervisorCanonicalID() -> String {
        let raw = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scalars = raw.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let token = String(String.UnicodeScalarView(scalars))
        return token.isEmpty ? "supervisor-main" : "supervisor-\(token)"
    }

    @discardableResult
    private static func pushNotificationViaPreferredRoute(
        payload: NotificationPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.pushRemoteNotificationMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteNotificationPayload(
                    source: payload.source,
                    title: payload.title,
                    body: payload.body,
                    dedupeKey: payload.dedupeKey,
                    actionURL: payload.actionURL,
                    unread: payload.unread
                )
            )
            if remote.ok {
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeNotificationViaFileIPC(payload)
    }

    private static func writeNotificationViaFileIPC(_ payload: NotificationPayload) -> Bool {
        guard let dir = fileIPCEventsDir() else { return false }
        let reqId = UUID().uuidString
        let req = NotificationIPCRequest(type: "push_notification", reqId: reqId, notification: payload)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { return false }
        return writeEvent(data: data, reqId: reqId, filePrefix: "xterminal_notify", tmpPrefix: ".xterminal_notify", in: dir)
    }

    @discardableResult
    private static func removeNotificationViaLocalIPC(
        dedupeKey: String?,
        id: String?
    ) -> Bool {
        let normalizedDedupeKey = dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedDedupeKey.isEmpty || !normalizedID.isEmpty else { return false }
        guard let transport = localIPCTransport(ttl: 3.0) else { return false }

        let reqId = UUID().uuidString
        let req = NotificationDismissIPCRequest(
            type: "remove_notification",
            reqId: reqId,
            notificationDismiss: NotificationDismissPayload(
                id: normalizedID.isEmpty ? nil : normalizedID,
                dedupeKey: normalizedDedupeKey.isEmpty ? nil : normalizedDedupeKey
            )
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(req) else { return false }
            let status = writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_notify_remove",
                tmpPrefix: ".xterminal_notify_remove",
                in: transport.ipcURL
            )
            return status.requestQueued == true
        case "socket":
            guard let ack: AckIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return false
            }
            return ack.ok
        default:
            return false
        }
    }

    static func requestMemoryContext(
        useMode: XTMemoryUseMode,
        requesterRole: XTMemoryRequesterRole,
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        latestUser: String,
        reviewLevelHint: String? = nil,
        constitutionHint: String?,
        dialogueWindowText: String? = nil,
        portfolioBriefText: String? = nil,
        focusedProjectAnchorPackText: String? = nil,
        longtermOutlineText: String? = nil,
        deltaFeedText: String? = nil,
        conflictSetText: String? = nil,
        contextRefsText: String? = nil,
        evidencePackText: String? = nil,
        canonicalText: String?,
        observationsText: String?,
        workingSetText: String?,
        rawEvidenceText: String?,
        servingProfile: XTMemoryServingProfile? = nil,
        progressiveDisclosure: Bool = false,
        budgets: MemoryContextBudgets? = nil,
        timeoutSec: Double = 1.2
    ) async -> MemoryContextResponsePayload? {
        let result = await requestMemoryContextDetailed(
            useMode: useMode,
            requesterRole: requesterRole,
            projectId: projectId,
            projectRoot: projectRoot,
            displayName: displayName,
            latestUser: latestUser,
            reviewLevelHint: reviewLevelHint,
            constitutionHint: constitutionHint,
            dialogueWindowText: dialogueWindowText,
            portfolioBriefText: portfolioBriefText,
            focusedProjectAnchorPackText: focusedProjectAnchorPackText,
            longtermOutlineText: longtermOutlineText,
            deltaFeedText: deltaFeedText,
            conflictSetText: conflictSetText,
            contextRefsText: contextRefsText,
            evidencePackText: evidencePackText,
            canonicalText: canonicalText,
            observationsText: observationsText,
            workingSetText: workingSetText,
            rawEvidenceText: rawEvidenceText,
            servingProfile: servingProfile,
            progressiveDisclosure: progressiveDisclosure,
            budgets: budgets,
            timeoutSec: timeoutSec
        )
        return result.response
    }

    struct MemoryLongtermDisclosure: Equatable {
        var longtermMode: String
        var retrievalAvailable: Bool
        var fulltextNotLoaded: Bool
        var policyCode: String?
        var stage0: String?
        var stage1: String?
        var stage2: String?
        var stage1Rule: String?
        var stage2Rule: String?
    }

    struct MemoryRetrievalRequest: Equatable, Sendable {
        var requesterRole: XTMemoryRequesterRole
        var useMode: XTMemoryUseMode
        var scope: String = "current_project"
        var projectId: String?
        var crossProjectTargetIds: [String] = []
        var projectRoot: String?
        var displayName: String?
        var query: String
        var reason: String?
        var requestedKinds: [String] = []
        var explicitRefs: [String] = []
        var allowedLayers: [XTMemoryLayer] = []
        var retrievalKind: String? = nil
        var maxResults: Int = 3
        var maxSnippetChars: Int = 420
        var requireExplainability: Bool = true
    }

    private static func defaultRetrievalAvailability(for useMode: XTMemoryUseMode) -> Bool {
        switch useMode {
        case .projectChat, .supervisorOrchestration, .toolPlan:
            return true
        default:
            return false
        }
    }

    static func resolveMemoryLongtermDisclosure(
        useMode: XTMemoryUseMode,
        retrievalAvailable fallbackRetrievalAvailable: Bool,
        overrideLongtermMode: String? = nil,
        overrideRetrievalAvailable: Bool? = nil,
        overrideFulltextNotLoaded: Bool? = nil
    ) -> MemoryLongtermDisclosure {
        let policy = XTMemoryRoleScopedRouter.contract(for: useMode).longtermPolicy
        let retrievalAvailable = overrideRetrievalAvailable ?? fallbackRetrievalAvailable
        let defaultLongtermMode: String
        switch policy {
        case .progressiveDisclosureRequired where retrievalAvailable:
            defaultLongtermMode = "progressive_disclosure"
        case .denied:
            defaultLongtermMode = XTMemoryLongtermPolicy.denied.rawValue
        default:
            defaultLongtermMode = XTMemoryLongtermPolicy.summaryOnly.rawValue
        }
        let resolvedMode = normalized(overrideLongtermMode) ?? defaultLongtermMode
        let enableStageRules = policy == .progressiveDisclosureRequired || resolvedMode == "progressive_disclosure"

        return MemoryLongtermDisclosure(
            longtermMode: resolvedMode,
            retrievalAvailable: retrievalAvailable,
            fulltextNotLoaded: overrideFulltextNotLoaded ?? true,
            policyCode: policy.rawValue,
            stage0: enableStageRules ? "outline_summary" : nil,
            stage1: enableStageRules ? "related_snippets" : nil,
            stage2: enableStageRules ? "explicit_ref_read_only" : nil,
            stage1Rule: enableStageRules ? "state_summary_insufficient_before_requesting_snippets" : nil,
            stage2Rule: enableStageRules ? "explicit_ref_required_before_ref_read" : nil
        )
    }

    static func ensureMemoryLongtermDisclosureText(
        _ text: String,
        disclosure: MemoryLongtermDisclosure
    ) -> String {
        var sectionLines = [
            "[LONGTERM_MEMORY]",
            "longterm_mode=\(disclosure.longtermMode)",
            "retrieval_available=\(disclosure.retrievalAvailable ? "true" : "false")",
            "fulltext_not_loaded=\(disclosure.fulltextNotLoaded ? "true" : "false")"
        ]
        if let policyCode = normalized(disclosure.policyCode) {
            sectionLines.append("policy=\(policyCode)")
        }
        if let stage0 = normalized(disclosure.stage0) {
            sectionLines.append("stage_0=\(stage0)")
        }
        if let stage1 = normalized(disclosure.stage1) {
            sectionLines.append("stage_1=\(stage1)")
        }
        if let stage2 = normalized(disclosure.stage2) {
            sectionLines.append("stage_2=\(stage2)")
        }
        if let stage1Rule = normalized(disclosure.stage1Rule) {
            sectionLines.append("stage_1_rule=\(stage1Rule)")
        }
        if let stage2Rule = normalized(disclosure.stage2Rule) {
            sectionLines.append("stage_2_rule=\(stage2Rule)")
        }
        sectionLines.append("[/LONGTERM_MEMORY]")
        let section = sectionLines.joined(separator: "\n")

        if let start = text.range(of: "[LONGTERM_MEMORY]"),
           let end = text.range(of: "[/LONGTERM_MEMORY]"),
           start.lowerBound <= end.lowerBound {
            return String(text[..<start.lowerBound]) + section + String(text[end.upperBound...])
        }

        if let range = text.range(of: "[/SERVING_PROFILE]\n") {
            return String(text[..<range.upperBound]) + section + "\n" + String(text[range.upperBound...])
        }
        if let range = text.range(of: "[MEMORY_V1]\n") {
            return String(text[..<range.upperBound]) + section + "\n" + String(text[range.upperBound...])
        }
        return section + "\n" + text
    }

    static func requestMemoryContextDetailed(
        useMode: XTMemoryUseMode,
        requesterRole: XTMemoryRequesterRole,
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        latestUser: String,
        reviewLevelHint: String? = nil,
        constitutionHint: String?,
        dialogueWindowText: String? = nil,
        portfolioBriefText: String? = nil,
        focusedProjectAnchorPackText: String? = nil,
        longtermOutlineText: String? = nil,
        deltaFeedText: String? = nil,
        conflictSetText: String? = nil,
        contextRefsText: String? = nil,
        evidencePackText: String? = nil,
        canonicalText: String?,
        observationsText: String?,
        workingSetText: String?,
        rawEvidenceText: String?,
        servingProfile: XTMemoryServingProfile? = nil,
        progressiveDisclosure: Bool = false,
        budgets: MemoryContextBudgets? = nil,
        timeoutSec: Double = 1.2
    ) async -> MemoryContextResolutionResult {
        let rawPayload = MemoryContextPayload(
            mode: useMode.rawValue,
            projectId: normalized(projectId),
            projectRoot: normalized(projectRoot),
            displayName: normalized(displayName),
            latestUser: latestUser,
            reviewLevelHint: normalizedReviewLevelHint(reviewLevelHint),
            constitutionHint: normalized(constitutionHint),
            dialogueWindowText: normalized(dialogueWindowText),
            portfolioBriefText: normalized(portfolioBriefText),
            focusedProjectAnchorPackText: normalized(focusedProjectAnchorPackText),
            longtermOutlineText: normalized(longtermOutlineText),
            deltaFeedText: normalized(deltaFeedText),
            conflictSetText: normalized(conflictSetText),
            contextRefsText: normalized(contextRefsText),
            evidencePackText: normalized(evidencePackText),
            canonicalText: normalized(canonicalText),
            observationsText: normalized(observationsText),
            workingSetText: normalized(workingSetText),
            rawEvidenceText: normalized(rawEvidenceText),
            servingProfile: servingProfile?.rawValue,
            budgets: budgets
        )
        let targetRoute = XTMemoryRoleScopedRouter.route(
            role: requesterRole,
            mode: useMode,
            payload: rawPayload
        )
        let requestedProfile = targetRoute.servingProfile.rawValue
        if let denyCode = targetRoute.denyCode?.rawValue {
            return MemoryContextResolutionResult(
                response: nil,
                source: "memory_router",
                resolvedMode: useMode,
                requestedProfile: requestedProfile,
                attemptedProfiles: [requestedProfile],
                freshness: "unavailable",
                cacheHit: false,
                denyCode: denyCode,
                downgradeCode: targetRoute.downgradeCode?.rawValue,
                reasonCode: denyCode
            )
        }
        let progressiveProfiles = progressiveDisclosureProfiles(
            enabled: progressiveDisclosure,
            mode: useMode,
            targetProfile: targetRoute.servingProfile,
            reviewLevelHint: rawPayload.reviewLevelHint,
            hasFocusedProjectAnchor: normalized(rawPayload.focusedProjectAnchorPackText) != nil
        )
        var attemptedProfiles: [String] = []
        var lastResult: MemoryContextResolutionResult?

        for profile in progressiveProfiles {
            var stagedPayload = rawPayload
            stagedPayload.servingProfile = profile.rawValue
            let stagedRoute = XTMemoryRoleScopedRouter.route(
                role: requesterRole,
                mode: useMode,
                payload: stagedPayload
            )
            let single = await requestMemoryContextSingleDetailed(
                useMode: useMode,
                route: stagedRoute,
                timeoutSec: timeoutSec
            )
            attemptedProfiles.append(stagedRoute.servingProfile.rawValue)
            let enriched = enrichProgressiveMemoryContextResult(
                single,
                requestedProfile: requestedProfile,
                attemptedProfiles: attemptedProfiles
            )
            lastResult = enriched
            guard let response = enriched.response else {
                return enriched
            }
            if !shouldUpgradeMemoryContextProgressively(
                response: response,
                currentProfile: stagedRoute.servingProfile,
                targetProfile: targetRoute.servingProfile
            ) {
                return enriched
            }
        }

        return lastResult ?? MemoryContextResolutionResult(
            response: nil,
            source: "memory_router",
            resolvedMode: useMode,
            requestedProfile: requestedProfile,
            attemptedProfiles: attemptedProfiles.isEmpty ? [requestedProfile] : attemptedProfiles,
            freshness: "unavailable",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: "memory_context_unavailable"
        )
    }

    private static func requestMemoryContextSingleDetailed(
        useMode: XTMemoryUseMode,
        route: XTMemoryRouteDecision,
        timeoutSec: Double
    ) async -> MemoryContextResolutionResult {
        if let override = memoryContextResolutionOverride() {
            return await override(route, useMode, timeoutSec)
        }

        let payload = route.payload
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await fetchRemoteMemorySnapshot(
                mode: useMode,
                projectId: payload.projectId,
                bypassCache: route.bypassRemoteCache,
                timeoutSec: timeoutSec
            )
            if remote.snapshot.ok {
                var response = buildMemoryContextFromRemoteSnapshot(snapshot: remote.snapshot, payload: payload)
                let disclosure = resolveMemoryLongtermDisclosure(
                    useMode: useMode,
                    retrievalAvailable: defaultRetrievalAvailability(for: useMode),
                    overrideLongtermMode: response.longtermMode,
                    overrideRetrievalAvailable: response.retrievalAvailable,
                    overrideFulltextNotLoaded: response.fulltextNotLoaded
                )
                response.resolvedMode = useMode.rawValue
                response.resolvedProfile = route.servingProfile.rawValue
                response.longtermMode = disclosure.longtermMode
                response.retrievalAvailable = disclosure.retrievalAvailable
                response.fulltextNotLoaded = disclosure.fulltextNotLoaded
                response.text = ensureMemoryLongtermDisclosureText(response.text, disclosure: disclosure)
                response.freshness = remote.cacheHit ? "ttl_cache" : "fresh_remote"
                response.cacheHit = remote.cacheHit
                response.remoteSnapshotCacheScope = remote.cacheMetadata?.scope
                response.remoteSnapshotCachedAtMs = remote.cacheMetadata?.storedAtMs
                response.remoteSnapshotAgeMs = remote.cacheMetadata?.ageMs
                response.remoteSnapshotTTLRemainingMs = remote.cacheMetadata?.ttlRemainingMs
                response.remoteSnapshotCachePosture = remote.cacheMetadata?.cachePosture.rawValue
                response.remoteSnapshotInvalidationReason = remote.cacheMetadata?.invalidationReason?.rawValue
                response.denyCode = nil
                response.downgradeCode = route.downgradeCode?.rawValue
                return MemoryContextResolutionResult(
                    response: response,
                    source: response.source,
                    resolvedMode: useMode,
                    requestedProfile: route.servingProfile.rawValue,
                    attemptedProfiles: [route.servingProfile.rawValue],
                    freshness: response.freshness ?? "fresh_remote",
                    cacheHit: remote.cacheHit,
                    remoteSnapshotCacheScope: remote.cacheMetadata?.scope,
                    remoteSnapshotCachedAtMs: remote.cacheMetadata?.storedAtMs,
                    remoteSnapshotAgeMs: remote.cacheMetadata?.ageMs,
                    remoteSnapshotTTLRemainingMs: remote.cacheMetadata?.ttlRemainingMs,
                    remoteSnapshotCachePosture: remote.cacheMetadata?.cachePosture.rawValue,
                    remoteSnapshotInvalidationReason: remote.cacheMetadata?.invalidationReason?.rawValue,
                    denyCode: nil,
                    downgradeCode: route.downgradeCode?.rawValue,
                    reasonCode: nil
                )
            }
            if !routeDecision.allowFileFallback {
                return MemoryContextResolutionResult(
                    response: nil,
                    source: remote.snapshot.source,
                    resolvedMode: useMode,
                    requestedProfile: route.servingProfile.rawValue,
                    attemptedProfiles: [route.servingProfile.rawValue],
                    freshness: route.bypassRemoteCache ? "fresh_remote_required" : "remote_failed",
                    cacheHit: remote.cacheHit,
                    remoteSnapshotCacheScope: remote.cacheMetadata?.scope,
                    remoteSnapshotCachedAtMs: remote.cacheMetadata?.storedAtMs,
                    remoteSnapshotAgeMs: remote.cacheMetadata?.ageMs,
                    remoteSnapshotTTLRemainingMs: remote.cacheMetadata?.ttlRemainingMs,
                    remoteSnapshotCachePosture: remote.cacheMetadata?.cachePosture.rawValue,
                    remoteSnapshotInvalidationReason: remote.cacheMetadata?.invalidationReason?.rawValue,
                    denyCode: route.bypassRemoteCache
                        ? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue
                        : nil,
                    downgradeCode: nil,
                    reasonCode: normalizedReasonCode(remote.snapshot.reasonCode, fallback: "remote_memory_snapshot_failed")
                )
            }
        }

        if routeDecision.requiresRemote {
            return MemoryContextResolutionResult(
                response: nil,
                source: "hub_memory_v1_grpc",
                resolvedMode: useMode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "unavailable",
                cacheHit: false,
                denyCode: route.bypassRemoteCache
                    ? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue
                    : nil,
                downgradeCode: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        let local = await requestMemoryContextViaLocalIPC(payload: payload, timeoutSec: timeoutSec)
        guard let localResponse = local.response else {
            return MemoryContextResolutionResult(
                response: nil,
                source: "local_ipc",
                resolvedMode: useMode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "unavailable",
                cacheHit: false,
                denyCode: route.bypassRemoteCache
                    ? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue
                    : nil,
                downgradeCode: nil,
                reasonCode: local.reasonCode ?? "memory_context_unavailable",
                detail: local.detail
            )
        }

        var response = localResponse
        let disclosure = resolveMemoryLongtermDisclosure(
            useMode: useMode,
            retrievalAvailable: defaultRetrievalAvailability(for: useMode),
            overrideLongtermMode: response.longtermMode,
            overrideRetrievalAvailable: response.retrievalAvailable,
            overrideFulltextNotLoaded: response.fulltextNotLoaded
        )
        response.resolvedMode = useMode.rawValue
        response.resolvedProfile = route.servingProfile.rawValue
        response.longtermMode = disclosure.longtermMode
        response.retrievalAvailable = disclosure.retrievalAvailable
        response.fulltextNotLoaded = disclosure.fulltextNotLoaded
        response.text = ensureMemoryLongtermDisclosureText(response.text, disclosure: disclosure)
        response.freshness = "fresh_local_ipc"
        response.cacheHit = false
        response.denyCode = nil
        response.downgradeCode = route.downgradeCode?.rawValue
        return MemoryContextResolutionResult(
            response: response,
            source: response.source,
            resolvedMode: useMode,
            requestedProfile: route.servingProfile.rawValue,
            attemptedProfiles: [route.servingProfile.rawValue],
            freshness: "fresh_local_ipc",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: route.downgradeCode?.rawValue,
            reasonCode: nil,
            detail: nil
        )
    }

    private static func progressiveDisclosureProfiles(
        enabled: Bool,
        mode: XTMemoryUseMode,
        targetProfile: XTMemoryServingProfile,
        reviewLevelHint: String? = nil,
        hasFocusedProjectAnchor: Bool = false
    ) -> [XTMemoryServingProfile] {
        guard enabled else { return [targetProfile] }
        switch mode {
        case .projectChat, .supervisorOrchestration:
            guard targetProfile.rank >= XTMemoryServingProfile.m2PlanReview.rank else {
                return [targetProfile]
            }
            let startProfile = progressiveDisclosureStartProfile(
                mode: mode,
                targetProfile: targetProfile,
                reviewLevelHint: reviewLevelHint,
                hasFocusedProjectAnchor: hasFocusedProjectAnchor
            )
            var profiles: [XTMemoryServingProfile] = [startProfile]
            if targetProfile.rank >= XTMemoryServingProfile.m2PlanReview.rank {
                profiles.append(.m2PlanReview)
            }
            if targetProfile.rank >= XTMemoryServingProfile.m3DeepDive.rank {
                profiles.append(.m3DeepDive)
            }
            if targetProfile.rank >= XTMemoryServingProfile.m4FullScan.rank {
                profiles.append(.m4FullScan)
            }
            return Array(NSOrderedSet(array: profiles)) as? [XTMemoryServingProfile] ?? profiles
        default:
            return [targetProfile]
        }
    }

    private static func progressiveDisclosureStartProfile(
        mode: XTMemoryUseMode,
        targetProfile: XTMemoryServingProfile,
        reviewLevelHint: String?,
        hasFocusedProjectAnchor: Bool
    ) -> XTMemoryServingProfile {
        guard mode == .supervisorOrchestration,
              let reviewLevel = parseSupervisorReviewLevelHint(reviewLevelHint) else {
            return .m1Execute
        }

        let floor = minimumSupervisorServingProfile(
            for: reviewLevel,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        if floor.rank >= targetProfile.rank {
            return targetProfile
        }
        return floor
    }

    private static func shouldUpgradeMemoryContextProgressively(
        response: MemoryContextResponsePayload,
        currentProfile: XTMemoryServingProfile,
        targetProfile: XTMemoryServingProfile
    ) -> Bool {
        guard currentProfile.rank < targetProfile.rank else { return false }
        if !response.truncatedLayers.isEmpty { return true }
        let totalRatio = usageRatio(used: response.usedTotalTokens, budget: response.budgetTotalTokens)
        if totalRatio >= 0.82 { return true }

        let saturatedCoreLayer = response.layerUsage.contains { layer in
            switch layer.layer {
            case "l1_canonical", "l2_observations", "l3_working_set":
                return usageRatio(used: layer.usedTokens, budget: layer.budgetTokens) >= 0.88
            default:
                return false
            }
        }
        return saturatedCoreLayer
    }

    private static func usageRatio(used: Int, budget: Int) -> Double {
        guard budget > 0, used > 0 else { return 0 }
        return Double(used) / Double(budget)
    }

    private static func enrichProgressiveMemoryContextResult(
        _ result: MemoryContextResolutionResult,
        requestedProfile: String,
        attemptedProfiles: [String]
    ) -> MemoryContextResolutionResult {
        var enriched = result
        enriched.requestedProfile = requestedProfile
        enriched.attemptedProfiles = attemptedProfiles
        if var response = enriched.response {
            response.requestedProfile = requestedProfile
            response.attemptedProfiles = attemptedProfiles
            response.progressiveUpgradeCount = max(0, attemptedProfiles.count - 1)
            enriched.response = response
        }
        return enriched
    }

    private static func memoryContextResolutionOverride() -> (@Sendable (XTMemoryRouteDecision, XTMemoryUseMode, Double) async -> MemoryContextResolutionResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryContextResolutionOverrideForTesting,
                scoped: scopedMemoryContextResolutionOverridesForTesting
            )
        }
    }

    private static func routeDecisionOverride() -> (@Sendable () async -> HubRouteDecision)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: routeDecisionOverrideForTesting,
                scoped: scopedRouteDecisionOverridesForTesting
            )
        }
    }

    private static func supervisorRouteDecisionOverride() -> (@Sendable (SupervisorRouteDecisionRequestPayload) async -> SupervisorRouteDecisionResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: supervisorRouteDecisionOverrideForTesting,
                scoped: scopedSupervisorRouteDecisionOverridesForTesting
            )
        }
    }

    private static func supervisorRemoteContinuityOverride() -> (@Sendable (Bool) async -> SupervisorRemoteContinuityResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: supervisorRemoteContinuityOverrideForTesting,
                scoped: scopedSupervisorRemoteContinuityOverridesForTesting
            )
        }
    }

    private static func supervisorConversationAppendOverride() -> (@Sendable (HubRemoteSupervisorConversationPayload) async -> Bool)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: supervisorConversationAppendOverrideForTesting,
                scoped: scopedSupervisorConversationAppendOverridesForTesting
            )
        }
    }

    private static func memoryRetrievalOverride() -> (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: memoryRetrievalOverrideForTesting,
                scoped: scopedMemoryRetrievalOverridesForTesting
            )
        }
    }

    private static func remoteMemoryRetrievalOverride() -> (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: remoteMemoryRetrievalOverrideForTesting,
                scoped: scopedRemoteMemoryRetrievalOverridesForTesting
            )
        }
    }

    private static func remoteRuntimeSurfaceOverridesOverride() -> (@Sendable (String?, Int, Double) async -> HubRemoteRuntimeSurfaceOverridesResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: remoteRuntimeSurfaceOverridesOverrideForTesting,
                scoped: scopedRemoteRuntimeSurfaceOverridesForTesting
            )
        }
    }

    private static func remoteMemorySnapshotOverride() -> (@Sendable (XTMemoryUseMode, String?, Bool, Double) async -> HubRemoteMemorySnapshotResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: remoteMemorySnapshotOverrideForTesting,
                scoped: scopedRemoteMemorySnapshotOverridesForTesting
            )
        }
    }

    private static func voiceGrantChallengeOverride() -> (@Sendable (VoiceGrantChallengeRequestPayload) async -> VoiceGrantChallengeResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: voiceGrantChallengeOverrideForTesting,
                scoped: scopedVoiceGrantChallengeOverridesForTesting
            )
        }
    }

    private static func voiceGrantVerificationOverride() -> (@Sendable (VoiceGrantVerificationPayload) async -> VoiceGrantVerificationResult)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: voiceGrantVerificationOverrideForTesting,
                scoped: scopedVoiceGrantVerificationOverridesForTesting
            )
        }
    }

    private static func localMemoryRetrievalIPCOverride() -> (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)? {
        withTestingOverrideLock {
            testingOverride(
                fallback: localMemoryRetrievalIPCOverrideForTesting,
                scoped: scopedLocalMemoryRetrievalIPCOverridesForTesting
            )
        }
    }

    private static func normalizedMemoryRetrievalKind(
        explicitRefs: [String],
        requestedKinds: [String]
    ) -> String {
        if !explicitRefs.isEmpty {
            return "get_ref"
        }
        if requestedKinds.contains(where: { $0.lowercased().contains("drilldown") }) {
            return "drilldown"
        }
        return "search"
    }

    private static func allowedLayersForMemoryRetrieval(
        requestedKinds: [String],
        explicitRefs: [String]
    ) -> [String] {
        var layers = Set<String>()
        let normalizedKinds = requestedKinds.map { $0.lowercased() }

        if !explicitRefs.isEmpty {
            layers.insert(XTMemoryLayer.l1Canonical.rawValue)
            layers.insert(XTMemoryLayer.l2Observations.rawValue)
        }

        for kind in normalizedKinds {
            if kind.contains("spec")
                || kind.contains("decision")
                || kind.contains("canonical")
                || kind.contains("blocker")
                || kind.contains("checkpoint")
                || kind.contains("execution")
                || kind.contains("guidance")
                || kind.contains("plan")
                || kind.contains("skill") {
                layers.insert(XTMemoryLayer.l1Canonical.rawValue)
            }
            if kind.contains("background")
                || kind.contains("context")
                || kind.contains("recent")
                || kind.contains("observation")
                || kind.contains("retry")
                || kind.contains("heartbeat")
                || kind.contains("outline") {
                layers.insert(XTMemoryLayer.l2Observations.rawValue)
            }
            if kind.contains("automation") {
                layers.insert(XTMemoryLayer.l1Canonical.rawValue)
                layers.insert(XTMemoryLayer.l2Observations.rawValue)
            }
        }

        if layers.isEmpty {
            layers = [
                XTMemoryLayer.l1Canonical.rawValue,
                XTMemoryLayer.l2Observations.rawValue
            ]
        }

        return Array(layers).sorted()
    }

    private static func normalizedMemoryRetrievalStatus(
        _ response: MemoryRetrievalResponsePayload
    ) -> String {
        let denyCode = response.denyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !denyCode.isEmpty {
            return "denied"
        }
        if response.truncatedItems > 0 {
            return "truncated"
        }
        return "ok"
    }

    private static func normalizedMemoryRetrievalResults(
        snippets: [MemoryRetrievalSnippet]
    ) -> [MemoryRetrievalResultItem] {
        snippets.map { snippet in
            MemoryRetrievalResultItem(
                ref: snippet.ref,
                sourceKind: snippet.sourceKind,
                summary: snippet.title,
                snippet: snippet.text,
                score: min(1.0, max(0.0, Double(snippet.score) / 100.0)),
                redacted: false
            )
        }
    }

    private static func synthesizedMemoryRetrievalSnippets(
        results: [MemoryRetrievalResultItem]
    ) -> [MemoryRetrievalSnippet] {
        results.enumerated().map { index, result in
            MemoryRetrievalSnippet(
                snippetId: "remote-snippet-\(index + 1)",
                sourceKind: result.sourceKind,
                title: result.summary,
                ref: result.ref,
                text: result.snippet,
                score: Int((min(1.0, max(0.0, result.score)) * 100.0).rounded()),
                truncated: false
            )
        }
    }

    private static func estimatedMemoryRetrievalBudgetUsedChars(
        snippets: [MemoryRetrievalSnippet]
    ) -> Int {
        snippets.reduce(into: 0) { total, snippet in
            total += snippet.title.count
            total += snippet.text.count
            total += snippet.ref.count
        }
    }

    private static func normalizedMemoryRetrievalResponse(
        _ response: MemoryRetrievalResponsePayload?,
        request: MemoryRetrievalPayload
    ) -> MemoryRetrievalResponsePayload? {
        guard var response else { return nil }
        response.schemaVersion = response.schemaVersion ?? "xt.memory_retrieval_result.v1"
        response.requestId = response.requestId ?? request.requestId
        response.status = response.status ?? normalizedMemoryRetrievalStatus(response)
        response.resolvedScope = response.resolvedScope ?? response.scope
        response.results = response.results ?? normalizedMemoryRetrievalResults(snippets: response.snippets)
        response.truncated = response.truncated ?? (response.truncatedItems > 0)
        response.budgetUsedChars = response.budgetUsedChars ?? estimatedMemoryRetrievalBudgetUsedChars(snippets: response.snippets)
        return response
    }

    private static func requestMemoryRetrievalViaPreferredRemote(
        payload: MemoryRetrievalPayload,
        timeoutSec: Double
    ) async -> MemoryRetrievalResponsePayload? {
        if let override = remoteMemoryRetrievalOverride() {
            return await override(payload, timeoutSec)
        }

        let remote = await HubPairingCoordinator.shared.fetchRemoteMemoryRetrieval(
            options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
            payload: payload,
            timeoutSec: timeoutSec,
            allowClientKitInstallRetry: false
        )
        guard remote.ok else { return nil }

        let results = remote.results.map { item in
            MemoryRetrievalResultItem(
                ref: item.ref,
                sourceKind: item.sourceKind,
                summary: item.summary,
                snippet: item.snippet,
                score: min(1.0, max(0.0, item.score)),
                redacted: item.redacted
            )
        }

        return MemoryRetrievalResponsePayload(
            schemaVersion: remote.schemaVersion,
            requestId: remote.requestId ?? payload.requestId,
            status: remote.status,
            resolvedScope: remote.resolvedScope,
            source: remote.source,
            scope: remote.scope,
            auditRef: remote.auditRef,
            reasonCode: remote.reasonCode,
            denyCode: remote.denyCode,
            results: results,
            snippets: synthesizedMemoryRetrievalSnippets(results: results),
            truncated: remote.truncated,
            budgetUsedChars: remote.budgetUsedChars,
            truncatedItems: remote.truncatedItems,
            redactedItems: remote.redactedItems
        )
    }

    static func requestMemoryRetrieval(
        _ request: MemoryRetrievalRequest,
        timeoutSec: Double = 1.0
    ) async -> MemoryRetrievalResponsePayload? {
        let requestId = "memreq_\(String(UUID().uuidString.lowercased().prefix(12)))"
        let normalizedRequestedKinds = HubIPCClient.orderedUniqueStringTokens(request.requestedKinds)
        let normalizedExplicitRefs = HubIPCClient.orderedUniqueStringTokens(request.explicitRefs)
        let explicitRetrievalKind = normalized(request.retrievalKind) ?? ""
        let normalizedScope = normalized(request.scope) ?? "current_project"
        let payload = MemoryRetrievalPayload(
            requestId: requestId,
            scope: normalizedScope,
            requesterRole: request.requesterRole.rawValue,
            mode: request.useMode.rawValue,
            projectId: normalized(request.projectId),
            crossProjectTargetIds: orderedUniqueStringTokens(request.crossProjectTargetIds),
            projectRoot: normalized(request.projectRoot),
            displayName: normalized(request.displayName),
            query: request.query,
            latestUser: request.query,
            allowedLayers: request.allowedLayers.isEmpty
                ? allowedLayersForMemoryRetrieval(
                    requestedKinds: normalizedRequestedKinds,
                    explicitRefs: normalizedExplicitRefs
                )
                : orderedUniqueStringTokens(request.allowedLayers.map(\.rawValue)),
            retrievalKind: explicitRetrievalKind.isEmpty
                ? normalizedMemoryRetrievalKind(
                    explicitRefs: normalizedExplicitRefs,
                    requestedKinds: normalizedRequestedKinds
                )
                : explicitRetrievalKind,
            maxResults: max(1, min(6, request.maxResults)),
            reason: normalized(request.reason),
            requireExplainability: request.requireExplainability,
            requestedKinds: normalizedRequestedKinds,
            explicitRefs: normalizedExplicitRefs,
            maxSnippets: max(1, min(6, request.maxResults)),
            maxSnippetChars: max(120, min(1_200, request.maxSnippetChars)),
            auditRef: "audit-xt-memory-retrieval-\(String(UUID().uuidString.lowercased().prefix(12)))"
        )
        if let override = memoryRetrievalOverride() {
            let response = await override(payload, timeoutSec)
            return normalizedMemoryRetrievalResponse(response, request: payload)
        }
        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await requestMemoryRetrievalViaPreferredRemote(
                payload: payload,
                timeoutSec: timeoutSec
            )
            if remote != nil {
                return normalizedMemoryRetrievalResponse(remote, request: payload)
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }
        if routeDecision.requiresRemote {
            return nil
        }
        let response = await requestMemoryRetrievalViaLocalIPC(payload: payload, timeoutSec: timeoutSec)
        return normalizedMemoryRetrievalResponse(response, request: payload)
    }

    static func requestProjectMemoryRetrieval(
        requesterRole: XTMemoryRequesterRole,
        useMode: XTMemoryUseMode = .projectChat,
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        latestUser: String,
        reason: String?,
        requestedKinds: [String] = [],
        explicitRefs: [String] = [],
        maxSnippets: Int = 3,
        maxSnippetChars: Int = 420,
        timeoutSec: Double = 1.0
    ) async -> MemoryRetrievalResponsePayload? {
        await requestMemoryRetrieval(
            MemoryRetrievalRequest(
                requesterRole: requesterRole,
                useMode: useMode,
                projectId: projectId,
                projectRoot: projectRoot,
                displayName: displayName,
                query: latestUser,
                reason: reason,
                requestedKinds: requestedKinds,
                explicitRefs: explicitRefs,
                maxResults: maxSnippets,
                maxSnippetChars: maxSnippetChars
            ),
            timeoutSec: timeoutSec
        )
    }

    static func pushNotification(
        source: String,
        title: String,
        body: String,
        dedupeKey: String? = nil,
        actionURL: String? = nil,
        unread: Bool = true
    ) {
        let payload = NotificationPayload(
            id: "",
            source: source,
            title: title,
            body: body,
            createdAt: Date().timeIntervalSince1970,
            dedupeKey: dedupeKey,
            actionURL: actionURL,
            unread: unread
        )
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await pushNotificationViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await pushNotificationViaPreferredRoute(payload: payload, allowFileFallback: true)
            }
        case .fileIPC:
            _ = writeNotificationViaFileIPC(payload)
        }
    }

    static func removeNotification(dedupeKey: String? = nil, id: String? = nil) {
        _ = removeNotificationViaLocalIPC(dedupeKey: dedupeKey, id: id)
    }

    static func appendSupervisorIncidentAudit(
        incidentID: String,
        laneID: String,
        taskID: UUID,
        projectID: UUID?,
        incidentCode: String,
        eventType: String,
        denyCode: String,
        proposedAction: String,
        severity: String,
        category: String,
        detectedAtMs: Int64,
        handledAtMs: Int64?,
        takeoverLatencyMs: Int64?,
        auditRef: String,
        detail: String?,
        status: String
    ) {
        guard let dir = supervisorIncidentAuditEventsDir() else { return }

        let normalizedEventType = normalized(eventType) ?? ""
        let normalizedIncidentCode = normalized(incidentCode) ?? ""
        let normalizedDenyCode = normalized(denyCode) ?? ""
        let normalizedLaneID = normalized(laneID) ?? ""
        let normalizedAuditRef = normalized(auditRef) ?? ""
        guard !normalizedEventType.isEmpty,
              !normalizedIncidentCode.isEmpty,
              !normalizedDenyCode.isEmpty,
              !normalizedLaneID.isEmpty,
              !normalizedAuditRef.isEmpty else {
            return
        }

        let reqId = UUID().uuidString
        let payload = SupervisorIncidentAuditPayload(
            incidentId: normalized(incidentID) ?? "",
            laneId: normalizedLaneID,
            taskId: taskID.uuidString.lowercased(),
            projectId: projectID?.uuidString.lowercased(),
            incidentCode: normalizedIncidentCode,
            eventType: normalizedEventType,
            denyCode: normalizedDenyCode,
            proposedAction: normalized(proposedAction) ?? "",
            severity: normalized(severity) ?? "",
            category: normalized(category) ?? "",
            detectedAtMs: max(0, detectedAtMs),
            handledAtMs: handledAtMs != nil ? max(0, handledAtMs ?? 0) : nil,
            takeoverLatencyMs: takeoverLatencyMs != nil ? max(0, takeoverLatencyMs ?? 0) : nil,
            auditRef: normalizedAuditRef,
            detail: normalized(detail),
            status: normalized(status) ?? "",
            source: "x_terminal_supervisor"
        )
        let req = SupervisorIncidentAuditIPCRequest(
            type: "supervisor_incident_audit",
            reqId: reqId,
            supervisorIncident: payload
        )
        guard let data = try? JSONEncoder().encode(req) else { return }
        _ = writeEvent(
            data: data,
            reqId: reqId,
            filePrefix: "xterminal_incident_audit",
            tmpPrefix: ".xterminal_incident_audit",
            in: dir
        )
    }

    static func appendSupervisorProjectActionAudit(
        eventID: String,
        projectID: String,
        projectName: String,
        eventType: String,
        severity: String,
        actionTitle: String,
        actionSummary: String,
        whyItMatters: String,
        nextAction: String,
        occurredAtMs: Int64,
        deliveryChannel: String,
        deliveryStatus: String,
        jurisdictionRole: String?,
        grantedScope: String?,
        auditRef: String
    ) {
        let normalizedEventID = normalized(eventID) ?? ""
        let normalizedProjectID = normalized(projectID) ?? ""
        let normalizedProjectName = normalized(projectName) ?? ""
        let normalizedEventType = normalized(eventType) ?? ""
        let normalizedSeverity = normalized(severity) ?? ""
        let normalizedActionTitle = normalized(actionTitle) ?? ""
        let normalizedActionSummary = normalized(actionSummary) ?? ""
        let normalizedWhy = normalized(whyItMatters) ?? ""
        let normalizedNextAction = normalized(nextAction) ?? ""
        let normalizedDeliveryChannel = normalized(deliveryChannel) ?? ""
        let normalizedDeliveryStatus = normalized(deliveryStatus) ?? ""
        let normalizedAuditRef = normalized(auditRef) ?? ""
        guard !normalizedEventID.isEmpty,
              !normalizedProjectID.isEmpty,
              !normalizedProjectName.isEmpty,
              !normalizedEventType.isEmpty,
              !normalizedSeverity.isEmpty,
              !normalizedActionTitle.isEmpty,
              !normalizedActionSummary.isEmpty,
              !normalizedWhy.isEmpty,
              !normalizedNextAction.isEmpty,
              !normalizedDeliveryChannel.isEmpty,
              !normalizedDeliveryStatus.isEmpty,
              !normalizedAuditRef.isEmpty else {
            return
        }

        let payload = SupervisorProjectActionAuditPayload(
            eventId: normalizedEventID,
            projectId: normalizedProjectID,
            projectName: normalizedProjectName,
            eventType: normalizedEventType,
            severity: normalizedSeverity,
            actionTitle: normalizedActionTitle,
            actionSummary: normalizedActionSummary,
            whyItMatters: normalizedWhy,
            nextAction: normalizedNextAction,
            occurredAtMs: max(0, occurredAtMs),
            deliveryChannel: normalizedDeliveryChannel,
            deliveryStatus: normalizedDeliveryStatus,
            jurisdictionRole: normalized(jurisdictionRole),
            grantedScope: normalized(grantedScope),
            auditRef: normalizedAuditRef,
            source: "x_terminal_supervisor"
        )
        let wroteLocalAudit = writeSupervisorProjectActionAuditViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await appendSupervisorProjectActionAuditViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await appendSupervisorProjectActionAuditViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .fileIPC:
            _ = wroteLocalAudit
        }
    }

    @discardableResult
    private static func appendSupervisorProjectActionAuditViaPreferredRoute(
        payload: SupervisorProjectActionAuditPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let record = SupervisorProjectActionCanonicalRecord(
                schemaVersion: SupervisorProjectActionCanonicalSync.schemaVersion,
                eventId: payload.eventId,
                projectId: payload.projectId,
                projectName: payload.projectName,
                eventType: payload.eventType,
                severity: payload.severity,
                actionTitle: payload.actionTitle,
                actionSummary: payload.actionSummary,
                whyItMatters: payload.whyItMatters,
                nextAction: payload.nextAction,
                occurredAtMs: payload.occurredAtMs,
                deliveryChannel: payload.deliveryChannel,
                deliveryStatus: payload.deliveryStatus,
                jurisdictionRole: payload.jurisdictionRole,
                grantedScope: payload.grantedScope,
                auditRef: payload.auditRef
            )
            let remote = await HubPairingCoordinator.shared.upsertRemoteProjectCanonicalMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteProjectCanonicalMemoryPayload(
                    projectId: payload.projectId,
                    items: SupervisorProjectActionCanonicalSync.items(record: record).map { item in
                        HubRemoteCanonicalMemoryItem(key: item.key, value: item.value)
                    }
                )
            )
            if remote.ok {
                await invalidateProjectRemoteMemorySnapshotCache(
                        projectId: payload.projectId,
                        reason: .projectCanonicalSave
                    )
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeSupervisorProjectActionAuditViaLocalIPC(payload)
    }

    private static func writeSupervisorProjectActionAuditViaLocalIPC(_ payload: SupervisorProjectActionAuditPayload) -> Bool {
        guard let dir = supervisorIncidentAuditEventsDir() else { return false }

        let reqId = UUID().uuidString
        let req = SupervisorProjectActionAuditIPCRequest(
            type: "supervisor_project_action_audit",
            reqId: reqId,
            supervisorProjectAction: payload
        )
        guard let data = try? JSONEncoder().encode(req) else { return false }
        return writeEvent(
            data: data,
            reqId: reqId,
            filePrefix: "xterminal_project_action_audit",
            tmpPrefix: ".xterminal_project_action_audit",
            in: dir
        )
    }

    static func requestSchedulerStatus(
        includeQueueItems: Bool = true,
        queueItemsLimit: Int = 80
    ) async -> SchedulerStatusSnapshot? {
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSchedulerStatus(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                includeQueueItems: includeQueueItems,
                queueItemsLimit: max(1, min(500, queueItemsLimit))
            )
            if remote.ok {
                return SchedulerStatusSnapshot(
                    source: remote.source,
                    updatedAtMs: max(0, remote.updatedAtMs),
                    inFlightTotal: max(0, remote.inFlightTotal),
                    queueDepth: max(0, remote.queueDepth),
                    oldestQueuedMs: max(0, remote.oldestQueuedMs),
                    inFlightByScope: remote.inFlightByScope.map { row in
                        SchedulerScopeCount(
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            count: max(0, row.count)
                        )
                    },
                    queuedByScope: remote.queuedByScope.map { row in
                        SchedulerScopeCount(
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            count: max(0, row.count)
                        )
                    },
                    queueItems: remote.queueItems.map { row in
                        SchedulerQueueItem(
                            requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            enqueuedAtMs: max(0, row.enqueuedAtMs),
                            queuedMs: max(0, row.queuedMs)
                        )
                    }
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalSchedulerStatus(
            includeQueueItems: includeQueueItems,
            queueItemsLimit: max(1, min(500, queueItemsLimit))
        )
    }

    static func requestPendingGrantRequests(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> PendingGrantSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)
        var sourceOverrideForLocalSnapshot: String?

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemotePendingGrantRequests(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if remote.ok {
                let items = remote.items.map { row in
                    PendingGrantItem(
                        grantRequestId: row.grantRequestId,
                        requestId: row.requestId,
                        deviceId: row.deviceId,
                        userId: row.userId,
                        appId: row.appId,
                        projectId: row.projectId,
                        capability: row.capability,
                        modelId: row.modelId,
                        reason: row.reason,
                        requestedTtlSec: max(0, row.requestedTtlSec),
                        requestedTokenCap: max(0, row.requestedTokenCap),
                        status: row.status,
                        decision: row.decision,
                        createdAtMs: max(0, row.createdAtMs),
                        decidedAtMs: max(0, row.decidedAtMs)
                    )
                }
                return PendingGrantSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, remote.updatedAtMs),
                    items: items
                )
            }

            let remoteReasonCode = normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_pending_grants_failed"
            )
            guard HubRouteStateMachine.shouldFallbackToFileForPendingGrantSnapshot(
                routeDecision: routeDecision,
                remoteReasonCode: remoteReasonCode
            ) else {
                return nil
            }
            sourceOverrideForLocalSnapshot = HubRouteStateMachine.pendingGrantSnapshotFallbackSource(
                localSource: "hub_pending_grants_file",
                routeDecision: routeDecision,
                remoteReasonCode: remoteReasonCode
            )
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalPendingGrantRequests(
            projectId: normalizedProjectId,
            limit: boundedLimit,
            sourceOverride: sourceOverrideForLocalSnapshot
        )
    }

    static func requestSupervisorCandidateReviewSnapshot(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> SupervisorCandidateReviewSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSupervisorCandidateReviewQueue(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if remote.ok {
                return SupervisorCandidateReviewSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, remote.updatedAtMs),
                    items: remote.items.map { row in
                        SupervisorCandidateReviewItem(
                            schemaVersion: row.schemaVersion,
                            reviewId: row.reviewId,
                            requestId: row.requestId,
                            evidenceRef: row.evidenceRef,
                            reviewState: row.reviewState,
                            durablePromotionState: row.durablePromotionState,
                            promotionBoundary: row.promotionBoundary,
                            deviceId: row.deviceId,
                            userId: row.userId,
                            appId: row.appId,
                            threadId: row.threadId,
                            threadKey: row.threadKey,
                            projectId: row.projectId,
                            projectIds: row.projectIds,
                            scopes: row.scopes,
                            recordTypes: row.recordTypes,
                            auditRefs: row.auditRefs,
                            idempotencyKeys: row.idempotencyKeys,
                            candidateCount: max(0, row.candidateCount),
                            summaryLine: row.summaryLine,
                            mirrorTarget: row.mirrorTarget,
                            localStoreRole: row.localStoreRole,
                            carrierKind: row.carrierKind,
                            carrierSchemaVersion: row.carrierSchemaVersion,
                            pendingChangeId: row.pendingChangeId,
                            pendingChangeStatus: row.pendingChangeStatus,
                            editSessionId: row.editSessionId,
                            docId: row.docId,
                            writebackRef: row.writebackRef,
                            stageCreatedAtMs: max(0, row.stageCreatedAtMs),
                            stageUpdatedAtMs: max(0, row.stageUpdatedAtMs),
                            latestEmittedAtMs: max(0, row.latestEmittedAtMs),
                            createdAtMs: max(0, row.createdAtMs),
                            updatedAtMs: max(0, row.updatedAtMs)
                        )
                    }
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalSupervisorCandidateReviewSnapshot(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func requestSupervisorSkillRegistrySnapshot(
        projectId: String?,
        projectName: String?
    ) async -> SupervisorSkillRegistrySnapshot? {
        guard let normalizedProjectId = normalized(projectId) else { return nil }
        return AXSkillsLibrary.supervisorSkillRegistrySnapshot(
            projectId: normalizedProjectId,
            projectName: normalized(projectName),
            hubBaseDir: HubPaths.baseDir()
        )
    }

    static func searchSkills(
        query: String,
        sourceFilter: String? = nil,
        projectId: String? = nil,
        limit: Int = 20
    ) async -> SkillsSearchResult {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSourceFilter = normalized(sourceFilter)
        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(100, limit))

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.searchRemoteSkills(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                query: normalizedQuery,
                sourceFilter: normalizedSourceFilter,
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            return SkillsSearchResult(
                ok: remote.ok,
                source: remote.source,
                updatedAtMs: remote.updatedAtMs,
                results: remote.results.map { row in
                    SkillCatalogEntry(
                        skillID: row.skillID,
                        name: row.name,
                        version: row.version,
                        description: row.description,
                        publisherID: row.publisherID,
                        capabilitiesRequired: row.capabilitiesRequired,
                        sourceID: row.sourceID,
                        packageSHA256: row.packageSHA256,
                        installHint: row.installHint,
                        riskLevel: row.riskLevel,
                        requiresGrant: row.requiresGrant,
                        sideEffectClass: row.sideEffectClass
                    )
                },
                reasonCode: remote.reasonCode,
                officialChannelStatus: remote.officialChannelStatus.map { status in
                    OfficialSkillChannelStatus(
                        channelID: status.channelID,
                        status: status.status,
                        updatedAtMs: status.updatedAtMs,
                        lastAttemptAtMs: status.lastAttemptAtMs,
                        lastSuccessAtMs: status.lastSuccessAtMs,
                        skillCount: status.skillCount,
                        errorCode: status.errorCode,
                        maintenanceEnabled: status.maintenanceEnabled,
                        maintenanceIntervalMs: status.maintenanceIntervalMs,
                        maintenanceLastRunAtMs: status.maintenanceLastRunAtMs,
                        maintenanceSourceKind: status.maintenanceSourceKind,
                        lastTransitionAtMs: status.lastTransitionAtMs,
                        lastTransitionKind: status.lastTransitionKind,
                        lastTransitionSummary: status.lastTransitionSummary
                    )
                }
            )
        }

        return SkillsSearchResult(
            ok: false,
            source: "file_ipc",
            updatedAtMs: 0,
            results: [],
            reasonCode: "skills_search_file_ipc_not_supported",
            officialChannelStatus: nil
        )
    }

    static func setSkillPin(
        scope: String,
        skillId: String,
        packageSHA256: String,
        projectId: String? = nil,
        note: String? = nil,
        requestId: String? = nil
    ) async -> SkillPinResult {
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSkillId = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedProjectId = normalized(projectId)
        let override = withTestingOverrideLock { skillPinOverrideForTesting }
        if let override {
            return await override(
                SkillPinRequestPayload(
                    scope: normalizedScope,
                    skillId: normalizedSkillId,
                    packageSHA256: normalizedPackageSHA256,
                    projectId: normalizedProjectId,
                    note: note,
                    requestId: requestId
                )
            )
        }

        guard normalizedScope == "global" || normalizedScope == "project" else {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: "",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "unsupported_skill_pin_scope"
            )
        }
        if normalizedScope == "project", normalizedProjectId == nil {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: "",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_project_id"
            )
        }
        guard !normalizedSkillId.isEmpty else {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId ?? "",
                skillId: "",
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_skill_id"
            )
        }
        guard !normalizedPackageSHA256.isEmpty else {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId ?? "",
                skillId: normalizedSkillId,
                packageSHA256: "",
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_package_sha256"
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.setRemoteSkillPin(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                scope: normalizedScope,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                projectId: normalizedProjectId,
                note: note,
                requestId: requestId
            )
            return SkillPinResult(
                ok: remote.ok,
                source: remote.source,
                scope: remote.scope,
                userId: remote.userId,
                projectId: remote.projectId,
                skillId: remote.skillId,
                packageSHA256: remote.packageSHA256,
                previousPackageSHA256: remote.previousPackageSHA256,
                updatedAtMs: remote.updatedAtMs,
                reasonCode: remote.reasonCode
            )
        }

        return SkillPinResult(
            ok: false,
            source: "file_ipc",
            scope: normalizedScope,
            userId: "",
            projectId: normalizedProjectId ?? "",
            skillId: normalizedSkillId,
            packageSHA256: normalizedPackageSHA256,
            previousPackageSHA256: "",
            updatedAtMs: 0,
            reasonCode: "skills_pin_file_ipc_not_supported"
        )
    }

    static func listResolvedSkills(
        projectId: String? = nil
    ) async -> ResolvedSkillsResult {
        let normalizedProjectId = normalized(projectId)
        if let override = withTestingOverrideLock({ resolvedSkillsOverrideForTesting }) {
            return await override(normalizedProjectId)
        }
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteResolvedSkills(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId
            )
            return ResolvedSkillsResult(
                ok: remote.ok,
                source: remote.source,
                skills: remote.skills.map { row in
                    ResolvedSkillEntry(
                        scope: row.scope,
                        skill: SkillCatalogEntry(
                            skillID: row.skill.skillID,
                            name: row.skill.name,
                            version: row.skill.version,
                            description: row.skill.description,
                            publisherID: row.skill.publisherID,
                            capabilitiesRequired: row.skill.capabilitiesRequired,
                            sourceID: row.skill.sourceID,
                            packageSHA256: row.skill.packageSHA256,
                            installHint: row.skill.installHint,
                            riskLevel: row.skill.riskLevel,
                            requiresGrant: row.skill.requiresGrant,
                            sideEffectClass: row.skill.sideEffectClass
                        )
                    )
                },
                reasonCode: remote.reasonCode
            )
        }

        return ResolvedSkillsResult(
            ok: false,
            source: "file_ipc",
            skills: [],
            reasonCode: "skills_resolved_file_ipc_not_supported"
        )
    }

    static func getSkillManifest(
        packageSHA256: String
    ) async -> SkillManifestResult {
        let normalizedPackageSHA256 = packageSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedPackageSHA256.isEmpty else {
            return SkillManifestResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: "",
                manifestJSON: "",
                reasonCode: "missing_package_sha256"
            )
        }

        if let override = withTestingOverrideLock({ skillManifestOverrideForTesting }) {
            return await override(normalizedPackageSHA256)
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSkillManifest(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                packageSHA256: normalizedPackageSHA256
            )
            return SkillManifestResult(
                ok: remote.ok,
                source: remote.source,
                packageSHA256: remote.packageSHA256,
                manifestJSON: remote.manifestJSON,
                reasonCode: remote.reasonCode
            )
        }

        return SkillManifestResult(
            ok: false,
            source: "file_ipc",
            packageSHA256: normalizedPackageSHA256,
            manifestJSON: "",
            reasonCode: "skills_manifest_file_ipc_not_supported"
        )
    }

    static func stageAgentImport(
        importManifestJSON: String,
        findingsJSON: String? = nil,
        scanInputJSON: String? = nil,
        requestedBy: String? = nil,
        note: String? = nil,
        requestId: String? = nil
    ) async -> AgentImportStageResult {
        let manifestText = importManifestJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifestText.isEmpty else {
            return AgentImportStageResult(
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
                reasonCode: "missing_agent_import_manifest"
            )
        }

        if let override = agentImportStageOverrideSnapshotForTesting() {
            return await override(
                AgentImportStageRequestPayload(
                    importManifestJSON: manifestText,
                    findingsJSON: findingsJSON,
                    scanInputJSON: scanInputJSON,
                    requestedBy: requestedBy,
                    note: note,
                    requestId: requestId
                )
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.stageRemoteAgentImport(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                importManifestJSON: manifestText,
                findingsJSON: findingsJSON,
                scanInputJSON: scanInputJSON,
                requestedBy: requestedBy,
                note: note,
                requestId: requestId
            )
            return AgentImportStageResult(
                ok: remote.ok,
                source: remote.source,
                stagingId: remote.stagingId,
                status: remote.status,
                auditRef: remote.auditRef,
                preflightStatus: remote.preflightStatus,
                skillId: remote.skillId,
                policyScope: remote.policyScope,
                findingsCount: remote.findingsCount,
                vetterStatus: remote.vetterStatus,
                vetterCriticalCount: remote.vetterCriticalCount,
                vetterWarnCount: remote.vetterWarnCount,
                vetterAuditRef: remote.vetterAuditRef,
                recordPath: remote.recordPath,
                reasonCode: remote.reasonCode
            )
        }

        return AgentImportStageResult(
            ok: false,
            source: "file_ipc",
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
            reasonCode: "skills_stage_file_ipc_not_supported"
        )
    }

    static func getAgentImportRecord(
        stagingId: String? = nil,
        selector: String? = nil,
        skillId: String? = nil,
        projectId: String? = nil
    ) async -> AgentImportRecordResult {
        let normalizedStagingId = stagingId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedSkillId = skillId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lookup = AgentImportRecordLookupPayload(
            stagingId: normalizedStagingId.isEmpty ? nil : normalizedStagingId,
            selector: normalizedSelector.isEmpty ? nil : normalizedSelector,
            skillId: normalizedSkillId.isEmpty ? nil : normalizedSkillId,
            projectId: normalizedProjectId.isEmpty ? nil : normalizedProjectId
        )

        guard lookup.stagingId != nil || lookup.selector != nil else {
            return AgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: lookup.selector,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: lookup.skillId,
                projectId: lookup.projectId,
                recordJSON: nil,
                reasonCode: "missing_agent_import_locator"
            )
        }

        if let override = agentImportRecordOverrideSnapshotForTesting() {
            return await override(lookup)
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote: HubRemoteAgentImportRecordResult
            if let normalizedStagingId = lookup.stagingId {
                remote = await HubPairingCoordinator.shared.fetchRemoteAgentImportRecord(
                    options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                    stagingId: normalizedStagingId
                )
            } else {
                remote = await HubPairingCoordinator.shared.fetchRemoteResolvedAgentImportRecord(
                    options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                    selector: lookup.selector ?? "last_import",
                    skillId: lookup.skillId,
                    projectId: lookup.projectId
                )
            }
            return AgentImportRecordResult(
                ok: remote.ok,
                source: remote.source,
                selector: remote.selector ?? lookup.selector,
                stagingId: remote.stagingId,
                status: remote.status,
                auditRef: remote.auditRef,
                schemaVersion: remote.schemaVersion,
                skillId: remote.skillId ?? lookup.skillId,
                projectId: remote.projectId ?? lookup.projectId,
                recordJSON: remote.recordJSON,
                reasonCode: remote.reasonCode
            )
        }

        return AgentImportRecordResult(
            ok: false,
            source: "file_ipc",
            selector: lookup.selector,
            stagingId: nil,
            status: nil,
            auditRef: nil,
            schemaVersion: nil,
            skillId: lookup.skillId,
            projectId: lookup.projectId,
            recordJSON: nil,
            reasonCode: "skills_record_file_ipc_not_supported"
        )
    }

    private static func agentImportRecordOverrideSnapshotForTesting() -> (@Sendable (AgentImportRecordLookupPayload) async -> AgentImportRecordResult)? {
        withTestingOverrideLock {
            agentImportRecordOverrideForTesting
        }
    }

    private static func agentImportStageOverrideSnapshotForTesting() -> (@Sendable (AgentImportStageRequestPayload) async -> AgentImportStageResult)? {
        withTestingOverrideLock {
            agentImportStageOverrideForTesting
        }
    }

    private static func secretUseOverrideSnapshotForTesting() -> (@Sendable (SecretUseRequestPayload) async -> SecretUseResult)? {
        withTestingOverrideLock {
            secretUseOverrideForTesting
        }
    }

    private static func skillPackageUploadOverrideSnapshotForTesting() -> (@Sendable (SkillPackageUploadRequestPayload) async -> SkillPackageUploadResult)? {
        withTestingOverrideLock {
            skillPackageUploadOverrideForTesting
        }
    }

    private static func secretRedeemOverrideSnapshotForTesting() -> (@Sendable (SecretRedeemRequestPayload) async -> SecretRedeemResult)? {
        withTestingOverrideLock {
            secretRedeemOverrideForTesting
        }
    }

    private static func agentImportPromoteOverrideSnapshotForTesting() -> (@Sendable (AgentImportPromoteRequestPayload) async -> AgentImportPromoteResult)? {
        withTestingOverrideLock {
            agentImportPromoteOverrideForTesting
        }
    }

    static func uploadSkillPackage(
        packageFileURL: URL,
        manifestJSON: String,
        sourceId: String = "local:xt-import",
        requestId: String? = nil
    ) async -> SkillPackageUploadResult {
        let manifestText = manifestJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifestText.isEmpty else {
            return SkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: "missing_manifest_json"
            )
        }

        if let override = skillPackageUploadOverrideSnapshotForTesting() {
            return await override(
                SkillPackageUploadRequestPayload(
                    packageFileURL: packageFileURL,
                    manifestJSON: manifestText,
                    sourceId: sourceId,
                    requestId: requestId
                )
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.uploadRemoteSkillPackage(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                packageFileURL: packageFileURL,
                manifestJSON: manifestText,
                sourceId: sourceId,
                requestId: requestId
            )
            return SkillPackageUploadResult(
                ok: remote.ok,
                source: remote.source,
                packageSHA256: remote.packageSHA256,
                alreadyPresent: remote.alreadyPresent,
                skillId: remote.skillId,
                version: remote.version,
                reasonCode: remote.reasonCode
            )
        }

        return SkillPackageUploadResult(
            ok: false,
            source: "file_ipc",
            packageSHA256: nil,
            alreadyPresent: false,
            skillId: nil,
            version: nil,
            reasonCode: "skills_upload_file_ipc_not_supported"
        )
    }

    static func promoteAgentImport(
        stagingId: String,
        packageSHA256: String,
        note: String? = nil,
        requestId: String? = nil
    ) async -> AgentImportPromoteResult {
        let normalizedStagingId = stagingId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedStagingId.isEmpty else {
            return AgentImportPromoteResult(
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
                reasonCode: "missing_agent_staging_id"
            )
        }
        guard !normalizedPackageSHA256.isEmpty else {
            return AgentImportPromoteResult(
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
                reasonCode: "missing_package_sha256"
            )
        }

        if let override = agentImportPromoteOverrideSnapshotForTesting() {
            return await override(
                AgentImportPromoteRequestPayload(
                    stagingId: normalizedStagingId,
                    packageSHA256: normalizedPackageSHA256,
                    note: note,
                    requestId: requestId
                )
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.promoteRemoteAgentImport(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                stagingId: normalizedStagingId,
                packageSHA256: normalizedPackageSHA256,
                note: note,
                requestId: requestId
            )
            return AgentImportPromoteResult(
                ok: remote.ok,
                source: remote.source,
                stagingId: remote.stagingId,
                status: remote.status,
                auditRef: remote.auditRef,
                packageSHA256: remote.packageSHA256,
                scope: remote.scope,
                skillId: remote.skillId,
                previousPackageSHA256: remote.previousPackageSHA256,
                recordPath: remote.recordPath,
                reasonCode: remote.reasonCode
            )
        }

        return AgentImportPromoteResult(
            ok: false,
            source: "file_ipc",
            stagingId: nil,
            status: nil,
            auditRef: nil,
            packageSHA256: nil,
            scope: nil,
            skillId: nil,
            previousPackageSHA256: nil,
            recordPath: nil,
            reasonCode: "skills_promote_file_ipc_not_supported"
        )
    }

    static func requestConnectorIngressReceipts(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> ConnectorIngressSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteConnectorIngressReceipts(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if remote.ok {
                let items = remote.items.map { row in
                    ConnectorIngressReceipt(
                        receiptId: row.receiptId.trimmingCharacters(in: .whitespacesAndNewlines),
                        requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                        projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                        connector: row.connector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        targetId: row.targetId.trimmingCharacters(in: .whitespacesAndNewlines),
                        ingressType: row.ingressType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        channelScope: row.channelScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        sourceId: row.sourceId.trimmingCharacters(in: .whitespacesAndNewlines),
                        messageId: row.messageId.trimmingCharacters(in: .whitespacesAndNewlines),
                        dedupeKey: row.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        receivedAtMs: max(0, row.receivedAtMs),
                        eventSequence: Swift.max(0, row.eventSequence),
                        deliveryState: row.deliveryState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        runtimeState: row.runtimeState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    )
                }
                return ConnectorIngressSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, remote.updatedAtMs),
                    items: items
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalConnectorIngressReceipts(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func requestOperatorChannelXTCommands(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> OperatorChannelXTCommandSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote, !routeDecision.allowFileFallback {
            return nil
        }

        if routeDecision.requiresRemote, !routeDecision.allowFileFallback {
            return nil
        }

        return readLocalOperatorChannelXTCommands(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func requestOperatorChannelXTCommandResults(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> OperatorChannelXTCommandResultSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote, !routeDecision.allowFileFallback {
            return nil
        }

        if routeDecision.requiresRemote, !routeDecision.allowFileFallback {
            return nil
        }

        return readLocalOperatorChannelXTCommandResults(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    @discardableResult
    static func appendOperatorChannelXTCommandResult(
        _ result: OperatorChannelXTCommandResultItem
    ) -> Bool {
        let commandId = result.commandId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandId.isEmpty else { return false }

        let baseDir = HubPaths.baseDir()
        let url = baseDir.appendingPathComponent("operator_channel_xt_command_results_status.json")
        let existing = readLocalOperatorChannelXTCommandResults(projectId: nil, limit: 1_000)
        var deduped: [String: OperatorChannelXTCommandResultItem] = [:]
        for item in existing?.items ?? [] {
            deduped[item.commandId] = item
        }
        deduped[commandId] = result

        let merged = deduped.values.sorted { lhs, rhs in
            let leftTimestamp = max(lhs.completedAtMs, lhs.createdAtMs)
            let rightTimestamp = max(rhs.completedAtMs, rhs.createdAtMs)
            if leftTimestamp != rightTimestamp { return leftTimestamp > rightTimestamp }
            return lhs.commandId.localizedCaseInsensitiveCompare(rhs.commandId) == .orderedAscending
        }

        let payload = OperatorChannelXTCommandResultSnapshot(
            source: "xterminal_operator_channel_result_writer",
            updatedAtMs: max(
                result.completedAtMs,
                result.createdAtMs,
                Date().timeIntervalSince1970 * 1000.0
            ),
            items: Array(merged.prefix(1_000))
        )
        return writeLocalSnapshot(payload, to: url)
    }

    private struct RemoteRuntimeSurfaceOverridesFetchResult {
        var snapshot: RuntimeSurfaceOverridesSnapshot
        var cacheHit: Bool
    }

    private enum RuntimeSurfaceFetchWaitOutcome {
        case completed(RuntimeSurfaceOverridesSnapshot?)
        case timedOut
    }

    private static func runtimeSurfaceInFlightTask(
        for key: HubRemoteRuntimeSurfaceOverrideCache.Key,
        createIfMissing: () -> Task<RuntimeSurfaceOverridesSnapshot?, Never>
    ) -> (task: Task<RuntimeSurfaceOverridesSnapshot?, Never>, isOwner: Bool) {
        runtimeSurfaceFetchLock.lock()
        defer { runtimeSurfaceFetchLock.unlock() }
        if let task = inFlightRuntimeSurfaceOverrideFetches[key] {
            return (task, false)
        }
        let task = createIfMissing()
        inFlightRuntimeSurfaceOverrideFetches[key] = task
        return (task, true)
    }

    private static func clearRuntimeSurfaceInFlightTask(
        for key: HubRemoteRuntimeSurfaceOverrideCache.Key
    ) {
        runtimeSurfaceFetchLock.lock()
        defer { runtimeSurfaceFetchLock.unlock() }
        inFlightRuntimeSurfaceOverrideFetches[key] = nil
    }

    private static func waitForRuntimeSurfaceFetchTask(
        _ task: Task<RuntimeSurfaceOverridesSnapshot?, Never>,
        for key: HubRemoteRuntimeSurfaceOverrideCache.Key,
        cache: HubRemoteRuntimeSurfaceOverrideCache,
        timeoutSec: Double
    ) async -> RuntimeSurfaceOverridesSnapshot? {
        let clampedTimeoutNs = UInt64(
            (max(0.2, min(4.0, timeoutSec)) * 1_000_000_000).rounded()
        )
        let outcome: RuntimeSurfaceFetchWaitOutcome = await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false

            func resumeOnce(_ value: RuntimeSurfaceFetchWaitOutcome) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            Task.detached(priority: .userInitiated) {
                resumeOnce(.completed(await task.value))
            }
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: clampedTimeoutNs)
                resumeOnce(.timedOut)
            }
        }

        switch outcome {
        case .completed(let snapshot):
            return snapshot
        case .timedOut:
            task.cancel()
            clearRuntimeSurfaceInFlightTask(for: key)
            await cache.markMiss(for: key)
            return nil
        }
    }

    private static func resetRuntimeSurfaceRemoteStateForTesting() {
        runtimeSurfaceFetchLock.lock()
        let tasks = Array(inFlightRuntimeSurfaceOverrideFetches.values)
        inFlightRuntimeSurfaceOverrideFetches.removeAll(keepingCapacity: false)
        runtimeSurfaceFetchLock.unlock()
        tasks.forEach { $0.cancel() }
        remoteRuntimeSurfaceOverrideCache = HubRemoteRuntimeSurfaceOverrideCache(
            ttlSeconds: remoteRuntimeSurfaceOverrideCacheTTLSeconds
        )
    }

    private static func fetchRemoteRuntimeSurfaceOverrides(
        projectId: String?,
        limit: Int,
        bypassCache: Bool,
        timeoutSec: Double
    ) async -> RemoteRuntimeSurfaceOverridesFetchResult? {
        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))
        let cache = remoteRuntimeSurfaceOverrideCache
        let cacheKey = HubRemoteRuntimeSurfaceOverrideCache.Key(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
        if !bypassCache, let cached = await cache.snapshot(for: cacheKey) {
            return RemoteRuntimeSurfaceOverridesFetchResult(snapshot: cached, cacheHit: true)
        }
        if !bypassCache, await cache.hasRecentMiss(for: cacheKey) {
            return nil
        }
        let taskFactory = {
            Task<RuntimeSurfaceOverridesSnapshot?, Never> {
            let remote: HubRemoteRuntimeSurfaceOverridesResult
            if let override = remoteRuntimeSurfaceOverridesOverride() {
                remote = await override(normalizedProjectId, boundedLimit, timeoutSec)
            } else {
                remote = await HubPairingCoordinator.shared.fetchRemoteRuntimeSurfaceOverrides(
                    options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                    projectId: normalizedProjectId,
                    limit: boundedLimit,
                    timeoutSec: timeoutSec
                )
            }
            guard remote.ok else {
                await cache.markMiss(for: cacheKey)
                return nil
            }

            let snapshot = RuntimeSurfaceOverridesSnapshot(
                source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                updatedAtMs: max(0, Int64(remote.updatedAtMs.rounded())),
                items: remote.items.map { row in
                    RuntimeSurfaceOverrideItem(
                        projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                        overrideMode: row.overrideMode,
                        updatedAtMs: max(0, Int64(row.updatedAtMs.rounded())),
                        reason: row.reason.trimmingCharacters(in: .whitespacesAndNewlines),
                        auditRef: row.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            )
            await cache.store(snapshot, for: cacheKey)
            return snapshot
        }
        }
        if !bypassCache {
            let inFlight = runtimeSurfaceInFlightTask(for: cacheKey, createIfMissing: taskFactory)
            if !inFlight.isOwner {
                guard let snapshot = await waitForRuntimeSurfaceFetchTask(
                    inFlight.task,
                    for: cacheKey,
                    cache: cache,
                    timeoutSec: timeoutSec
                ) else {
                    return nil
                }
                return RemoteRuntimeSurfaceOverridesFetchResult(snapshot: snapshot, cacheHit: false)
            }
            defer { clearRuntimeSurfaceInFlightTask(for: cacheKey) }
            let snapshot = await waitForRuntimeSurfaceFetchTask(
                inFlight.task,
                for: cacheKey,
                cache: cache,
                timeoutSec: timeoutSec
            )
            guard let snapshot else { return nil }
            return RemoteRuntimeSurfaceOverridesFetchResult(snapshot: snapshot, cacheHit: false)
        }
        let directTask = taskFactory()
        let snapshot = await waitForRuntimeSurfaceFetchTask(
            directTask,
            for: cacheKey,
            cache: cache,
            timeoutSec: timeoutSec
        )
        guard let snapshot else { return nil }
        return RemoteRuntimeSurfaceOverridesFetchResult(snapshot: snapshot, cacheHit: false)
    }

    static func requestRuntimeSurfaceOverrides(
        projectId: String? = nil,
        limit: Int = 200,
        bypassCache: Bool = false,
        timeoutSec: Double = 1.0
    ) async -> RuntimeSurfaceOverridesSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            if let remote = await fetchRemoteRuntimeSurfaceOverrides(
                projectId: normalizedProjectId,
                limit: boundedLimit,
                bypassCache: bypassCache,
                timeoutSec: timeoutSec
            ) {
                return remote.snapshot
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalRuntimeSurfaceOverrides(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    @available(*, deprecated, message: "Use requestRuntimeSurfaceOverrides(projectId:limit:bypassCache:)")
    static func requestAutonomyPolicyOverrides(
        projectId: String? = nil,
        limit: Int = 200,
        bypassCache: Bool = false
    ) async -> AutonomyPolicyOverridesSnapshot? {
        await requestRuntimeSurfaceOverrides(
            projectId: projectId,
            limit: limit,
            bypassCache: bypassCache
        )
    }

    static func requestSecretVaultSnapshot(
        scope: String? = nil,
        namePrefix: String? = nil,
        projectId: String? = nil,
        limit: Int = 200
    ) async -> SecretVaultSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedScope = normalized(scope)?.lowercased()
        let normalizedNamePrefix = normalized(namePrefix)?.lowercased()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSecretVaultItems(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                scope: normalizedScope,
                namePrefix: normalizedNamePrefix,
                limit: boundedLimit
            )
            if remote.ok {
                return SecretVaultSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, Int64(remote.updatedAtMs.rounded())),
                    items: remote.items.map { row in
                        SecretVaultItem(
                            itemId: row.itemId.trimmingCharacters(in: .whitespacesAndNewlines),
                            scope: row.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                            name: row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                            sensitivity: row.sensitivity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                            createdAtMs: max(0, Int64(row.createdAtMs.rounded())),
                            updatedAtMs: max(0, Int64(row.updatedAtMs.rounded()))
                        )
                    }
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        if let snapshot = readLocalSecretVaultSnapshot(
            scope: normalizedScope,
            namePrefix: normalizedNamePrefix,
            projectId: normalizedProjectId,
            limit: boundedLimit
        ) {
            return snapshot
        }

        return await requestSecretVaultSnapshotViaLocalIPC(
            scope: normalizedScope,
            namePrefix: normalizedNamePrefix,
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func createProtectedSecret(
        _ payload: SecretCreateRequestPayload
    ) async -> SecretCreateResult {
        let normalizedScope = normalized(payload.scope)?.lowercased()
        let normalizedName = normalized(payload.name)
        let normalizedPlaintext = normalized(payload.plaintext)
        let normalizedSensitivity = normalized(payload.sensitivity)?.lowercased() ?? "secret"

        guard normalizedScope != nil, normalizedName != nil, normalizedPlaintext != nil else {
            return SecretCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "invalid_request"
            )
        }

        let sanitizedPayload = SecretCreateRequestPayload(
            scope: normalizedScope ?? "",
            name: normalizedName ?? "",
            plaintext: normalizedPlaintext ?? "",
            sensitivity: normalizedSensitivity,
            projectId: normalized(payload.projectId),
            displayName: normalized(payload.displayName),
            reason: normalized(payload.reason)
        )

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.createRemoteSecretVaultItem(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                scope: sanitizedPayload.scope,
                name: sanitizedPayload.name,
                plaintext: sanitizedPayload.plaintext,
                sensitivity: sanitizedPayload.sensitivity,
                projectId: sanitizedPayload.projectId,
                displayName: sanitizedPayload.displayName,
                reason: sanitizedPayload.reason
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return mapSecretVaultCreateResult(remote)
            }
        }

        if routeDecision.requiresRemote {
            return SecretCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return await createProtectedSecretViaLocalIPC(sanitizedPayload)
    }

    static func beginSecretUse(
        _ payload: SecretUseRequestPayload
    ) async -> SecretUseResult {
        let override = secretUseOverrideSnapshotForTesting()
        if let override {
            return await override(payload)
        }

        let normalizedItemId = normalized(payload.itemId)
        let normalizedScope = normalized(payload.scope)?.lowercased()
        let normalizedName = normalized(payload.name)
        let normalizedPurpose = normalized(payload.purpose)

        guard normalizedPurpose != nil,
              normalizedItemId != nil || (normalizedScope != nil && normalizedName != nil) else {
            return SecretUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: nil,
                expiresAtMs: nil,
                reasonCode: "invalid_request"
            )
        }

        let sanitizedPayload = SecretUseRequestPayload(
            itemId: normalizedItemId,
            scope: normalizedScope,
            name: normalizedName,
            projectId: normalized(payload.projectId),
            purpose: normalizedPurpose ?? "",
            target: normalized(payload.target),
            ttlMs: max(1_000, min(600_000, payload.ttlMs))
        )

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.beginRemoteSecretVaultUse(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                itemId: sanitizedPayload.itemId,
                scope: sanitizedPayload.scope,
                name: sanitizedPayload.name,
                projectId: sanitizedPayload.projectId,
                purpose: sanitizedPayload.purpose,
                target: sanitizedPayload.target,
                ttlMs: sanitizedPayload.ttlMs
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return mapSecretVaultUseResult(remote)
            }
        }

        if routeDecision.requiresRemote {
            return SecretUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: sanitizedPayload.itemId,
                expiresAtMs: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return await beginSecretUseViaLocalIPC(sanitizedPayload)
    }

    static func redeemSecretUse(
        _ payload: SecretRedeemRequestPayload
    ) async -> SecretRedeemResult {
        let override = secretRedeemOverrideSnapshotForTesting()
        if let override {
            return await override(payload)
        }

        let normalizedUseToken = normalized(payload.useToken)
        guard normalizedUseToken != nil else {
            return SecretRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "invalid_request"
            )
        }

        let sanitizedPayload = SecretRedeemRequestPayload(
            useToken: normalizedUseToken ?? "",
            projectId: normalized(payload.projectId)
        )

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.redeemRemoteSecretVaultUse(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                useToken: sanitizedPayload.useToken,
                projectId: sanitizedPayload.projectId
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return mapSecretVaultRedeemResult(remote)
            }
        }

        if routeDecision.requiresRemote {
            return SecretRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return await redeemSecretUseViaLocalIPC(sanitizedPayload)
    }

    static func requestProjectRuntimeSurfaceOverride(
        projectId: String,
        bypassCache: Bool = false,
        timeoutSec: Double = 1.0
    ) async -> AXProjectRuntimeSurfaceRemoteOverrideSnapshot? {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return nil }
        if !bypassCache {
            let sharedCache = remoteRuntimeSurfaceOverrideCache
            let sharedCacheKey = HubRemoteRuntimeSurfaceOverrideCache.Key(projectId: nil, limit: 500)
            if let sharedSnapshot = await requestRuntimeSurfaceOverrides(
                projectId: nil,
                limit: 500,
                bypassCache: false,
                timeoutSec: timeoutSec
            ) {
                if let row = sharedSnapshot.items.first(where: { $0.projectId == normalizedProjectId }) {
                    return AXProjectRuntimeSurfaceRemoteOverrideSnapshot(
                        projectId: row.projectId,
                        overrideMode: row.overrideMode,
                        updatedAtMs: row.updatedAtMs,
                        source: sharedSnapshot.source,
                        reason: row.reason.isEmpty ? nil : row.reason,
                        auditRef: row.auditRef.isEmpty ? nil : row.auditRef
                    )
                }
                if sharedSnapshot.items.count < 500 {
                    return nil
                }
            }
            if await sharedCache.hasRecentMiss(for: sharedCacheKey) {
                return nil
            }
        }

        guard let snapshot = await requestRuntimeSurfaceOverrides(
            projectId: normalizedProjectId,
            limit: 1,
            bypassCache: bypassCache,
            timeoutSec: timeoutSec
        ) else {
            return nil
        }
        guard let row = snapshot.items.first(where: { $0.projectId == normalizedProjectId }) else {
            return nil
        }
        return AXProjectRuntimeSurfaceRemoteOverrideSnapshot(
            projectId: row.projectId,
            overrideMode: row.overrideMode,
            updatedAtMs: row.updatedAtMs,
            source: snapshot.source,
            reason: row.reason.isEmpty ? nil : row.reason,
            auditRef: row.auditRef.isEmpty ? nil : row.auditRef
        )
    }

    @available(*, deprecated, message: "Use requestProjectRuntimeSurfaceOverride(projectId:bypassCache:)")
    static func requestProjectAutonomyPolicyOverride(
        projectId: String,
        bypassCache: Bool = false
    ) async -> AXProjectAutonomyRemoteOverrideSnapshot? {
        await requestProjectRuntimeSurfaceOverride(
            projectId: projectId,
            bypassCache: bypassCache
        )
    }

    static func approvePendingGrantRequest(
        grantRequestId: String,
        projectId: String? = nil,
        requestedTtlSec: Int? = nil,
        requestedTokenCap: Int? = nil,
        note: String? = nil
    ) async -> PendingGrantActionResult {
        let normalizedGrantId = normalized(grantRequestId)
        guard let normalizedGrantId else {
            return PendingGrantActionResult(
                ok: false,
                decision: .failed,
                source: "hub_runtime_grpc",
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.approveRemotePendingGrantRequest(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                grantRequestId: normalizedGrantId,
                projectId: normalizedProjectId,
                ttlSec: requestedTtlSec,
                tokenCap: requestedTokenCap,
                note: note
            )
            let result = mapPendingGrantActionResult(remote, defaultGrantRequestId: normalizedGrantId)
            if result.ok {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        let fallbackReason = routeDecision.requiresRemote
            ? (routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing")
            : "pending_grant_action_not_supported"
        return PendingGrantActionResult(
            ok: false,
            decision: .failed,
            source: "hub_runtime_grpc",
            grantRequestId: normalizedGrantId,
            grantId: nil,
            expiresAtMs: nil,
            reasonCode: fallbackReason
        )
    }

    static func denyPendingGrantRequest(
        grantRequestId: String,
        projectId: String? = nil,
        reason: String? = nil
    ) async -> PendingGrantActionResult {
        let normalizedGrantId = normalized(grantRequestId)
        guard let normalizedGrantId else {
            return PendingGrantActionResult(
                ok: false,
                decision: .failed,
                source: "hub_runtime_grpc",
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.denyRemotePendingGrantRequest(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                grantRequestId: normalizedGrantId,
                projectId: normalizedProjectId,
                reason: reason
            )
            let result = mapPendingGrantActionResult(remote, defaultGrantRequestId: normalizedGrantId)
            if result.ok {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        let fallbackReason = routeDecision.requiresRemote
            ? (routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing")
            : "pending_grant_action_not_supported"
        return PendingGrantActionResult(
            ok: false,
            decision: .failed,
            source: "hub_runtime_grpc",
            grantRequestId: normalizedGrantId,
            grantId: nil,
            expiresAtMs: nil,
            reasonCode: fallbackReason
        )
    }

    static func stageSupervisorCandidateReview(
        candidateRequestId: String,
        projectId: String? = nil
    ) async -> SupervisorCandidateReviewStageResult {
        let normalizedCandidateRequestId = normalized(candidateRequestId)
        guard let normalizedCandidateRequestId else {
            return SupervisorCandidateReviewStageResult(
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
                reasonCode: "candidate_request_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.stageRemoteSupervisorCandidateReview(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                candidateRequestId: normalizedCandidateRequestId,
                projectId: normalizedProjectId
            )
            return SupervisorCandidateReviewStageResult(
                ok: remote.ok,
                staged: remote.staged,
                idempotent: remote.idempotent,
                source: remote.source,
                reviewState: remote.reviewState,
                durablePromotionState: remote.durablePromotionState,
                promotionBoundary: remote.promotionBoundary,
                candidateRequestId: remote.candidateRequestId ?? normalizedCandidateRequestId,
                evidenceRef: remote.evidenceRef,
                editSessionId: remote.editSessionId,
                pendingChangeId: remote.pendingChangeId,
                docId: remote.docId,
                baseVersion: remote.baseVersion,
                workingVersion: remote.workingVersion,
                sessionRevision: remote.sessionRevision,
                status: remote.status,
                markdown: remote.markdown,
                createdAtMs: max(0, remote.createdAtMs),
                updatedAtMs: max(0, remote.updatedAtMs),
                expiresAtMs: max(0, remote.expiresAtMs),
                reasonCode: normalizedReasonCode(
                    remote.reasonCode,
                    fallback: remote.ok ? nil : "supervisor_candidate_review_stage_failed"
                )
            )
        }

        let fallbackReason = routeDecision.requiresRemote
            ? normalizedReasonCode(
                routeDecision.remoteUnavailableReasonCode,
                fallback: "hub_env_missing"
            )
            : "supervisor_candidate_review_stage_file_ipc_not_supported"
        return SupervisorCandidateReviewStageResult(
            ok: false,
            staged: false,
            idempotent: false,
            source: routeDecision.requiresRemote ? "hub_memory_v1_grpc" : "file_ipc",
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
            reasonCode: fallbackReason
        )
    }

    static func requestSupervisorBriefProjection(
        _ payload: SupervisorBriefProjectionRequestPayload
    ) async -> SupervisorBriefProjectionResult {
        let normalizedRequestId = normalized(payload.requestId)
        guard let normalizedRequestId else {
            return SupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "request_id_empty"
            )
        }

        let normalizedProjectId = normalized(payload.projectId)
        guard let normalizedProjectId else {
            return SupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "project_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let projectionKind = normalized(payload.projectionKind) ?? "progress_brief"
        let trigger = normalized(payload.trigger) ?? "daily_digest"
        let boundedEvidenceRefs = max(0, min(12, payload.maxEvidenceRefs))

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSupervisorBriefProjection(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestId: normalizedRequestId,
                projectId: normalizedProjectId,
                runId: normalized(payload.runId),
                missionId: normalized(payload.missionId),
                projectionKind: projectionKind,
                trigger: trigger,
                includeTtsScript: payload.includeTtsScript,
                includeCardSummary: payload.includeCardSummary,
                maxEvidenceRefs: boundedEvidenceRefs
            )
            let projection = remote.projection.map { row in
                SupervisorBriefProjectionSnapshot(
                    schemaVersion: row.schemaVersion,
                    projectionId: row.projectionId,
                    projectionKind: row.projectionKind,
                    projectId: row.projectId,
                    runId: row.runId,
                    missionId: row.missionId,
                    trigger: row.trigger,
                    status: row.status,
                    criticalBlocker: row.criticalBlocker,
                    topline: row.topline,
                    nextBestAction: row.nextBestAction,
                    pendingGrantCount: max(0, row.pendingGrantCount),
                    ttsScript: row.ttsScript,
                    cardSummary: row.cardSummary,
                    evidenceRefs: row.evidenceRefs,
                    generatedAtMs: max(0, row.generatedAtMs),
                    expiresAtMs: max(0, row.expiresAtMs),
                    auditRef: row.auditRef
                )
            }
            return SupervisorBriefProjectionResult(
                ok: remote.ok && projection != nil,
                source: remote.source,
                projection: projection,
                reasonCode: normalizedReasonCode(
                    remote.reasonCode,
                    fallback: remote.ok ? nil : "supervisor_brief_projection_failed"
                )
            )
        }

        let fallbackReason = routeDecision.requiresRemote
            ? normalizedReasonCode(
                routeDecision.remoteUnavailableReasonCode,
                fallback: "hub_env_missing"
            )
            : "supervisor_brief_projection_file_ipc_not_supported"
        return SupervisorBriefProjectionResult(
            ok: false,
            source: routeDecision.requiresRemote ? "hub_supervisor_grpc" : "file_ipc",
            projection: nil,
            reasonCode: fallbackReason
        )
    }

    static func requestSupervisorRouteDecision(
        _ payload: SupervisorRouteDecisionRequestPayload
    ) async -> SupervisorRouteDecisionResult {
        let normalizedRequestId = normalized(payload.requestId)
        guard let normalizedRequestId else {
            return SupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: nil,
                governanceRuntimeReadiness: nil,
                reasonCode: "request_id_empty"
            )
        }

        let normalizedProjectId = normalized(payload.projectId)
        guard let normalizedProjectId else {
            return SupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: nil,
                governanceRuntimeReadiness: nil,
                reasonCode: "project_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let surfaceType = normalized(payload.surfaceType) ?? "xt_ui"
        let trustLevel = normalized(payload.trustLevel) ?? "paired_surface"
        let normalizedIntentType = normalized(payload.normalizedIntentType) ?? "directive"

        if routeDecision.preferRemote {
            let remote: HubRemoteSupervisorRouteDecisionResult
            if let override = supervisorRouteDecisionOverride() {
                let result = await override(
                    SupervisorRouteDecisionRequestPayload(
                        requestId: normalizedRequestId,
                        projectId: normalizedProjectId,
                        runId: normalized(payload.runId),
                        missionId: normalized(payload.missionId),
                        surfaceType: surfaceType,
                        trustLevel: trustLevel,
                        normalizedIntentType: normalizedIntentType,
                        preferredDeviceId: normalized(payload.preferredDeviceId),
                        requireXT: payload.requireXT,
                        requireRunner: payload.requireRunner,
                        actorRef: normalized(payload.actorRef),
                        conversationId: normalized(payload.conversationId),
                        threadKey: normalized(payload.threadKey)
                    )
                )
                return result
            } else {
                remote = await HubPairingCoordinator.shared.fetchRemoteSupervisorRouteDecision(
                    options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                    requestId: normalizedRequestId,
                    projectId: normalizedProjectId,
                    runId: normalized(payload.runId),
                    missionId: normalized(payload.missionId),
                    surfaceType: surfaceType,
                    trustLevel: trustLevel,
                    normalizedIntentType: normalizedIntentType,
                    preferredDeviceId: normalized(payload.preferredDeviceId),
                    requireXT: payload.requireXT,
                    requireRunner: payload.requireRunner,
                    actorRef: normalized(payload.actorRef),
                    conversationId: normalized(payload.conversationId),
                    threadKey: normalized(payload.threadKey)
                )
            }

            let route = remote.route.map { row in
                SupervisorRouteDecisionSnapshot(
                    schemaVersion: row.schemaVersion,
                    routeId: row.routeId,
                    requestId: row.requestId,
                    projectId: row.projectId,
                    runId: row.runId,
                    missionId: row.missionId,
                    decision: row.decision,
                    riskTier: row.riskTier,
                    preferredDeviceId: row.preferredDeviceId,
                    resolvedDeviceId: row.resolvedDeviceId,
                    runnerId: row.runnerId,
                    xtOnline: row.xtOnline,
                    runnerRequired: row.runnerRequired,
                    sameProjectScope: row.sameProjectScope,
                    requiresGrant: row.requiresGrant,
                    grantScope: row.grantScope,
                    denyCode: row.denyCode,
                    updatedAtMs: max(0, row.updatedAtMs),
                    auditRef: row.auditRef
                )
            }
            let governanceRuntimeReadiness = remote.governanceRuntimeReadiness.map { row in
                SupervisorRouteGovernanceRuntimeReadinessSnapshot(
                    schemaVersion: row.schemaVersion,
                    source: row.source,
                    governanceSurface: row.governanceSurface,
                    context: row.context,
                    configured: row.configured,
                    state: row.state,
                    runtimeReady: row.runtimeReady,
                    projectId: row.projectId,
                    blockers: row.blockers,
                    blockedComponentKeys: row.blockedComponentKeys,
                    missingReasonCodes: row.missingReasonCodes,
                    summaryLine: row.summaryLine,
                    missingSummaryLine: row.missingSummaryLine,
                    components: row.components.map { component in
                        SupervisorRouteGovernanceComponentSnapshot(
                            key: component.key,
                            state: component.state,
                            denyCode: component.denyCode,
                            summaryLine: component.summaryLine,
                            missingReasonCodes: component.missingReasonCodes
                        )
                    }
                )
            }
            return SupervisorRouteDecisionResult(
                ok: remote.ok && route != nil,
                source: remote.source,
                route: route,
                governanceRuntimeReadiness: governanceRuntimeReadiness,
                reasonCode: normalizedReasonCode(
                    remote.reasonCode,
                    fallback: remote.ok ? nil : "supervisor_route_decision_failed"
                )
            )
        }

        let fallbackReason = routeDecision.requiresRemote
            ? normalizedReasonCode(
                routeDecision.remoteUnavailableReasonCode,
                fallback: "hub_env_missing"
            )
            : "supervisor_route_file_ipc_not_supported"
        return SupervisorRouteDecisionResult(
            ok: false,
            source: routeDecision.requiresRemote ? "hub_supervisor_grpc" : "file_ipc",
            route: nil,
            governanceRuntimeReadiness: nil,
            reasonCode: fallbackReason
        )
    }

    static func issueVoiceGrantChallenge(
        _ payload: VoiceGrantChallengeRequestPayload
    ) async -> VoiceGrantChallengeResult {
        let normalizedRequestId = normalized(payload.requestId)
        guard let normalizedRequestId else {
            return VoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "request_id_empty"
            )
        }

        let normalizedTemplateId = normalized(payload.templateId)
        let normalizedActionDigest = normalized(payload.actionDigest)
        let normalizedScopeDigest = normalized(payload.scopeDigest)
        let normalizedProjectId = normalized(payload.projectId)
        guard normalizedTemplateId != nil, normalizedActionDigest != nil, normalizedScopeDigest != nil else {
            return VoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "invalid_request"
            )
        }

        if let override = voiceGrantChallengeOverride() {
            let result = await override(payload)
            if shouldInvalidateRemoteMemoryForVoiceGrantChallenge(result) {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.issueRemoteVoiceGrantChallenge(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestId: normalizedRequestId,
                projectId: normalizedProjectId,
                templateId: normalizedTemplateId ?? "",
                actionDigest: normalizedActionDigest ?? "",
                scopeDigest: normalizedScopeDigest ?? "",
                amountDigest: normalized(payload.amountDigest),
                challengeCode: normalized(payload.challengeCode),
                riskLevel: normalized(payload.riskLevel) ?? "high",
                boundDeviceId: normalized(payload.boundDeviceId),
                mobileTerminalId: normalized(payload.mobileTerminalId),
                allowVoiceOnly: payload.allowVoiceOnly,
                requiresMobileConfirm: payload.requiresMobileConfirm,
                ttlMs: max(10_000, min(600_000, payload.ttlMs))
            )
            let result = mapVoiceGrantChallengeResult(remote)
            if shouldInvalidateRemoteMemoryForVoiceGrantChallenge(result) {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        if routeDecision.requiresRemote {
            return VoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return VoiceGrantChallengeResult(
            ok: false,
            source: "file_ipc",
            challenge: nil,
            reasonCode: "voice_grant_file_ipc_not_supported"
        )
    }

    static func verifyVoiceGrantResponse(
        _ payload: VoiceGrantVerificationPayload
    ) async -> VoiceGrantVerificationResult {
        let normalizedRequestId = normalized(payload.requestId)
        guard let normalizedRequestId else {
            return VoiceGrantVerificationResult(
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
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "request_id_empty"
            )
        }

        let normalizedChallengeId = normalized(payload.challengeId)
        let normalizedProjectId = normalized(payload.projectId)
        guard let normalizedChallengeId else {
            return VoiceGrantVerificationResult(
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
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "challenge_id_empty"
            )
        }

        let normalizedVerifyNonce = normalized(payload.verifyNonce)
        guard let normalizedVerifyNonce else {
            return VoiceGrantVerificationResult(
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
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "verify_nonce_empty"
            )
        }

        if let override = voiceGrantVerificationOverride() {
            let result = await override(payload)
            if shouldInvalidateRemoteMemoryForVoiceGrantVerification(result) {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.verifyRemoteVoiceGrantResponse(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestId: normalizedRequestId,
                projectId: normalizedProjectId,
                challengeId: normalizedChallengeId,
                challengeCode: normalized(payload.challengeCode),
                transcript: payload.transcript,
                transcriptHash: normalized(payload.transcriptHash),
                semanticMatchScore: payload.semanticMatchScore,
                parsedActionDigest: normalized(payload.parsedActionDigest),
                parsedScopeDigest: normalized(payload.parsedScopeDigest),
                parsedAmountDigest: normalized(payload.parsedAmountDigest),
                verifyNonce: normalizedVerifyNonce,
                boundDeviceId: normalized(payload.boundDeviceId),
                mobileConfirmed: payload.mobileConfirmed
            )
            let result = mapVoiceGrantVerificationResult(remote)
            if shouldInvalidateRemoteMemoryForVoiceGrantVerification(result) {
                await noteRemoteMemoryGrantStateChanged(projectId: normalizedProjectId)
            }
            return result
        }

        if routeDecision.requiresRemote {
            return VoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: payload.semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return VoiceGrantVerificationResult(
            ok: false,
            verified: false,
            decision: .failed,
            source: "file_ipc",
            denyCode: nil,
            challengeId: normalizedChallengeId,
            transcriptHash: nil,
            semanticMatchScore: payload.semanticMatchScore ?? 0,
            challengeMatch: false,
            deviceBindingOK: false,
            mobileConfirmed: payload.mobileConfirmed,
            reasonCode: "voice_grant_file_ipc_not_supported"
        )
    }

    private static func requestMemoryContextViaLocalIPC(
        payload: MemoryContextPayload,
        timeoutSec: Double
    ) async -> LocalMemoryContextIPCResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return LocalMemoryContextIPCResult(
                response: nil,
                reasonCode: "hub_not_connected",
                detail: nil
            )
        }

        let reqId = UUID().uuidString
        let req = MemoryContextIPCRequest(type: "memory_context", reqId: reqId, memoryContext: payload)

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: "memory_context_encode_failed",
                    detail: summarized(error)
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_mem",
                tmpPrefix: ".xterminal_mem",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: "memory_context_write_failed",
                    detail: normalized(writeStatus.requestError)
                )
            }

            guard let ack = await pollMemoryContextResponse(
                baseDir: transport.baseDir,
                reqId: reqId,
                timeoutSec: timeoutSec
            ) else {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: "ack_timeout",
                    detail: "memory context ack timeout"
                )
            }
            guard ack.ok else {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: normalizedReasonCode(ack.error, fallback: "memory_context_failed"),
                    detail: normalized(ack.error)
                )
            }
            return LocalMemoryContextIPCResult(
                response: ack.memoryContext,
                reasonCode: nil,
                detail: nil
            )
        case "socket":
            guard let ack: MemoryContextIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: "socket_request_failed",
                    detail: "memory context socket request failed"
                )
            }
            guard ack.ok else {
                return LocalMemoryContextIPCResult(
                    response: nil,
                    reasonCode: normalizedReasonCode(ack.error, fallback: "memory_context_failed"),
                    detail: normalized(ack.error)
                )
            }
            return LocalMemoryContextIPCResult(
                response: ack.memoryContext,
                reasonCode: nil,
                detail: nil
            )
        default:
            return LocalMemoryContextIPCResult(
                response: nil,
                reasonCode: "unsupported_ipc_mode",
                detail: "memory context local IPC mode unsupported"
            )
        }
    }

    private static func requestMemoryRetrievalViaLocalIPC(
        payload: MemoryRetrievalPayload,
        timeoutSec: Double
    ) async -> MemoryRetrievalResponsePayload? {
        if let override = localMemoryRetrievalIPCOverride() {
            return await override(payload, timeoutSec)
        }
        guard let transport = localIPCTransport(ttl: 3.0) else { return nil }

        let reqId = UUID().uuidString
        let req = MemoryRetrievalIPCRequest(
            type: "memory_retrieval",
            reqId: reqId,
            memoryRetrieval: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "file_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: "memory_retrieval_encode_failed",
                    detail: summarized(error),
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_mem_retrieval",
                tmpPrefix: ".xterminal_mem_retrieval",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "file_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: "memory_retrieval_write_failed",
                    detail: normalized(writeStatus.requestError),
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }

            guard let ack = await pollMemoryRetrievalResponse(
                baseDir: transport.baseDir,
                reqId: reqId,
                timeoutSec: timeoutSec
            ) else {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "file_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: "ack_timeout",
                    detail: "memory retrieval ack timeout",
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }
            guard ack.ok else {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "file_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: normalizedReasonCode(ack.error, fallback: "memory_retrieval_failed"),
                    detail: normalized(ack.error),
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }
            return ack.memoryRetrieval
        case "socket":
            guard let ack: MemoryContextIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "socket_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: "socket_request_failed",
                    detail: "memory retrieval socket request failed",
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }
            guard ack.ok else {
                return MemoryRetrievalResponsePayload(
                    requestId: payload.requestId,
                    status: "error",
                    resolvedScope: payload.scope,
                    source: "socket_ipc",
                    scope: payload.scope,
                    auditRef: payload.auditRef,
                    reasonCode: normalizedReasonCode(ack.error, fallback: "memory_retrieval_failed"),
                    detail: normalized(ack.error),
                    snippets: [],
                    truncated: false,
                    budgetUsedChars: 0,
                    truncatedItems: 0,
                    redactedItems: 0
                )
            }
            return ack.memoryRetrieval
        default:
            return MemoryRetrievalResponsePayload(
                requestId: payload.requestId,
                status: "error",
                resolvedScope: payload.scope,
                source: "local_ipc",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "unsupported_ipc_mode",
                detail: "memory retrieval local IPC mode unsupported",
                snippets: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0
            )
        }
    }

    private static func requestVoiceTTSReadinessViaLocalIPC(
        preferredModelID: String,
        timeoutSec: Double
    ) -> VoiceTTSReadinessResult {
        let normalizedPreferredModelID = normalized(preferredModelID)
        guard let normalizedPreferredModelID else {
            return VoiceTTSReadinessResult(
                ok: false,
                source: "local_ipc",
                provider: nil,
                modelId: nil,
                reasonCode: "voice_tts_missing_model_id",
                detail: "preferred_model_id is required"
            )
        }

        guard let transport = localIPCTransport(ttl: 3.0) else {
            return VoiceTTSReadinessResult(
                ok: false,
                source: "local_ipc",
                provider: nil,
                modelId: normalizedPreferredModelID,
                reasonCode: "hub_not_connected",
                detail: "voice TTS readiness local IPC unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = VoiceTTSReadinessIPCRequest(
            type: "voice_tts_readiness",
            reqId: reqId,
            voiceTTSReadiness: VoiceTTSReadinessRequestPayload(
                preferredModelId: normalizedPreferredModelID
            )
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return VoiceTTSReadinessResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalizedPreferredModelID,
                    reasonCode: "voice_tts_readiness_encode_failed",
                    detail: summarized(error)
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_voice_tts_readiness",
                tmpPrefix: ".xterminal_voice_tts_readiness",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return VoiceTTSReadinessResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalizedPreferredModelID,
                    reasonCode: "voice_tts_readiness_write_failed",
                    detail: normalized(writeStatus.requestError) ?? "voice TTS readiness request write failed"
                )
            }
            guard let ack = Self.pollVoiceTTSReadinessResponse(
                baseDir: transport.baseDir,
                reqId: reqId,
                timeoutSec: timeoutSec
            ) else {
                return VoiceTTSReadinessResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalizedPreferredModelID,
                    reasonCode: "ack_timeout",
                    detail: "voice TTS readiness ack timeout"
                )
            }
            return mapVoiceTTSReadinessAck(ack, source: "file_ipc", fallbackModelID: normalizedPreferredModelID)
        case "socket":
            guard let ack: VoiceTTSReadinessIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return VoiceTTSReadinessResult(
                    ok: false,
                    source: "socket_ipc",
                    provider: nil,
                    modelId: normalizedPreferredModelID,
                    reasonCode: "ack_timeout",
                    detail: "voice TTS readiness ack timeout"
                )
            }
            return mapVoiceTTSReadinessAck(ack, source: "socket_ipc", fallbackModelID: normalizedPreferredModelID)
        default:
            return VoiceTTSReadinessResult(
                ok: false,
                source: "local_ipc",
                provider: nil,
                modelId: normalizedPreferredModelID,
                reasonCode: "unsupported_ipc_mode",
                detail: "voice TTS readiness local IPC mode unsupported"
            )
        }
    }

    private static func requestVoiceTTSSynthesisViaLocalIPC(
        _ payload: VoiceTTSRequestPayload,
        timeoutSec: Double
    ) -> VoiceTTSResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return VoiceTTSResult(
                ok: false,
                source: "local_ipc",
                provider: nil,
                modelId: normalized(payload.preferredModelId),
                taskKind: "text_to_speech",
                audioFilePath: nil,
                reasonCode: "hub_not_connected",
                runtimeReasonCode: nil,
                error: nil,
                detail: "voice TTS local IPC unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = VoiceTTSIPCRequest(
            type: "voice_tts_synthesize",
            reqId: reqId,
            voiceTTS: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return VoiceTTSResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalized(payload.preferredModelId),
                    taskKind: "text_to_speech",
                    audioFilePath: nil,
                    reasonCode: "voice_tts_encode_failed",
                    runtimeReasonCode: nil,
                    error: summarized(error),
                    detail: "voice TTS request encoding failed"
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_voice_tts",
                tmpPrefix: ".xterminal_voice_tts",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return VoiceTTSResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalized(payload.preferredModelId),
                    taskKind: "text_to_speech",
                    audioFilePath: nil,
                    reasonCode: "voice_tts_write_failed",
                    runtimeReasonCode: nil,
                    error: normalized(writeStatus.requestError),
                    detail: "voice TTS request write failed"
                )
            }
            guard let ack = pollVoiceTTSResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: timeoutSec) else {
                return VoiceTTSResult(
                    ok: false,
                    source: "file_ipc",
                    provider: nil,
                    modelId: normalized(payload.preferredModelId),
                    taskKind: "text_to_speech",
                    audioFilePath: nil,
                    reasonCode: "ack_timeout",
                    runtimeReasonCode: nil,
                    error: nil,
                    detail: "voice TTS ack timeout"
                )
            }
            return mapVoiceTTSAck(ack, source: "file_ipc", fallbackModelID: payload.preferredModelId)
        case "socket":
            guard let ack: VoiceTTSIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return VoiceTTSResult(
                    ok: false,
                    source: "socket_ipc",
                    provider: nil,
                    modelId: normalized(payload.preferredModelId),
                    taskKind: "text_to_speech",
                    audioFilePath: nil,
                    reasonCode: "socket_request_failed",
                    runtimeReasonCode: nil,
                    error: nil,
                    detail: "voice TTS socket request failed"
                )
            }
            return mapVoiceTTSAck(ack, source: "socket_ipc", fallbackModelID: payload.preferredModelId)
        default:
            return VoiceTTSResult(
                ok: false,
                source: "local_ipc",
                provider: nil,
                modelId: normalized(payload.preferredModelId),
                taskKind: "text_to_speech",
                audioFilePath: nil,
                reasonCode: "unsupported_ipc_mode",
                runtimeReasonCode: nil,
                error: nil,
                detail: "voice TTS local IPC mode unsupported"
            )
        }
    }

    private static func requestLocalTaskExecutionViaLocalIPC(
        _ payload: LocalTaskRequestPayload,
        timeoutSec: Double
    ) -> LocalTaskResult {
        if let override = withTestingOverrideLock({ localTaskExecutionOverrideForTesting }) {
            return override(payload, timeoutSec)
        }

        let normalizedTaskKind = normalized(payload.taskKind)
        let normalizedModelID = normalized(payload.modelId)

        guard let transport = localIPCTransport(ttl: 3.0) else {
            return LocalTaskResult(
                ok: false,
                source: "local_ipc",
                runtimeSource: nil,
                provider: nil,
                modelId: normalizedModelID,
                taskKind: normalizedTaskKind,
                reasonCode: "hub_not_connected",
                runtimeReasonCode: nil,
                error: nil,
                detail: "local task IPC unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = LocalTaskIPCRequest(
            type: "local_task_execute",
            reqId: reqId,
            localTask: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return LocalTaskResult(
                    ok: false,
                    source: "file_ipc",
                    runtimeSource: nil,
                    provider: nil,
                    modelId: normalizedModelID,
                    taskKind: normalizedTaskKind,
                    reasonCode: "local_task_encode_failed",
                    runtimeReasonCode: nil,
                    error: summarized(error),
                    detail: "local task request encoding failed"
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_local_task",
                tmpPrefix: ".xterminal_local_task",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return LocalTaskResult(
                    ok: false,
                    source: "file_ipc",
                    runtimeSource: nil,
                    provider: nil,
                    modelId: normalizedModelID,
                    taskKind: normalizedTaskKind,
                    reasonCode: "local_task_write_failed",
                    runtimeReasonCode: nil,
                    error: normalized(writeStatus.requestError),
                    detail: "local task request write failed"
                )
            }
            guard let ack = pollLocalTaskResponse(
                baseDir: transport.baseDir,
                reqId: reqId,
                timeoutSec: timeoutSec
            ) else {
                return LocalTaskResult(
                    ok: false,
                    source: "file_ipc",
                    runtimeSource: nil,
                    provider: nil,
                    modelId: normalizedModelID,
                    taskKind: normalizedTaskKind,
                    reasonCode: "ack_timeout",
                    runtimeReasonCode: nil,
                    error: nil,
                    detail: "local task ack timeout"
                )
            }
            return mapLocalTaskAck(
                ack,
                source: "file_ipc",
                fallbackModelID: payload.modelId,
                fallbackTaskKind: payload.taskKind
            )
        case "socket":
            guard let ack: LocalTaskIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return LocalTaskResult(
                    ok: false,
                    source: "socket_ipc",
                    runtimeSource: nil,
                    provider: nil,
                    modelId: normalizedModelID,
                    taskKind: normalizedTaskKind,
                    reasonCode: "socket_request_failed",
                    runtimeReasonCode: nil,
                    error: nil,
                    detail: "local task socket request failed"
                )
            }
            return mapLocalTaskAck(
                ack,
                source: "socket_ipc",
                fallbackModelID: payload.modelId,
                fallbackTaskKind: payload.taskKind
            )
        default:
            return LocalTaskResult(
                ok: false,
                source: "local_ipc",
                runtimeSource: nil,
                provider: nil,
                modelId: normalizedModelID,
                taskKind: normalizedTaskKind,
                reasonCode: "unsupported_ipc_mode",
                runtimeReasonCode: nil,
                error: nil,
                detail: "local task IPC mode unsupported"
            )
        }
    }

    private static func fetchVoiceWakeProfileViaLocalIPC(
        desiredWakeMode: VoiceWakeMode
    ) async -> VoiceWakeProfileSyncResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "hub_not_connected",
                logLines: ["voice wake profile fetch local IPC unavailable"],
                syncedAtMs: nil
            )
        }

        let reqId = UUID().uuidString
        let req = VoiceWakeProfileGetIPCRequest(
            type: "voice_wake_profile_get",
            reqId: reqId,
            voiceWakeProfileRequest: VoiceWakeProfileRequestPayload(desiredWakeMode: desiredWakeMode.rawValue)
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_write_failed",
                    logLines: ["voice wake profile get request encode failed: \(summarized(error))"],
                    syncedAtMs: nil
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_voicewake_get",
                tmpPrefix: ".xterminal_voicewake_get",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_write_failed",
                    logLines: ["voice wake profile get request write failed: \(writeStatus.requestError)"],
                    syncedAtMs: nil
                )
            }

            guard let ack = await pollVoiceWakeProfileResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "ack_timeout",
                    logLines: ["voice wake profile get ack timeout"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "file_ipc", verb: "get")
        case "socket":
            guard let ack: VoiceWakeProfileIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "socket_ipc",
                    profile: nil,
                    reasonCode: "socket_request_failed",
                    logLines: ["voice wake profile get socket request failed"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "socket_ipc", verb: "get")
        default:
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "unsupported_ipc_mode",
                logLines: ["voice wake profile fetch local IPC mode unsupported"],
                syncedAtMs: nil
            )
        }
    }

    private static func setVoiceWakeProfileViaLocalIPC(
        _ profile: VoiceWakeProfile
    ) async -> VoiceWakeProfileSyncResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "hub_not_connected",
                logLines: ["voice wake profile set local IPC unavailable"],
                syncedAtMs: nil
            )
        }

        let reqId = UUID().uuidString
        let req = VoiceWakeProfileSetIPCRequest(
            type: "voice_wake_profile_set",
            reqId: reqId,
            voiceWakeProfile: profile.sanitized()
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let data: Data
            do {
                data = try JSONEncoder().encode(req)
            } catch {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_write_failed",
                    logLines: ["voice wake profile set request encode failed: \(summarized(error))"],
                    syncedAtMs: nil
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_voicewake_set",
                tmpPrefix: ".xterminal_voicewake_set",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_write_failed",
                    logLines: ["voice wake profile set request write failed: \(writeStatus.requestError)"],
                    syncedAtMs: nil
                )
            }

            guard let ack = await pollVoiceWakeProfileResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "ack_timeout",
                    logLines: ["voice wake profile set ack timeout"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "file_ipc", verb: "set")
        case "socket":
            guard let ack: VoiceWakeProfileIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "socket_ipc",
                    profile: nil,
                    reasonCode: "socket_request_failed",
                    logLines: ["voice wake profile set socket request failed"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "socket_ipc", verb: "set")
        default:
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "unsupported_ipc_mode",
                logLines: ["voice wake profile set local IPC mode unsupported"],
                syncedAtMs: nil
            )
        }
    }

    private static func requestSecretVaultSnapshotViaLocalIPC(
        scope: String?,
        namePrefix: String?,
        projectId: String?,
        limit: Int
    ) async -> SecretVaultSnapshot? {
        guard let transport = localIPCTransport(ttl: 3.0) else { return nil }

        let reqId = UUID().uuidString
        let req = SecretVaultListIPCRequest(
            type: "secret_vault_list",
            reqId: reqId,
            secretVaultList: SecretVaultListRequestPayload(
                scope: scope,
                namePrefix: namePrefix,
                projectId: projectId,
                limit: max(1, min(500, limit))
            )
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(req),
                  writeEvent(
                    data: data,
                    reqId: reqId,
                    filePrefix: "xterminal_secret_vault_list",
                    tmpPrefix: ".xterminal_secret_vault_list",
                    in: transport.ipcURL
                  ),
                  let ack = await pollSecretVaultListResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0),
                  ack.ok,
                  let snapshot = ack.secretVaultSnapshot else {
                return nil
            }
            return snapshot
        case "socket":
            guard let ack: SecretVaultListIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0),
                  ack.ok,
                  let snapshot = ack.secretVaultSnapshot else {
                return nil
            }
            return snapshot
        default:
            return nil
        }
    }

    private static func createProtectedSecretViaLocalIPC(
        _ payload: SecretCreateRequestPayload
    ) async -> SecretCreateResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return SecretCreateResult(
                ok: false,
                source: "local_ipc",
                item: nil,
                reasonCode: "secret_vault_local_ipc_unavailable"
            )
        }

        if transport.mode == "file" {
            return SecretCreateResult(
                ok: false,
                source: "file_ipc",
                item: nil,
                reasonCode: "secret_vault_secure_capture_requires_socket_ipc"
            )
        }

        let req = SecretVaultCreateIPCRequest(
            type: "secret_vault_create",
            reqId: UUID().uuidString,
            secretVaultCreate: payload
        )

        guard let ack: SecretVaultCreateIPCResponse = sendSocketRequest(
            req,
            socketURL: transport.ipcURL,
            timeoutSec: 3.0
        ) else {
            return SecretCreateResult(
                ok: false,
                source: "socket_ipc",
                item: nil,
                reasonCode: "socket_request_failed"
            )
        }

        guard ack.ok else {
            return SecretCreateResult(
                ok: false,
                source: "socket_ipc",
                item: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "secret_vault_create_failed")
            )
        }

        guard let item = ack.secretVaultItem else {
            return SecretCreateResult(
                ok: false,
                source: "socket_ipc",
                item: nil,
                reasonCode: "secret_vault_item_missing"
            )
        }

        return SecretCreateResult(
            ok: true,
            source: "socket_ipc",
            item: item,
            reasonCode: nil
        )
    }

    private static func beginSecretUseViaLocalIPC(
        _ payload: SecretUseRequestPayload
    ) async -> SecretUseResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return SecretUseResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                useToken: nil,
                itemId: payload.itemId,
                expiresAtMs: nil,
                reasonCode: "secret_vault_local_ipc_unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = SecretVaultBeginUseIPCRequest(
            type: "secret_vault_begin_use",
            reqId: reqId,
            secretVaultUse: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(req) else {
                return SecretUseResult(
                    ok: false,
                    source: "file_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "secret_vault_use_encode_failed",
                    detail: "secret vault use request encoding failed"
                )
            }
            let writeStatus = Self.writeEventStatus(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_secret_vault_use",
                tmpPrefix: ".xterminal_secret_vault_use",
                in: transport.ipcURL
            )
            guard writeStatus.requestQueued == true else {
                return SecretUseResult(
                    ok: false,
                    source: "file_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "secret_vault_use_write_failed",
                    detail: normalized(writeStatus.requestError)
                )
            }
            guard let ack = await pollSecretVaultUseResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0) else {
                return SecretUseResult(
                    ok: false,
                    source: "file_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "ack_timeout",
                    detail: "secret vault use ack timeout"
                )
            }
            return mapSecretVaultUseAck(ack, source: "file_ipc", fallbackItemId: payload.itemId)
        case "socket":
            guard let ack: SecretVaultUseIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return SecretUseResult(
                    ok: false,
                    source: "socket_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "socket_request_failed",
                    detail: "secret vault use socket request failed"
                )
            }
            return mapSecretVaultUseAck(ack, source: "socket_ipc", fallbackItemId: payload.itemId)
        default:
            return SecretUseResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                useToken: nil,
                itemId: payload.itemId,
                expiresAtMs: nil,
                reasonCode: "unsupported_ipc_mode",
                detail: "secret vault use local IPC mode unsupported"
            )
        }
    }

    private static func redeemSecretUseViaLocalIPC(
        _ payload: SecretRedeemRequestPayload
    ) async -> SecretRedeemResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return SecretRedeemResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "secret_vault_local_ipc_unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = SecretVaultRedeemIPCRequest(
            type: "secret_vault_redeem_use",
            reqId: reqId,
            secretVaultRedeem: payload
        )

        switch transport.mode {
        case "file":
            return SecretRedeemResult(
                ok: false,
                source: "file_ipc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "secret_vault_redeem_requires_socket_ipc",
                detail: "secret vault redeem requires socket IPC"
            )
        case "socket":
            guard let ack: SecretVaultRedeemIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return SecretRedeemResult(
                    ok: false,
                    source: "socket_ipc",
                    leaseId: nil,
                    itemId: nil,
                    plaintext: nil,
                    reasonCode: "socket_request_failed",
                    detail: "secret vault redeem socket request failed"
                )
            }
            return mapSecretVaultRedeemAck(ack, source: "socket_ipc")
        default:
            return SecretRedeemResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "unsupported_ipc_mode",
                detail: "secret vault redeem local IPC mode unsupported"
            )
        }
    }

    private static func mapVoiceWakeProfileAck(
        _ ack: VoiceWakeProfileIPCResponse,
        source: String,
        verb: String
    ) -> VoiceWakeProfileSyncResult {
        guard ack.ok else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: source,
                profile: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "voice_wake_profile_\(verb)_failed"),
                logLines: ["voice wake profile \(verb) failed: \(ack.error ?? "unknown_error")"],
                syncedAtMs: nil
            )
        }
        guard let profile = ack.voiceWakeProfile else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: source,
                profile: nil,
                reasonCode: "voice_wake_profile_missing",
                logLines: ["voice wake profile \(verb) missing payload"],
                syncedAtMs: nil
            )
        }
        return VoiceWakeProfileSyncResult(
            ok: true,
            source: source,
            profile: profile,
            reasonCode: nil,
            logLines: ["voice wake profile \(verb) succeeded via \(source)"],
            syncedAtMs: profile.updatedAtMs
        )
    }

    private static func mapVoiceTTSReadinessAck(
        _ ack: VoiceTTSReadinessIPCResponse,
        source: String,
        fallbackModelID: String
    ) -> VoiceTTSReadinessResult {
        if let result = ack.voiceTTSReadiness {
            return VoiceTTSReadinessResult(
                ok: result.ok,
                source: source,
                provider: result.provider,
                modelId: result.modelId ?? normalized(fallbackModelID),
                reasonCode: result.reasonCode ?? (!ack.ok ? normalizedReasonCode(ack.error, fallback: "voice_tts_readiness_failed") : nil),
                detail: result.detail ?? (!ack.ok ? ack.error : nil)
            )
        }

        return VoiceTTSReadinessResult(
            ok: false,
            source: source,
            provider: nil,
            modelId: normalized(fallbackModelID),
            reasonCode: normalizedReasonCode(ack.error, fallback: "voice_tts_readiness_missing_payload"),
            detail: "voice TTS readiness response payload missing"
        )
    }

    private static func mapVoiceTTSAck(
        _ ack: VoiceTTSIPCResponse,
        source: String,
        fallbackModelID: String
    ) -> VoiceTTSResult {
        if let result = ack.voiceTTS {
            return VoiceTTSResult(
                ok: result.ok,
                source: source,
                provider: result.provider,
                modelId: result.modelId ?? normalized(fallbackModelID),
                taskKind: result.taskKind ?? "text_to_speech",
                audioFilePath: result.audioFilePath,
                audioFormat: result.audioFormat,
                voiceName: result.voiceName,
                engineName: result.engineName,
                speakerId: result.speakerId,
                deviceBackend: result.deviceBackend,
                nativeTTSUsed: result.nativeTTSUsed,
                fallbackMode: result.fallbackMode,
                fallbackReasonCode: result.fallbackReasonCode,
                reasonCode: result.reasonCode ?? (!ack.ok ? normalizedReasonCode(ack.error, fallback: "voice_tts_failed") : nil),
                runtimeReasonCode: result.runtimeReasonCode,
                error: result.error ?? (!ack.ok ? ack.error : nil),
                detail: result.detail,
                ttsAudit: result.ttsAudit,
                ttsAuditLine: result.ttsAuditLine
            )
        }

        return VoiceTTSResult(
            ok: false,
            source: source,
            provider: nil,
            modelId: normalized(fallbackModelID),
            taskKind: "text_to_speech",
            audioFilePath: nil,
            reasonCode: normalizedReasonCode(ack.error, fallback: "voice_tts_missing_payload"),
            runtimeReasonCode: nil,
            error: ack.error,
            detail: "voice TTS response payload missing"
        )
    }

    private static func mapLocalTaskAck(
        _ ack: LocalTaskIPCResponse,
        source: String,
        fallbackModelID: String,
        fallbackTaskKind: String
    ) -> LocalTaskResult {
        if let result = ack.localTask {
            return LocalTaskResult(
                ok: result.ok,
                source: source,
                runtimeSource: result.runtimeSource ?? normalized(result.source),
                provider: result.provider,
                modelId: result.modelId ?? normalized(fallbackModelID),
                taskKind: result.taskKind ?? normalized(fallbackTaskKind),
                reasonCode: result.reasonCode ?? (!ack.ok ? normalizedReasonCode(ack.error, fallback: "local_task_failed") : nil),
                runtimeReasonCode: result.runtimeReasonCode,
                error: result.error ?? (!ack.ok ? ack.error : nil),
                detail: result.detail,
                payload: result.payload
            )
        }

        return LocalTaskResult(
            ok: false,
            source: source,
            runtimeSource: nil,
            provider: nil,
            modelId: normalized(fallbackModelID),
            taskKind: normalized(fallbackTaskKind),
            reasonCode: normalizedReasonCode(ack.error, fallback: "local_task_missing_payload"),
            runtimeReasonCode: nil,
            error: ack.error,
            detail: "local task response payload missing",
            payload: [:]
        )
    }

    private static func buildMemoryContextFromRemoteSnapshot(
        snapshot: HubRemoteMemorySnapshotResult,
        payload: MemoryContextPayload
    ) -> MemoryContextResponsePayload {
        let servingProfile = normalized(payload.servingProfile)
        let reviewLevelHint = normalizedReviewLevelHint(payload.reviewLevelHint)
        let useMode = XTMemoryUseMode.parse(payload.mode) ?? .projectChat
        let disclosure = resolveMemoryLongtermDisclosure(
            useMode: useMode,
            retrievalAvailable: defaultRetrievalAvailability(for: useMode)
        )
        let localCanonical = XTMemorySanitizer.sanitizeText(payload.canonicalText, maxChars: 3_200, lineCap: 36) ?? ""
        let localObservations = XTMemorySanitizer.sanitizeText(payload.observationsText, maxChars: 1_800, lineCap: 24) ?? ""
        let localWorking = XTMemorySanitizer.sanitizeText(payload.workingSetText, maxChars: 2_600, lineCap: 28) ?? ""
        let dialogueWindow = XTMemorySanitizer.sanitizeText(payload.dialogueWindowText, maxChars: 4_800, lineCap: 80) ?? ""
        let portfolioBrief = XTMemorySanitizer.sanitizeText(payload.portfolioBriefText, maxChars: 900, lineCap: 16) ?? ""
        let focusedProjectAnchorPack = XTMemorySanitizer.sanitizeText(payload.focusedProjectAnchorPackText, maxChars: 1_400, lineCap: 24) ?? ""
        let longtermOutline = XTMemorySanitizer.sanitizeText(payload.longtermOutlineText, maxChars: 1_200, lineCap: 20) ?? ""
        let deltaFeed = XTMemorySanitizer.sanitizeText(payload.deltaFeedText, maxChars: 700, lineCap: 14) ?? ""
        let conflictSet = XTMemorySanitizer.sanitizeText(payload.conflictSetText, maxChars: 700, lineCap: 16) ?? ""
        let contextRefs = XTMemorySanitizer.sanitizeText(payload.contextRefsText, maxChars: 900, lineCap: 16) ?? ""
        let evidencePack = XTMemorySanitizer.sanitizeText(payload.evidencePackText, maxChars: 1_200, lineCap: 18) ?? ""
        let rawEvidence = XTMemorySanitizer.sanitizeRawEvidenceSummary(payload.rawEvidenceText, maxChars: 1_100, lineCap: 18) ?? ""
        let constitution = XTMemorySanitizer.sanitizeText(payload.constitutionHint, maxChars: 320, lineCap: 6)
            ?? "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"

        let remoteCanonical = XTMemorySanitizer.sanitizeText(snapshot.canonicalEntries.joined(separator: "\n"), maxChars: 3_200, lineCap: 36) ?? ""
        let remoteWorking = XTMemorySanitizer.sanitizeText(snapshot.workingEntries.joined(separator: "\n"), maxChars: 2_400, lineCap: 24) ?? ""

        let mergedCanonical = mergedMemoryLayer(localPrimary: localCanonical, remoteSecondary: remoteCanonical)
        let mergedWorking = mergedMemoryLayer(localPrimary: localWorking, remoteSecondary: remoteWorking)
        let servingProfileSection = memoryServingProfileSection(servingProfile)
        let servingGovernorSection = memoryServingGovernorSection(
            useMode: useMode,
            servingProfile: servingProfile,
            reviewLevelHint: reviewLevelHint,
            hasFocusedProjectAnchor: !focusedProjectAnchorPack.isEmpty
        )
        let dialogueWindowSection = namedMemorySection("DIALOGUE_WINDOW", body: dialogueWindow)
        let portfolioBriefSection = namedMemorySection("PORTFOLIO_BRIEF", body: portfolioBrief)
        let focusedProjectAnchorPackSection = namedMemorySection("FOCUSED_PROJECT_ANCHOR_PACK", body: focusedProjectAnchorPack)
        let longtermOutlineSection = namedMemorySection("LONGTERM_OUTLINE", body: longtermOutline)
        let deltaFeedSection = namedMemorySection("DELTA_FEED", body: deltaFeed)
        let conflictSetSection = namedMemorySection("CONFLICT_SET", body: conflictSet)
        let contextRefsSection = namedMemorySection("CONTEXT_REFS", body: contextRefs)
        let evidencePackSection = namedMemorySection("EVIDENCE_PACK", body: evidencePack)

        let finalText = ensureMemoryLongtermDisclosureText(
            """
[MEMORY_V1]
\(servingProfileSection.isEmpty ? "" : "\(servingProfileSection)\n")
\(servingGovernorSection.isEmpty ? "" : "\(servingGovernorSection)\n")
\(dialogueWindowSection.isEmpty ? "" : "\(dialogueWindowSection)\n")
\(portfolioBriefSection.isEmpty ? "" : "\(portfolioBriefSection)\n")
\(focusedProjectAnchorPackSection.isEmpty ? "" : "\(focusedProjectAnchorPackSection)\n")
\(longtermOutlineSection.isEmpty ? "" : "\(longtermOutlineSection)\n")
\(deltaFeedSection.isEmpty ? "" : "\(deltaFeedSection)\n")
\(conflictSetSection.isEmpty ? "" : "\(conflictSetSection)\n")
\(contextRefsSection.isEmpty ? "" : "\(contextRefsSection)\n")
\(evidencePackSection.isEmpty ? "" : "\(evidencePackSection)\n")
[L0_CONSTITUTION]
\(constitution.isEmpty ? "(none)" : constitution)
[/L0_CONSTITUTION]

[L1_CANONICAL]
\(mergedCanonical.isEmpty ? "(none)" : mergedCanonical)
[/L1_CANONICAL]

[L2_OBSERVATIONS]
\(localObservations.isEmpty ? "(none)" : localObservations)
[/L2_OBSERVATIONS]

[L3_WORKING_SET]
\(mergedWorking.isEmpty ? "(none)" : mergedWorking)
[/L3_WORKING_SET]

[L4_RAW_EVIDENCE]
\(rawEvidence.isEmpty ? "(none)" : rawEvidence)
latest_user:
\(payload.latestUser)
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
""",
            disclosure: disclosure
        )

        let l0Used = TokenEstimator.estimateTokens(constitution)
        let l1Used = TokenEstimator.estimateTokens(mergedCanonical)
            + TokenEstimator.estimateTokens(portfolioBrief)
            + TokenEstimator.estimateTokens(longtermOutline)
        let l2Used = TokenEstimator.estimateTokens(localObservations)
            + TokenEstimator.estimateTokens(deltaFeed)
            + TokenEstimator.estimateTokens(conflictSet)
        let l3Used = TokenEstimator.estimateTokens(dialogueWindow)
            + TokenEstimator.estimateTokens(mergedWorking)
            + TokenEstimator.estimateTokens(focusedProjectAnchorPack)
        let l4Used = TokenEstimator.estimateTokens(rawEvidence + "\n" + payload.latestUser)
            + TokenEstimator.estimateTokens(contextRefs)
            + TokenEstimator.estimateTokens(evidencePack)
        let usedTotal = max(0, l0Used + l1Used + l2Used + l3Used + l4Used)

        let b = payload.budgets
        let configuredBudget: Int
        if let v = b?.totalTokens {
            configuredBudget = v
        } else if let v = b?.l0Tokens {
            configuredBudget = v
        } else if let v = b?.l1Tokens {
            configuredBudget = v
        } else if let v = b?.l2Tokens {
            configuredBudget = v
        } else if let v = b?.l3Tokens {
            configuredBudget = v
        } else if let v = b?.l4Tokens {
            configuredBudget = v
        } else {
            configuredBudget = 1600
        }
        let budgetTotal = max(usedTotal, configuredBudget)

        let layerUsage = [
            MemoryContextLayerUsage(layer: "l0_constitution", usedTokens: l0Used, budgetTokens: payload.budgets?.l0Tokens ?? max(80, l0Used)),
            MemoryContextLayerUsage(layer: "l1_canonical", usedTokens: l1Used, budgetTokens: payload.budgets?.l1Tokens ?? max(220, l1Used)),
            MemoryContextLayerUsage(layer: "l2_observations", usedTokens: l2Used, budgetTokens: payload.budgets?.l2Tokens ?? max(220, l2Used)),
            MemoryContextLayerUsage(layer: "l3_working_set", usedTokens: l3Used, budgetTokens: payload.budgets?.l3Tokens ?? max(300, l3Used)),
            MemoryContextLayerUsage(layer: "l4_raw_evidence", usedTokens: l4Used, budgetTokens: payload.budgets?.l4Tokens ?? max(300, l4Used)),
        ]

        return MemoryContextResponsePayload(
            text: finalText,
            source: snapshot.source,
            resolvedMode: payload.mode,
            resolvedProfile: servingProfile,
            longtermMode: disclosure.longtermMode,
            retrievalAvailable: disclosure.retrievalAvailable,
            fulltextNotLoaded: disclosure.fulltextNotLoaded,
            freshness: nil,
            cacheHit: nil,
            denyCode: nil,
            downgradeCode: nil,
            budgetTotalTokens: budgetTotal,
            usedTotalTokens: usedTotal,
            layerUsage: layerUsage,
            truncatedLayers: [],
            redactedItems: 0,
            privateDrops: 0
        )
    }

    private static func memoryServingProfileSection(_ servingProfile: String?) -> String {
        let normalizedProfile = normalized(servingProfile) ?? ""
        guard !normalizedProfile.isEmpty else { return "" }
        return """
[SERVING_PROFILE]
profile_id: \(normalizedProfile)
[/SERVING_PROFILE]
"""
    }

    private static func memoryServingGovernorSection(
        useMode: XTMemoryUseMode,
        servingProfile: String?,
        reviewLevelHint: String?,
        hasFocusedProjectAnchor: Bool = false
    ) -> String {
        guard useMode == .supervisorOrchestration else { return "" }

        let normalizedProfile = XTMemoryServingProfile.parse(servingProfile) ?? .m1Execute
        let normalizedReviewLevel = parseSupervisorReviewLevelHint(reviewLevelHint)
            ?? defaultSupervisorReviewLevelHint(for: normalizedProfile)
        let profileFloor = minimumSupervisorServingProfile(
            for: normalizedReviewLevel,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        let minimumPack = orderedSupervisorMinimumPack(
            servingProfile: normalizedProfile,
            reviewLevelHint: normalizedReviewLevel,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        let compressionPolicy: String
        switch normalizedReviewLevel {
        case .r1Pulse:
            compressionPolicy = "protect_anchor_then_delta_then_portfolio"
        case .r2Strategic:
            compressionPolicy = hasFocusedProjectAnchor
                ? "protect_anchor_longterm_decision_blocker_and_evidence_first"
                : "protect_anchor_conflict_longterm_then_refs"
        case .r3Rescue:
            compressionPolicy = "protect_anchor_conflict_and_evidence_first"
        }

        return """
[SERVING_GOVERNOR]
review_level_hint: \(normalizedReviewLevel.rawValue)
profile_floor: \(profileFloor.rawValue)
minimum_pack: \(minimumPack.joined(separator: ", "))
compression_policy: \(compressionPolicy)
[/SERVING_GOVERNOR]
"""
    }

    private static func parseSupervisorReviewLevelHint(
        _ raw: String?
    ) -> SupervisorReviewLevel? {
        guard let normalizedRaw = normalizedReviewLevelHint(raw) else { return nil }
        return SupervisorReviewLevel(rawValue: normalizedRaw)
    }

    private static func defaultSupervisorReviewLevelHint(
        for servingProfile: XTMemoryServingProfile
    ) -> SupervisorReviewLevel {
        switch servingProfile {
        case .m3DeepDive, .m4FullScan:
            return .r3Rescue
        case .m2PlanReview:
            return .r2Strategic
        default:
            return .r1Pulse
        }
    }

    private static func minimumSupervisorServingProfile(
        for reviewLevelHint: SupervisorReviewLevel,
        hasFocusedProjectAnchor: Bool
    ) -> XTMemoryServingProfile {
        switch reviewLevelHint {
        case .r1Pulse:
            return .m1Execute
        case .r2Strategic:
            return hasFocusedProjectAnchor ? .m3DeepDive : .m2PlanReview
        case .r3Rescue:
            return .m3DeepDive
        }
    }

    private static func orderedSupervisorMinimumPack(
        servingProfile: XTMemoryServingProfile,
        reviewLevelHint: SupervisorReviewLevel,
        hasFocusedProjectAnchor: Bool
    ) -> [String] {
        let profilePack = minimumPackForSupervisorServingProfile(servingProfile)
        let reviewPack = minimumPackForSupervisorReviewLevel(
            reviewLevelHint,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        let reviewFloor = minimumSupervisorServingProfile(
            for: reviewLevelHint,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        let orderedPacks = reviewFloor.rank > servingProfile.rank
            ? [reviewPack, profilePack]
            : [profilePack, reviewPack]
        var seen = Set<String>()
        var ordered: [String] = []
        for pack in orderedPacks {
            for item in pack {
                guard seen.insert(item).inserted else { continue }
                ordered.append(item)
            }
        }
        return ordered
    }

    private static func minimumPackForSupervisorServingProfile(
        _ servingProfile: XTMemoryServingProfile
    ) -> [String] {
        switch servingProfile {
        case .m0Heartbeat:
            return ["portfolio_brief", "delta_feed"]
        case .m1Execute:
            return ["portfolio_brief", "focused_project_anchor_pack", "delta_feed"]
        case .m2PlanReview:
            return [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs"
            ]
        case .m3DeepDive, .m4FullScan:
            return [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack"
            ]
        }
    }

    private static func minimumPackForSupervisorReviewLevel(
        _ reviewLevelHint: SupervisorReviewLevel,
        hasFocusedProjectAnchor: Bool
    ) -> [String] {
        switch reviewLevelHint {
        case .r1Pulse:
            return ["portfolio_brief", "focused_project_anchor_pack", "delta_feed"]
        case .r2Strategic:
            return hasFocusedProjectAnchor ? [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack"
            ] : [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs"
            ]
        case .r3Rescue:
            return [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack"
            ]
        }
    }

    private static func namedMemorySection(_ tag: String, body: String) -> String {
        let normalizedBody = normalized(body) ?? ""
        guard !normalizedBody.isEmpty else { return "" }
        return """
[\(tag)]
\(normalizedBody)
[/\(tag)]
"""
    }

    private static func mergedMemoryLayer(localPrimary: String, remoteSecondary: String) -> String {
        let local = localPrimary.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = remoteSecondary.trimmingCharacters(in: .whitespacesAndNewlines)
        if local.isEmpty { return remote }
        if remote.isEmpty { return local }
        return """
\(local)

[hub_remote]
\(remote)
"""
    }

    private struct RemoteMemorySnapshotFetchResult {
        var snapshot: HubRemoteMemorySnapshotResult
        var cacheHit: Bool
        var cacheMetadata: HubRemoteMemorySnapshotCache.Metadata?
    }

    private static func remoteMemorySnapshotWorkingLimit(
        for mode: XTMemoryUseMode
    ) -> Int {
        switch mode {
        case .supervisorOrchestration:
            return 80
        default:
            return 12
        }
    }

    private static func fetchRemoteMemorySnapshot(
        mode: XTMemoryUseMode,
        projectId: String?,
        bypassCache: Bool,
        timeoutSec: Double
    ) async -> RemoteMemorySnapshotFetchResult {
        let cacheKey = HubRemoteMemorySnapshotCache.Key(
            mode: mode.rawValue,
            projectId: normalized(projectId)
        )
        let posture = XTMemoryRoleScopedRouter.remoteSnapshotCachePosture(for: mode)
        if !bypassCache, let cached = await remoteMemorySnapshotCache.snapshotRecord(for: cacheKey) {
            return RemoteMemorySnapshotFetchResult(
                snapshot: cached.snapshot,
                cacheHit: true,
                cacheMetadata: cached.metadata
            )
        }

        let fetchStartedAt = Date()
        let remote: HubRemoteMemorySnapshotResult
        if let override = remoteMemorySnapshotOverride() {
            remote = await override(mode, projectId, bypassCache, timeoutSec)
        } else {
            remote = await HubPairingCoordinator.shared.fetchRemoteMemorySnapshot(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                mode: mode.rawValue,
                projectId: normalized(projectId),
                canonicalLimit: 24,
                workingLimit: remoteMemorySnapshotWorkingLimit(for: mode),
                timeoutSec: timeoutSec,
                allowClientKitInstallRetry: false
            )
        }
        let cacheMetadata: HubRemoteMemorySnapshotCache.Metadata?
        if remote.ok {
            cacheMetadata = await remoteMemorySnapshotCache.store(
                remote,
                for: cacheKey,
                posture: posture,
                now: fetchStartedAt
            )
        } else {
            await remoteMemorySnapshotCache.invalidate(key: cacheKey, reason: .remoteFetchFailed)
            cacheMetadata = nil
        }
        return RemoteMemorySnapshotFetchResult(
            snapshot: remote,
            cacheHit: false,
            cacheMetadata: cacheMetadata
        )
    }

    private struct LocalPaidSchedulerConfig: Codable {
        var globalConcurrency: Int?
        var perProjectConcurrency: Int?
        var queueLimit: Int?
        var queueTimeoutMs: Int?

        enum CodingKeys: String, CodingKey {
            case globalConcurrency = "global_concurrency"
            case perProjectConcurrency = "per_project_concurrency"
            case queueLimit = "queue_limit"
            case queueTimeoutMs = "queue_timeout_ms"
        }
    }

    private struct LocalPaidSchedulerState: Codable {
        var inFlightTotal: Int?
        var queueDepth: Int?
        var oldestQueuedMs: Int?

        enum CodingKeys: String, CodingKey {
            case inFlightTotal = "in_flight_total"
            case queueDepth = "queue_depth"
            case oldestQueuedMs = "oldest_queued_ms"
        }
    }

    private struct LocalPaidSchedulerInFlightScope: Codable {
        var scopeKey: String
        var inFlight: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case inFlight = "in_flight"
        }
    }

    private struct LocalPaidSchedulerQueuedScope: Codable {
        var scopeKey: String
        var queued: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case queued
        }
    }

    private struct LocalPaidSchedulerQueueItem: Codable {
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

    private struct LocalPaidSchedulerSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var config: LocalPaidSchedulerConfig?
        var state: LocalPaidSchedulerState?
        var inFlightByScope: [LocalPaidSchedulerInFlightScope]?
        var queuedByScope: [LocalPaidSchedulerQueuedScope]?
        var queueItems: [LocalPaidSchedulerQueueItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case config
            case state
            case inFlightByScope = "in_flight_by_scope"
            case queuedByScope = "queued_by_scope"
            case queueItems = "queue_items"
        }
    }

    private static func readLocalSchedulerStatus(
        includeQueueItems: Bool,
        queueItemsLimit: Int
    ) -> SchedulerStatusSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("paid_ai_scheduler_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalPaidSchedulerSnapshotFile.self, from: data) else {
            return nil
        }

        let inFlightByScope = (decoded.inFlightByScope ?? []).compactMap { row -> SchedulerScopeCount? in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return SchedulerScopeCount(scopeKey: key, count: max(0, row.inFlight ?? 0))
        }
        let queuedByScope = (decoded.queuedByScope ?? []).compactMap { row -> SchedulerScopeCount? in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return SchedulerScopeCount(scopeKey: key, count: max(0, row.queued ?? 0))
        }
        let queueItems: [SchedulerQueueItem] = includeQueueItems
            ? (decoded.queueItems ?? []).prefix(max(1, min(500, queueItemsLimit))).compactMap { row in
                let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
                let scopeKey = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !requestId.isEmpty, !scopeKey.isEmpty else { return nil }
                return SchedulerQueueItem(
                    requestId: requestId,
                    scopeKey: scopeKey,
                    enqueuedAtMs: max(0, row.enqueuedAtMs ?? 0),
                    queuedMs: max(0, row.queuedMs ?? 0)
                )
            }
            : []

        return SchedulerStatusSnapshot(
            source: "hub_scheduler_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            inFlightTotal: max(0, decoded.state?.inFlightTotal ?? inFlightByScope.reduce(0, { $0 + max(0, $1.count) })),
            queueDepth: max(0, decoded.state?.queueDepth ?? queuedByScope.reduce(0, { $0 + max(0, $1.count) })),
            oldestQueuedMs: max(0, decoded.state?.oldestQueuedMs ?? queueItems.map(\.queuedMs).max() ?? 0),
            inFlightByScope: inFlightByScope,
            queuedByScope: queuedByScope,
            queueItems: queueItems
        )
    }

    private struct LocalPendingGrantItem: Codable {
        var grantRequestId: String
        var requestId: String?
        var client: LocalPendingGrantClient?
        var capability: String?
        var modelId: String?
        var reason: String?
        var requestedTtlSec: Int?
        var requestedTokenCap: Int?
        var status: String?
        var decision: String?
        var createdAtMs: Double?
        var decidedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case grantRequestId = "grant_request_id"
            case requestId = "request_id"
            case client
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

    private struct LocalPendingGrantClient: Codable {
        var deviceId: String?
        var userId: String?
        var appId: String?
        var projectId: String?

        enum CodingKeys: String, CodingKey {
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case projectId = "project_id"
        }
    }

    private struct LocalPendingGrantSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalPendingGrantItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalPendingGrantRequests(
        projectId: String?,
        limit: Int,
        sourceOverride: String? = nil
    ) -> PendingGrantSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("pending_grant_requests_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalPendingGrantSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> PendingGrantItem? in
            let grantRequestId = row.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !grantRequestId.isEmpty else { return nil }

            let project = row.client?.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return PendingGrantItem(
                grantRequestId: grantRequestId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                deviceId: row.client?.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                userId: row.client?.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                appId: row.client?.appId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                capability: row.capability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                modelId: row.modelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                reason: row.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                requestedTtlSec: max(0, row.requestedTtlSec ?? 0),
                requestedTokenCap: max(0, row.requestedTokenCap ?? 0),
                status: row.status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                decision: row.decision?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAtMs: max(0, row.createdAtMs ?? 0),
                decidedAtMs: max(0, row.decidedAtMs ?? 0)
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAtMs != rhs.createdAtMs { return lhs.createdAtMs < rhs.createdAtMs }
            return lhs.grantRequestId.localizedCaseInsensitiveCompare(rhs.grantRequestId) == .orderedAscending
        }
        let resolvedSource = {
            let normalized = sourceOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return normalized.isEmpty ? "hub_pending_grants_file" : normalized
        }()

        return PendingGrantSnapshot(
            source: resolvedSource,
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalSupervisorCandidateReviewItem: Codable {
        var schemaVersion: String?
        var reviewId: String?
        var requestId: String?
        var evidenceRef: String?
        var reviewState: String?
        var durablePromotionState: String?
        var promotionBoundary: String?
        var deviceId: String?
        var userId: String?
        var appId: String?
        var threadId: String?
        var threadKey: String?
        var projectId: String?
        var projectIds: [String]?
        var scopes: [String]?
        var recordTypes: [String]?
        var auditRefs: [String]?
        var idempotencyKeys: [String]?
        var candidateCount: Int?
        var summaryLine: String?
        var mirrorTarget: String?
        var localStoreRole: String?
        var carrierKind: String?
        var carrierSchemaVersion: String?
        var pendingChangeId: String?
        var pendingChangeStatus: String?
        var editSessionId: String?
        var docId: String?
        var writebackRef: String?
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

    private struct LocalSupervisorCandidateReviewSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalSupervisorCandidateReviewItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalSupervisorCandidateReviewSnapshot(
        projectId: String?,
        limit: Int
    ) -> SupervisorCandidateReviewSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("supervisor_candidate_review_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalSupervisorCandidateReviewSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> SupervisorCandidateReviewItem? in
            let requestId = row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !requestId.isEmpty else { return nil }

            let project = row.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let projectIDs = (row.projectIds ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let normalizedProjectId, !normalizedProjectId.isEmpty,
               project != normalizedProjectId,
               !projectIDs.contains(normalizedProjectId) {
                return nil
            }

            return SupervisorCandidateReviewItem(
                schemaVersion: row.schemaVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                reviewId: row.reviewId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                requestId: requestId,
                evidenceRef: row.evidenceRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                reviewState: row.reviewState?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                durablePromotionState: row.durablePromotionState?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                promotionBoundary: row.promotionBoundary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                deviceId: row.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                userId: row.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                appId: row.appId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                threadId: row.threadId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                threadKey: row.threadKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                projectIds: projectIDs,
                scopes: (row.scopes ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                recordTypes: (row.recordTypes ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                auditRefs: (row.auditRefs ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                idempotencyKeys: (row.idempotencyKeys ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                candidateCount: max(0, row.candidateCount ?? 0),
                summaryLine: row.summaryLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                mirrorTarget: row.mirrorTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                localStoreRole: row.localStoreRole?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                carrierKind: row.carrierKind?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                carrierSchemaVersion: row.carrierSchemaVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                pendingChangeId: row.pendingChangeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                pendingChangeStatus: row.pendingChangeStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                editSessionId: row.editSessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                docId: row.docId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                writebackRef: row.writebackRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                stageCreatedAtMs: max(0, row.stageCreatedAtMs ?? 0),
                stageUpdatedAtMs: max(0, row.stageUpdatedAtMs ?? 0),
                latestEmittedAtMs: max(0, row.latestEmittedAtMs ?? 0),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                updatedAtMs: max(0, row.updatedAtMs ?? 0)
            )
        }
        .sorted { lhs, rhs in
            if lhs.latestEmittedAtMs != rhs.latestEmittedAtMs {
                return lhs.latestEmittedAtMs > rhs.latestEmittedAtMs
            }
            if lhs.candidateCount != rhs.candidateCount {
                return lhs.candidateCount > rhs.candidateCount
            }
            return lhs.requestId.localizedCaseInsensitiveCompare(rhs.requestId) == .orderedAscending
        }

        return SupervisorCandidateReviewSnapshot(
            source: "hub_supervisor_candidate_review_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalConnectorIngressReceipt: Codable {
        var receiptId: String
        var requestId: String?
        var projectId: String?
        var connector: String?
        var targetId: String?
        var ingressType: String?
        var channelScope: String?
        var sourceId: String?
        var messageId: String?
        var dedupeKey: String?
        var receivedAtMs: Double?
        var eventSequence: Int64?
        var deliveryState: String?
        var runtimeState: String?

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

    private struct LocalConnectorIngressSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalConnectorIngressReceipt]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalConnectorIngressReceipts(
        projectId: String?,
        limit: Int
    ) -> ConnectorIngressSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("connector_ingress_receipts_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalConnectorIngressSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> ConnectorIngressReceipt? in
            let receiptId = row.receiptId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !receiptId.isEmpty else { return nil }

            let project = row.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return ConnectorIngressReceipt(
                receiptId: receiptId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                connector: row.connector?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                targetId: row.targetId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                ingressType: row.ingressType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                channelScope: row.channelScope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                sourceId: row.sourceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                messageId: row.messageId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                dedupeKey: row.dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                receivedAtMs: max(0, row.receivedAtMs ?? 0),
                eventSequence: Swift.max(0, row.eventSequence ?? 0),
                deliveryState: row.deliveryState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                runtimeState: row.runtimeState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            )
        }
        .sorted { lhs, rhs in
            if lhs.receivedAtMs != rhs.receivedAtMs { return lhs.receivedAtMs > rhs.receivedAtMs }
            return lhs.receiptId.localizedCaseInsensitiveCompare(rhs.receiptId) == .orderedAscending
        }

        return ConnectorIngressSnapshot(
            source: "hub_connector_ingress_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalOperatorChannelXTCommandItem: Codable {
        var commandId: String?
        var requestId: String?
        var actionName: String?
        var bindingId: String?
        var routeId: String?
        var scopeType: String?
        var scopeId: String?
        var projectId: String?
        var provider: String?
        var accountId: String?
        var conversationId: String?
        var threadKey: String?
        var actorRef: String?
        var resolvedDeviceId: String?
        var preferredDeviceId: String?
        var note: String?
        var createdAtMs: Double?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case commandId = "command_id"
            case requestId = "request_id"
            case actionName = "action_name"
            case bindingId = "binding_id"
            case routeId = "route_id"
            case scopeType = "scope_type"
            case scopeId = "scope_id"
            case projectId = "project_id"
            case provider
            case accountId = "account_id"
            case conversationId = "conversation_id"
            case threadKey = "thread_key"
            case actorRef = "actor_ref"
            case resolvedDeviceId = "resolved_device_id"
            case preferredDeviceId = "preferred_device_id"
            case note
            case createdAtMs = "created_at_ms"
            case auditRef = "audit_ref"
        }
    }

    private struct LocalOperatorChannelXTCommandSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalOperatorChannelXTCommandItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalOperatorChannelXTCommands(
        projectId: String?,
        limit: Int
    ) -> OperatorChannelXTCommandSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("operator_channel_xt_command_queue_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalOperatorChannelXTCommandSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> OperatorChannelXTCommandItem? in
            let commandId = row.commandId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !commandId.isEmpty else { return nil }

            let project = (row.projectId ?? row.scopeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return OperatorChannelXTCommandItem(
                commandId: commandId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                actionName: row.actionName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                bindingId: row.bindingId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                routeId: row.routeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                scopeType: row.scopeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                scopeId: row.scopeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                provider: row.provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                accountId: row.accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                conversationId: row.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                threadKey: row.threadKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                actorRef: row.actorRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                resolvedDeviceId: row.resolvedDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                preferredDeviceId: row.preferredDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                note: row.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAtMs: max(0, row.createdAtMs ?? 0),
                auditRef: row.auditRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAtMs != rhs.createdAtMs { return lhs.createdAtMs > rhs.createdAtMs }
            return lhs.commandId.localizedCaseInsensitiveCompare(rhs.commandId) == .orderedAscending
        }

        return OperatorChannelXTCommandSnapshot(
            source: "hub_operator_channel_xt_command_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalOperatorChannelXTCommandResultItem: Codable {
        var commandId: String?
        var requestId: String?
        var actionName: String?
        var projectId: String?
        var resolvedDeviceId: String?
        var status: String?
        var denyCode: String?
        var detail: String?
        var runId: String?
        var createdAtMs: Double?
        var completedAtMs: Double?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case commandId = "command_id"
            case requestId = "request_id"
            case actionName = "action_name"
            case projectId = "project_id"
            case resolvedDeviceId = "resolved_device_id"
            case status
            case denyCode = "deny_code"
            case detail
            case runId = "run_id"
            case createdAtMs = "created_at_ms"
            case completedAtMs = "completed_at_ms"
            case auditRef = "audit_ref"
        }
    }

    private struct LocalOperatorChannelXTCommandResultSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalOperatorChannelXTCommandResultItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalOperatorChannelXTCommandResults(
        projectId: String?,
        limit: Int
    ) -> OperatorChannelXTCommandResultSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("operator_channel_xt_command_results_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalOperatorChannelXTCommandResultSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> OperatorChannelXTCommandResultItem? in
            let commandId = row.commandId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !commandId.isEmpty else { return nil }

            let project = row.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return OperatorChannelXTCommandResultItem(
                commandId: commandId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                actionName: row.actionName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                projectId: project,
                resolvedDeviceId: row.resolvedDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                status: row.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                denyCode: row.denyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                detail: row.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                runId: row.runId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAtMs: max(0, row.createdAtMs ?? 0),
                completedAtMs: max(0, row.completedAtMs ?? 0),
                auditRef: row.auditRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        .sorted { lhs, rhs in
            let leftTimestamp = max(lhs.completedAtMs, lhs.createdAtMs)
            let rightTimestamp = max(rhs.completedAtMs, rhs.createdAtMs)
            if leftTimestamp != rightTimestamp { return leftTimestamp > rightTimestamp }
            return lhs.commandId.localizedCaseInsensitiveCompare(rhs.commandId) == .orderedAscending
        }

        return OperatorChannelXTCommandResultSnapshot(
            source: "hub_operator_channel_xt_command_result_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalRuntimeSurfaceOverrideItem: Codable {
        var projectId: String
        var overrideMode: String
        var updatedAtMs: Double?
        var reason: String?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case overrideMode = "override_mode"
            case updatedAtMs = "updated_at_ms"
            case reason
            case auditRef = "audit_ref"
        }
    }

    private struct LocalRuntimeSurfaceOverridesSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalRuntimeSurfaceOverrideItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalRuntimeSurfaceOverrides(
        projectId: String?,
        limit: Int
    ) -> RuntimeSurfaceOverridesSnapshot? {
        // Legacy filename/source retained for Hub file-IPC compatibility.
        let url = HubPaths.baseDir().appendingPathComponent(
            RuntimeSurfaceOverrideCompatContract.snapshotFilename
        )
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalRuntimeSurfaceOverridesSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> RuntimeSurfaceOverrideItem? in
            let projectId = row.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            let overrideModeRaw = row.overrideMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !projectId.isEmpty,
                  let overrideMode = AXProjectRuntimeSurfaceHubOverrideMode(rawValue: overrideModeRaw) else {
                return nil
            }
            if let normalizedProjectId, !normalizedProjectId.isEmpty, projectId != normalizedProjectId {
                return nil
            }

            return RuntimeSurfaceOverrideItem(
                projectId: projectId,
                overrideMode: overrideMode,
                updatedAtMs: max(0, Int64((row.updatedAtMs ?? 0).rounded())),
                reason: row.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                auditRef: row.auditRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        .sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
            return lhs.projectId.localizedCaseInsensitiveCompare(rhs.projectId) == .orderedAscending
        }

        return RuntimeSurfaceOverridesSnapshot(
            source: RuntimeSurfaceOverrideCompatContract.fileSource,
            updatedAtMs: max(0, Int64((decoded.updatedAtMs ?? 0).rounded())),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    @available(*, deprecated, message: "Use readLocalRuntimeSurfaceOverrides(projectId:limit:)")
    private static func readLocalAutonomyPolicyOverrides(
        projectId: String?,
        limit: Int
    ) -> AutonomyPolicyOverridesSnapshot? {
        readLocalRuntimeSurfaceOverrides(
            projectId: projectId,
            limit: limit
        )
    }

    private struct LocalSecretVaultItem: Codable {
        var itemId: String
        var scope: String
        var name: String
        var sensitivity: String?
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

    private struct LocalSecretVaultSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalSecretVaultItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalSecretVaultSnapshot(
        scope: String?,
        namePrefix: String?,
        projectId: String?,
        limit: Int
    ) -> SecretVaultSnapshot? {
        if normalized(projectId) != nil {
            return nil
        }

        let url = HubPaths.baseDir().appendingPathComponent("secret_vault_items_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalSecretVaultSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedScope = normalized(scope)?.lowercased()
        let normalizedNamePrefix = normalized(namePrefix)?.lowercased()
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> SecretVaultItem? in
            let itemId = row.itemId.trimmingCharacters(in: .whitespacesAndNewlines)
            let scope = row.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let sensitivity = row.sensitivity?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "secret"
            guard !itemId.isEmpty, !scope.isEmpty, !name.isEmpty else { return nil }
            if scope == "project" {
                return nil
            }
            if let normalizedScope, scope != normalizedScope {
                return nil
            }
            if let normalizedNamePrefix, !name.lowercased().hasPrefix(normalizedNamePrefix) {
                return nil
            }
            return SecretVaultItem(
                itemId: itemId,
                scope: scope,
                name: name,
                sensitivity: sensitivity,
                createdAtMs: max(0, Int64((row.createdAtMs ?? 0).rounded())),
                updatedAtMs: max(0, Int64((row.updatedAtMs ?? 0).rounded()))
            )
        }
        .sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return lhs.itemId.localizedCaseInsensitiveCompare(rhs.itemId) == .orderedAscending
        }

        return SecretVaultSnapshot(
            source: "hub_secret_vault_file",
            updatedAtMs: max(0, Int64((decoded.updatedAtMs ?? 0).rounded())),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private static func fileIPCEventsDir() -> URL? {
        guard let st = HubConnector.readHubStatusIfAny(ttl: 3.0) else { return nil }
        guard let mode = st.ipcMode, mode == "file" else { return nil }
        guard let ipcPath = st.ipcPath, !ipcPath.isEmpty else { return nil }

        let dir = URL(fileURLWithPath: ipcPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func supervisorIncidentAuditEventsDir() -> URL? {
        if let dir = fileIPCEventsDir() {
            return dir
        }
        let fallback = HubPaths.baseDir().appendingPathComponent("ipc_events", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        } catch {
            return nil
        }
    }

    private static func pollMemoryContextResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> MemoryContextIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.25, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(MemoryContextIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollMemoryRetrievalResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> MemoryContextIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.25, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(MemoryContextIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollVoiceWakeProfileResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> VoiceWakeProfileIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(VoiceWakeProfileIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollVoiceTTSReadinessResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) -> VoiceTTSReadinessIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(3.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(VoiceTTSReadinessIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            usleep(90_000)
        }
        return nil
    }

    private static func pollVoiceTTSResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) -> VoiceTTSIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(5.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(VoiceTTSIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            usleep(90_000)
        }
        return nil
    }

    private static func pollLocalTaskResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) -> LocalTaskIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(8.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(LocalTaskIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            usleep(90_000)
        }
        return nil
    }

    private static func cachedVoiceTTSReadiness(for key: String) -> VoiceTTSReadinessResult? {
        voiceTTSReadinessCacheLock.lock()
        defer { voiceTTSReadinessCacheLock.unlock() }
        guard let cached = voiceTTSReadinessCache[key] else { return nil }
        if cached.expiresAt <= Date().timeIntervalSince1970 {
            voiceTTSReadinessCache.removeValue(forKey: key)
            return nil
        }
        return cached.result
    }

    private static func storeVoiceTTSReadiness(_ result: VoiceTTSReadinessResult, for key: String) {
        voiceTTSReadinessCacheLock.lock()
        voiceTTSReadinessCache[key] = CachedVoiceTTSReadiness(
            result: result,
            expiresAt: Date().timeIntervalSince1970 + voiceTTSReadinessCacheTTL
        )
        voiceTTSReadinessCacheLock.unlock()
    }

    private static func pollSecretVaultListResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> SecretVaultListIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(SecretVaultListIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollSecretVaultUseResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> SecretVaultUseIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(SecretVaultUseIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollNetworkResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> NetworkIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(6.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(NetworkIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func waitForBridgeEnabled(timeoutSec: Double) async -> HubBridgeClient.BridgeStatus {
        let deadline = Date().addingTimeInterval(max(0.2, min(8.0, timeoutSec)))
        while Date() < deadline {
            let st = HubBridgeClient.status()
            if st.enabled {
                return st
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return HubBridgeClient.status()
    }

    private static func mapPendingGrantActionResult(
        _ remote: HubRemotePendingGrantActionResult,
        defaultGrantRequestId: String
    ) -> PendingGrantActionResult {
        let mappedDecision: PendingGrantActionDecision = {
            switch remote.decision {
            case .approved:
                return .approved
            case .denied:
                return .denied
            case .failed:
                return .failed
            }
        }()
        let reason = normalizedReasonCode(remote.reasonCode, fallback: remote.ok ? nil : "pending_grant_action_failed")
        return PendingGrantActionResult(
            ok: remote.ok,
            decision: mappedDecision,
            source: "hub_runtime_grpc",
            grantRequestId: normalized(remote.grantRequestId) ?? defaultGrantRequestId,
            grantId: normalized(remote.grantId),
            expiresAtMs: remote.expiresAtMs,
            reasonCode: reason
        )
    }

    private static func mapSecretVaultCreateResult(
        _ remote: HubRemoteSecretVaultCreateResult
    ) -> SecretCreateResult {
        let mappedItem: SecretVaultItem? = {
            guard let item = remote.item else { return nil }
            return SecretVaultItem(
                itemId: item.itemId,
                scope: item.scope,
                name: item.name,
                sensitivity: item.sensitivity,
                createdAtMs: max(0, Int64(item.createdAtMs.rounded())),
                updatedAtMs: max(0, Int64(item.updatedAtMs.rounded()))
            )
        }()
        return SecretCreateResult(
            ok: remote.ok,
            source: remote.source,
            item: mappedItem,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_secret_vault_create_failed"
            )
        )
    }

    private static func mapSecretVaultUseResult(
        _ remote: HubRemoteSecretVaultUseResult
    ) -> SecretUseResult {
        SecretUseResult(
            ok: remote.ok,
            source: remote.source,
            leaseId: normalized(remote.leaseId),
            useToken: normalized(remote.useToken),
            itemId: normalized(remote.itemId),
            expiresAtMs: remote.expiresAtMs.map { max(0, Int64($0.rounded())) },
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_secret_vault_use_failed"
            ),
            detail: normalized(remote.logText)
        )
    }

    private static func mapSecretVaultUseAck(
        _ ack: SecretVaultUseIPCResponse,
        source: String,
        fallbackItemId: String?
    ) -> SecretUseResult {
        guard ack.ok else {
            return SecretUseResult(
                ok: false,
                source: source,
                leaseId: nil,
                useToken: nil,
                itemId: fallbackItemId,
                expiresAtMs: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "secret_vault_use_failed"),
                detail: normalized(ack.error)
            )
        }
        guard let result = ack.secretVaultUse else {
            return SecretUseResult(
                ok: false,
                source: source,
                leaseId: nil,
                useToken: nil,
                itemId: fallbackItemId,
                expiresAtMs: nil,
                reasonCode: "secret_vault_use_missing",
                detail: "secret vault use result missing from IPC ack"
            )
        }
        return SecretUseResult(
            ok: result.ok,
            source: source,
            leaseId: normalized(result.leaseId),
            useToken: normalized(result.useToken),
            itemId: normalized(result.itemId) ?? fallbackItemId,
            expiresAtMs: result.expiresAtMs.map { max(0, $0) },
            reasonCode: normalizedReasonCode(
                result.reasonCode,
                fallback: result.ok ? nil : "secret_vault_use_failed"
            ),
            detail: normalized(result.detail)
        )
    }

    private static func mapSecretVaultRedeemResult(
        _ remote: HubRemoteSecretVaultRedeemResult
    ) -> SecretRedeemResult {
        SecretRedeemResult(
            ok: remote.ok,
            source: remote.source,
            leaseId: normalized(remote.leaseId),
            itemId: normalized(remote.itemId),
            plaintext: remote.plaintext,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_secret_vault_redeem_failed"
            ),
            detail: normalized(remote.logText)
        )
    }

    private static func mapSecretVaultRedeemAck(
        _ ack: SecretVaultRedeemIPCResponse,
        source: String
    ) -> SecretRedeemResult {
        guard ack.ok else {
            return SecretRedeemResult(
                ok: false,
                source: source,
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "secret_vault_redeem_failed"),
                detail: normalized(ack.error)
            )
        }
        guard let result = ack.secretVaultRedeem else {
            return SecretRedeemResult(
                ok: false,
                source: source,
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "secret_vault_redeem_missing",
                detail: "secret vault redeem result missing from IPC ack"
            )
        }
        return SecretRedeemResult(
            ok: result.ok,
            source: source,
            leaseId: normalized(result.leaseId),
            itemId: normalized(result.itemId),
            plaintext: result.plaintext,
            reasonCode: normalizedReasonCode(
                result.reasonCode,
                fallback: result.ok ? nil : "secret_vault_redeem_failed"
            ),
            detail: normalized(result.detail)
        )
    }

    private static func mapVoiceGrantChallengeResult(
        _ remote: HubRemoteVoiceGrantChallengeResult
    ) -> VoiceGrantChallengeResult {
        let mappedChallenge: VoiceGrantChallengeSnapshot? = {
            guard let challenge = remote.challenge else { return nil }
            return VoiceGrantChallengeSnapshot(
                challengeId: challenge.challengeId,
                templateId: challenge.templateId,
                actionDigest: challenge.actionDigest,
                scopeDigest: challenge.scopeDigest,
                amountDigest: challenge.amountDigest,
                challengeCode: challenge.challengeCode,
                riskLevel: challenge.riskLevel,
                requiresMobileConfirm: challenge.requiresMobileConfirm,
                allowVoiceOnly: challenge.allowVoiceOnly,
                boundDeviceId: challenge.boundDeviceId,
                mobileTerminalId: challenge.mobileTerminalId,
                issuedAtMs: challenge.issuedAtMs,
                expiresAtMs: challenge.expiresAtMs
            )
        }()
        return VoiceGrantChallengeResult(
            ok: remote.ok,
            source: remote.source,
            challenge: mappedChallenge,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_voice_grant_challenge_failed"
            )
        )
    }

    private static func mapVoiceGrantVerificationResult(
        _ remote: HubRemoteVoiceGrantVerificationResult
    ) -> VoiceGrantVerificationResult {
        let mappedDecision: VoiceGrantVerificationDecision = {
            switch remote.decision {
            case .allow:
                return .allow
            case .deny:
                return .deny
            case .failed:
                return .failed
            }
        }()
        return VoiceGrantVerificationResult(
            ok: remote.ok,
            verified: remote.verified,
            decision: mappedDecision,
            source: remote.source,
            denyCode: normalized(remote.denyCode),
            challengeId: normalized(remote.challengeId),
            transcriptHash: normalized(remote.transcriptHash),
            semanticMatchScore: remote.semanticMatchScore,
            challengeMatch: remote.challengeMatch,
            deviceBindingOK: remote.deviceBindingOK,
            mobileConfirmed: remote.mobileConfirmed,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_voice_grant_verify_failed"
            )
        )
    }

    private static func shouldInvalidateRemoteMemoryForVoiceGrantChallenge(
        _ result: VoiceGrantChallengeResult
    ) -> Bool {
        result.ok && result.challenge != nil
    }

    private static func shouldInvalidateRemoteMemoryForVoiceGrantVerification(
        _ result: VoiceGrantVerificationResult
    ) -> Bool {
        if result.ok || result.verified {
            return true
        }

        switch result.decision {
        case .allow, .deny:
            return true
        case .failed:
            return false
        }
    }

    static func normalizedReasonCode(_ raw: String?, fallback: String? = nil) -> String? {
        let primary = normalized(raw)
        let backup = normalized(fallback)
        let token = sanitizeReasonToken(primary ?? backup ?? "")
        guard !token.isEmpty else { return nil }

        if token.contains("grant_required") { return "grant_required" }
        if token.contains("bridge_disabled") { return "bridge_disabled" }
        if token.contains("bridge_unavailable") { return "bridge_unavailable" }
        if token.contains("permission_denied") || token.contains("forbidden") || token == "403" || token.contains("_403") {
            return "forbidden"
        }
        if token.contains("unauthenticated") || token == "401" || token.contains("_401") {
            return "unauthenticated"
        }
        if token.contains("certificate") || token.contains("tls") || token.contains("ssl") {
            return "tls_error"
        }
        if token.contains("timeout") { return "timeout" }
        if token.contains("hub_env_missing") { return "hub_env_missing" }
        if token.contains("client_kit_missing") { return "client_kit_missing" }
        if token.contains("node_missing") { return "node_missing" }
        if token.contains("hub_not_connected") || token.contains("not_connected") {
            return "hub_not_connected"
        }
        if token.contains("auto_approved") { return "auto_approved" }
        if token.contains("ack_timeout") { return "ack_timeout" }
        if token.contains("denied") { return "denied" }
        return token
    }

    static func isBridgeGrantRequiredReason(_ reasonCode: String?) -> Bool {
        guard let reason = normalizedReasonCode(reasonCode, fallback: nil) else { return false }
        return reason == "grant_required" || reason == "bridge_disabled" || reason == "bridge_unavailable"
    }

    private static func networkFailureState(reasonCode: String?) -> NetworkAccessState {
        guard let reason = normalizedReasonCode(reasonCode, fallback: nil) else { return .failed }
        if reason == "denied" || reason == "forbidden" {
            return .denied
        }
        return .failed
    }

    private static func sanitizeReasonToken(_ raw: String) -> String {
        var token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        while token.contains("__") {
            token = token.replacingOccurrences(of: "__", with: "_")
        }
        return token.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    static func canonicalMemorySyncStatusSnapshot(
        limit: Int = 120
    ) -> CanonicalMemorySyncStatusSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("canonical_memory_sync_status.json")
        let boundedLimit = max(1, min(500, limit))
        guard let signature = canonicalMemorySyncStatusFileSignature(url: url) else {
            withCanonicalMemorySyncStatusCacheLock {
                canonicalMemorySyncStatusCache = nil
            }
            return nil
        }
        if let cached = withCanonicalMemorySyncStatusCacheLock({
            canonicalMemorySyncStatusCache
        }), cached.urlPath == url.path, cached.fileSize == signature.fileSize, cached.modificationTime == signature.modificationTime {
            return boundedCanonicalMemorySyncStatusSnapshot(cached.snapshot, limit: boundedLimit)
        }

        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CanonicalMemorySyncStatusSnapshot.self, from: data) else {
            withCanonicalMemorySyncStatusCacheLock {
                canonicalMemorySyncStatusCache = nil
            }
            return nil
        }
        let items = decoded.items
            .sorted { lhs, rhs in
                if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
        let snapshot = CanonicalMemorySyncStatusSnapshot(
            schemaVersion: decoded.schemaVersion,
            updatedAtMs: max(0, decoded.updatedAtMs),
            items: items
        )
        withCanonicalMemorySyncStatusCacheLock {
            canonicalMemorySyncStatusCache = CachedCanonicalMemorySyncStatus(
                urlPath: url.path,
                fileSize: signature.fileSize,
                modificationTime: signature.modificationTime,
                snapshot: snapshot
            )
        }
        return boundedCanonicalMemorySyncStatusSnapshot(snapshot, limit: boundedLimit)
    }

    private static func recordCanonicalMemorySyncStatus(
        scopeKind: String,
        scopeId: String,
        displayName: String?,
        result: CanonicalMemorySyncDispatchResult
    ) {
        let normalizedScopeKind = normalized(scopeKind) ?? ""
        let normalizedScopeId = normalized(scopeId) ?? ""
        guard !normalizedScopeKind.isEmpty, !normalizedScopeId.isEmpty else { return }

        let updatedAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let item = CanonicalMemorySyncStatusItem(
            scopeKind: normalizedScopeKind,
            scopeId: normalizedScopeId,
            displayName: normalized(displayName) ?? "",
            source: normalized(result.source) ?? "unknown",
            ok: result.ok,
            updatedAtMs: max(0, updatedAtMs),
            reasonCode: normalizedReasonCode(result.reasonCode, fallback: result.ok ? nil : "canonical_memory_sync_failed"),
            detail: normalized(result.detail),
            deliveryState: normalized(result.deliveryState),
            auditRefs: orderedUniqueNormalizedStrings(result.auditRefs).nonEmptyArray,
            evidenceRefs: orderedUniqueNormalizedStrings(result.evidenceRefs).nonEmptyArray,
            writebackRefs: orderedUniqueNormalizedStrings(result.writebackRefs).nonEmptyArray
        )
        let existing = canonicalMemorySyncStatusSnapshot(limit: 500)
        var deduped: [String: CanonicalMemorySyncStatusItem] = [:]
        for current in existing?.items ?? [] {
            deduped[current.id] = current
        }
        deduped[item.id] = item
        let merged = deduped.values.sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
        let payload = CanonicalMemorySyncStatusSnapshot(
            schemaVersion: "canonical_memory_sync_status.v1",
            updatedAtMs: max(0, updatedAtMs),
            items: Array(merged.prefix(500))
        )
        let url = HubPaths.baseDir().appendingPathComponent("canonical_memory_sync_status.json")
        if writeLocalSnapshot(payload, to: url) {
            updateCanonicalMemorySyncStatusCache(snapshot: payload, url: url)
        } else {
            withCanonicalMemorySyncStatusCacheLock {
                canonicalMemorySyncStatusCache = nil
            }
        }
    }

    private static func canonicalMemorySyncStatusFileSignature(url: URL) -> (fileSize: UInt64, modificationTime: TimeInterval)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modificationTime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return (fileSize, modificationTime)
    }

    private static func boundedCanonicalMemorySyncStatusSnapshot(
        _ snapshot: CanonicalMemorySyncStatusSnapshot,
        limit: Int
    ) -> CanonicalMemorySyncStatusSnapshot {
        CanonicalMemorySyncStatusSnapshot(
            schemaVersion: snapshot.schemaVersion,
            updatedAtMs: snapshot.updatedAtMs,
            items: Array(snapshot.items.prefix(limit))
        )
    }

    private static func updateCanonicalMemorySyncStatusCache(
        snapshot: CanonicalMemorySyncStatusSnapshot,
        url: URL
    ) {
        guard let signature = canonicalMemorySyncStatusFileSignature(url: url) else {
            withCanonicalMemorySyncStatusCacheLock {
                canonicalMemorySyncStatusCache = nil
            }
            return
        }
        withCanonicalMemorySyncStatusCacheLock {
            canonicalMemorySyncStatusCache = CachedCanonicalMemorySyncStatus(
                urlPath: url.path,
                fileSize: signature.fileSize,
                modificationTime: signature.modificationTime,
                snapshot: snapshot
            )
        }
    }

    private static func withCanonicalMemorySyncStatusCacheLock<T>(_ body: () -> T) -> T {
        canonicalMemorySyncStatusCacheLock.lock()
        defer { canonicalMemorySyncStatusCacheLock.unlock() }
        return body()
    }

    private static func mergedCanonicalMemorySyncResult(
        primary: CanonicalMemorySyncDispatchResult,
        secondary: CanonicalMemorySyncDispatchResult?
    ) -> CanonicalMemorySyncDispatchResult {
        if primary.ok {
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: primary.source,
                deliveryState: primary.deliveryState,
                auditRefs: primary.auditRefs,
                evidenceRefs: primary.evidenceRefs,
                writebackRefs: primary.writebackRefs,
                detail: primary.detail
            )
        }
        if let secondary, secondary.ok {
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: secondary.source,
                deliveryState: secondary.deliveryState,
                auditRefs: secondary.auditRefs,
                evidenceRefs: secondary.evidenceRefs,
                writebackRefs: secondary.writebackRefs,
                detail: secondary.detail
            )
        }

        let sources = [normalized(primary.source), normalized(secondary?.source)]
            .compactMap { $0 }
        let details = [
            normalized(primary.detail).map { "primary=\($0)" },
            normalized(secondary?.detail).map { "secondary=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " | ")

        return CanonicalMemorySyncDispatchResult(
            ok: false,
            source: sources.isEmpty ? "unknown" : sources.joined(separator: "+"),
            deliveryState: normalized(primary.deliveryState) ?? normalized(secondary?.deliveryState),
            auditRefs: orderedUniqueNormalizedStrings(primary.auditRefs + (secondary?.auditRefs ?? [])),
            evidenceRefs: orderedUniqueNormalizedStrings(primary.evidenceRefs + (secondary?.evidenceRefs ?? [])),
            writebackRefs: orderedUniqueNormalizedStrings(primary.writebackRefs + (secondary?.writebackRefs ?? [])),
            reasonCode: normalizedReasonCode(
                primary.reasonCode,
                fallback: secondary?.reasonCode
            ),
            detail: details.isEmpty ? nil : details
        )
    }

    private static func writeLocalSnapshot<T: Encodable>(_ payload: T, to url: URL) -> Bool {
        do {
            let data = try JSONEncoder().encode(payload)
            try XTStoreWriteSupport.writeSnapshotData(data, to: url)
            return true
        } catch {
            return false
        }
    }

    private static func writeEventStatus(
        data: Data,
        reqId: String,
        filePrefix: String,
        tmpPrefix: String,
        in dir: URL
    ) -> IPCEventWriteStatus {
        let file = dir.appendingPathComponent("\(filePrefix)_\(Int(Date().timeIntervalSince1970))_\(reqId).json")
        let tmp = dir.appendingPathComponent("\(tmpPrefix)_\(reqId).tmp")
        do {
            if let override = withTestingOverrideLock({ eventWriteOverrideForTesting }) {
                try override(data, tmp, file)
            } else {
                try data.write(to: tmp, options: .atomic)
                try FileManager.default.moveItem(at: tmp, to: file)
            }
            return IPCEventWriteStatus(requestQueued: true, requestError: "")
        } catch {
            return IPCEventWriteStatus(
                requestQueued: false,
                requestError: "\(filePrefix)_write_failed=\(summarized(error))"
            )
        }
    }

    private static func writeEvent(
        data: Data,
        reqId: String,
        filePrefix: String,
        tmpPrefix: String,
        in dir: URL
    ) -> Bool {
        writeEventStatus(
            data: data,
            reqId: reqId,
            filePrefix: filePrefix,
            tmpPrefix: tmpPrefix,
            in: dir
        ).requestQueued == true
    }

    private static func orderedUniqueStringTokens(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.compactMap { item in
            guard let token = normalized(item)?.lowercased(), !token.isEmpty else { return nil }
            guard seen.insert(token).inserted else { return nil }
            return token
        }
    }

    private static func orderedUniqueNormalizedStrings(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in raw {
            guard let trimmed = normalized(item) else { continue }
            let dedupeKey = trimmed.lowercased()
            guard seen.insert(dedupeKey).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    private static func localModelStateSnapshot() -> ModelStateSnapshot? {
        let url = HubPaths.modelsStateURL()
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func normalizedReviewLevelHint(_ raw: String?) -> String? {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case SupervisorReviewLevel.r1Pulse.rawValue:
            return SupervisorReviewLevel.r1Pulse.rawValue
        case SupervisorReviewLevel.r2Strategic.rawValue:
            return SupervisorReviewLevel.r2Strategic.rawValue
        case SupervisorReviewLevel.r3Rescue.rawValue:
            return SupervisorReviewLevel.r3Rescue.rawValue
        default:
            return nil
        }
    }

    static func installSecretVaultUseOverrideForTesting(
        _ override: (@Sendable (SecretUseRequestPayload) async -> SecretUseResult)?
    ) {
        withTestingOverrideLock {
            secretUseOverrideForTesting = override
        }
    }

    static func installAgentImportStageOverrideForTesting(
        _ override: (@Sendable (AgentImportStageRequestPayload) async -> AgentImportStageResult)?
    ) {
        withTestingOverrideLock {
            agentImportStageOverrideForTesting = override
        }
    }

    static func installAgentImportRecordOverrideForTesting(
        _ override: (@Sendable (AgentImportRecordLookupPayload) async -> AgentImportRecordResult)?
    ) {
        withTestingOverrideLock {
            agentImportRecordOverrideForTesting = override
        }
    }

    static func installSkillPackageUploadOverrideForTesting(
        _ override: (@Sendable (SkillPackageUploadRequestPayload) async -> SkillPackageUploadResult)?
    ) {
        withTestingOverrideLock {
            skillPackageUploadOverrideForTesting = override
        }
    }

    static func installAgentImportPromoteOverrideForTesting(
        _ override: (@Sendable (AgentImportPromoteRequestPayload) async -> AgentImportPromoteResult)?
    ) {
        withTestingOverrideLock {
            agentImportPromoteOverrideForTesting = override
        }
    }

    static func installSkillPinOverrideForTesting(
        _ override: (@Sendable (SkillPinRequestPayload) async -> SkillPinResult)?
    ) {
        withTestingOverrideLock {
            skillPinOverrideForTesting = override
        }
    }

    static func installResolvedSkillsOverrideForTesting(
        _ override: (@Sendable (String?) async -> ResolvedSkillsResult)?
    ) {
        withTestingOverrideLock {
            resolvedSkillsOverrideForTesting = override
        }
    }

    static func installSkillManifestOverrideForTesting(
        _ override: (@Sendable (String) async -> SkillManifestResult)?
    ) {
        withTestingOverrideLock {
            skillManifestOverrideForTesting = override
        }
    }

    static func installSecretVaultRedeemOverrideForTesting(
        _ override: (@Sendable (SecretRedeemRequestPayload) async -> SecretRedeemResult)?
    ) {
        withTestingOverrideLock {
            secretRedeemOverrideForTesting = override
        }
    }

    static func installLocalTaskExecutionOverrideForTesting(
        _ override: (@Sendable (LocalTaskRequestPayload, Double) -> LocalTaskResult)?
    ) {
        withTestingOverrideLock {
            localTaskExecutionOverrideForTesting = override
        }
    }

    static func installHubRouteDecisionOverrideForTesting(
        _ override: (@Sendable () async -> HubRouteDecision)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &routeDecisionOverrideForTesting,
                scoped: &scopedRouteDecisionOverridesForTesting
            )
        }
    }

    static func installMemoryContextResolutionOverrideForTesting(
        _ override: (@Sendable (XTMemoryRouteDecision, XTMemoryUseMode, Double) async -> MemoryContextResolutionResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryContextResolutionOverrideForTesting,
                scoped: &scopedMemoryContextResolutionOverridesForTesting
            )
        }
    }

    static func installMemoryRetrievalOverrideForTesting(
        _ override: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &memoryRetrievalOverrideForTesting,
                scoped: &scopedMemoryRetrievalOverridesForTesting
            )
        }
    }

    static func installSupervisorRemoteContinuityOverrideForTesting(
        _ override: (@Sendable (Bool) async -> SupervisorRemoteContinuityResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &supervisorRemoteContinuityOverrideForTesting,
                scoped: &scopedSupervisorRemoteContinuityOverridesForTesting
            )
        }
    }

    static func installSupervisorConversationAppendOverrideForTesting(
        _ override: (@Sendable (HubRemoteSupervisorConversationPayload) async -> Bool)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &supervisorConversationAppendOverrideForTesting,
                scoped: &scopedSupervisorConversationAppendOverridesForTesting
            )
        }
    }

    static func installSupervisorRouteDecisionOverrideForTesting(
        _ override: (@Sendable (SupervisorRouteDecisionRequestPayload) async -> SupervisorRouteDecisionResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &supervisorRouteDecisionOverrideForTesting,
                scoped: &scopedSupervisorRouteDecisionOverridesForTesting
            )
        }
    }

    static func installLocalMemoryRetrievalIPCOverrideForTesting(
        _ override: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &localMemoryRetrievalIPCOverrideForTesting,
                scoped: &scopedLocalMemoryRetrievalIPCOverridesForTesting
            )
        }
    }

    static func installRemoteMemorySnapshotOverrideForTesting(
        _ override: (@Sendable (XTMemoryUseMode, String?, Bool, Double) async -> HubRemoteMemorySnapshotResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &remoteMemorySnapshotOverrideForTesting,
                scoped: &scopedRemoteMemorySnapshotOverridesForTesting
            )
        }
    }

    static func installVoiceGrantChallengeOverrideForTesting(
        _ override: (@Sendable (VoiceGrantChallengeRequestPayload) async -> VoiceGrantChallengeResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &voiceGrantChallengeOverrideForTesting,
                scoped: &scopedVoiceGrantChallengeOverridesForTesting
            )
        }
    }

    static func installVoiceGrantVerificationOverrideForTesting(
        _ override: (@Sendable (VoiceGrantVerificationPayload) async -> VoiceGrantVerificationResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &voiceGrantVerificationOverrideForTesting,
                scoped: &scopedVoiceGrantVerificationOverridesForTesting
            )
        }
    }

    static func installRemoteMemoryRetrievalOverrideForTesting(
        _ override: (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &remoteMemoryRetrievalOverrideForTesting,
                scoped: &scopedRemoteMemoryRetrievalOverridesForTesting
            )
        }
    }

    static func installRemoteRuntimeSurfaceOverridesOverrideForTesting(
        _ override: (@Sendable (String?, Int, Double) async -> HubRemoteRuntimeSurfaceOverridesResult)?
    ) {
        withTestingOverrideLock {
            setTestingOverride(
                override,
                fallback: &remoteRuntimeSurfaceOverridesOverrideForTesting,
                scoped: &scopedRemoteRuntimeSurfaceOverridesForTesting
            )
        }
    }

    static func installRemoteMemoryRetrievalOverrideForTesting(
        _ override: (@Sendable (MemoryRetrievalPayload) async -> MemoryRetrievalResponsePayload?)?
    ) {
        withTestingOverrideLock {
            guard let override else {
                setTestingOverride(
                    nil as (@Sendable (MemoryRetrievalPayload, Double) async -> MemoryRetrievalResponsePayload?)?,
                    fallback: &remoteMemoryRetrievalOverrideForTesting,
                    scoped: &scopedRemoteMemoryRetrievalOverridesForTesting
                )
                return
            }
            setTestingOverride(
                { payload, _ in
                    await override(payload)
                },
                fallback: &remoteMemoryRetrievalOverrideForTesting,
                scoped: &scopedRemoteMemoryRetrievalOverridesForTesting
            )
        }
    }

    static func installIPCEventWriteOverrideForTesting(
        _ override: (@Sendable (Data, URL, URL) throws -> Void)?
    ) {
        withTestingOverrideLock {
            eventWriteOverrideForTesting = override
        }
    }

    static func resetSecretVaultOverridesForTesting() {
        withTestingOverrideLock {
            secretUseOverrideForTesting = nil
            secretRedeemOverrideForTesting = nil
        }
    }

    static func resetLocalTaskExecutionOverrideForTesting() {
        withTestingOverrideLock {
            localTaskExecutionOverrideForTesting = nil
        }
    }

    static func resetMemoryContextResolutionOverrideForTesting() {
        withTestingOverrideLock {
            resetTestingOverride(
                fallback: &routeDecisionOverrideForTesting,
                scoped: &scopedRouteDecisionOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryContextResolutionOverrideForTesting,
                scoped: &scopedMemoryContextResolutionOverridesForTesting
            )
            resetTestingOverride(
                fallback: &memoryRetrievalOverrideForTesting,
                scoped: &scopedMemoryRetrievalOverridesForTesting
            )
            resetTestingOverride(
                fallback: &localMemoryRetrievalIPCOverrideForTesting,
                scoped: &scopedLocalMemoryRetrievalIPCOverridesForTesting
            )
            resetTestingOverride(
                fallback: &remoteMemorySnapshotOverrideForTesting,
                scoped: &scopedRemoteMemorySnapshotOverridesForTesting
            )
            resetTestingOverride(
                fallback: &voiceGrantChallengeOverrideForTesting,
                scoped: &scopedVoiceGrantChallengeOverridesForTesting
            )
            resetTestingOverride(
                fallback: &voiceGrantVerificationOverrideForTesting,
                scoped: &scopedVoiceGrantVerificationOverridesForTesting
            )
            resetTestingOverride(
                fallback: &remoteMemoryRetrievalOverrideForTesting,
                scoped: &scopedRemoteMemoryRetrievalOverridesForTesting
            )
            resetTestingOverride(
                fallback: &remoteRuntimeSurfaceOverridesOverrideForTesting,
                scoped: &scopedRemoteRuntimeSurfaceOverridesForTesting
            )
            resetTestingOverride(
                fallback: &supervisorRemoteContinuityOverrideForTesting,
                scoped: &scopedSupervisorRemoteContinuityOverridesForTesting
            )
            resetTestingOverride(
                fallback: &supervisorConversationAppendOverrideForTesting,
                scoped: &scopedSupervisorConversationAppendOverridesForTesting
            )
            resetTestingOverride(
                fallback: &supervisorRouteDecisionOverrideForTesting,
                scoped: &scopedSupervisorRouteDecisionOverridesForTesting
            )
        }
        resetRuntimeSurfaceRemoteStateForTesting()
    }

    static func resetIPCEventWriteOverrideForTesting() {
        withTestingOverrideLock {
            eventWriteOverrideForTesting = nil
        }
    }

    static func resetAgentImportRecordOverrideForTesting() {
        withTestingOverrideLock {
            agentImportRecordOverrideForTesting = nil
        }
    }

    static func resetAgentImportStageOverrideForTesting() {
        withTestingOverrideLock {
            agentImportStageOverrideForTesting = nil
        }
    }

    static func resetSkillPackageUploadOverrideForTesting() {
        withTestingOverrideLock {
            skillPackageUploadOverrideForTesting = nil
        }
    }

    static func resetAgentImportPromoteOverrideForTesting() {
        withTestingOverrideLock {
            agentImportPromoteOverrideForTesting = nil
        }
    }

    static func resetSkillPinOverrideForTesting() {
        withTestingOverrideLock {
            skillPinOverrideForTesting = nil
        }
    }

    static func resetResolvedSkillsOverrideForTesting() {
        withTestingOverrideLock {
            resolvedSkillsOverrideForTesting = nil
        }
    }

    static func resetSkillManifestOverrideForTesting() {
        withTestingOverrideLock {
            skillManifestOverrideForTesting = nil
        }
    }
}

private extension Array where Element == String {
    var nonEmptyArray: [String]? {
        isEmpty ? nil : self
    }
}
