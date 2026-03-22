import Foundation

enum SupervisorCrossLinkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case personWaitingOnProject = "person_waiting_on_project"
    case commitmentDependsOnProject = "commitment_depends_on_project"
    case meetingAboutProject = "meeting_about_project"
    case followUpTriggeredByProject = "follow_up_triggered_by_project"
    case userPriorityConstrainedByProject = "user_priority_constrained_by_project"

    var id: String { rawValue }
}

enum SupervisorCrossLinkStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case watch
    case resolved
    case archived

    var id: String { rawValue }
}

struct SupervisorCrossLinkRecord: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_cross_link_record.v1"

    var schemaVersion: String
    var linkId: String
    var kind: SupervisorCrossLinkKind
    var status: SupervisorCrossLinkStatus
    var summary: String
    var personName: String
    var commitmentId: String?
    var projectId: String
    var projectName: String
    var backingRecordRefs: [String]
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var auditRef: String

    var id: String { linkId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case linkId = "link_id"
        case kind
        case status
        case summary
        case personName = "person_name"
        case commitmentId = "commitment_id"
        case projectId = "project_id"
        case projectName = "project_name"
        case backingRecordRefs = "backing_record_refs"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case auditRef = "audit_ref"
    }

    var isActiveLike: Bool {
        switch status {
        case .active, .watch:
            return true
        case .resolved, .archived:
            return false
        }
    }

    func normalized() -> SupervisorCrossLinkRecord {
        let normalizedLinkId = normalizedCrossLinkToken(linkId, fallback: UUID().uuidString)
        let normalizedUpdatedAt = max(updatedAtMs, createdAtMs, 0)
        return SupervisorCrossLinkRecord(
            schemaVersion: Self.currentSchemaVersion,
            linkId: normalizedLinkId,
            kind: kind,
            status: status,
            summary: normalizedCrossLinkSummary(summary),
            personName: normalizedCrossLinkScalar(personName),
            commitmentId: normalizedOptionalCrossLinkScalar(commitmentId),
            projectId: normalizedCrossLinkScalar(projectId),
            projectName: normalizedCrossLinkScalar(projectName),
            backingRecordRefs: orderedUniqueCrossLinkScalars(backingRecordRefs),
            createdAtMs: max(0, createdAtMs),
            updatedAtMs: normalizedUpdatedAt,
            auditRef: normalizedCrossLinkAuditRef(
                auditRef,
                linkId: normalizedLinkId,
                kind: kind,
                updatedAtMs: normalizedUpdatedAt
            )
        )
    }
}

struct SupervisorCrossLinkSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_cross_link_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var items: [SupervisorCrossLinkRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case items
    }

    static let empty = SupervisorCrossLinkSnapshot(
        schemaVersion: currentSchemaVersion,
        updatedAtMs: 0,
        items: []
    )

    func normalized() -> SupervisorCrossLinkSnapshot {
        var seen = Set<String>()
        let normalizedItems = items
            .map { $0.normalized() }
            .filter { record in
                guard !record.projectId.isEmpty else { return false }
                guard !record.summary.isEmpty || !record.personName.isEmpty || record.commitmentId != nil else {
                    return false
                }
                return seen.insert(record.linkId).inserted
            }
            .sorted { lhs, rhs in
                if crossLinkSortRank(lhs) != crossLinkSortRank(rhs) {
                    return crossLinkSortRank(lhs) < crossLinkSortRank(rhs)
                }
                if lhs.updatedAtMs != rhs.updatedAtMs {
                    return lhs.updatedAtMs > rhs.updatedAtMs
                }
                return lhs.linkId > rhs.linkId
            }
        let updatedAt = max(
            max(0, updatedAtMs),
            normalizedItems.map(\.updatedAtMs).max() ?? 0
        )
        return SupervisorCrossLinkSnapshot(
            schemaVersion: Self.currentSchemaVersion,
            updatedAtMs: updatedAt,
            items: normalizedItems
        )
    }

    func upserting(_ item: SupervisorCrossLinkRecord) -> SupervisorCrossLinkSnapshot {
        var next = normalized()
        let normalizedItem = item.normalized()
        if let index = next.items.firstIndex(where: { $0.linkId == normalizedItem.linkId }) {
            next.items[index] = normalizedItem
        } else {
            next.items.append(normalizedItem)
        }
        next.updatedAtMs = max(next.updatedAtMs, normalizedItem.updatedAtMs)
        return next.normalized()
    }
}

