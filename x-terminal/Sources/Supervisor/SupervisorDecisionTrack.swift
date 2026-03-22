import Foundation

struct SupervisorDecisionCategory: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    static let techStack = SupervisorDecisionCategory(rawValue: "tech_stack")
    static let scopeFreeze = SupervisorDecisionCategory(rawValue: "scope_freeze")
    static let riskPosture = SupervisorDecisionCategory(rawValue: "risk_posture")
    static let approvalResult = SupervisorDecisionCategory(rawValue: "approval_result")
    static let uiStyle = SupervisorDecisionCategory(rawValue: "ui_style")

    static let minimumFormalCategories: [SupervisorDecisionCategory] = [
        .techStack,
        .scopeFreeze,
        .riskPosture,
        .approvalResult
    ]

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = SupervisorDecisionCategory.normalize(rawValue)
    }

    init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func normalize(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let pieces = trimmed.split(separator: "_").map(String.init).filter { !$0.isEmpty }
        return pieces.joined(separator: "_")
    }
}

enum SupervisorDecisionStatus: String, Codable, Sendable {
    case proposed
    case approved
    case rejected
    case superseded
    case revoked
}

enum SupervisorDecisionTrackMergeError: Error, Equatable {
    case schemaVersionMismatch
    case decisionIdentityMismatch
}

struct SupervisorDecisionTrackEvent: Identifiable, Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_decision_track_event.v1"

    var schemaVersion: String
    var decisionId: String
    var projectId: String
    var category: SupervisorDecisionCategory
    var status: SupervisorDecisionStatus
    var statement: String
    var source: String
    var reversible: Bool
    var approvalRequired: Bool
    var approvedBy: String
    var auditRef: String
    var evidenceRefs: [String]
    var createdAtMs: Int64
    var updatedAtMs: Int64

    var id: String { decisionId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case decisionId = "decision_id"
        case projectId = "project_id"
        case category
        case status
        case statement
        case source
        case reversible
        case approvalRequired = "approval_required"
        case approvedBy = "approved_by"
        case auditRef = "audit_ref"
        case evidenceRefs = "evidence_refs"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    var canWriteApproved: Bool {
        guard !decisionId.isEmpty,
              !projectId.isEmpty,
              !category.rawValue.isEmpty,
              !statement.isEmpty,
              !source.isEmpty,
              !auditRef.isEmpty,
              updatedAtMs >= createdAtMs else {
            return false
        }
        if approvalRequired {
            return !approvedBy.isEmpty
        }
        return true
    }

    var sanitizedForStorage: SupervisorDecisionTrackEvent {
        var normalized = self
        normalized.schemaVersion = Self.schemaVersion
        normalized.decisionId = normalizedToken(decisionId)
        normalized.projectId = normalizedProjectID(projectId)
        normalized.statement = normalizedScalar(statement)
        normalized.source = normalizedScalar(source)
        normalized.approvedBy = normalizedScalar(approvedBy)
        normalized.auditRef = normalizedScalar(auditRef)
        normalized.evidenceRefs = orderedUniqueDecisionRefs(evidenceRefs)
        normalized.createdAtMs = max(0, createdAtMs)
        normalized.updatedAtMs = max(normalized.createdAtMs, updatedAtMs)
        if normalized.status == .approved && !normalized.canWriteApproved {
            normalized.status = .proposed
        }
        return normalized
    }

    func merged(with incoming: SupervisorDecisionTrackEvent) throws -> SupervisorDecisionTrackEvent {
        guard schemaVersion == Self.schemaVersion, incoming.schemaVersion == Self.schemaVersion else {
            throw SupervisorDecisionTrackMergeError.schemaVersionMismatch
        }

        let incomingWasInvalidApprovedAttempt = incoming.status == .approved && !incoming.canWriteApproved
        let base = sanitizedForStorage
        let other = incoming.sanitizedForStorage
        guard base.decisionId == other.decisionId,
              base.projectId == other.projectId,
              base.category == other.category else {
            throw SupervisorDecisionTrackMergeError.decisionIdentityMismatch
        }

        let incomingWins = other.updatedAtMs > base.updatedAtMs
        let secondary = incomingWins ? base : other
        let preserveBaseApprovedPayload = shouldPreserveBaseApprovedPayload(
            base: base,
            incoming: other,
            incomingWasInvalidApprovedAttempt: incomingWasInvalidApprovedAttempt
        )
        let mergedStatus = preserveBaseApprovedPayload
            ? base.status
            : resolvedStatus(base: base, incoming: other)
        let authoritative = preserveBaseApprovedPayload
            ? base
            : authoritativePayload(base: base, incoming: other)

        return SupervisorDecisionTrackEvent(
            schemaVersion: Self.schemaVersion,
            decisionId: base.decisionId,
            projectId: base.projectId,
            category: base.category,
            status: mergedStatus,
            statement: preferredScalar(authoritative.statement, secondary.statement),
            source: preferredScalar(authoritative.source, secondary.source),
            reversible: authoritative.reversible,
            approvalRequired: authoritative.approvalRequired,
            approvedBy: preferredScalar(authoritative.approvedBy, secondary.approvedBy),
            auditRef: preferredScalar(authoritative.auditRef, secondary.auditRef),
            evidenceRefs: orderedUniqueDecisionRefs(base.evidenceRefs + other.evidenceRefs),
            createdAtMs: min(base.createdAtMs, other.createdAtMs),
            updatedAtMs: max(base.updatedAtMs, other.updatedAtMs)
        ).sanitizedForStorage
    }
}

