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
    var effectiveSupervisorTier: AXProjectSupervisorInterventionTier? = nil
    var effectiveWorkOrderDepth: AXProjectSupervisorWorkOrderDepth? = nil
    var workOrderRef: String? = nil
    var ackNote: String
    var injectedAtMs: Int64
    var ackUpdatedAtMs: Int64
    var expiresAtMs: Int64 = 0
    var retryAtMs: Int64 = 0
    var retryCount: Int = 0
    var maxRetryCount: Int = 0
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
        case effectiveSupervisorTier = "effective_supervisor_tier"
        case effectiveWorkOrderDepth = "effective_work_order_depth"
        case workOrderRef = "work_order_ref"
        case ackNote = "ack_note"
        case injectedAtMs = "injected_at_ms"
        case ackUpdatedAtMs = "ack_updated_at_ms"
        case expiresAtMs = "expires_at_ms"
        case retryAtMs = "retry_at_ms"
        case retryCount = "retry_count"
        case maxRetryCount = "max_retry_count"
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
        effectiveSupervisorTier: AXProjectSupervisorInterventionTier? = nil,
        effectiveWorkOrderDepth: AXProjectSupervisorWorkOrderDepth? = nil,
        workOrderRef: String? = nil,
        ackNote: String,
        injectedAtMs: Int64,
        ackUpdatedAtMs: Int64,
        expiresAtMs: Int64 = 0,
        retryAtMs: Int64 = 0,
        retryCount: Int = 0,
        maxRetryCount: Int = 0,
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
            effectiveSupervisorTier: effectiveSupervisorTier,
            effectiveWorkOrderDepth: effectiveWorkOrderDepth,
            workOrderRef: normalizedOptionalGuidanceScalar(workOrderRef),
            ackNote: normalizedGuidanceScalar(ackNote),
            injectedAtMs: max(0, injectedAtMs),
            ackUpdatedAtMs: max(0, ackUpdatedAtMs),
            expiresAtMs: max(0, expiresAtMs),
            retryAtMs: max(0, retryAtMs),
            retryCount: max(0, retryCount),
            maxRetryCount: max(0, maxRetryCount),
            auditRef: normalizedGuidanceScalar(auditRef)
        )
    }
}

enum SupervisorGuidanceInjectionStore {
    private static let fileName = "supervisor_guidance_injections.json"
    private static let maxItems = 64