struct SupervisorCrossLinkSummary: Equatable {
    var totalCount: Int
    var activeCount: Int
    var selectedCount: Int
    var statusLine: String
    var promptContext: String
}

enum SupervisorCrossLinkSummaryBuilder {
    private static let focusedLimit = 4
    private static let portfolioLimit = 3

    static func build(
        snapshot: SupervisorCrossLinkSnapshot,
        projects: [AXProjectEntry],
        focusedProjectId: String?,
        focusedPersonName: String?,
        focusedCommitmentId: String?,
        turnMode: SupervisorTurnMode?,
        now: Date = Date()
    ) -> SupervisorCrossLinkSummary {
        let normalizedSnapshot = snapshot.normalized()
        let activeItems = normalizedSnapshot.items.filter(\.isActiveLike)
        let selected = selectedItems(
            from: activeItems,
            projects: projects,
            focusedProjectId: focusedProjectId,
            focusedPersonName: focusedPersonName,
            focusedCommitmentId: focusedCommitmentId,
            turnMode: turnMode
        )
        let statusLine: String
        if activeItems.isEmpty {
            statusLine = "No durable cross-links recorded."
        } else if selected.isEmpty {
            statusLine = "No relevant cross-links selected for this turn."
        } else {
            statusLine = "\(selected.count) cross-link refs selected · active total \(activeItems.count)"
        }
        return SupervisorCrossLinkSummary(
            totalCount: normalizedSnapshot.items.count,
            activeCount: activeItems.count,
            selectedCount: selected.count,
            statusLine: statusLine,
            promptContext: promptContext(
                selected,
                projects: projects,
                now: now,
                statusLine: statusLine
            )
        )
    }