struct SupervisorDecisionTrackSnapshot: Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_decision_track.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var events: [SupervisorDecisionTrackEvent]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case events
    }
}

enum SupervisorDecisionTrack {
    static func merged(
        existing: [SupervisorDecisionTrackEvent],
        incoming: [SupervisorDecisionTrackEvent]
    ) throws -> [SupervisorDecisionTrackEvent] {
        var mergedByID: [String: SupervisorDecisionTrackEvent] = [:]

        for event in existing + incoming {
            let normalized = event.sanitizedForStorage
            guard !normalized.decisionId.isEmpty else { continue }
            if let current = mergedByID[normalized.decisionId] {
                mergedByID[normalized.decisionId] = try current.merged(with: normalized)
            } else {
                mergedByID[normalized.decisionId] = normalized
            }
        }

        return mergedByID.values.sorted(by: decisionEventSort)
    }

    static func hardConstraints(from events: [SupervisorDecisionTrackEvent]) -> [SupervisorDecisionCategory: SupervisorDecisionTrackEvent] {
        let sorted = events.map(\.sanitizedForStorage).sorted(by: decisionEventSort)
        var resolved: [SupervisorDecisionCategory: SupervisorDecisionTrackEvent] = [:]

        for event in sorted where event.status == .approved && event.canWriteApproved {
            if resolved[event.category] == nil {
                resolved[event.category] = event
            }
        }

        return resolved
    }
}

enum SupervisorDecisionTrackBuilder {
    static func build(
        decisionId: String,
        projectId: String,
        category: SupervisorDecisionCategory,
        status: SupervisorDecisionStatus,
        statement: String,
        source: String,
        reversible: Bool,
        approvalRequired: Bool,
        approvedBy: String = "",
        auditRef: String,
        evidenceRefs: [String] = [],
        createdAtMs: Int64,
        updatedAtMs: Int64? = nil
    ) -> SupervisorDecisionTrackEvent {
        SupervisorDecisionTrackEvent(
            schemaVersion: SupervisorDecisionTrackEvent.schemaVersion,
            decisionId: decisionId,
            projectId: projectId,
            category: category,
            status: status,
            statement: statement,
            source: source,
            reversible: reversible,
            approvalRequired: approvalRequired,
            approvedBy: approvedBy,
            auditRef: auditRef,
            evidenceRefs: evidenceRefs,
            createdAtMs: createdAtMs,
            updatedAtMs: updatedAtMs ?? createdAtMs
        ).sanitizedForStorage
    }
}

enum SupervisorDecisionTrackStore {
    private static let fileName = "supervisor_decision_track.json"

