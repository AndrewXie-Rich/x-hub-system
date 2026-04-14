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
        #expect(presentation.rows.map(\.blockedSummaryText) == [nil, nil])
        #expect(presentation.rows.map(\.governanceTruthText) == [nil, nil])
        #expect(presentation.rows.map(\.governanceReasonText) == [nil, nil])
        #expect(presentation.rows.map(\.policyReasonText) == [nil, nil])
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
        #expect(presentation.rows[0].nextSafeActionText == "安全下一步： 打开 Hub 授权面板")
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
        #expect(presentation.rows[0].nextSafeActionText == "安全下一步： 先检查当前异常，再决定是否重规划")
        #expect(presentation.rows[0].actionDescriptors.map(\.label) == ["打开诊断"])
        #expect(presentation.rows[0].actionDescriptors.first?.isEnabled == true)
    }

    @Test
    func mapExtractsGovernanceEvidenceTokensFromRuntimeEntry() {
        let entries = [
            runtimeEntry(
                id: "log-governance",
                createdAt: 1_000,
                text: "skill_runtime status=blocked · blocked_summary=当前项目 A-Tier 不允许浏览器自动化。 打开项目设置 -> A-Tier，把档位提升到 A4 Agent 或更高后，再使用浏览器自动化。 · governance_reason=当前项目 A-Tier 不允许浏览器自动化。 · policy_reason=execution_tier_missing_browser_runtime · governance_truth=治理真相：当前生效 A1/S2 · 审查 Periodic · 节奏 心跳 15m / 脉冲 30m / 脑暴 off。"
            )
        ]

        let presentation = SupervisorRuntimeActivityPresentation.map(entries: entries)

        #expect(presentation.rows.count == 1)
        #expect(presentation.rows[0].blockedSummaryText?.contains("当前项目 A-Tier 不允许浏览器自动化。") == true)
        #expect(presentation.rows[0].governanceTruthText == "治理真相：当前生效 A1/S2 · 审查 周期 · 节奏 心跳 15m / 脉冲 30m / 脑暴 关闭。")
        #expect(presentation.rows[0].governanceReasonText == "治理原因： 当前项目 A-Tier 不允许浏览器自动化。")
        #expect(presentation.rows[0].policyReasonText == "策略原因： execution_tier_missing_browser_runtime")
        #expect(presentation.rows[0].contractText == nil)
        #expect(presentation.rows[0].actionDescriptors.isEmpty)
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
