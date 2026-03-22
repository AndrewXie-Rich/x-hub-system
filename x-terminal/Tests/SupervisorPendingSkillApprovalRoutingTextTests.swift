import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorPendingSkillApprovalRoutingTextTests {

    @Test
    @MainActor
    func displaySkillPrefersWrapperToBuiltinRoutingSummary() {
        let manager = SupervisorManager.makeForTesting()
        let approval = makeApproval(
            requestId: "req-routing-display",
            projectName: "Project Alpha",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open"
        )

        let summary = manager.pendingSupervisorSkillApprovalDisplaySkillForTesting(approval)

        #expect(summary == "browser.open -> guarded-automation")
    }

    @Test
    @MainActor
    func genericDisplaySummaryIncludesNormalizedActionWhenPayloadProvidesIt() {
        let manager = SupervisorManager.makeForTesting()

        let summary = manager.supervisorSkillDisplaySummaryForTesting(
            requestedSkillId: "browser.open",
            effectiveSkillId: "guarded-automation",
            payload: ["action": .string("open")]
        )

        #expect(summary == "browser.open -> guarded-automation · action=open")
    }

    @Test
    @MainActor
    func ambiguityReplyUsesRequestedWrapperWhenBuiltinRoutingIsActive() {
        let manager = SupervisorManager.makeForTesting()
        let approvals = [
            makeApproval(
                requestId: "req-routing-1",
                projectName: "Project Alpha",
                skillId: "guarded-automation",
                requestedSkillId: "browser.open",
                toolSummary: "open https://example.com/login",
                reason: "browser control touches login flow"
            ),
            makeApproval(
                requestId: "req-routing-2",
                projectName: "Project Beta",
                skillId: "guarded-automation",
                requestedSkillId: "browser.runtime.inspect",
                toolSummary: "inspect checkout page",
                reason: "browser snapshot touches checkout surface"
            )
        ]

        let reply = manager.pendingSupervisorSkillApprovalAmbiguityReplyForTesting(approvals)

        #expect(reply.contains("Project Alpha / browser.open -> guarded-automation /"))
        #expect(reply.contains("Project Beta / browser.runtime.inspect -> guarded-automation /"))
    }

    @Test
    @MainActor
    func voiceAnnouncementUsesRequestedWrapperWhenBuiltinRoutingIsActive() {
        let manager = SupervisorManager.makeForTesting()
        let approval = makeApproval(
            requestId: "req-routing-voice",
            projectName: "Project Alpha",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            toolSummary: "open https://example.com/login",
            reason: "browser control touches login flow"
        )

        let text = manager.pendingSupervisorSkillApprovalVoiceAnnouncementTextForTesting(
            approval: approval,
            pendingCount: 1
        )

        #expect(text.contains("《Project Alpha》现在有一条待处理的本地技能调用：browser.open -> guarded-automation。"))
        #expect(text.contains("路由说明：浏览器入口会先收敛到受治理内建 guarded-automation 再执行"))
        #expect(text.contains("目标：open https://example.com/login"))
    }

    private func makeApproval(
        requestId: String,
        projectName: String,
        skillId: String,
        requestedSkillId: String?,
        toolSummary: String = "Open dashboard",
        reason: String = "browser control touches live admin surface"
    ) -> SupervisorManager.SupervisorPendingSkillApproval {
        SupervisorManager.SupervisorPendingSkillApproval(
            id: "approval-\(requestId)",
            requestId: requestId,
            projectId: "project-\(requestId)",
            projectName: projectName,
            jobId: "job-\(requestId)",
            planId: "plan-\(requestId)",
            stepId: "step-\(requestId)",
            skillId: skillId,
            requestedSkillId: requestedSkillId,
            toolName: ToolName.deviceBrowserControl.rawValue,
            tool: .deviceBrowserControl,
            toolSummary: toolSummary,
            reason: reason,
            createdAt: 10,
            actionURL: "x-terminal://approval/\(requestId)"
        )
    }
}
