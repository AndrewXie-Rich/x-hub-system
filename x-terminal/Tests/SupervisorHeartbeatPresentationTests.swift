import Foundation
import Testing
@testable import XTerminal

struct SupervisorHeartbeatPresentationTests {

    @Test
    func mapBuildsEmptyStatePresentation() {
        let presentation = SupervisorHeartbeatPresentation.map(entries: [])

        #expect(presentation.title == "Supervisor 心跳")
        #expect(presentation.iconName == "heart.fill")
        #expect(presentation.iconTone == .danger)
        #expect(presentation.overview == nil)
        #expect(presentation.isEmpty)
        #expect(!presentation.emptyStateText.isEmpty)
    }

    @Test
    func mapLimitsEntriesAndPreservesFocusAction() {
        let entries = [
            heartbeat(id: "hb-1", createdAt: 1_000, changed: true, focusActionURL: "x-terminal://focus/1"),
            heartbeat(id: "hb-2", createdAt: 2_000, changed: false, focusActionURL: "  "),
            heartbeat(id: "hb-3", createdAt: 3_000, changed: true, focusActionURL: nil)
        ]

        let presentation = SupervisorHeartbeatPresentation.map(
            entries: entries,
            limit: 2,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_GB_POSIX")
        )

        #expect(!presentation.isEmpty)
        #expect(presentation.entries.map(\.id) == ["hb-1", "hb-2"])
        #expect(presentation.entries[0].changeText == "有变化")
        #expect(presentation.entries[0].changeTone == .success)
        #expect(presentation.entries[0].reasonText == "定时巡检")
        #expect(presentation.entries[0].priority == .stable)
        #expect(presentation.entries[0].priorityText == "最近汇报")
        #expect(presentation.entries[0].headlineText == "状态稳定")
        #expect(presentation.entries[0].focusAction?.label == "打开相关视图")
        #expect(presentation.entries[0].focusAction?.style == .standard)
        #expect(presentation.entries[1].changeText == "无重大变化")
        #expect(presentation.entries[1].changeTone == .neutral)
        #expect(presentation.entries[1].focusAction == nil)
        #expect(presentation.overview?.headlineText == "状态稳定")
        #expect(presentation.overview?.detailText == "summary hb-1")
        #expect(presentation.overview?.metadataText == "定时巡检 · 00:16 · 另有 1 条更新")
        #expect(!presentation.entries[0].timeText.isEmpty)
    }

