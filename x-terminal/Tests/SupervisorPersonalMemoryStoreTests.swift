import Foundation
import Testing
@testable import XTerminal

struct SupervisorPersonalMemoryStoreTests {

    @Test
    func summaryHighlightsPeopleAndOverdueCommitments() throws {
        let now = try #require(isoDate("2026-03-16T10:00:00+08:00"))
        let snapshot = SupervisorPersonalMemorySnapshot(
            schemaVersion: SupervisorPersonalMemorySnapshot.currentSchemaVersion,
            updatedAtMs: 1,
            items: [
                record(
                    id: "mem-1",
                    category: .relationship,
                    title: "Alex is waiting on partnership feedback",
                    personName: "Alex",
                    dueAtMs: nil,
                    updatedAtMs: 10
                ),
                record(
                    id: "mem-2",
                    category: .commitment,
                    title: "Reply to Alex about the partnership draft",
                    personName: "Alex",
                    dueAtMs: Int64((try #require(isoDate("2026-03-15T18:00:00+08:00")).timeIntervalSince1970 * 1000.0).rounded()),
                    updatedAtMs: 20
                ),
                record(
                    id: "mem-3",
                    category: .preference,
                    title: "Prefer deep work before noon",
                    personName: "",
                    dueAtMs: nil,
                    updatedAtMs: 30
                )
            ]
        )

        let summary = SupervisorPersonalMemorySummaryBuilder.build(
            snapshot: snapshot,
            lastWriteObservation: SupervisorLocalMemoryWriteObservation(
                surface: .personalMemory,
                intent: SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue,
                updatedAtMs: 40
            ),
            now: now,
            timeZone: try #require(TimeZone(identifier: "Asia/Shanghai")),
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(summary.totalCount == 3)
        #expect(summary.activeCommitmentCount == 1)
        #expect(summary.overdueCommitmentCount == 1)
        #expect(summary.peopleCount == 1)
        #expect(summary.localStoreRole == SupervisorLocalMemoryStoreRole.rawValue)
        #expect(summary.lastLocalWriteIntent == SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue)
        #expect(summary.statusLine.contains("XT local personal memory cache"))
        #expect(summary.statusLine.contains("1 overdue"))
        #expect(summary.promptContext.contains("XT local store role: \(SupervisorLocalMemoryStoreRole.rawValue)"))
        #expect(summary.promptContext.contains("Latest XT local write intent: \(SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue)"))
        #expect(summary.promptContext.contains("not treat it as the durable source of truth"))
        #expect(summary.promptContext.contains("Key people: Alex"))
        #expect(summary.promptContext.contains("Overdue commitments: Reply to Alex about the partnership draft"))
        #expect(summary.promptContext.contains("Stable preferences and habits: Prefer deep work before noon"))
    }

    @MainActor
    @Test
    func storePersistsSnapshotAndDeletesRecords() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_memory_\(UUID().uuidString).json")
        let store = SupervisorPersonalMemoryStore(url: tempURL)
        let record = record(
            id: "commitment-1",
            category: .commitment,
            title: "Send follow-up note",
            personName: "Taylor",
            dueAtMs: nil,
            updatedAtMs: 100
        )

        store.upsert(record, intent: .testSeed)
        #expect(store.snapshot.items.count == 1)
        #expect(store.lastWriteObservation?.surface == .personalMemory)
        #expect(store.lastWriteObservation?.intent == SupervisorPersonalMemoryStoreWriteIntent.testSeed.rawValue)

        let reloaded = SupervisorPersonalMemoryStore(url: tempURL)
        #expect(reloaded.snapshot.items.count == 1)
        #expect(reloaded.snapshot.items.first?.title == "Send follow-up note")

        reloaded.delete(memoryId: "commitment-1", intent: .manualEditBufferCommit)
        let afterDelete = SupervisorPersonalMemoryStore(url: tempURL)
        #expect(afterDelete.snapshot.items.isEmpty)
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
