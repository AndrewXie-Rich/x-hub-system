import Foundation

extension HubIPCClient {
    struct MemoryWritebackCandidateExtractPayload: Codable, Equatable, Sendable {
        static let schemaVersion = "xt.axmemory_delta_candidate_extract_request.v1"

        var schemaVersion: String = MemoryWritebackCandidateExtractPayload.schemaVersion
        var projectId: String
        var auditRef: String
        var actor: String
        var source: String
        var delta: AXMemoryDelta
        var evidenceRefs: [String] = []
        var runId: String? = nil
        var agentId: String? = nil

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case projectId = "project_id"
            case auditRef = "audit_ref"
            case actor
            case source
            case delta
            case evidenceRefs = "evidence_refs"
            case runId = "run_id"
            case agentId = "agent_id"
        }
    }

    struct MemoryWritebackCandidateWriteback: Codable, Equatable, Sendable {
        var enabled: Bool?
        var authority: String?
        var requiresApproval: Bool?
        var activeWrite: Bool?
        var productionAuthorityChange: Bool?

        enum CodingKeys: String, CodingKey {
            case enabled
            case authority
            case requiresApproval = "requires_approval"
            case activeWrite = "active_write"
            case productionAuthorityChange = "production_authority_change"
        }
    }

    struct MemoryWritebackCandidateDiagnostics: Codable, Equatable, Sendable {
        var schemaVersion: String? = nil
        var ready: Bool? = nil
        var source: String? = nil
        var candidateCount: Int? = nil
        var conflictCandidateCount: Int? = nil
        var staleReviewRequiredCount: Int? = nil
        var staleCandidateCount: Int? = nil
        var plannedArchiveCount: Int? = nil
        var plannedStaleReviewRequiredCount: Int? = nil
        var activeReviewLockCount: Int? = nil
        var supersedingCandidateCount: Int? = nil
        var archivedSupersededCount: Int? = nil
        var supersededCandidateCount: Int? = nil
        var queuePressure: String? = nil
        var noiseScore: Int? = nil
        var productionAuthorityChange: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ready
            case source
            case candidateCount = "candidate_count"
            case conflictCandidateCount = "conflict_candidate_count"
            case staleReviewRequiredCount = "stale_review_required_count"
            case staleCandidateCount = "stale_candidate_count"
            case plannedArchiveCount = "planned_archive_count"
            case plannedStaleReviewRequiredCount = "planned_stale_review_required_count"
            case activeReviewLockCount = "active_review_lock_count"
            case supersedingCandidateCount = "superseding_candidate_count"
            case archivedSupersededCount = "archived_superseded_count"
            case supersededCandidateCount = "superseded_candidate_count"
            case queuePressure = "queue_pressure"
            case noiseScore = "noise_score"
            case productionAuthorityChange = "production_authority_change"
        }
    }

    struct MemoryWritebackCandidateMetadata: Codable, Equatable, Sendable {
        var conflictWith: [String]? = nil
        var duplicateWith: [String]? = nil
        var supersedes: [String]? = nil
        var conflictReason: String? = nil
        var conflictResolutionRequired: Bool? = nil
        var conflictResolved: Bool? = nil
        var staleReviewRequired: Bool? = nil
        var candidateStaleReviewRequired: Bool? = nil
        var supersededBy: String? = nil
        var supersessionReason: String? = nil
        var candidateGeneration: Int? = nil

        enum CodingKeys: String, CodingKey {
            case conflictWith = "conflict_with"
            case duplicateWith = "duplicate_with"
            case supersedes
            case conflictReason = "conflict_reason"
            case conflictResolutionRequired = "conflict_resolution_required"
            case conflictResolved = "conflict_resolved"
            case staleReviewRequired = "stale_review_required"
            case candidateStaleReviewRequired = "candidate_stale_review_required"
            case supersededBy = "superseded_by"
            case supersessionReason = "supersession_reason"
            case candidateGeneration = "candidate_generation"
        }
    }

    struct MemoryWritebackCandidateExtractResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String? = nil
        var status: String? = nil
        var projectId: String? = nil
        var applyRequested: Bool? = nil
        var dryRun: Bool? = nil
        var applied: Bool? = nil
        var plannedCount: Int? = nil
        var candidateCount: Int? = nil
        var createdCount: Int? = nil
        var plannedCreateCount: Int? = nil
        var duplicateCount: Int? = nil
        var skippedCount: Int? = nil
        var blockingCount: Int? = nil
        var candidateWriteback: MemoryWritebackCandidateWriteback? = nil
        var reasonCode: String? = nil
        var denyCode: String? = nil
        var errorCode: String? = nil
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case status
            case projectId = "project_id"
            case applyRequested = "apply_requested"
            case dryRun = "dry_run"
            case applied
            case plannedCount = "planned_count"
            case candidateCount = "candidate_count"
            case createdCount = "created_count"
            case plannedCreateCount = "planned_create_count"
            case duplicateCount = "duplicate_count"
            case skippedCount = "skipped_count"
            case blockingCount = "blocking_count"
            case candidateWriteback = "candidate_writeback"
            case reasonCode = "reason_code"
            case denyCode = "deny_code"
            case errorCode = "error_code"
            case detail
        }
    }

    struct MemoryWritebackCandidateObject: Codable, Equatable, Sendable, Identifiable {
        var id: String { memoryId }

        var schemaVersion: String?
        var memoryId: String
        var scope: String?
        var ownerId: String?
        var runId: String?
        var projectId: String?
        var agentId: String?
        var sourceKind: String?
        var layer: String?
        var title: String
        var text: String?
        var summary: String?
        var sensitivity: String?
        var visibility: String?
        var status: String?
        var pinned: Bool?
        var immutable: Bool?
        var ttlMs: Int64?
        var createdAtMs: Int64?
        var updatedAtMs: Int64?
        var lastAccessedAtMs: Int64?
        var version: Int?
        var provenance: MemoryWritebackCandidateMetadata? = nil
        var policy: MemoryWritebackCandidateMetadata? = nil

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case memoryId = "memory_id"
            case scope
            case ownerId = "owner_id"
            case runId = "run_id"
            case projectId = "project_id"
            case agentId = "agent_id"
            case sourceKind = "source_kind"
            case layer
            case title
            case text
            case summary
            case sensitivity
            case visibility
            case status
            case pinned
            case immutable
            case ttlMs = "ttl_ms"
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
            case lastAccessedAtMs = "last_accessed_at_ms"
            case version
            case provenance
            case policy
        }

        var redactedContentByDefault: Bool {
            let normalizedSensitivity = sensitivity?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if normalizedSensitivity == "secret" || normalizedSensitivity == "private" {
                return true
            }
            let normalizedVisibility = visibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return normalizedVisibility == "private"
        }

        func isStale(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
            guard let ttlMs, ttlMs > 0 else { return false }
            let baseline = updatedAtMs ?? createdAtMs ?? 0
            guard baseline > 0 else { return false }
            return nowMs - baseline > ttlMs
        }

        var conflictWithMemoryIds: [String] {
            Self.uniqueStrings((policy?.conflictWith ?? []) + (provenance?.conflictWith ?? []))
        }

        var hasConflict: Bool {
            !conflictWithMemoryIds.isEmpty
                || policy?.conflictResolutionRequired == true
                || provenance?.conflictResolutionRequired == true
        }

        var requiresStaleReview: Bool {
            policy?.staleReviewRequired == true
                || policy?.candidateStaleReviewRequired == true
                || provenance?.staleReviewRequired == true
                || provenance?.candidateStaleReviewRequired == true
        }

        var supersedesMemoryIds: [String] {
            Self.uniqueStrings((policy?.supersedes ?? []) + (provenance?.supersedes ?? []))
        }

        var supersededByMemoryId: String? {
            let policyValue = policy?.supersededBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !policyValue.isEmpty { return policyValue }
            let provenanceValue = provenance?.supersededBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return provenanceValue.isEmpty ? nil : provenanceValue
        }

        var isSuperseded: Bool {
            supersededByMemoryId != nil
        }

        private static func uniqueStrings(_ values: [String]) -> [String] {
            var seen = Set<String>()
            var output: [String] = []
            for raw in values {
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, !seen.contains(value) else { continue }
                seen.insert(value)
                output.append(value)
            }
            return output
        }
    }

    struct MemoryWritebackCandidateListResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String? = nil
        var status: String? = nil
        var candidateCount: Int? = nil
        var objects: [MemoryWritebackCandidateObject] = []
        var candidateDiagnostics: MemoryWritebackCandidateDiagnostics? = nil
        var candidateWriteback: MemoryWritebackCandidateWriteback? = nil
        var reasonCode: String? = nil
        var denyCode: String? = nil
        var errorCode: String? = nil
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case status
            case candidateCount = "candidate_count"
            case objects
            case candidateDiagnostics = "candidate_diagnostics"
            case candidateWriteback = "candidate_writeback"
            case reasonCode = "reason_code"
            case denyCode = "deny_code"
            case errorCode = "error_code"
            case detail
        }
    }

    struct MemoryObjectListFilter: Codable, Equatable, Sendable {
        var scope: String? = nil
        var ownerId: String? = nil
        var projectId: String? = nil
        var agentId: String? = nil
        var sourceKind: String? = nil
        var layer: String? = nil
        var status: String? = nil
        var sensitivity: String? = nil
        var visibility: String? = nil
        var limit: Int = 50

        enum CodingKeys: String, CodingKey {
            case scope
            case ownerId = "owner_id"
            case projectId = "project_id"
            case agentId = "agent_id"
            case sourceKind = "source_kind"
            case layer
            case status
            case sensitivity
            case visibility
            case limit
        }
    }

    struct MemoryObjectListResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String? = nil
        var status: String? = nil
        var count: Int? = nil
        var objects: [MemoryWritebackCandidateObject] = []
        var filter: MemoryObjectListFilter? = nil
        var reasonCode: String? = nil
        var denyCode: String? = nil
        var errorCode: String? = nil
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case status
            case count
            case objects
            case filter
            case reasonCode = "reason_code"
            case denyCode = "deny_code"
            case errorCode = "error_code"
            case detail
        }
    }

    struct MemoryUserRevealGrantRequest: Codable, Equatable, Sendable {
        var action: String = "evaluate"
        var grantId: String? = nil
        var scope: String = "user"
        var surface: String = "assistant_user_memory_inspector"
        var actor: String = "xt_swift_shell"
        var requesterRole: String = "supervisor"
        var useMode: String = "assistant_user_memory_inspector"
        var ttlMs: Int64? = nil
        var auditRef: String? = nil

        enum CodingKeys: String, CodingKey {
            case action
            case grantId = "grant_id"
            case scope
            case surface
            case actor
            case requesterRole = "requester_role"
            case useMode = "use_mode"
            case ttlMs = "ttl_ms"
            case auditRef = "audit_ref"
        }
    }

    struct MemoryUserRevealGrantResult: Codable, Equatable, Sendable {
        var schemaVersion: String? = nil
        var ok: Bool
        var source: String? = nil
        var status: String? = nil
        var grantId: String? = nil
        var scope: String? = nil
        var surface: String? = nil
        var actor: String? = nil
        var issuedAtMs: Int64? = nil
        var expiresAtMs: Int64? = nil
        var ttlMs: Int64? = nil
        var reasonCode: String? = nil
        var denyCode: String? = nil
        var errorCode: String? = nil
        var message: String? = nil
        var auditRefPresent: Bool? = nil
        var revokedAtMs: Int64? = nil
        var generatedAtMs: Int64? = nil
        var contentIncluded: Bool? = nil
        var memoryIdsIncluded: Bool? = nil
        var projectCoderAllowed: Bool? = nil
        var modelContextAuthority: Bool? = nil
        var memoryServingAuthorityChange: Bool? = nil
        var productionAuthorityChange: Bool? = nil
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ok
            case source
            case status
            case grantId = "grant_id"
            case scope
            case surface
            case actor
            case issuedAtMs = "issued_at_ms"
            case expiresAtMs = "expires_at_ms"
            case ttlMs = "ttl_ms"
            case reasonCode = "reason_code"
            case denyCode = "deny_code"
            case errorCode = "error_code"
            case message
            case auditRefPresent = "audit_ref_present"
            case revokedAtMs = "revoked_at_ms"
            case generatedAtMs = "generated_at_ms"
            case contentIncluded = "content_included"
            case memoryIdsIncluded = "memory_ids_included"
            case projectCoderAllowed = "project_coder_allowed"
            case modelContextAuthority = "model_context_authority"
            case memoryServingAuthorityChange = "memory_serving_authority_change"
            case productionAuthorityChange = "production_authority_change"
            case detail
        }

        func isActive(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)) -> Bool {
            guard ok,
                  (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "granted",
                  (scope ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "user",
                  (surface ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "assistant_user_memory_inspector",
                  contentIncluded != true,
                  memoryIdsIncluded != true,
                  projectCoderAllowed != true,
                  modelContextAuthority != true,
                  memoryServingAuthorityChange != true,
                  productionAuthorityChange != true,
                  let expiresAtMs,
                  expiresAtMs > nowMs else {
                return false
            }
            return true
        }
    }

    struct MemoryObjectHistoryEvent: Codable, Equatable, Sendable, Identifiable {
        var id: String { eventId }

        var schemaVersion: String? = nil
        var eventId: String
        var memoryId: String? = nil
        var operation: String? = nil
        var actor: String? = nil
        var reason: String? = nil
        var beforeVersion: Int? = nil
        var afterVersion: Int? = nil
        var beforeJson: JSONValue? = nil
        var afterJson: JSONValue? = nil
        var policyDecision: String? = nil
        var denyCode: String? = nil
        var auditRef: String? = nil
        var createdAtMs: Int64? = nil

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case eventId = "event_id"
            case memoryId = "memory_id"
            case operation
            case actor
            case reason
            case beforeVersion = "before_version"
            case afterVersion = "after_version"
            case beforeJson = "before_json"
            case afterJson = "after_json"
            case policyDecision = "policy_decision"
            case denyCode = "deny_code"
            case auditRef = "audit_ref"
            case createdAtMs = "created_at_ms"
        }
    }

    struct MemoryObjectHistoryResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String? = nil
        var status: String? = nil
        var memoryId: String? = nil
        var count: Int? = nil
        var events: [MemoryObjectHistoryEvent] = []
        var reasonCode: String? = nil
        var denyCode: String? = nil
        var errorCode: String? = nil
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case status
            case memoryId = "memory_id"
            case count
            case events
            case reasonCode = "reason_code"
            case denyCode = "deny_code"
            case errorCode = "error_code"
            case detail
        }
    }

    struct MemoryObjectResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String? = nil
        var status: String? = nil
        var memoryId: String? = nil
        var object: MemoryWritebackCandidateObject? = nil
        var reasonCode: String? = nil
        var denyCode: String? = nil
        var errorCode: String? = nil
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case status
            case memoryId = "memory_id"
            case object
            case reasonCode = "reason_code"
            case denyCode = "deny_code"
            case errorCode = "error_code"
            case detail
        }
    }

    struct MemoryObjectMutationPayload: Codable, Equatable, Sendable {
        var actor: String = "xt_swift_shell"
        var auditRef: String
        var reason: String
        var requesterRole: String = "tool"
        var useMode: String = "tool_plan"
        var confirm: Bool = false
        var confirmArchive: Bool? = nil
        var confirmDelete: Bool? = nil
        var confirmation: String? = nil
        var userRevealGrantId: String? = nil

        enum CodingKeys: String, CodingKey {
            case actor
            case auditRef = "audit_ref"
            case reason
            case requesterRole = "requester_role"
            case useMode = "use_mode"
            case confirm
            case confirmArchive = "confirm_archive"
            case confirmDelete = "confirm_delete"
            case confirmation
            case userRevealGrantId = "user_reveal_grant_id"
        }
    }

    struct MemoryObjectMutationSummary: Codable, Equatable, Sendable {
        var operation: String?
        var fromStatus: String?
        var toStatus: String?
        var fromPinned: Bool?
        var toPinned: Bool?
        var confirmationRequired: Bool?
        var confirmed: Bool?
        var confirmationSatisfied: Bool?
        var activeMemoryMutation: Bool?
        var deleteMode: String?
        var authority: String?
        var productionAuthorityChange: Bool?

        enum CodingKeys: String, CodingKey {
            case operation
            case fromStatus = "from_status"
            case toStatus = "to_status"
            case fromPinned = "from_pinned"
            case toPinned = "to_pinned"
            case confirmationRequired = "confirmation_required"
            case confirmed
            case confirmationSatisfied = "confirmation_satisfied"
            case activeMemoryMutation = "active_memory_mutation"
            case deleteMode = "delete_mode"
            case authority
            case productionAuthorityChange = "production_authority_change"
        }
    }

    struct MemoryObjectMutationResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String? = nil
        var status: String? = nil
        var memoryId: String? = nil
        var version: Int? = nil
        var eventId: String? = nil
        var action: String? = nil
        var mutation: MemoryObjectMutationSummary? = nil
        var object: MemoryWritebackCandidateObject? = nil
        var policy: JSONValue? = nil
        var productionAuthorityChange: Bool? = nil
        var reasonCode: String? = nil
        var denyCode: String? = nil
        var errorCode: String? = nil
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case status
            case memoryId = "memory_id"
            case version
            case eventId = "event_id"
            case action
            case mutation
            case object
            case policy
            case productionAuthorityChange = "production_authority_change"
            case reasonCode = "reason_code"
            case denyCode = "deny_code"
            case errorCode = "error_code"
            case detail
        }
    }

    struct MemoryWritebackCandidateDecisionPayload: Codable, Equatable, Sendable {
        var actor: String = "xt_swift_shell"
        var auditRef: String
        var reason: String
        var conflictResolutionReason: String? = nil
        var requesterRole: String = "tool"
        var useMode: String = "tool_plan"

        enum CodingKeys: String, CodingKey {
            case actor
            case auditRef = "audit_ref"
            case reason
            case conflictResolutionReason = "conflict_resolution_reason"
            case requesterRole = "requester_role"
            case useMode = "use_mode"
        }
    }

    struct MemoryWritebackCandidateMaintenancePayload: Codable, Equatable, Sendable {
        var actor: String = "xt_swift_shell"
        var auditRef: String
        var reason: String
        var projectId: String? = nil
        var apply: Bool = false
        var dryRun: Bool = true
        var limit: Int = 100
        var maxAgeMs: Int64? = nil

        enum CodingKeys: String, CodingKey {
            case actor
            case auditRef = "audit_ref"
            case reason
            case projectId = "project_id"
            case apply
            case dryRun = "dry_run"
            case limit
            case maxAgeMs = "max_age_ms"
        }
    }

    struct MemoryWritebackCandidateMaintenanceItem: Codable, Equatable, Sendable, Identifiable {
        var id: String { memoryId }

        var memoryId: String
        var ownerId: String? = nil
        var projectId: String? = nil
        var sourceKind: String? = nil
        var layer: String? = nil
        var currentStatus: String? = nil
        var plannedStatus: String? = nil
        var operation: String? = nil
        var reasonCode: String? = nil
        var ageMs: Int64? = nil
        var ttlMs: Int64? = nil
        var applied: Bool? = nil
        var eventId: String? = nil

        enum CodingKeys: String, CodingKey {
            case memoryId = "memory_id"
            case ownerId = "owner_id"
            case projectId = "project_id"
            case sourceKind = "source_kind"
            case layer
            case currentStatus = "current_status"
            case plannedStatus = "planned_status"
            case operation
            case reasonCode = "reason_code"
            case ageMs = "age_ms"
            case ttlMs = "ttl_ms"
            case applied
            case eventId = "event_id"
        }
    }

    struct MemoryWritebackCandidateMaintenanceResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String? = nil
        var status: String? = nil
        var projectId: String? = nil
        var applyRequested: Bool? = nil
        var dryRun: Bool? = nil
        var applied: Bool? = nil
        var limit: Int? = nil
        var maxAgeMs: Int64? = nil
        var candidateCount: Int? = nil
        var staleCount: Int? = nil
        var archivedCount: Int? = nil
        var plannedArchiveCount: Int? = nil
        var staleReviewRequiredCount: Int? = nil
        var plannedStaleReviewRequiredCount: Int? = nil
        var skippedCount: Int? = nil
        var mutationCount: Int? = nil
        var items: [MemoryWritebackCandidateMaintenanceItem] = []
        var candidateWriteback: MemoryWritebackCandidateWriteback? = nil
        var productionAuthorityChange: Bool? = nil
        var reasonCode: String? = nil
        var denyCode: String? = nil
        var errorCode: String? = nil
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case status
            case projectId = "project_id"
            case applyRequested = "apply_requested"
            case dryRun = "dry_run"
            case applied
            case limit
            case maxAgeMs = "max_age_ms"
            case candidateCount = "candidate_count"
            case staleCount = "stale_count"
            case archivedCount = "archived_count"
            case plannedArchiveCount = "planned_archive_count"
            case staleReviewRequiredCount = "stale_review_required_count"
            case plannedStaleReviewRequiredCount = "planned_stale_review_required_count"
            case skippedCount = "skipped_count"
            case mutationCount = "mutation_count"
            case items
            case candidateWriteback = "candidate_writeback"
            case productionAuthorityChange = "production_authority_change"
            case reasonCode = "reason_code"
            case denyCode = "deny_code"
            case errorCode = "error_code"
            case detail
        }
    }

    struct MemoryWritebackCandidateDecisionTransition: Codable, Equatable, Sendable {
        var operation: String?
        var fromStatus: String?
        var toStatus: String?
        var candidateWriteback: Bool?

        enum CodingKeys: String, CodingKey {
            case operation
            case fromStatus = "from_status"
            case toStatus = "to_status"
            case candidateWriteback = "candidate_writeback"
        }
    }

    struct MemoryWritebackCandidateDecisionResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String? = nil
        var status: String? = nil
        var memoryId: String? = nil
        var version: Int? = nil
        var eventId: String? = nil
        var denyCode: String? = nil
        var reasonCode: String? = nil
        var errorCode: String? = nil
        var currentStatus: String? = nil
        var requiredStatus: String? = nil
        var action: String? = nil
        var transition: MemoryWritebackCandidateDecisionTransition? = nil
        var object: MemoryWritebackCandidateObject? = nil
        var productionAuthorityChange: Bool? = nil
        var detail: String? = nil

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case status
            case memoryId = "memory_id"
            case version
            case eventId = "event_id"
            case denyCode = "deny_code"
            case reasonCode = "reason_code"
            case errorCode = "error_code"
            case currentStatus = "current_status"
            case requiredStatus = "required_status"
            case action
            case transition
            case object
            case productionAuthorityChange = "production_authority_change"
            case detail
        }
    }

}