    static func load(for ctx: AXProjectContext) -> SupervisorDecisionTrackSnapshot {
        try? ctx.ensureDirs()
        guard let data = try? Data(contentsOf: url(for: ctx)),
              let snapshot = try? JSONDecoder().decode(SupervisorDecisionTrackSnapshot.self, from: data) else {
            return SupervisorDecisionTrackSnapshot(
                schemaVersion: SupervisorDecisionTrackSnapshot.schemaVersion,
                updatedAtMs: 0,
                events: []
            )
        }
        return snapshot
    }

    @discardableResult
    static func upsert(_ event: SupervisorDecisionTrackEvent, for ctx: AXProjectContext) throws -> SupervisorDecisionTrackSnapshot {
        try ctx.ensureDirs()
        var snapshot = load(for: ctx)
        snapshot.schemaVersion = SupervisorDecisionTrackSnapshot.schemaVersion
        snapshot.events = try SupervisorDecisionTrack.merged(existing: snapshot.events, incoming: [event])
        snapshot.updatedAtMs = max(snapshot.updatedAtMs, event.sanitizedForStorage.updatedAtMs)
        try save(snapshot, for: ctx)
        return snapshot
    }

    static func save(_ snapshot: SupervisorDecisionTrackSnapshot, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let target = url(for: ctx)
        try SupervisorStoreWriteSupport.writeSnapshotData(data, to: target)
    }

    private static func url(for ctx: AXProjectContext) -> URL {
        ctx.xterminalDir.appendingPathComponent(fileName)
    }
}

func decisionEventSort(_ lhs: SupervisorDecisionTrackEvent, _ rhs: SupervisorDecisionTrackEvent) -> Bool {
    if lhs.updatedAtMs != rhs.updatedAtMs {
        return lhs.updatedAtMs > rhs.updatedAtMs
    }
    return lhs.decisionId > rhs.decisionId
}

private func resolvedStatus(
    base: SupervisorDecisionTrackEvent,
    incoming: SupervisorDecisionTrackEvent
) -> SupervisorDecisionStatus {
    if incoming.updatedAtMs > base.updatedAtMs {
        if incoming.status == .approved && !incoming.canWriteApproved {
            return base.status
        }
        return incoming.status
    }
    if incoming.updatedAtMs < base.updatedAtMs {
        return base.status
    }

    if statusRank(incoming.status) > statusRank(base.status) {
        if incoming.status == .approved && !incoming.canWriteApproved {
            return base.status
        }
        return incoming.status
    }
    return base.status
}

private func shouldPreserveBaseApprovedPayload(
    base: SupervisorDecisionTrackEvent,
    incoming: SupervisorDecisionTrackEvent,
    incomingWasInvalidApprovedAttempt: Bool
) -> Bool {
    base.status == .approved &&
    base.canWriteApproved &&
    incomingWasInvalidApprovedAttempt &&
    incoming.updatedAtMs >= base.updatedAtMs
}

private func authoritativePayload(
    base: SupervisorDecisionTrackEvent,
    incoming: SupervisorDecisionTrackEvent
) -> SupervisorDecisionTrackEvent {
    if incoming.updatedAtMs > base.updatedAtMs {
        return incoming
    }
    if incoming.updatedAtMs < base.updatedAtMs {
        return base
    }
    if statusRank(incoming.status) > statusRank(base.status) {
        return incoming
    }
    return base
}

private func statusRank(_ status: SupervisorDecisionStatus) -> Int {
    switch status {
    case .approved:
        return 5
    case .superseded:
        return 4
    case .rejected:
        return 3
    case .revoked:
        return 2
    case .proposed:
        return 1
    }
}

private func orderedUniqueDecisionRefs(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for raw in values {
        let normalized = normalizedScalar(raw)
        guard !normalized.isEmpty else { continue }
        if seen.insert(normalized).inserted {
            ordered.append(normalized)
        }
    }
    return ordered
}

private func normalizedToken(_ raw: String) -> String {
    normalizedScalar(raw)
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")
}

private func normalizedProjectID(_ raw: String) -> String {
    normalizedScalar(raw).lowercased()
}

private func normalizedScalar(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func preferredScalar(_ primary: String, _ fallback: String) -> String {
    let normalizedPrimary = normalizedScalar(primary)
    if !normalizedPrimary.isEmpty {
        return normalizedPrimary
    }
    return normalizedScalar(fallback)
}
