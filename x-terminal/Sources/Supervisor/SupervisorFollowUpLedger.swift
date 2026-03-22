import Foundation

enum SupervisorFollowUpUrgency: String, Codable, CaseIterable, Identifiable, Sendable {
    case overdue
    case dueSoon = "due_soon"
    case watch
    case stable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overdue:
            return "Overdue"
        case .dueSoon:
            return "Due Soon"
        case .watch:
            return "Watch"
        case .stable:
            return "Stable"
        }
    }
}

struct SupervisorFollowUpLedgerItem: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_follow_up_ledger_item.v1"

    var schemaVersion: String
    var followUpId: String
    var sourceMemoryId: String
    var category: SupervisorPersonalMemoryCategory
    var title: String
    var personName: String
    var urgency: SupervisorFollowUpUrgency
    var dueAtMs: Int64?
    var sourceUpdatedAtMs: Int64
    var sourceStatus: SupervisorPersonalMemoryStatus
    var recommendedNextAction: String
    var auditRef: String

    var id: String { followUpId }
}

struct SupervisorFollowUpLedgerSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_follow_up_ledger_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var items: [SupervisorFollowUpLedgerItem]

    static let empty = SupervisorFollowUpLedgerSnapshot(
        schemaVersion: currentSchemaVersion,
        updatedAtMs: 0,
        items: []
    )
}

struct SupervisorFollowUpLedgerSummary: Equatable {
    var openCount: Int
    var overdueCount: Int
    var dueSoonCount: Int
    var watchCount: Int
    var peopleWaitingCount: Int
    var waitingPeople: [String]
    var highlightedItems: [String]
    var statusLine: String
    var promptContext: String
}

enum SupervisorFollowUpLedgerBuilder {
    static func build(
        from personalMemory: SupervisorPersonalMemorySnapshot,
        now: Date = Date(),
        dueSoonWindowSec: TimeInterval = 24 * 60 * 60
    ) -> SupervisorFollowUpLedgerSnapshot {
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let dueSoonCutoff = now.addingTimeInterval(max(60, dueSoonWindowSec))
        let dueSoonCutoffMs = Int64((dueSoonCutoff.timeIntervalSince1970 * 1000.0).rounded())

        let items = personalMemory.normalized().items.compactMap { record -> SupervisorFollowUpLedgerItem? in
            guard shouldAppearInFollowUpLedger(record) else { return nil }
            let urgency = resolveUrgency(
                record: record,
                nowMs: nowMs,
                dueSoonCutoffMs: dueSoonCutoffMs
            )
            return SupervisorFollowUpLedgerItem(
                schemaVersion: SupervisorFollowUpLedgerItem.currentSchemaVersion,
                followUpId: followUpId(for: record),
                sourceMemoryId: record.memoryId,
                category: record.category,
                title: record.title,
                personName: record.personName,
                urgency: urgency,
                dueAtMs: record.dueAtMs,
                sourceUpdatedAtMs: record.updatedAtMs,
                sourceStatus: record.status,
                recommendedNextAction: recommendedNextAction(for: record, urgency: urgency),
                auditRef: record.auditRef
            )
        }
        .sorted(by: compareItems)

        return SupervisorFollowUpLedgerSnapshot(
            schemaVersion: SupervisorFollowUpLedgerSnapshot.currentSchemaVersion,
            updatedAtMs: max(nowMs, personalMemory.normalized().updatedAtMs),
            items: items
        )
    }

