import Foundation
import Testing
@testable import XTerminal

struct SupervisorDashboardFeedBoardPresentationTests {

    @Test
    func recentSkillBoardBuildsEmptyState() {
        let presentation = SupervisorRecentSkillActivityBoardPresentationMapper.map(
            feed: .init(
                summaryLine: "recent activity",
                items: [],
                actionableCount: 0
            )
        )

        #expect(presentation.iconName == "sparkles.rectangle.stack")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "最近技能活动：0")
        #expect(presentation.summaryLine == "recent activity")
        #expect(presentation.items.isEmpty)
        #expect(presentation.emptyStateText != nil)
    }

    @Test
    func recentSkillBoardBuildsActiveState() {
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-1",
            projectName: "Project 1",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-1",
                projectId: "project-1",
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "agent-browser",
                toolName: "tool.call_skill",
                status: .running,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "Running",
                denyCode: "",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1000,
                updatedAtMs: 2000,
                auditRef: "audit-1"
            ),
            tool: nil,
            toolCall: nil,
            toolSummary: "Open site"
        )
        let presentation = SupervisorRecentSkillActivityBoardPresentationMapper.map(
            feed: .init(
                summaryLine: "running 1",
                items: [item],
                actionableCount: 0
            )
        )

        #expect(presentation.iconName == "sparkles.rectangle.stack.fill")
        #expect(presentation.iconTone == .accent)
        #expect(presentation.title == "最近技能活动：1")
        #expect(presentation.items.map(\.requestId) == ["req-1"])
        #expect(presentation.emptyStateText == nil)
    }

    @Test
    func infrastructureBoardBuildsEmptyState() {
        let presentation = SupervisorInfrastructureFeedBoardPresentationMapper.map(
            feed: .init(summaryLine: "passive watch", items: [])
        )

        #expect(presentation.iconName == "server.rack")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "基础设施动态")
        #expect(presentation.summaryLine == "passive watch")
        #expect(presentation.items.isEmpty)
        #expect(presentation.emptyStateText != nil)
    }

    @Test
    func infrastructureBoardBuildsActiveState() {
        let item = SupervisorInfrastructureFeedPresentation.Item(
            id: "event-1",
            kind: .eventLoop,
            iconName: "bolt.horizontal.circle",
            title: "Event Loop",
            summary: "skill callback received",
            detail: "project-1",
            badgeText: "running",
            tone: .attention,
            timestamp: 100,
            actionURL: "https://example.com",
            actionLabel: "Open"
        )
        let presentation = SupervisorInfrastructureFeedBoardPresentationMapper.map(
            feed: .init(summaryLine: "watch 1", items: [item])
        )

        #expect(presentation.iconName == "server.rack.fill")
        #expect(presentation.iconTone == .accent)
        #expect(presentation.items.map(\.id) == ["event-1"])
        #expect(presentation.emptyStateText == nil)
    }
}
