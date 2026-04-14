import Foundation
import Testing
@testable import XTerminal

struct ProjectGovernanceThreeAxisOverviewPresentationTests {
    @Test
    func recommendedAgentCombinationUsesDualDialMainline() {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )

        let overview = ProjectGovernanceThreeAxisOverviewPresentation(presentation: presentation)

        #expect(overview.principleLines == [
            "A-Tier 决定项目 AI 能动多大",
            "S-Tier 决定 Supervisor 管多深",
            "Heartbeat / Review 决定多久看一次、什么时候插手"
        ])
        #expect(overview.executionDial.token == "A4")
        #expect(overview.executionDial.selectedIndex == 4)
        #expect(overview.supervisorDial.token == "S3")
        #expect(overview.supervisorDial.selectedIndex == 3)
        #expect(overview.bridgeTitle == "推荐主档")
        #expect(overview.bridgeLabel == "A4 + S3")
        #expect(overview.bridgeDetail.contains("高自治执行 + 旁路战略监督"))
        #expect(overview.rhythmCards.map(\.title) == ["Heartbeat", "Review", "插手方式", "事件触发"])
        #expect(overview.memoryLanes.map(\.title) == ["Project AI", "Supervisor"])
        #expect(overview.memoryLanes[0].summary.contains("Recent Project Dialogue"))
        #expect(overview.memoryLanes[1].summary.contains("Review Memory Depth"))
        #expect(overview.runtimeLoops.map(\.title) == [
            "Project Coder Loop",
            "Supervisor Governance Loop",
            "Hub Run Scheduler"
        ])
        #expect(overview.runtimeSummary.contains("A4 不是去掉 Supervisor"))
        #expect(overview.guidanceSteps.map(\.title) == [
            "Review Note",
            "Guidance Injection",
            "Safe Point",
            "Ack"
        ])
        #expect(overview.guidanceFlowSummary.contains("safe point"))
        #expect(overview.memoryRuleSummary.contains("configured / recommended / effective"))
        #expect(overview.boundaryTokens.contains("grant"))
        #expect(overview.boundaryTokens.contains("kill-switch"))
        #expect(overview.boundarySummary.contains("grant"))
    }

    @Test
    func highRiskCombinationStillExplainsHardBoundariesOutsideAS() {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s0SilentAudit,
            reviewPolicyMode: .milestoneOnly,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 0,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false
        )

        let overview = ProjectGovernanceThreeAxisOverviewPresentation(presentation: presentation)

        #expect(overview.bridgeTitle == "高风险组合")
        #expect(overview.bridgeLabel == "A4 + S0")
        #expect(overview.bridgeDetail.contains("系统允许保存"))
        #expect(overview.boundarySummary == "真正 fail-closed 的是 grant、runtime、policy、TTL、kill-switch，不是单纯 A/S 组合。")
        #expect(overview.executionDial.detail.contains("当前生效"))
        #expect(overview.supervisorDial.detail.contains("当前生效"))
        #expect(overview.memoryLanes[0].detail.contains("A-Tier 只提供 project-memory ceiling"))
        #expect(overview.memoryLanes[1].detail.contains("S-Tier 只提供 review-memory ceiling"))
        #expect(overview.runtimeLoops[2].detail.contains("grant"))
        #expect(overview.guidanceSteps[3].detail.contains("接受、延后或拒绝"))
        #expect(overview.rhythmCards.last?.detail.contains("只保留 A 档强制检查点") == true)
    }
}
