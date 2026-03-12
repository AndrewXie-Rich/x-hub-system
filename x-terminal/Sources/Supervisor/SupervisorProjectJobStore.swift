import Foundation

enum SupervisorJobPriority: String, Codable, CaseIterable, Sendable {
    case critical
    case high
    case normal
    case low

    static func parse(_ raw: String?) -> SupervisorJobPriority {
        let token = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch token {
        case "critical", "urgent", "紧急", "关键":
            return .critical
        case "high", "高":
            return .high
        case "low", "低":
            return .low
        default:
            return .normal
        }
    }
}

enum SupervisorJobStatus: String, Codable, Sendable {
    case queued
    case planning
    case running
    case blocked
    case awaitingAuthorization = "awaiting_authorization"
    case completed
    case failed
    case canceled
}

enum SupervisorJobSource: String, Codable, Sendable {
    case user
    case supervisor
    case heartbeat
    case externalTrigger = "external_trigger"
    case incident
    case skillCallback = "skill_callback"
    case grantResolution = "grant_resolution"
    case approvalResolution = "approval_resolution"

    static func parse(_ raw: String?, fallback: SupervisorJobSource) -> SupervisorJobSource {
        let token = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch token {
        case "user":
            return .user
        case "supervisor":
            return .supervisor
        case "heartbeat":
            return .heartbeat
        case "external_trigger", "externaltrigger", "external-trigger":
            return .externalTrigger
        case "incident":
            return .incident
        case "skill_callback", "skillcallback", "skill-callback":
            return .skillCallback
        case "grant_resolution", "grantresolution", "grant-resolution":
            return .grantResolution
        case "approval_resolution", "approvalresolution", "approval-resolution":
            return .approvalResolution
        default:
            return fallback
        }
    }
}

struct SupervisorJobRecord: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_job.v1"

    var schemaVersion: String
    var jobId: String
    var projectId: String
    var goal: String
    var priority: SupervisorJobPriority
    var status: SupervisorJobStatus
    var source: SupervisorJobSource
    var currentOwner: String
    var activePlanId: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var auditRef: String

    var id: String { jobId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case jobId = "job_id"
        case projectId = "project_id"
        case goal
        case priority
        case status
        case source
        case currentOwner = "current_owner"
        case activePlanId = "active_plan_id"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case auditRef = "audit_ref"
    }
}

struct SupervisorProjectJobSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_jobs_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var jobs: [SupervisorJobRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case jobs
    }
}

enum SupervisorProjectJobStore {
    static func load(for ctx: AXProjectContext) -> SupervisorProjectJobSnapshot {
        try? ctx.ensureDirs()
        guard let data = try? Data(contentsOf: ctx.supervisorJobsURL),
              let snapshot = try? JSONDecoder().decode(SupervisorProjectJobSnapshot.self, from: data) else {
            return SupervisorProjectJobSnapshot(
                schemaVersion: SupervisorProjectJobSnapshot.currentSchemaVersion,
                updatedAtMs: 0,
                jobs: []
            )
        }
        return snapshot
    }

    static func append(_ job: SupervisorJobRecord, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        var snapshot = load(for: ctx)
        snapshot.schemaVersion = SupervisorProjectJobSnapshot.currentSchemaVersion
        snapshot.jobs.append(job)
        try normalizeAndSave(&snapshot, for: ctx)
    }

    static func upsert(_ job: SupervisorJobRecord, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        var snapshot = load(for: ctx)
        snapshot.schemaVersion = SupervisorProjectJobSnapshot.currentSchemaVersion
        if let index = snapshot.jobs.firstIndex(where: { $0.jobId == job.jobId }) {
            snapshot.jobs[index] = job
        } else {
            snapshot.jobs.append(job)
        }
        try normalizeAndSave(&snapshot, for: ctx)
    }

    private static func normalizeAndSave(_ snapshot: inout SupervisorProjectJobSnapshot, for ctx: AXProjectContext) throws {
        snapshot.jobs.sort { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs {
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            return lhs.jobId > rhs.jobId
        }
        snapshot.updatedAtMs = snapshot.jobs.map(\.updatedAtMs).max() ?? snapshot.updatedAtMs
        try save(snapshot, for: ctx)
    }

    private static func save(_ snapshot: SupervisorProjectJobSnapshot, for ctx: AXProjectContext) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let target = ctx.supervisorJobsURL
        let temp = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.moveItem(at: temp, to: target)
    }
}
