import Foundation
import Testing
@testable import XTerminal

struct SupervisorFollowUpLedgerTests {

    @Test
    func ledgerBuildsContactLinkedItemsAndClassifiesUrgency() throws {
        let now = try #require(isoDate("2026-03-16T10:00:00+08:00"))
        let snapshot = SupervisorPersonalMemorySnapshot(
            schemaVersion: SupervisorPersonalMemorySnapshot.currentSchemaVersion,
            updatedAtMs: 100,
            items: [
                memory(
                    id: "relationship-1",
                    category: .relationship,
                    status: .watch,
                    title: "Keep Alex warm on the partnership thread",
                    person: "Alex",
                    dueAtMs: nil,
                    updatedAtMs: 10
                ),
                memory(
                    id: "commitment-1",
                    category: .commitment,
                    status: .active,
                    title: "Reply to Taylor about the invoice",
                    person: "Taylor",
                    dueAtMs: Int64((try #require(isoDate("2026-03-15T18:00:00+08:00")).timeIntervalSince1970 * 1000.0).rounded()),
                    updatedAtMs: 20
                ),
                memory(
                    id: "commitment-2",
                    category: .commitment,
                    status: .active,
                    title: "Send agenda to Morgan",
                    person: "Morgan",
                    dueAtMs: Int64((try #require(isoDate("2026-03-16T18:00:00+08:00")).timeIntervalSince1970 * 1000.0).rounded()),
                    updatedAtMs: 30
                ),
                memory(
                    id: "fact-1",
                    category: .personalFact,
                    status: .active,
                    title: "Prefers quiet mornings",
                    person: "",
                    dueAtMs: nil,
                    updatedAtMs: 40
                )
            ]
        )

        let ledger = SupervisorFollowUpLedgerBuilder.build(from: snapshot, now: now)

        #expect(ledger.items.count == 3)
        #expect(ledger.items.map(\.sourceMemoryId) == ["commitment-1", "commitment-2", "relationship-1"])
        #expect(ledger.items[0].urgency == .overdue)
        #expect(ledger.items[1].urgency == .dueSoon)
        #expect(ledger.items[2].urgency == .watch)
        #expect(ledger.items[0].recommendedNextAction.contains("Taylor"))
        #expect(ledger.items[2].recommendedNextAction.contains("Alex"))
    }

    @Test
    func reminderQueueSummaryPrioritizesHighestUrgencyItems() throws {
        let now = try #require(isoDate("2026-03-16T10:00:00+08:00"))
        let ledger = SupervisorFollowUpLedgerBuilder.build(
            from: SupervisorPersonalMemorySnapshot(
                schemaVersion: SupervisorPersonalMemorySnapshot.currentSchemaVersion,
                updatedAtMs: 1,
                items: [
                    memory(
                        id: "commitment-overdue",
                        category: .commitment,
                        status: .active,
                        title: "Reply to Alex",
                        person: "Alex",
                        dueAtMs: Int64((try #require(isoDate("2026-03-14T18:00:00+08:00")).timeIntervalSince1970 * 1000.0).rounded()),
                        updatedAtMs: 10
                    ),
                    memory(
                        id: "relationship-watch",
                        category: .relationship,
                        status: .watch,
                        title: "Check in with Morgan",
                        person: "Morgan",
                        dueAtMs: nil,
                        updatedAtMs: 20
                    )
                ]
            ),
            now: now
        )

        let summary = SupervisorFollowUpLedgerBuilder.summary(from: ledger)
        let reminderSummary = SupervisorReminderQueueBuilder.summary(
            from: SupervisorReminderQueueBuilder.build(from: ledger)
        )

        #expect(summary.statusLine.contains("1 overdue"))
        #expect(summary.waitingPeople == ["Alex", "Morgan"])
        #expect(summary.promptContext.contains("People waiting on the user: Alex, Morgan"))
        #expect(reminderSummary.statusLine.contains("top urgency Overdue"))
        #expect(reminderSummary.topTitles.first == "Reply to Alex")
        #expect(reminderSummary.promptContext.contains("Reply to Alex (overdue)"))
    }

    private func memory(
        id: String,
        category: SupervisorPersonalMemoryCategory,
        status: SupervisorPersonalMemoryStatus,
        title: String,
        person: String,
        dueAtMs: Int64?,
        updatedAtMs: Int64
    ) -> SupervisorPersonalMemoryRecord {
        SupervisorPersonalMemoryRecord(
            schemaVersion: SupervisorPersonalMemoryRecord.currentSchemaVersion,
            memoryId: id,
            category: category,
            status: status,
            title: title,
            detail: "",
            personName: person,
            tags: [],
            dueAtMs: dueAtMs,
            createdAtMs: updatedAtMs,
            updatedAtMs: updatedAtMs,
            auditRef: "audit-\(id)"
        )
    }

    private func isoDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }
}
