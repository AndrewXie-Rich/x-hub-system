import Foundation

enum SupervisorPersonalMemoryCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case personalFact = "personal_fact"
    case habit
    case preference
    case relationship
    case commitment
    case recurringObligation = "recurring_obligation"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personalFact:
            return "Personal Fact"
        case .habit:
            return "Habit"
        case .preference:
            return "Preference"
        case .relationship:
            return "Relationship"
        case .commitment:
            return "Commitment"
        case .recurringObligation:
            return "Recurring"
        }
    }

    var promptLabel: String {
        switch self {
        case .personalFact:
            return "facts"
        case .habit:
            return "habits"
        case .preference:
            return "preferences"
        case .relationship:
            return "relationships"
        case .commitment:
            return "commitments"
        case .recurringObligation:
            return "recurring obligations"
        }
    }
}

enum SupervisorPersonalMemoryStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case watch
    case completed
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .watch:
            return "Watch"
        case .completed:
            return "Completed"
        case .archived:
            return "Archived"
        }
    }
}

struct SupervisorPersonalMemoryRecord: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_personal_memory_record.v1"

    var schemaVersion: String
    var memoryId: String
    var category: SupervisorPersonalMemoryCategory
    var status: SupervisorPersonalMemoryStatus
    var title: String
    var detail: String
    var personName: String
    var tags: [String]
    var dueAtMs: Int64?
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var auditRef: String

    var id: String { memoryId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case memoryId = "memory_id"
        case category
        case status
        case title
        case detail
        case personName = "person_name"
        case tags
        case dueAtMs = "due_at_ms"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case auditRef = "audit_ref"
    }

    var isArchivedLike: Bool {
        status == .archived
    }

    var isActiveLike: Bool {
        switch status {
        case .active, .watch:
            return true
        case .completed, .archived:
            return false
        }
    }

    func normalized() -> SupervisorPersonalMemoryRecord {
        let normalizedId = normalizedPersonalMemoryToken(memoryId, fallback: UUID().uuidString)
        let normalizedTitle = normalizedPersonalMemoryTitle(title, detail: detail, category: category)
        let normalizedUpdatedAt = max(updatedAtMs, createdAtMs, 0)
        return SupervisorPersonalMemoryRecord(
            schemaVersion: Self.currentSchemaVersion,
            memoryId: normalizedId,
            category: category,
            status: status,
            title: normalizedTitle,
            detail: normalizedPersonalMemoryMultiline(detail),
            personName: normalizedPersonalMemorySingleLine(personName),
            tags: orderedUniquePersonalMemoryScalars(tags),
            dueAtMs: normalizedOptionalDueAtMs(dueAtMs),
            createdAtMs: max(0, createdAtMs),
            updatedAtMs: normalizedUpdatedAt,
            auditRef: normalizedPersonalMemoryAuditRef(
                auditRef,
                memoryId: normalizedId,
                category: category,
                updatedAtMs: normalizedUpdatedAt
            )
        )
    }

    static func draft(
        category: SupervisorPersonalMemoryCategory = .personalFact,
        now: Date = Date()
    ) -> SupervisorPersonalMemoryRecord {
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let id = UUID().uuidString
        return SupervisorPersonalMemoryRecord(
            schemaVersion: currentSchemaVersion,
            memoryId: id,
            category: category,
            status: .active,
            title: "",
            detail: "",
            personName: "",
            tags: [],
            dueAtMs: nil,
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            auditRef: "supervisor_personal_memory:\(normalizedPersonalMemoryToken(id, fallback: "draft")):\(nowMs)"
        )
    }
}

struct SupervisorPersonalMemorySnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_personal_memory_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var items: [SupervisorPersonalMemoryRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case items
    }

    static let empty = SupervisorPersonalMemorySnapshot(
        schemaVersion: currentSchemaVersion,
        updatedAtMs: 0,
        items: []
    )

    func normalized() -> SupervisorPersonalMemorySnapshot {
        var seen = Set<String>()
        let normalizedItems = items
            .map { $0.normalized() }
            .filter { record in
                guard !record.title.isEmpty else { return false }
                return seen.insert(record.memoryId).inserted
            }
            .sorted { lhs, rhs in
                if personalMemorySortRank(lhs) != personalMemorySortRank(rhs) {
                    return personalMemorySortRank(lhs) < personalMemorySortRank(rhs)
                }
                if lhs.updatedAtMs != rhs.updatedAtMs {
                    return lhs.updatedAtMs > rhs.updatedAtMs
                }
                return lhs.memoryId > rhs.memoryId
            }
        let updatedAt = max(
            max(0, updatedAtMs),
            normalizedItems.map(\.updatedAtMs).max() ?? 0
        )
        return SupervisorPersonalMemorySnapshot(
            schemaVersion: Self.currentSchemaVersion,
            updatedAtMs: updatedAt,
            items: normalizedItems
        )
    }

    func item(for memoryId: String) -> SupervisorPersonalMemoryRecord? {
        let normalized = normalizedPersonalMemorySingleLine(memoryId)
        guard !normalized.isEmpty else { return nil }
        return items.first { $0.memoryId == normalized }
    }

    func upserting(_ item: SupervisorPersonalMemoryRecord) -> SupervisorPersonalMemorySnapshot {
        var next = normalized()
        let normalizedItem = item.normalized()
        if let index = next.items.firstIndex(where: { $0.memoryId == normalizedItem.memoryId }) {
            next.items[index] = normalizedItem
        } else {
            next.items.append(normalizedItem)
        }
        next.updatedAtMs = max(next.updatedAtMs, normalizedItem.updatedAtMs)
        return next.normalized()
    }

    func deleting(memoryId: String) -> SupervisorPersonalMemorySnapshot {
        var next = normalized()
        next.items.removeAll { $0.memoryId == memoryId }
        next.updatedAtMs = max(next.updatedAtMs, Int64((Date().timeIntervalSince1970 * 1000.0).rounded()))
        return next.normalized()
    }

    func preferredUserName() -> String? {
        SupervisorPersonalMemoryAutoCapture.preferredUserName(from: normalized())
    }
}

struct SupervisorPersonalMemorySummary: Equatable {
    struct CategoryCount: Equatable, Identifiable {
        var category: SupervisorPersonalMemoryCategory
        var count: Int

        var id: String { category.rawValue }
    }

    var totalCount: Int
    var activeCommitmentCount: Int
    var overdueCommitmentCount: Int
    var peopleCount: Int
    var categoryCounts: [CategoryCount]
    var highlightedItems: [String]
    var statusLine: String
    var promptContext: String
}

