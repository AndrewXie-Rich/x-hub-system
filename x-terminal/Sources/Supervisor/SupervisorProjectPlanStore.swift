import Foundation

enum SupervisorPlanStatus: String, Codable, Sendable {
    case planning
    case active
    case blocked
    case awaitingAuthorization = "awaiting_authorization"
    case completed
    case failed
    case canceled
}

enum SupervisorPlanStepKind: String, Codable, Sendable {
    case callSkill = "call_skill"
    case launchRun = "launch_run"
    case awaitEvent = "await_event"
    case askUser = "ask_user"
    case writeMemory = "write_memory"
    case notifyUser = "notify_user"
    case unknown

    static func parse(_ raw: String?) -> SupervisorPlanStepKind {
        let token = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch token {
        case "call_skill", "callskill", "skill", "skill_call":
            return .callSkill
        case "launch_run", "launchrun", "run":
            return .launchRun
        case "await_event", "awaitevent", "wait", "await":
            return .awaitEvent
        case "ask_user", "askuser", "ask":
            return .askUser
        case "write_memory", "writememory", "memory":
            return .writeMemory
        case "notify_user", "notifyuser", "notify":
            return .notifyUser
        default:
            return .unknown
        }
    }
}

enum SupervisorPlanStepStatus: String, Codable, Sendable {
    case pending
    case running
    case blocked
    case awaitingAuthorization = "awaiting_authorization"
    case completed
    case failed
    case canceled

    static func parse(_ raw: String?) -> SupervisorPlanStepStatus {
        let token = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch token {
        case "running", "in_progress", "inprogress":
            return .running
        case "blocked":
            return .blocked
        case "awaiting_authorization", "awaitingauthorization", "grant_pending":
            return .awaitingAuthorization
        case "completed", "done":
            return .completed
        case "failed", "error":
            return .failed
        case "canceled", "cancelled":
            return .canceled
        default:
            return .pending
        }
    }
}

struct SupervisorPlanStepRecord: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_plan_step.v1"

    var schemaVersion: String
    var stepId: String
    var title: String
    var kind: SupervisorPlanStepKind
    var status: SupervisorPlanStepStatus
    var skillId: String
    var currentOwner: String
    var detail: String
    var orderIndex: Int
    var updatedAtMs: Int64

    var id: String { stepId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case stepId = "step_id"
        case title
        case kind
        case status
        case skillId = "skill_id"
        case currentOwner = "current_owner"
        case detail
        case orderIndex = "order_index"
        case updatedAtMs = "updated_at_ms"
    }
}

struct SupervisorPlanRecord: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_plan.v1"

    var schemaVersion: String
    var planId: String
    var jobId: String
    var projectId: String
    var status: SupervisorPlanStatus
    var currentOwner: String
    var steps: [SupervisorPlanStepRecord]
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var auditRef: String

    var id: String { planId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case planId = "plan_id"
        case jobId = "job_id"
        case projectId = "project_id"
        case status
        case currentOwner = "current_owner"
        case steps
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case auditRef = "audit_ref"
    }
}

struct SupervisorProjectPlanSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_plans_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var plans: [SupervisorPlanRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case plans
    }
}

enum SupervisorProjectPlanStore {
    static func load(for ctx: AXProjectContext) -> SupervisorProjectPlanSnapshot {
        try? ctx.ensureDirs()
        guard let data = try? Data(contentsOf: ctx.supervisorPlansURL),
              let snapshot = try? JSONDecoder().decode(SupervisorProjectPlanSnapshot.self, from: data) else {
            return SupervisorProjectPlanSnapshot(
                schemaVersion: SupervisorProjectPlanSnapshot.currentSchemaVersion,
                updatedAtMs: 0,
                plans: []
            )
        }
        return snapshot
    }

    static func upsert(_ plan: SupervisorPlanRecord, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        var snapshot = load(for: ctx)
        snapshot.schemaVersion = SupervisorProjectPlanSnapshot.currentSchemaVersion
        if let index = snapshot.plans.firstIndex(where: { $0.planId == plan.planId }) {
            snapshot.plans[index] = plan
        } else {
            snapshot.plans.append(plan)
        }
        snapshot.plans.sort { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs {
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            return lhs.planId > rhs.planId
        }
        snapshot.updatedAtMs = max(snapshot.updatedAtMs, plan.updatedAtMs)
        try save(snapshot, for: ctx)
    }

    private static func save(_ snapshot: SupervisorProjectPlanSnapshot, for ctx: AXProjectContext) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let target = ctx.supervisorPlansURL
        let temp = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.moveItem(at: temp, to: target)
    }
}
