import Foundation
import Testing
@testable import XTerminal

struct SupervisorPersonalAssistantCockpitPresentationTests {

    @Test
    func buildSurfacesDueReviewsAndPeopleWaiting() throws {
        let now = try #require(isoDate("2026-03-20T19:10:00+08:00"))
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let personalMemory = SupervisorPersonalMemorySnapshot(
            schemaVersion: SupervisorPersonalMemorySnapshot.currentSchemaVersion,
            updatedAtMs: 1,
            items: [
                record(
                    id: "commitment-1",
                    category: .commitment,
                    title: "Reply to Alex about partnership draft",
                    personName: "Alex",
                    dueAtMs: Int64((try #require(isoDate("2026-03-19T18:00:00+08:00")).timeIntervalSince1970 * 1000.0).rounded()),
                    updatedAtMs: 10
                ),
                record(
                    id: "relationship-1",
                    category: .relationship,
                    title: "Taylor is waiting on a check-in",
                    personName: "Taylor",
                    dueAtMs: nil,
                    updatedAtMs: 20
                )
            ]
        )

        let presentation = SupervisorPersonalAssistantCockpitPresentationBuilder.build(
            persona: SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational).slot(for: "persona_slot_2")
                ?? SupervisorPersonaSlot.seed(index: 1, defaultVoicePersona: .briefing),
            personalMemory: personalMemory,
            reviewSnapshot: .empty,
            now: now,
            timeZone: timeZone,
            locale: Locale(identifier: "en_US_POSIX")
        )

        #expect(presentation.statusLine.contains("复盘待处理"))
        #expect(presentation.badges.contains(where: { $0.text.contains("位在等你") }))
        #expect(presentation.highlights.contains(where: { $0.contains("Weekly Review") || $0.contains("Morning Brief") || $0.contains("Evening Wrap-Up") }))
        #expect(presentation.quickActions.contains(where: { $0.title == "谁在等你" }))
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
