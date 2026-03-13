import Foundation

enum SupervisorGuidanceInterventionMode: String, Codable, Sendable {
    case observeOnly = "observe_only"
    case suggestNextSafePoint = "suggest_next_safe_point"
    case replanNextSafePoint = "replan_next_safe_point"
    case stopImmediately = "stop_immediately"
}

enum SupervisorGuidanceSafePointPolicy: String, Codable, Sendable {
    case nextToolBoundary = "next_tool_boundary"
    case nextStepBoundary = "next_step_boundary"
    case checkpointBoundary = "checkpoint_boundary"
    case immediate
}

enum SupervisorGuidanceAckStatus: String, Codable, Sendable {
    case pending
    case accepted
    case deferred
    case rejected
}

struct SupervisorGuidanceInjectionRecord: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_guidance_injection.v1"

    var schemaVersion: String
    var injectionId: String
    var reviewId: String
    var projectId: String
    var targetRole: SupervisorGuidanceTargetRole
    var deliveryMode: SupervisorGuidanceDeliveryMode
    var interventionMode: SupervisorGuidanceInterventionMode
    var safePointPolicy: SupervisorGuidanceSafePointPolicy
    var guidanceText: String
    var ackStatus: SupervisorGuidanceAckStatus
    var ackRequired: Bool
    var ackNote: String
    var injectedAtMs: Int64
    var ackUpdatedAtMs: Int64
    var auditRef: String

    var id: String { injectionId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case injectionId = "injection_id"
        case reviewId = "review_id"
        case projectId = "project_id"
        case targetRole = "target_role"
        case deliveryMode = "delivery_mode"
        case interventionMode = "intervention_mode"
        case safePointPolicy = "safe_point_policy"
        case guidanceText = "guidance_text"
        case ackStatus = "ack_status"
        case ackRequired = "ack_required"
        case ackNote = "ack_note"
        case injectedAtMs = "injected_at_ms"
        case ackUpdatedAtMs = "ack_updated_at_ms"
        case auditRef = "audit_ref"
    }
}

struct SupervisorGuidanceInjectionSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_guidance_injection_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var items: [SupervisorGuidanceInjectionRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case items
    }
}

enum SupervisorGuidanceInjectionBuilder {
    static func build(
        injectionId: String,
        reviewId: String,
        projectId: String,
        targetRole: SupervisorGuidanceTargetRole,
        deliveryMode: SupervisorGuidanceDeliveryMode,
        interventionMode: SupervisorGuidanceInterventionMode,
        safePointPolicy: SupervisorGuidanceSafePointPolicy,
        guidanceText: String,
        ackStatus: SupervisorGuidanceAckStatus,
        ackRequired: Bool,
        ackNote: String,
        injectedAtMs: Int64,
        ackUpdatedAtMs: Int64,
        auditRef: String
    ) -> SupervisorGuidanceInjectionRecord {
        SupervisorGuidanceInjectionRecord(
            schemaVersion: SupervisorGuidanceInjectionRecord.currentSchemaVersion,
            injectionId: normalizedGuidanceToken(injectionId),
            reviewId: normalizedGuidanceToken(reviewId),
            projectId: normalizedGuidanceToken(projectId),
            targetRole: targetRole,
            deliveryMode: deliveryMode,
            interventionMode: interventionMode,
            safePointPolicy: safePointPolicy,
            guidanceText: normalizedGuidanceScalar(guidanceText),
            ackStatus: ackStatus,
            ackRequired: ackRequired,
            ackNote: normalizedGuidanceScalar(ackNote),
            injectedAtMs: max(0, injectedAtMs),
            ackUpdatedAtMs: max(0, ackUpdatedAtMs),
            auditRef: normalizedGuidanceScalar(auditRef)
        )
    }
}

enum SupervisorGuidanceInjectionStore {
    private static let fileName = "supervisor_guidance_injections.json"
    private static let maxItems = 64

    static func load(for ctx: AXProjectContext) -> SupervisorGuidanceInjectionSnapshot {
        try? ctx.ensureDirs()
        guard let data = try? Data(contentsOf: url(for: ctx)),
              let snapshot = try? JSONDecoder().decode(SupervisorGuidanceInjectionSnapshot.self, from: data) else {
            return SupervisorGuidanceInjectionSnapshot(
                schemaVersion: SupervisorGuidanceInjectionSnapshot.currentSchemaVersion,
                updatedAtMs: 0,
                items: []
            )
        }
        return snapshot
    }

    static func upsert(_ item: SupervisorGuidanceInjectionRecord, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        var snapshot = load(for: ctx)
        snapshot.schemaVersion = SupervisorGuidanceInjectionSnapshot.currentSchemaVersion
        if let index = snapshot.items.firstIndex(where: { $0.injectionId == item.injectionId }) {
            snapshot.items[index] = item
        } else {
            snapshot.items.append(item)
        }
        snapshot.items.sort { lhs, rhs in
            if lhs.injectedAtMs != rhs.injectedAtMs {
                return lhs.injectedAtMs > rhs.injectedAtMs
            }
            return lhs.injectionId > rhs.injectionId
        }
        if snapshot.items.count > maxItems {
            snapshot.items = Array(snapshot.items.prefix(maxItems))
        }
        snapshot.updatedAtMs = max(snapshot.updatedAtMs, item.injectedAtMs, item.ackUpdatedAtMs)
        try save(snapshot, for: ctx)
    }

    static func latest(for ctx: AXProjectContext) -> SupervisorGuidanceInjectionRecord? {
        load(for: ctx).items.first
    }

    static func latestPendingAck(for ctx: AXProjectContext) -> SupervisorGuidanceInjectionRecord? {
        load(for: ctx).items.first(where: { $0.ackRequired && $0.ackStatus == .pending })
    }

    static func acknowledge(
        injectionId: String,
        status: SupervisorGuidanceAckStatus,
        note: String,
        atMs: Int64,
        for ctx: AXProjectContext
    ) throws {
        try ctx.ensureDirs()
        var snapshot = load(for: ctx)
        guard let index = snapshot.items.firstIndex(where: { $0.injectionId == injectionId }) else {
            return
        }
        snapshot.items[index].ackStatus = status
        snapshot.items[index].ackNote = normalizedGuidanceScalar(note)
        snapshot.items[index].ackUpdatedAtMs = max(0, atMs)
        snapshot.updatedAtMs = max(snapshot.updatedAtMs, atMs)
        try save(snapshot, for: ctx)
    }

    private static func save(_ snapshot: SupervisorGuidanceInjectionSnapshot, for ctx: AXProjectContext) throws {
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

private func normalizedGuidanceScalar(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedGuidanceToken(_ value: String) -> String {
    let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let scalars = lowered.unicodeScalars.filter {
        CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
    }
    return String(String.UnicodeScalarView(scalars))
}