    @Test
    func mapHighlightsGovernanceRepairHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governance",
                pane: .chat,
                governanceDestination: .executionTier
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-governance",
            createdAt: 1_000,
            changed: true,
            content: governanceHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(presentation.iconTone == .warning)
        #expect(mapped.headlineText == "治理修复")
        #expect(mapped.headlineTone == .warning)
        #expect(mapped.priority == .immediate)
        #expect(mapped.priorityText == "立即处理")
        #expect(mapped.detailLines.first?.contains("Execution Tier") == true)
        #expect(mapped.focusAction?.label == "打开治理设置")
        #expect(mapped.focusAction?.style == .prominent)
        #expect(overview.priority == .immediate)
        #expect(overview.headlineText == "治理修复")
        #expect(overview.detailText.contains("Execution Tier"))
        #expect(overview.focusAction?.label == "打开治理设置")
    }

    @Test
    func mapHighlightsRouteDiagnoseHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-route",
                pane: .chat,
                focusTarget: .routeDiagnose
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-route",
            createdAt: 1_000,
            changed: true,
            content: routeHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(presentation.iconTone == .accent)
        #expect(mapped.headlineText == "模型路由诊断")
        #expect(mapped.headlineTone == .accent)
        #expect(mapped.priority == .attention)
        #expect(mapped.priorityText == "优先关注")
        #expect(mapped.detailLines.first?.contains("模型路由") == true)
        #expect(mapped.focusAction?.label == "打开路由诊断")
        #expect(mapped.focusAction?.style == .prominent)
        #expect(overview.priority == .attention)
        #expect(overview.detailText.contains("模型路由"))
    }

    @Test
    func mapSortsActionableHeartbeatAheadOfStableUpdates() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governance",
                pane: .chat,
                governanceDestination: .executionTier
            )?.absoluteString
        )
        let entries = [
            heartbeat(
                id: "hb-stable",
                createdAt: 2_000,
                changed: false,
                content: "summary hb-stable",
                focusActionURL: nil
            ),
            heartbeat(
                id: "hb-governance",
                createdAt: 1_000,
                changed: true,
                content: governanceHeartbeatContent(),
                focusActionURL: focusActionURL
            )
        ]

        let presentation = SupervisorHeartbeatPresentation.map(entries: entries)

        #expect(presentation.entries.map(\.id) == ["hb-governance", "hb-stable"])
        #expect(presentation.entries.first?.priority == .immediate)
        #expect(presentation.entries.last?.priority == .stable)
        #expect(presentation.overview?.headlineText == "治理修复")
        #expect(presentation.overview?.metadataText.contains("另有 1 条更新") == true)
    }

    @Test
    func highestPriorityPrefersMostActionableHeartbeat() throws {
        let governanceActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governance",
                pane: .chat,
                governanceDestination: .executionTier
            )?.absoluteString
        )
        let routeActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-route",
                pane: .chat,
                focusTarget: .routeDiagnose
            )?.absoluteString
        )

        let entries = [
            heartbeat(
                id: "hb-stable",
                createdAt: 3_000,
                changed: false,
                content: "summary hb-stable",
                focusActionURL: nil
            ),
            heartbeat(
                id: "hb-route",
                createdAt: 2_000,
                changed: true,
                content: routeHeartbeatContent(),
                focusActionURL: routeActionURL
            ),
            heartbeat(
                id: "hb-governance",
                createdAt: 1_000,
                changed: true,
                content: governanceHeartbeatContent(),
                focusActionURL: governanceActionURL
            )
        ]

        #expect(
            SupervisorHeartbeatPresentation.highestPriority(entries: entries) == .immediate
        )
    }

    @Test
    func mapHighlightsVoiceReadinessRepairHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.supervisorSettingsURL()?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-voice",
            createdAt: 1_000,
            changed: true,
            content: voiceHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.headlineText == "语音链路待修复")
        #expect(mapped.priority == .attention)
        #expect(mapped.detailLines.first?.contains("fail-closed on bridge / tool readiness") == true)
        #expect(mapped.focusAction?.label == "打开设置")
        #expect(overview.headlineText == "语音链路待修复")
        #expect(overview.detailText.contains("bridge / tool readiness"))
    }

    @Test
    func mapLocalizesGuidanceFollowUpReason() {
        let entry = heartbeat(
            id: "hb-guidance",
            createdAt: 1_000,
            changed: true,
            content: "summary hb-guidance",
            focusActionURL: nil,
            reason: "guidance_ack_follow_up"
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])

        #expect(presentation.entries.first?.reasonText == "指导跟进")
        #expect(presentation.overview?.metadataText.contains("指导跟进") == true)
    }

    private func heartbeat(
        id: String,
        createdAt: Double,
        changed: Bool,
        content: String = "",
        focusActionURL: String?,
        reason: String = "periodic_check"
    ) -> SupervisorManager.HeartbeatFeedEntry {
        SupervisorManager.HeartbeatFeedEntry(
            id: id,
            createdAt: createdAt,
            reason: reason,
            projectCount: 3,
            changed: changed,
            content: content.isEmpty ? "summary \(id)" : content,
            focusActionURL: focusActionURL
        )
    }

    private func governanceHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理修复项目：1
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Governance Runtime：⏸️ 暂停中

排队态势：
（无）

权限申请：
（无）

治理修复：
• Governance Runtime：Execution Tier 需要调整；Open Project Settings -> Execution Tier and raise it to A2 Repo Auto or above before starting, inspecting, or stopping managed processes.

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. 治理修复：Governance Runtime — 建议先打开 Project Governance -> Execution Tier。
"""
    }

    private func routeHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理修复项目：0
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Route Runtime：✅ 继续当前任务

排队态势：
（无）

权限申请：
（无）

治理修复：
（无）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. 模型路由：Route Runtime 最近最常见是 目标模型未加载（model_not_found）（2 次）；最近一次失败停在 重连并重诊断。建议先看 /route diagnose。
"""
    }

    private func voiceHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理修复项目：0
语音修复项：1（语音链路失败闭锁）
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Supervisor Voice：⚠️ fail-closed on bridge / tool readiness: Model route ok, but bridge / tool route is unavailable

排队态势：
（无）

权限申请：
（无）

治理修复：
（无）

语音就绪：
• fail-closed on bridge / tool readiness: Model route ok, but bridge / tool route is unavailable（打开：xterminal://supervisor-settings）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. 语音 fail-closed：fail-closed on bridge / tool readiness: Model route ok, but bridge / tool route is unavailable（打开：xterminal://supervisor-settings）
"""
    }
}
