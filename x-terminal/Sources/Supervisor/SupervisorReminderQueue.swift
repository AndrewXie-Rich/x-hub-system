import Foundation

struct SupervisorReminderQueueItem: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_reminder_queue_item.v1"

    var schemaVersion: String
    var reminderId: String
    var followUpId: String
    var title: String
    var subtitle: String
    var urgency: SupervisorFollowUpUrgency
    var dueAtMs: Int64?
    var recommendedNextAction: String
    var auditRef: String

    var id: String { reminderId }
}

struct SupervisorReminderQueueSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_reminder_queue_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var items: [SupervisorReminderQueueItem]

    static let empty = SupervisorReminderQueueSnapshot(
        schemaVersion: currentSchemaVersion,
        updatedAtMs: 0,
        items: []
    )
}

struct SupervisorReminderQueueSummary: Equatable {
    var statusLine: String
    var topTitles: [String]
    var promptContext: String
}

enum SupervisorReminderQueueBuilder {
    static func build(from ledger: SupervisorFollowUpLedgerSnapshot) -> SupervisorReminderQueueSnapshot {
        let items = ledger.items.map { item in
            SupervisorReminderQueueItem(
                schemaVersion: SupervisorReminderQueueItem.currentSchemaVersion,
                reminderId: "reminder:\(item.followUpId)",
                followUpId: item.followUpId,
                title: item.title,
                subtitle: reminderSubtitle(for: item),
                urgency: item.urgency,
                dueAtMs: item.dueAtMs,
                recommendedNextAction: item.recommendedNextAction,
                auditRef: item.auditRef
            )
        }
        return SupervisorReminderQueueSnapshot(
            schemaVersion: SupervisorReminderQueueSnapshot.currentSchemaVersion,
            updatedAtMs: ledger.updatedAtMs,
            items: items
        )
    }

    static func summary(from snapshot: SupervisorReminderQueueSnapshot) -> SupervisorReminderQueueSummary {
        let topTitles = snapshot.items.prefix(3).map(\.title)
        let statusLine: String
        if snapshot.items.isEmpty {
            statusLine = "Reminder queue is empty."
        } else {
            let highestUrgency = snapshot.items.first?.urgency.displayName ?? "Stable"
            statusLine = "\(snapshot.items.count) reminders queued · top urgency \(highestUrgency)"
        }

        let promptContext: String
        if snapshot.items.isEmpty {
            promptContext = ""
        } else {
            let queue = snapshot.items.prefix(3).map { item in
                "\(item.title) (\(item.urgency.displayName.lowercased()))"
            }.joined(separator: " | ")
            promptContext = "- Reminder queue: \(queue)"
        }

        return SupervisorReminderQueueSummary(
            statusLine: statusLine,
            topTitles: topTitles,
            promptContext: promptContext
        )
    }

    private static func reminderSubtitle(for item: SupervisorFollowUpLedgerItem) -> String {
        let person = item.personName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.urgency {
        case .overdue:
            return person.isEmpty ? "Needs attention now" : "\(person) is waiting"
        case .dueSoon:
            return person.isEmpty ? "Due soon" : "Reply to \(person) before it slips"
        case .watch:
            return person.isEmpty ? "Keep on watch" : "Relationship follow-up for \(person)"
        case .stable:
            return person.isEmpty ? "Keep on radar" : "Open loop with \(person)"
        }
    }
}
