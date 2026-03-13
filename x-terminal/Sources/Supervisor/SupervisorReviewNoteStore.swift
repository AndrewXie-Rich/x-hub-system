import Foundation

enum SupervisorReviewTrigger: String, Codable, Sendable {
    case periodicHeartbeat = "periodic_heartbeat"
    case periodicPulse = "periodic_pulse"
    case failureStreak = "failure_streak"
    case noProgressWindow = "no_progress_window"
    case blockerDetected = "blocker_detected"
    case planDrift = "plan_drift"
    case preHighRiskAction = "pre_high_risk_action"
    case preDoneSummary = "pre_done_summary"
    case manualRequest = "manual_request"
    case userOverride = "user_override"
}

enum SupervisorReviewLevel: String, Codable, Sendable {
    case r1Pulse = "r1_pulse"
    case r2Strategic = "r2_strategic"
    case r3Rescue = "r3_rescue"
}

enum SupervisorReviewVerdict: String, Codable, Sendable {
    case onTrack = "on_track"
    case watch
    case betterPathFound = "better_path_found"
    case wrongDirection = "wrong_direction"
    case highRisk = "high_risk"
}

enum SupervisorGuidanceTargetRole: String, Codable, Sendable {
    case coder
    case supervisor
    case projectChat = "project_chat"
}

enum SupervisorGuidanceDeliveryMode: String, Codable, Sendable {
    case contextAppend = "context_append"
    case priorityInsert = "priority_insert"
    case replanRequest = "replan_request"
    case stopSignal = "stop_signal"
}

struct SupervisorReviewNoteRecord: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_review_note.v1"

    var schemaVersion: String
    var reviewId: String
    var projectId: String
    var trigger: SupervisorReviewTrigger
    var reviewLevel: SupervisorReviewLevel
    var verdict: SupervisorReviewVerdict
    var targetRole: SupervisorGuidanceTargetRole
    var deliveryMode: SupervisorGuidanceDeliveryMode
    var ackRequired: Bool
    var summary: String
    var recommendedActions: [String]
    var anchorGoal: String
    var anchorDoneDefinition: String
    var anchorConstraints: [String]
    var currentState: String
    var nextStep: String
    var blocker: String
    var createdAtMs: Int64
    var auditRef: String

    var id: String { reviewId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case reviewId = "review_id"
        case projectId = "project_id"
        case trigger
        case reviewLevel = "review_level"
        case verdict
        case targetRole = "target_role"
        case deliveryMode = "delivery_mode"
        case ackRequired = "ack_required"
        case summary
        case recommendedActions = "recommended_actions"
        case anchorGoal = "anchor_goal"
        case anchorDoneDefinition = "anchor_done_definition"
        case anchorConstraints = "anchor_constraints"
        case currentState = "current_state"
        case nextStep = "next_step"
        case blocker
        case createdAtMs = "created_at_ms"
        case auditRef = "audit_ref"
    }
}

struct SupervisorReviewNoteSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_review_notes_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var notes: [SupervisorReviewNoteRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case notes
    }
}

enum SupervisorReviewNoteBuilder {
    static func build(
        reviewId: String,
        projectId: String,
        trigger: SupervisorReviewTrigger,
        reviewLevel: SupervisorReviewLevel,
        verdict: SupervisorReviewVerdict,
        targetRole: SupervisorGuidanceTargetRole,
        deliveryMode: SupervisorGuidanceDeliveryMode,
        ackRequired: Bool,
        summary: String,
        recommendedActions: [String],
        anchorGoal: String,
        anchorDoneDefinition: String,
        anchorConstraints: [String],
        currentState: String,
        nextStep: String,
        blocker: String,
        createdAtMs: Int64,
        auditRef: String
    ) -> SupervisorReviewNoteRecord {
        SupervisorReviewNoteRecord(
            schemaVersion: SupervisorReviewNoteRecord.currentSchemaVersion,
            reviewId: normalizedReviewToken(reviewId),
            projectId: normalizedReviewToken(projectId),
            trigger: trigger,
            reviewLevel: reviewLevel,
            verdict: verdict,
            targetRole: targetRole,
            deliveryMode: deliveryMode,
            ackRequired: ackRequired,
            summary: normalizedReviewScalar(summary),
            recommendedActions: orderedUniqueReviewScalars(recommendedActions),
            anchorGoal: normalizedReviewScalar(anchorGoal),
            anchorDoneDefinition: normalizedReviewScalar(anchorDoneDefinition),
            anchorConstraints: orderedUniqueReviewScalars(anchorConstraints),
            currentState: normalizedReviewScalar(currentState),
            nextStep: normalizedReviewScalar(nextStep),
            blocker: normalizedReviewScalar(blocker),
            createdAtMs: max(0, createdAtMs),
            auditRef: normalizedReviewScalar(auditRef)
        )
    }
}

enum SupervisorReviewNoteStore {
    private static let fileName = "supervisor_review_notes.json"
    private static let maxNotes = 64

    static func load(for ctx: AXProjectContext) -> SupervisorReviewNoteSnapshot {
        try? ctx.ensureDirs()
        guard let data = try? Data(contentsOf: url(for: ctx)),
              let snapshot = try? JSONDecoder().decode(SupervisorReviewNoteSnapshot.self, from: data) else {
            return SupervisorReviewNoteSnapshot(
                schemaVersion: SupervisorReviewNoteSnapshot.currentSchemaVersion,
                updatedAtMs: 0,
                notes: []
            )
        }
        return snapshot
    }

    static func upsert(_ note: SupervisorReviewNoteRecord, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        var snapshot = load(for: ctx)
        snapshot.schemaVersion = SupervisorReviewNoteSnapshot.currentSchemaVersion
        if let index = snapshot.notes.firstIndex(where: { $0.reviewId == note.reviewId }) {
            snapshot.notes[index] = note
        } else {
            snapshot.notes.append(note)
        }
        snapshot.notes.sort { lhs, rhs in
            if lhs.createdAtMs != rhs.createdAtMs {
                return lhs.createdAtMs > rhs.createdAtMs
            }
            return lhs.reviewId > rhs.reviewId
        }
        if snapshot.notes.count > maxNotes {
            snapshot.notes = Array(snapshot.notes.prefix(maxNotes))
        }
        snapshot.updatedAtMs = max(snapshot.updatedAtMs, note.createdAtMs)
        try save(snapshot, for: ctx)
    }

    static func latest(for ctx: AXProjectContext) -> SupervisorReviewNoteRecord? {
        load(for: ctx).notes.first
    }

    private static func save(_ snapshot: SupervisorReviewNoteSnapshot, for ctx: AXProjectContext) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let target = url(for: ctx)
        let temp = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.moveItem(at: temp, to: target)
    }

    private static func url(for ctx: AXProjectContext) -> URL {
        ctx.xterminalDir.appendingPathComponent(fileName)
    }
}

private func normalizedReviewScalar(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func orderedUniqueReviewScalars(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for value in values {
        let normalized = normalizedReviewScalar(value)
        guard !normalized.isEmpty else { continue }
        guard seen.insert(normalized).inserted else { continue }
        ordered.append(normalized)
    }
    return ordered
}

private func normalizedReviewToken(_ value: String) -> String {
    let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let scalars = lowered.unicodeScalars.filter {
        CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
    }
    return String(String.UnicodeScalarView(scalars))
}
