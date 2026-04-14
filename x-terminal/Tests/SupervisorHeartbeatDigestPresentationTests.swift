import Foundation
import Testing
@testable import XTerminal

struct SupervisorHeartbeatDigestPresentationTests {

    @Test
    func mapBuildsThreeLineDigestContractForAuthorizationHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-auth-digest-contract",
                pane: .chat,
                focusTarget: .grant
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-auth-digest-contract",
            content: """
🫀 Supervisor Heartbeat (10:00)
原因：project_updated
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：1
待治理修复项目：0
lane 状态：total=1, running=0, blocked=1, stalled=0, failed=0

主动推进：
（本轮无需介入）

权限申请：
grant_pending
需要你批准 repo 写权限后，系统才会继续推进。（打开：xterminal://project?project_id=project-auth-digest-contract）
event_loop_tick=42 dedupe_key=heartbeat:grant_pending

Coder 下一步建议：
1. 先批准 repo 写权限，再继续执行。
""",
            focusActionURL: focusActionURL,
            reason: "project_updated"
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)

        #expect(mapped.digest.whatChangedText == "需要你批准 repo 写权限后，系统才会继续推进。")
        #expect(mapped.digest.whyImportantText.contains("授权") || mapped.digest.whyImportantText.contains("审批"))
        #expect(mapped.digest.systemNextStepText.contains("先批准 repo 写权限"))
        #expect(mapped.digest.visibility == .userFacing)
        #expect(presentation.digestModeNoteText.contains("用户 digest"))
        #expect(presentation.suppressedInternalCount == 0)
    }

    @Test
    func mapSuppressesInternalOnlyHeartbeatAndReportsSuppressedCount() {
        let entry = heartbeat(
            id: "hb-internal-only",
            content: """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理修复项目：0
lane 状态：total=1, running=0, blocked=1, stalled=0, failed=0
grant_pending
lane=lane-auth status=blocked reason=grant_pending
event_loop_tick=42 dedupe_key=heartbeat:grant_pending
""",
            focusActionURL: nil
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])

        #expect(presentation.isEmpty)
        #expect(presentation.suppressedInternalCount == 1)
        #expect(presentation.emptyStateText.contains("内部调试 heartbeat 已隐藏"))
        #expect(presentation.digestModeNoteText.contains("另有 1 条内部调试 heartbeat 已隐藏"))
    }

    @Test
    func mapBuildsThreeLineDigestContractForGrantRecoveryHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-recovery-grant-digest",
                pane: .chat,
                focusTarget: .grant
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-recovery-grant-digest",
            content: """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：1
待治理修复项目：0
lane 状态：total=1, running=0, blocked=1, stalled=0, failed=0

主动推进：
（本轮无需介入）

权限申请：
需要你批准 repo 写权限后，系统才会继续推进。（打开：xterminal://project?project_id=project-recovery-grant-digest）

Recovery 跟进：
Grant Recovery Runtime 需要 grant / 授权跟进
系统会先发起所需 grant 跟进，待放行后再继续恢复执行。
为什么先跟进：待授权会直接卡住推进（优先级：紧急 · score=8）

Coder 下一步建议：
1. Recovery 跟进：Grant Recovery Runtime — 建议先批准 repo 写权限，再继续恢复执行。
""",
            focusActionURL: focusActionURL,
            reason: "timer"
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)

        #expect(mapped.digest.whatChangedText == "Grant Recovery Runtime 需要 grant / 授权跟进")
        #expect(mapped.digest.whyImportantText.contains("grant / 授权跟进"))
        #expect(mapped.digest.systemNextStepText.contains("grant 跟进"))
        #expect(mapped.detailLines.contains(where: { $0.contains("为什么先跟进") }))
        #expect(mapped.digest.visibility == .userFacing)
    }

    @Test
    func mapBuildsThreeLineDigestContractForReplayRecoveryHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-recovery-replay-digest",
                pane: .chat,
                resumeRequested: true
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-recovery-replay-digest",
            content: """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：1
待授权项目：0
待治理修复项目：0
lane 状态：total=1, running=0, blocked=1, stalled=0, failed=0

主动推进：
（本轮无需介入）

排队态势：
Replay Recovery Runtime：1 个排队中（最长约 4 分钟）

Recovery 跟进：
Replay Recovery Runtime 需要重放 follow-up / 续跑链
系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链，再确认执行是否恢复。
为什么先跟进：存在明确 blocker，需要优先解阻（优先级：高 · score=6）

Coder 下一步建议：
1. Recovery 跟进：Replay Recovery Runtime — 建议先打开项目查看 resume / replan。
""",
            focusActionURL: focusActionURL,
            reason: "timer"
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)

        #expect(mapped.digest.whatChangedText == "Replay Recovery Runtime 需要重放 follow-up / 续跑链")
        #expect(mapped.digest.whyImportantText.contains("续跑链"))
        #expect(mapped.digest.systemNextStepText.contains("重放挂起的 follow-up"))
        #expect(mapped.detailLines.contains(where: { $0.contains("为什么先跟进") }))
        #expect(mapped.digest.visibility == .userFacing)
    }

    @Test
    func mapBuildsThreeLineDigestContractForProjectCreationHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.supervisorURL()?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-project-creation-digest",
            content: """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：0
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理审查项目：0
待治理修复项目：0
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

项目创建：
项目创建还差一句触发。
已锁定《贪食蛇游戏》，再说“立项”“创建一个project”或“按默认方案建项目”就会真正创建。
目标：我要做个贪食蛇游戏
可直接说：“立项” / “创建一个project” / “按默认方案建项目”

Coder 下一步建议：
直接说立项，或说创建一个project。
""",
            focusActionURL: focusActionURL,
            reason: "timer"
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)

        #expect(mapped.digest.whatChangedText == "项目创建还差一句触发。")
        #expect(mapped.digest.whyImportantText == "当前不会误把“已理解需求”当成“已真正创建项目”。")
        #expect(mapped.digest.systemNextStepText == "直接说立项，或说创建一个project。")
        #expect(mapped.digest.visibility == .userFacing)
    }

    private func heartbeat(
        id: String,
        content: String,
        focusActionURL: String?,
        reason: String = "periodic_check"
    ) -> SupervisorManager.HeartbeatFeedEntry {
        SupervisorManager.HeartbeatFeedEntry(
            id: id,
            createdAt: 1_000,
            reason: reason,
            projectCount: 1,
            changed: true,
            content: content,
            focusActionURL: focusActionURL
        )
    }
}
