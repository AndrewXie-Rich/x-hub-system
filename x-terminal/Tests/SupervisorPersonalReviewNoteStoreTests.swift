import Foundation
import Testing
@testable import XTerminal

struct SupervisorPersonalReviewNoteStoreTests {

    @Test
    func previewBuildsMorningReviewFromOverdueFollowUps() throws {
        let now = try #require(isoDate("2026-03-16T10:00:00+08:00"))
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let snapshot = SupervisorPersonalMemorySnapshot(
            schemaVersion: SupervisorPersonalMemorySnapshot.currentSchemaVersion,
            updatedAtMs: 1,
            items: [
                record(
                    id: "relationship-1",
                    category: .relationship,
                    title: "Alex is waiting on a response",
                    personName: "Alex",
                    dueAtMs: nil,
                    updatedAtMs: 10
                ),
                record(
                    id: "commitment-1",
                    category: .commitment,
                    title: "Reply to Alex about the partnership draft",
                    personName: "Alex",
                    dueAtMs: Int64((try #require(isoDate("2026-03-15T18:00:00+08:00")).timeIntervalSince1970 * 1000.0).rounded()),
                    updatedAtMs: 20
                )
            ]
        )

        let preview = SupervisorPersonalReviewNoteBuilder.preview(
            snapshot: .empty,
            policy: SupervisorPersonalPolicy(
                relationshipMode: .chiefOfStaff,
                briefingStyle: .proactive,
                riskTolerance: .balanced,
                interruptionTolerance: .balanced,
                reminderAggressiveness: .assertive,
                preferredMorningBriefTime: "09:00",
                preferredEveningWrapUpTime: "18:00",
                weeklyReviewDay: "Friday"
            ),
            personalMemory: snapshot,
            now: now,
            timeZone: timeZone,
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(preview.dueCount == 1)
        #expect(preview.dueNotes.map(\.reviewType) == [.morningBrief])
        #expect(preview.dueNotes[0].summary.contains("overdue follow-ups"))
        #expect(preview.dueNotes[0].recommendedActions.contains(where: { $0.contains("Reply to Alex") }))
        #expect(preview.promptContext.contains("Due personal reviews: Morning Brief"))
    }

    @MainActor
    @Test
    func storePersistsCompletionStateAndSuppressesCompletedReviewForSameWindow() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_reviews_\(UUID().uuidString).json")
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(isoDate("2026-03-16T10:00:00+08:00"))
        let store = SupervisorPersonalReviewNoteStore(url: tempURL)
        let personalMemory = SupervisorPersonalMemorySnapshot(
            schemaVersion: SupervisorPersonalMemorySnapshot.currentSchemaVersion,
            updatedAtMs: 1,
            items: [
                record(
                    id: "commitment-1",
                    category: .commitment,
                    title: "Send note to Taylor",
                    personName: "Taylor",
                    dueAtMs: Int64((try #require(isoDate("2026-03-15T20:00:00+08:00")).timeIntervalSince1970 * 1000.0).rounded()),
                    updatedAtMs: 10
                )
            ]
        )

        store.syncDerivedNotes(
            policy: .default(),
            personalMemory: personalMemory,
            now: now,
            timeZone: timeZone,
            locale: Locale(identifier: "en_US_POSIX")
        )
        #expect(store.preview(policy: .default(), personalMemory: personalMemory, now: now, timeZone: timeZone).dueCount == 1)
        #expect(store.snapshot.notes.count == 1)

        store.markCompleted(type: .morningBrief, at: now, timeZone: timeZone)

        let afterComplete = store.preview(
            policy: .default(),
            personalMemory: personalMemory,
            now: now,
            timeZone: timeZone,
            locale: Locale(identifier: "en_US_POSIX")
        )
        #expect(afterComplete.dueCount == 0)

        let reloaded = SupervisorPersonalReviewNoteStore(url: tempURL)
        let reloadedPreview = reloaded.preview(
            policy: .default(),
            personalMemory: personalMemory,
            now: now,
            timeZone: timeZone,
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(reloaded.snapshot.completionState.lastCompletedAnchor(for: .morningBrief) == "2026-03-16")
        #expect(reloadedPreview.dueCount == 0)
    }

    private func record(
        id: String,
        category: SupervisorPersonalMemoryCategory,
        title: String,
        personName: String,
        dueAtMs: Int64?,
        updatedAtMs: Int64
    ) -> SupervisorPersonalMemoryRecord {
        SupervisorPersonalMemoryRecord(
            schemaVersion: SupervisorPersonalMemoryRecord.currentSchemaVersion,
            memoryId: id,
            category: category,
            status: .active,
            title: title,
            detail: "",
            personName: personName,
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
