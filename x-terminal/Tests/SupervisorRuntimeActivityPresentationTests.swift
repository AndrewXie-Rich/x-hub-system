import Foundation
import Testing
@testable import XTerminal

struct SupervisorRuntimeActivityPresentationTests {

    @Test
    func mapBuildsEmptyStateBoard() {
        let presentation = SupervisorRuntimeActivityPresentation.map(entries: [])

        #expect(presentation.iconName == "list.bullet.rectangle")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "运行动态")
        #expect(presentation.countText == "0 条")
        #expect(presentation.isEmpty)
        #expect(presentation.emptyStateText?.isEmpty == false)
    }

    @Test
    func mapBuildsRowsWithDividerMetadata() {
        let entries = [
            runtimeEntry(id: "log-1", createdAt: 1_000, text: "first"),
            runtimeEntry(id: "log-2", createdAt: 2_000, text: "second"),
            runtimeEntry(id: "log-3", createdAt: 3_000, text: "third")
        ]

        let presentation = SupervisorRuntimeActivityPresentation.map(
            entries: entries,
            limit: 2,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_GB_POSIX")
        )

        #expect(presentation.iconName == "list.bullet.rectangle.fill")
        #expect(presentation.iconTone == .accent)
        #expect(presentation.title == "运行动态")
        #expect(presentation.countText == "3 条")
        #expect(presentation.emptyStateText == nil)
        #expect(presentation.rows.map(\.id) == ["log-1", "log-2"])
        #expect(presentation.rows.map(\.text) == ["first", "second"])
        #expect(presentation.rows.map(\.contractText) == [nil, nil])
        #expect(presentation.rows.map(\.nextSafeActionText) == [nil, nil])
        #expect(presentation.rows.map(\.actionDescriptors) == [[], []])
        #expect(presentation.rows.map(\.showsDivider) == [true, false])
        #expect(!presentation.rows[0].timeText.isEmpty)
    }

    @Test
    func mapParsesGrantResolutionContractForVoiceAuthorizationRuntimeEntries() {
        let entries = [
            runtimeEntry(
                id: "log-grant",
                createdAt: 1_000,
                text: "voice_playback state=failed output=hub_voice_pack reason=voice_authorization_not_started"
            )
        ]

        let presentation = SupervisorRuntimeActivityPresentation.map(entries: entries)

        #expect(presentation.rows.count == 1)
        #expect(presentation.rows[0].contractText == "合同： 授权处理 · blocker=voice_authorization_not_started")
        #expect(presentation.rows[0].nextSafeActionText == "安全下一步： open_hub_grants")
        #expect(presentation.rows[0].actionDescriptors.map(\.label) == ["打开授权"])
        #expect(presentation.rows[0].actionDescriptors.first?.isEnabled == true)
    }

    @Test
    func mapParsesIncidentRecoveryContractForProjectMemoryWritebackFailure() {
        let entries = [
            runtimeEntry(
                id: "log-memory-fail",
                createdAt: 1_000,
                text: "after_turn project_memory_failed · project=Project Alpha · error=disk_full"
            )
        ]

        let presentation = SupervisorRuntimeActivityPresentation.map(entries: entries)

        #expect(presentation.rows.count == 1)
        #expect(presentation.rows[0].contractText == "合同： 故障恢复 · blocker=project_memory_failed")
        #expect(presentation.rows[0].nextSafeActionText == "安全下一步： inspect_incident_and_replan")
        #expect(presentation.rows[0].actionDescriptors.map(\.label) == ["打开诊断"])
        #expect(presentation.rows[0].actionDescriptors.first?.isEnabled == true)
    }

    private func runtimeEntry(
        id: String,
        createdAt: Double,
        text: String
    ) -> SupervisorManager.RuntimeActivityEntry {
        SupervisorManager.RuntimeActivityEntry(
            id: id,
            createdAt: createdAt,
            text: text
        )
    }
}