    private static func selectedItems(
        from items: [SupervisorCrossLinkRecord],
        projects: [AXProjectEntry],
        focusedProjectId: String?,
        focusedPersonName: String?,
        focusedCommitmentId: String?,
        turnMode: SupervisorTurnMode?
    ) -> [SupervisorCrossLinkRecord] {
        let normalizedProjectId = normalizedOptionalCrossLinkScalar(focusedProjectId)
        let normalizedPersonName = normalizedCrossLinkLookupKey(focusedPersonName ?? "")
        let normalizedCommitmentId = normalizedOptionalCrossLinkScalar(focusedCommitmentId)
        let hasFocus = normalizedProjectId != nil || !normalizedPersonName.isEmpty || normalizedCommitmentId != nil

        let scored = items
            .map { item in
                (
                    item: item,
                    score: selectionScore(
                        item,
                        focusedProjectId: normalizedProjectId,
                        focusedPersonName: normalizedPersonName,
                        focusedCommitmentId: normalizedCommitmentId
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.item.updatedAtMs != rhs.item.updatedAtMs {
                    return lhs.item.updatedAtMs > rhs.item.updatedAtMs
                }
                return lhs.item.linkId > rhs.item.linkId
            }

        if hasFocus {
            return scored
                .filter { $0.score > 0 }
                .prefix(focusedLimit)
                .map(\.item)
        }

        guard turnMode == .portfolioReview else {
            return []
        }

        return scored
            .prefix(portfolioLimit)
            .map(\.item)
    }

    private static func selectionScore(
        _ item: SupervisorCrossLinkRecord,
        focusedProjectId: String?,
        focusedPersonName: String,
        focusedCommitmentId: String?
    ) -> Int {
        var score = 0
        if let focusedProjectId, item.projectId == focusedProjectId {
            score += 120
        }
        if !focusedPersonName.isEmpty,
           normalizedCrossLinkLookupKey(item.personName) == focusedPersonName {
            score += 120
        }
        if let focusedCommitmentId,
           item.commitmentId == focusedCommitmentId {
            score += 120
        }
        if score > 0,
           (focusedProjectId != nil && !focusedPersonName.isEmpty || focusedCommitmentId != nil) {
            score += 20
        }
        return score
    }

    private static func promptContext(
        _ items: [SupervisorCrossLinkRecord],
        projects: [AXProjectEntry],
        now: Date,
        statusLine: String
    ) -> String {
        guard !items.isEmpty else { return "" }
        let projectNames = projects.reduce(into: [String: String]()) { partial, project in
            partial[project.projectId] = project.displayName
        }
        let lines = items.map { item -> String in
            let projectName = projectNames[item.projectId] ?? item.projectName
            let backingRefs = item.backingRecordRefs.isEmpty
                ? "(none)"
                : item.backingRecordRefs.joined(separator: ", ")
            let commitmentPart = item.commitmentId.map { " commitment_id=\($0)" } ?? ""
            return "- link_id=\(item.linkId) kind=\(item.kind.rawValue) status=\(item.status.rawValue) summary=\(cappedCrossLinkText(item.summary, maxChars: 180)) person_name=\(item.personName.isEmpty ? "(none)" : item.personName)\(commitmentPart) project_id=\(item.projectId) project_name=\(projectName.isEmpty ? "(unknown)" : projectName) freshness_hint=\(freshnessHint(item.updatedAtMs, now: now)) backing_record_refs=\(backingRefs)"
        }
        return """
status_line: \(statusLine)
selected_items:
\(lines.joined(separator: "\n"))
"""
    }

    private static func freshnessHint(_ updatedAtMs: Int64, now: Date) -> String {
        let ageSec = max(0, now.timeIntervalSince1970 - (Double(updatedAtMs) / 1000.0))
        switch ageSec {
        case ..<3600:
            return "fresh"
        case ..<86400:
            return "recent"
        default:
            return "stale"
        }
    }
}

final class SupervisorCrossLinkStore: ObservableObject {
    static let shared = SupervisorCrossLinkStore()

    @Published private(set) var snapshot: SupervisorCrossLinkSnapshot

    private let url: URL

    init(
        url: URL? = nil,
        seededSnapshot: SupervisorCrossLinkSnapshot? = nil
    ) {
        let fm = FileManager.default
        let resolvedURL: URL = {
            if let url { return url }
            let supportBase = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
            let base = supportBase.appendingPathComponent("X-Terminal", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base.appendingPathComponent("supervisor_cross_links.json")
        }()
        self.url = resolvedURL

        if let seededSnapshot {
            snapshot = seededSnapshot.normalized()
        } else if let data = try? Data(contentsOf: resolvedURL),
                  let decoded = try? JSONDecoder().decode(SupervisorCrossLinkSnapshot.self, from: data) {
            snapshot = decoded.normalized()
        } else {
            snapshot = .empty
        }
    }

    func replaceSnapshot(_ snapshot: SupervisorCrossLinkSnapshot) {
        self.snapshot = snapshot.normalized()
        persist()
    }

    func upsert(_ record: SupervisorCrossLinkRecord) {
        snapshot = snapshot.upserting(record)
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot.normalized()) else { return }
        try? SupervisorStoreWriteSupport.writeSnapshotData(data, to: url)
    }
}

private func normalizedCrossLinkScalar(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedOptionalCrossLinkScalar(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = normalizedCrossLinkScalar(value)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedCrossLinkSummary(_ value: String) -> String {
    value
        .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedCrossLinkToken(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func normalizedCrossLinkAuditRef(
    _ auditRef: String,
    linkId: String,
    kind: SupervisorCrossLinkKind,
    updatedAtMs: Int64
) -> String {
    let trimmed = auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
        return trimmed
    }
    return "supervisor_cross_link:\(kind.rawValue):\(linkId):\(updatedAtMs)"
}

private func orderedUniqueCrossLinkScalars(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for value in values {
        let normalized = normalizedCrossLinkScalar(value)
        guard !normalized.isEmpty else { continue }
        let key = normalized.lowercased()
        guard seen.insert(key).inserted else { continue }
        output.append(normalized)
    }
    return output
}

private func crossLinkSortRank(_ item: SupervisorCrossLinkRecord) -> Int {
    switch item.status {
    case .active:
        return 0
    case .watch:
        return 1
    case .resolved:
        return 2
    case .archived:
        return 3
    }
}

private func cappedCrossLinkText(_ text: String, maxChars: Int) -> String {
    guard maxChars > 0, text.count > maxChars else { return text }
    return String(text.prefix(max(0, maxChars - 1))).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
}

private func normalizedCrossLinkLookupKey(_ text: String) -> String {
    text
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        .lowercased()
        .filter { $0.isLetter || $0.isNumber }
}