enum SupervisorPersonalMemorySummaryBuilder {
    static func build(
        snapshot: SupervisorPersonalMemorySnapshot,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> SupervisorPersonalMemorySummary {
        let normalized = snapshot.normalized()
        let visible = normalized.items.filter { !$0.isArchivedLike }
        let people = Set(
            visible.map(\.personName)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let activeCommitments = visible.filter { record in
            record.isActiveLike && (record.category == .commitment || record.category == .recurringObligation)
        }
        let overdueCommitments = activeCommitments.filter { isOverdue($0, now: now) }
        let categoryCounts = SupervisorPersonalMemoryCategory.allCases.compactMap { category -> SupervisorPersonalMemorySummary.CategoryCount? in
            let count = visible.filter { $0.category == category }.count
            return count > 0 ? .init(category: category, count: count) : nil
        }
        let highlights = highlightedLines(
            items: visible,
            now: now,
            timeZone: timeZone,
            locale: locale
        )

        let statusParts = [
            "\(visible.count) items",
            activeCommitments.isEmpty ? nil : "\(activeCommitments.count) open commitments",
            overdueCommitments.isEmpty ? nil : "\(overdueCommitments.count) overdue",
            people.isEmpty ? nil : "\(people.count) people"
        ].compactMap { $0 }

        return SupervisorPersonalMemorySummary(
            totalCount: visible.count,
            activeCommitmentCount: activeCommitments.count,
            overdueCommitmentCount: overdueCommitments.count,
            peopleCount: people.count,
            categoryCounts: categoryCounts,
            highlightedItems: highlights,
            statusLine: statusParts.isEmpty ? "No structured personal memory yet." : statusParts.joined(separator: " · "),
            promptContext: promptContext(
                visible: visible,
                people: Array(people).sorted(),
                activeCommitments: activeCommitments,
                overdueCommitments: overdueCommitments,
                categoryCounts: categoryCounts,
                now: now,
                timeZone: timeZone,
                locale: locale
            )
        )
    }

    private static func highlightedLines(
        items: [SupervisorPersonalMemoryRecord],
        now: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> [String] {
        items
            .sorted { lhs, rhs in
                if isOverdue(lhs, now: now) != isOverdue(rhs, now: now) {
                    return isOverdue(lhs, now: now)
                }
                if normalizedOptionalDueAtMs(lhs.dueAtMs) != normalizedOptionalDueAtMs(rhs.dueAtMs) {
                    return (lhs.dueAtMs ?? Int64.max) < (rhs.dueAtMs ?? Int64.max)
                }
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            .prefix(4)
            .map { item in
                let dueLabel = dueText(item, timeZone: timeZone, locale: locale)
                let person = item.personName.isEmpty ? "" : " · \(item.personName)"
                return "\(item.category.displayName): \(item.title)\(person)\(dueLabel)"
            }
    }

    private static func promptContext(
        visible: [SupervisorPersonalMemoryRecord],
        people: [String],
        activeCommitments: [SupervisorPersonalMemoryRecord],
        overdueCommitments: [SupervisorPersonalMemoryRecord],
        categoryCounts: [SupervisorPersonalMemorySummary.CategoryCount],
        now: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        guard !visible.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("- Structured personal memory items: \(visible.count)")
        if let preferredUserName = SupervisorPersonalMemoryAutoCapture.preferredUserName(
            from: SupervisorPersonalMemorySnapshot(
                schemaVersion: SupervisorPersonalMemorySnapshot.currentSchemaVersion,
                updatedAtMs: visible.map(\.updatedAtMs).max() ?? 0,
                items: visible
            )
        ) {
            lines.append("- Preferred user name: \(preferredUserName)")
        }
        if !categoryCounts.isEmpty {
            let categorySummary = categoryCounts
                .map { "\($0.category.promptLabel)=\($0.count)" }
                .joined(separator: " | ")
            lines.append("- Category counts: \(categorySummary)")
        }
        if !people.isEmpty {
            lines.append("- Key people: \(people.prefix(4).joined(separator: ", "))")
        }
        if !activeCommitments.isEmpty {
            let commitmentSummary = activeCommitments
                .sorted { ($0.dueAtMs ?? Int64.max) < ($1.dueAtMs ?? Int64.max) }
                .prefix(3)
                .map { item in
                    item.title + dueText(item, timeZone: timeZone, locale: locale)
                }
                .joined(separator: " | ")
            lines.append("- Open commitments: \(commitmentSummary)")
        }
        if !overdueCommitments.isEmpty {
            let overdueSummary = overdueCommitments
                .sorted { ($0.dueAtMs ?? Int64.max) < ($1.dueAtMs ?? Int64.max) }
                .prefix(3)
                .map { item in
                    item.title + dueText(item, timeZone: timeZone, locale: locale)
                }
                .joined(separator: " | ")
            lines.append("- Overdue commitments: \(overdueSummary)")
        }

        let preferences = visible.filter { $0.category == .preference || $0.category == .habit || $0.category == .personalFact }
        if !preferences.isEmpty {
            let preferenceSummary = preferences
                .prefix(4)
                .map(\.title)
                .joined(separator: " | ")
            lines.append("- Stable preferences and habits: \(preferenceSummary)")
        }

        return lines.joined(separator: "\n")
    }

    private static func isOverdue(_ item: SupervisorPersonalMemoryRecord, now: Date) -> Bool {
        guard item.isActiveLike, let dueAtMs = normalizedOptionalDueAtMs(item.dueAtMs) else { return false }
        return dueAtMs < Int64((now.timeIntervalSince1970 * 1000.0).rounded())
    }

    private static func dueText(
        _ item: SupervisorPersonalMemoryRecord,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        guard let dueAtMs = normalizedOptionalDueAtMs(item.dueAtMs) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dueText = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(dueAtMs) / 1000.0))
        return " · due \(dueText)"
    }
}

@MainActor
final class SupervisorPersonalMemoryStore: ObservableObject {
    static let shared = SupervisorPersonalMemoryStore()

    @Published private(set) var snapshot: SupervisorPersonalMemorySnapshot

    private let url: URL

    init(
        url: URL? = nil,
        seededSnapshot: SupervisorPersonalMemorySnapshot? = nil
    ) {
        let fm = FileManager.default
        let resolvedURL: URL = {
            if let url { return url }
            let supportBase = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
            let base = supportBase.appendingPathComponent("X-Terminal", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base.appendingPathComponent("supervisor_personal_memory.json")
        }()
        self.url = resolvedURL

        if let seededSnapshot {
            snapshot = seededSnapshot.normalized()
        } else if let data = try? Data(contentsOf: resolvedURL),
                  let decoded = try? JSONDecoder().decode(SupervisorPersonalMemorySnapshot.self, from: data) {
            snapshot = decoded.normalized()
        } else {
            snapshot = .empty
        }
    }

    var summary: SupervisorPersonalMemorySummary {
        SupervisorPersonalMemorySummaryBuilder.build(snapshot: snapshot)
    }

    func replaceSnapshot(_ snapshot: SupervisorPersonalMemorySnapshot) {
        self.snapshot = snapshot.normalized()
        persist()
    }

    func upsert(_ record: SupervisorPersonalMemoryRecord) {
        snapshot = snapshot.upserting(record)
        persist()
    }

    func delete(memoryId: String) {
        snapshot = snapshot.deleting(memoryId: memoryId)
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot.normalized()) else { return }
        try? SupervisorStoreWriteSupport.writeSnapshotData(data, to: url)
    }
}

private func normalizedPersonalMemorySingleLine(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedPersonalMemoryMultiline(_ value: String) -> String {
    value
        .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedPersonalMemoryToken(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func normalizedPersonalMemoryTitle(
    _ title: String,
    detail: String,
    category: SupervisorPersonalMemoryCategory
) -> String {
    let trimmedTitle = normalizedPersonalMemorySingleLine(title)
    if !trimmedTitle.isEmpty {
        return trimmedTitle
    }
    let detailLine = normalizedPersonalMemoryMultiline(detail)
        .split(separator: "\n", maxSplits: 1)
        .first
        .map(String.init)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !detailLine.isEmpty {
        return String(detailLine.prefix(80))
    }
    return ""
}

private func normalizedOptionalDueAtMs(_ value: Int64?) -> Int64? {
    guard let value, value > 0 else { return nil }
    return value
}

private func normalizedPersonalMemoryAuditRef(
    _ auditRef: String,
    memoryId: String,
    category: SupervisorPersonalMemoryCategory,
    updatedAtMs: Int64
) -> String {
    let trimmed = auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
        return trimmed
    }
    return "supervisor_personal_memory:\(category.rawValue):\(memoryId):\(updatedAtMs)"
}

private func orderedUniquePersonalMemoryScalars(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for value in values {
        let normalized = normalizedPersonalMemorySingleLine(value)
        guard !normalized.isEmpty else { continue }
        let key = normalized.lowercased()
        guard seen.insert(key).inserted else { continue }
        output.append(normalized)
    }
    return output
}

private func personalMemorySortRank(_ item: SupervisorPersonalMemoryRecord) -> Int {
    if item.status == .active, item.category == .commitment || item.category == .recurringObligation {
        return item.dueAtMs == nil ? 1 : 0
    }
    if item.status == .watch {
        return 2
    }
    if item.status == .completed {
        return 3
    }
    if item.status == .archived {
        return 4
    }
    return 2
}