    static func summary(
        from snapshot: SupervisorFollowUpLedgerSnapshot,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> SupervisorFollowUpLedgerSummary {
        let items = snapshot.items
        let people = Array(
            Set(items.map(\.personName).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        ).sorted()
        let overdue = items.filter { $0.urgency == .overdue }
        let dueSoon = items.filter { $0.urgency == .dueSoon }
        let watch = items.filter { $0.urgency == .watch }
        let parts = [
            items.isEmpty ? nil : "\(items.count) open follow-ups",
            overdue.isEmpty ? nil : "\(overdue.count) overdue",
            dueSoon.isEmpty ? nil : "\(dueSoon.count) due soon",
            watch.isEmpty ? nil : "\(watch.count) watch",
            people.isEmpty ? nil : "\(people.count) people waiting"
        ].compactMap { $0 }

        let highlighted = items.prefix(4).map { item in
            let dueLabel = followUpDueText(item.dueAtMs, timeZone: timeZone, locale: locale)
            let personLabel = item.personName.isEmpty ? "" : " · \(item.personName)"
            return "\(item.urgency.displayName): \(item.title)\(personLabel)\(dueLabel)"
        }

        var promptLines: [String] = []
        if !items.isEmpty {
            promptLines.append("- Follow-up queue: \(parts.joined(separator: " | "))")
        }
        if !people.isEmpty {
            promptLines.append("- People waiting on the user: \(people.prefix(4).joined(separator: ", "))")
        }
        if !items.isEmpty {
            let topItems = items.prefix(3).map { item in
                let urgency = item.urgency.displayName.lowercased()
                let due = followUpDueText(item.dueAtMs, timeZone: timeZone, locale: locale)
                return "\(item.title) (\(urgency)\(due))"
            }.joined(separator: " | ")
            promptLines.append("- Highest-priority follow-ups: \(topItems)")
        }

        return SupervisorFollowUpLedgerSummary(
            openCount: items.count,
            overdueCount: overdue.count,
            dueSoonCount: dueSoon.count,
            watchCount: watch.count,
            peopleWaitingCount: people.count,
            waitingPeople: people,
            highlightedItems: highlighted,
            statusLine: parts.isEmpty ? "No personal follow-ups are currently queued." : parts.joined(separator: " · "),
            promptContext: promptLines.joined(separator: "\n")
        )
    }

    private static func shouldAppearInFollowUpLedger(_ record: SupervisorPersonalMemoryRecord) -> Bool {
        guard !record.isArchivedLike else { return false }
        switch record.category {
        case .commitment, .recurringObligation:
            return record.isActiveLike
        case .relationship:
            return record.status == .watch || record.status == .active
        case .personalFact, .habit, .preference:
            return false
        }
    }

    private static func resolveUrgency(
        record: SupervisorPersonalMemoryRecord,
        nowMs: Int64,
        dueSoonCutoffMs: Int64
    ) -> SupervisorFollowUpUrgency {
        if let dueAtMs = record.dueAtMs {
            if dueAtMs < nowMs {
                return .overdue
            }
            if dueAtMs <= dueSoonCutoffMs {
                return .dueSoon
            }
            return .stable
        }

        if record.status == .watch || record.category == .relationship {
            return .watch
        }
        return .stable
    }

    private static func recommendedNextAction(
        for record: SupervisorPersonalMemoryRecord,
        urgency: SupervisorFollowUpUrgency
    ) -> String {
        let person = record.personName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch urgency {
        case .overdue:
            if !person.isEmpty {
                return "Reply to \(person) today and close the loop on \(record.title)."
            }
            return "Handle \(record.title) today before it drifts further."
        case .dueSoon:
            if !person.isEmpty {
                return "Prepare and send an update to \(person) before \(record.title) becomes overdue."
            }
            return "Schedule time to finish \(record.title) before the due window closes."
        case .watch:
            if !person.isEmpty {
                return "Check in with \(person) before the thread goes cold."
            }
            return "Review \(record.title) in the next personal follow-up sweep."
        case .stable:
            return "Keep \(record.title) on the radar and revisit it in the next review window."
        }
    }

    private static func compareItems(
        lhs: SupervisorFollowUpLedgerItem,
        rhs: SupervisorFollowUpLedgerItem
    ) -> Bool {
        let leftRank = urgencyRank(lhs.urgency)
        let rightRank = urgencyRank(rhs.urgency)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        let leftDue = lhs.dueAtMs ?? Int64.max
        let rightDue = rhs.dueAtMs ?? Int64.max
        if leftDue != rightDue {
            return leftDue < rightDue
        }
        if lhs.sourceUpdatedAtMs != rhs.sourceUpdatedAtMs {
            return lhs.sourceUpdatedAtMs > rhs.sourceUpdatedAtMs
        }
        return lhs.followUpId > rhs.followUpId
    }

    private static func urgencyRank(_ urgency: SupervisorFollowUpUrgency) -> Int {
        switch urgency {
        case .overdue:
            return 0
        case .dueSoon:
            return 1
        case .watch:
            return 2
        case .stable:
            return 3
        }
    }

    private static func followUpId(for record: SupervisorPersonalMemoryRecord) -> String {
        "follow_up:\(record.memoryId)"
    }

    private static func followUpDueText(
        _ dueAtMs: Int64?,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        guard let dueAtMs, dueAtMs > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = " due yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(dueAtMs) / 1000.0))
    }
}
