import Foundation

extension HubIPCClient {
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

    struct SkillPackageDownloadResult: Equatable, Sendable {
        var ok: Bool
        var source: String
        var packageSHA256: String
        var data: Data
        var reasonCode: String?
    }

    struct SkillRunnerGateRequestPayload: Equatable, Sendable {
        var requestId: String
        var projectId: String?
        var executionRole: String?
        var agentMode: String?
        var laneId: String?
        var auditRef: String?
        var skillId: String
        var packageSHA256: String
        var toolName: String
        var toolArgsHash: String
        var riskTier: String
        var requiredGrantScope: String
        var execArgv: [String]
        var execCwd: String
    }

    struct SkillRunnerGateResult: Codable, Equatable, Sendable {
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

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case skillId = "skill_id"
            case packageSHA256 = "package_sha256"
            case toolName = "tool_name"
            case decision
            case toolRequestId = "tool_request_id"
            case grantId = "grant_id"
            case executionId = "execution_id"
            case denyCode = "deny_code"
            case resultJSON = "result_json"
            case executedAtMs = "executed_at_ms"
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

}
