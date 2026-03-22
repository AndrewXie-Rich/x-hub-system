import Foundation

enum SupervisorSkillCallStatus: String, Codable, Sendable {
    case queued
    case running
    case awaitingAuthorization = "awaiting_authorization"
    case completed
    case failed
    case canceled
    case blocked
}

struct SupervisorSkillCallRecord: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_skill_call.v1"

    var schemaVersion: String
    var requestId: String
    var projectId: String
    var jobId: String
    var planId: String
    var stepId: String
    var skillId: String
    var requestedSkillId: String? = nil
    var routingReasonCode: String? = nil
    var routingExplanation: String? = nil
    var toolName: String
    var status: SupervisorSkillCallStatus
    var payload: [String: JSONValue]
    var currentOwner: String
    var resultSummary: String
    var denyCode: String
    var policySource: String? = nil
    var policyReason: String? = nil
    var resultEvidenceRef: String?
    var requiredCapability: String?
    var grantRequestId: String?
    var grantId: String?
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var auditRef: String

    var id: String { requestId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId = "request_id"
        case projectId = "project_id"
        case jobId = "job_id"
        case planId = "plan_id"
        case stepId = "step_id"
        case skillId = "skill_id"
        case requestedSkillId = "requested_skill_id"
        case routingReasonCode = "routing_reason_code"
        case routingExplanation = "routing_explanation"
        case toolName = "tool_name"
        case status
        case payload
        case currentOwner = "current_owner"
        case resultSummary = "result_summary"
        case denyCode = "deny_code"
        case policySource = "policy_source"
        case policyReason = "policy_reason"
        case resultEvidenceRef = "result_evidence_ref"
        case requiredCapability = "required_capability"
        case grantRequestId = "grant_request_id"
        case grantId = "grant_id"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case auditRef = "audit_ref"
    }
}

struct SupervisorProjectSkillCallSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_skill_calls_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var calls: [SupervisorSkillCallRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case calls
    }
}

enum SupervisorProjectSkillCallStore {
    static func load(for ctx: AXProjectContext) -> SupervisorProjectSkillCallSnapshot {
        try? ctx.ensureDirs()
        guard let data = try? Data(contentsOf: ctx.supervisorSkillCallsURL),
              let snapshot = try? JSONDecoder().decode(SupervisorProjectSkillCallSnapshot.self, from: data) else {
            return SupervisorProjectSkillCallSnapshot(
                schemaVersion: SupervisorProjectSkillCallSnapshot.currentSchemaVersion,
                updatedAtMs: 0,
                calls: []
            )
        }
        return snapshot
    }

    static func upsert(_ call: SupervisorSkillCallRecord, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        var snapshot = load(for: ctx)
        snapshot.schemaVersion = SupervisorProjectSkillCallSnapshot.currentSchemaVersion
        if let index = snapshot.calls.firstIndex(where: { $0.requestId == call.requestId }) {
            snapshot.calls[index] = call
        } else {
            snapshot.calls.append(call)
        }
        snapshot.calls.sort { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs {
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            return lhs.requestId > rhs.requestId
        }
        snapshot.updatedAtMs = max(snapshot.updatedAtMs, call.updatedAtMs)
        try save(snapshot, for: ctx)
    }

    private static func save(_ snapshot: SupervisorProjectSkillCallSnapshot, for ctx: AXProjectContext) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let target = ctx.supervisorSkillCallsURL
        try SupervisorStoreWriteSupport.writeSnapshotData(data, to: target)
    }
}
