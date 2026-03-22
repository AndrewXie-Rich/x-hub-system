import Foundation
import Testing
@testable import XTerminal

struct SupervisorPendingSkillApprovalPresentationTests {

    @Test
    func boardBuildsEmptyState() {
        let presentation = SupervisorPendingSkillApprovalPresentation.board(
            approvals: [],
            focusedRowAnchor: nil
        )

        #expect(presentation.iconName == "checkmark.shield")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "待审批技能：0")
        #expect(presentation.modeText == "本地审批")
        #expect(presentation.emptyStateText == "当前没有待审批的 Supervisor 高风险技能。")
        #expect(presentation.isEmpty)
    }

    @Test
    func rowBuildsMessageIconFocusAndActions() {
        let approval = SupervisorManager.SupervisorPendingSkillApproval(
            id: "approval-1",
            requestId: "req-approval-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            tool: .deviceBrowserControl,
            toolSummary: "Open dashboard and click submit",
            reason: "browser control touches live admin surface",
            createdAt: 940,
            actionURL: "x-terminal://supervisor?approval=req-approval-1",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open"
        )

        let row = SupervisorPendingSkillApprovalPresentation.row(
            approval,
            isFocused: true
        )

        #expect(row.anchorID == SupervisorFocusPresentation.pendingSupervisorSkillApprovalRowAnchor(approval))
        #expect(row.iconName == "safari")
        #expect(row.title == "Project Alpha · browser.open -> guarded-automation")
        #expect(row.ageText.isEmpty == false)
        #expect(row.summary.isEmpty == false)
        #expect(row.routingText?.contains("browser.open -> guarded-automation") == true)
        #expect(row.routingExplanationText?.contains("浏览器入口会先收敛到受治理内建 guarded-automation 再执行") == true)
        #expect(row.noteText?.contains("补充说明：") == true)
        #expect(row.requestIdentifierText == "请求单号：req-approval-1")
        #expect(row.isFocused)
        #expect(row.actionDescriptors.map(\.label) == ["详情", "打开", "批准", "拒绝"])
    }
}