    private static func currentNowMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }

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

    static func latestPendingAck(
        for ctx: AXProjectContext,
        nowMs: Int64 = currentNowMs()
    ) -> SupervisorGuidanceInjectionRecord? {
        actionableItems(
            from: load(for: ctx).items,
            nowMs: nowMs
        ).first
    }

    static func actionableItems(
        from items: [SupervisorGuidanceInjectionRecord],
        nowMs: Int64
    ) -> [SupervisorGuidanceInjectionRecord] {
        items.filter { isActionable($0, nowMs: nowMs) }
    }

    static func isActionable(
        _ item: SupervisorGuidanceInjectionRecord,
        nowMs: Int64
    ) -> Bool {
        guard item.ackRequired, !isExpired(item, nowMs: nowMs) else { return false }
        switch item.ackStatus {
        case .pending:
            return true
        case .deferred:
            return isRetryDue(item, nowMs: nowMs)
        case .accepted, .rejected:
            return false
        }
    }

    static func isExpired(
        _ item: SupervisorGuidanceInjectionRecord,
        nowMs: Int64
    ) -> Bool {
        item.expiresAtMs > 0 && nowMs >= item.expiresAtMs
    }

    static func isRetryDue(
        _ item: SupervisorGuidanceInjectionRecord,
        nowMs: Int64
    ) -> Bool {
        guard item.ackStatus == .deferred else { return false }
        guard item.maxRetryCount > 0 else { return false }
        guard item.retryCount > 0 && item.retryCount <= item.maxRetryCount else { return false }
        guard item.retryAtMs > 0 && nowMs >= item.retryAtMs else { return false }
        return !isExpired(item, nowMs: nowMs)
    }

    static func lifecycleSummary(
        for item: SupervisorGuidanceInjectionRecord,
        nowMs: Int64
    ) -> String {
        if isExpired(item, nowMs: nowMs) {
            return "expired"
        }

        switch item.ackStatus {
        case .pending:
            if item.expiresAtMs > 0 {
                return "expires \(relativeTimeText(from: nowMs, to: item.expiresAtMs))"
            }
            return "active"
        case .deferred:
            if isRetryDue(item, nowMs: nowMs) {
                return "retry due now"
            }
            if item.retryAtMs > 0 {
                return "retry \(relativeTimeText(from: nowMs, to: item.retryAtMs))"
            }
            return item.maxRetryCount > 0 ? "retry budget exhausted" : "deferred"
        case .accepted, .rejected:
            return "settled"
        }
    }

    static func record(
        injectionId: String,
        for ctx: AXProjectContext
    ) -> SupervisorGuidanceInjectionRecord? {
        let normalized = normalizedGuidanceToken(injectionId)
        guard !normalized.isEmpty else { return nil }
        return load(for: ctx).items.first(where: { $0.injectionId == normalized })
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
        switch status {
        case .accepted, .rejected, .pending:
            snapshot.items[index].retryAtMs = 0
        case .deferred:
            snapshot.items[index].retryCount += 1
            let retryCount = snapshot.items[index].retryCount
            let maxRetryCount = snapshot.items[index].maxRetryCount
            if maxRetryCount > 0, retryCount <= maxRetryCount {
                let retryDelayMs = deferredRetryDelayMs(
                    for: snapshot.items[index],
                    retryCount: retryCount
                )
                let candidate = max(0, atMs) + retryDelayMs
                if snapshot.items[index].expiresAtMs > 0,
                   candidate >= snapshot.items[index].expiresAtMs {
                    snapshot.items[index].retryAtMs = 0
                } else {
                    snapshot.items[index].retryAtMs = candidate
                }
            } else {
                snapshot.items[index].retryAtMs = 0
            }
        }
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

    private static func deferredRetryDelayMs(
        for item: SupervisorGuidanceInjectionRecord,
        retryCount: Int
    ) -> Int64 {
        let baseMinutes: Int64
        switch item.safePointPolicy {
        case .immediate:
            baseMinutes = 2
        case .nextToolBoundary:
            baseMinutes = 5
        case .nextStepBoundary:
            baseMinutes = 10
        case .checkpointBoundary:
            baseMinutes = 15
        }
        return baseMinutes * Int64(max(1, retryCount)) * 60 * 1000
    }

    private static func relativeTimeText(from nowMs: Int64, to targetMs: Int64) -> String {
        let deltaSeconds = Int(((targetMs - nowMs) + (targetMs >= nowMs ? 999 : -999)) / 1000)
        if deltaSeconds == 0 { return "now" }
        let isFuture = deltaSeconds > 0
        let absoluteSeconds = abs(deltaSeconds)
        let minutes = absoluteSeconds / 60
        if minutes < 1 {
            return isFuture ? "in <1m" : "<1m ago"
        }
        let hours = minutes / 60
        let restMinutes = minutes % 60
        if hours < 1 {
            return isFuture ? "in \(minutes)m" : "\(minutes)m ago"
        }
        if restMinutes == 0 {
            return isFuture ? "in \(hours)h" : "\(hours)h ago"
        }
        return isFuture ? "in \(hours)h \(restMinutes)m" : "\(hours)h \(restMinutes)m ago"
    }
}

private func normalizedGuidanceScalar(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedOptionalGuidanceScalar(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = normalizedGuidanceScalar(value)
    return normalized.isEmpty ? nil : normalized
}

private func normalizedGuidanceToken(_ value: String) -> String {
    let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let scalars = lowered.unicodeScalars.filter {
        CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
    }
    return String(String.UnicodeScalarView(scalars))
}
