import Foundation
import Testing
@testable import XTerminal

struct SupervisorSkillActivityFeedPresentationTests {

    @Test
    func mapPrioritizesActionableItemsAndBuildsStructuredSummary() {
        let completed = activity(
            requestId: "completed",
            skillId: "summarize",
            status: .completed,
            updatedAtMs: 1_000
        )
        let running = activity(
            requestId: "running",
            skillId: "agent-browser",
            status: .running,
            updatedAtMs: 2_000
        )
        let failed = activity(
            requestId: "failed",
            skillId: "self-improving-agent",
            status: .failed,
            updatedAtMs: 4_000
        )
        let blocked = activity(
            requestId: "blocked",
            skillId: "code-review",
            status: .blocked,
            updatedAtMs: 3_500
        )
        let hubGrant = activity(
            requestId: "grant",
            skillId: "agent-browser",
            status: .awaitingAuthorization,
            requiredCapability: "web.fetch",
            updatedAtMs: 3_000
        )
        let localApproval = activity(
            requestId: "local",
            skillId: "skill-creator",
            status: .awaitingAuthorization,
            updatedAtMs: 2_500
        )

        let presentation = SupervisorSkillActivityFeedPresentation.map(
            items: [completed, running, failed, blocked, hubGrant, localApproval]
        )

        #expect(presentation.summaryLine.contains("可处理 4"))
        #expect(presentation.summaryLine.contains("本地审批 1"))
        #expect(presentation.summaryLine.contains("Hub 授权 1"))
        #expect(presentation.summaryLine.contains("待恢复 2"))
        #expect(presentation.summaryLine.contains("进行中 1"))
        #expect(presentation.actionableCount == 4)
        #expect(presentation.items.map(\.requestId) == [
            "local",
            "grant",
            "failed",
            "blocked",
            "running",
            "completed"
        ])
    }

    @Test
    func mapFallsBackToQueuedAndCompletedWhenNoActionableItemsExist() {
        let queued = activity(
            requestId: "queued",
            skillId: "find-skills",
            status: .queued,
            updatedAtMs: 5_000
        )
        let completedNew = activity(
            requestId: "completed-new",
            skillId: "summarize",
            status: .completed,
            updatedAtMs: 4_000
        )
        let completedOld = activity(
            requestId: "completed-old",
            skillId: "summarize",
            status: .completed,
            updatedAtMs: 2_000
        )

        let presentation = SupervisorSkillActivityFeedPresentation.map(
            items: [completedOld, queued, completedNew]
        )

        #expect(presentation.summaryLine == "排队中 1 · 已完成 2")
        #expect(presentation.actionableCount == 0)
        #expect(presentation.items.map(\.requestId) == [
            "queued",
            "completed-new",
            "completed-old"
        ])
    }

    @Test
    func mapKeepsEmptyStateNeutral() {
        let presentation = SupervisorSkillActivityFeedPresentation.map(items: [])

        #expect(presentation.summaryLine == "最近活动")
        #expect(presentation.items.isEmpty)
        #expect(presentation.isEmpty)
        #expect(presentation.actionableCount == 0)
    }

    private func activity(
        requestId: String,
        skillId: String,
        status: SupervisorSkillCallStatus,
        requiredCapability: String? = nil,
        updatedAtMs: Int64
    ) -> SupervisorManager.SupervisorRecentSkillActivity {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: requestId,
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: skillId,
            toolName: ToolName.run_command.rawValue,
            status: status,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: requiredCapability,
            grantRequestId: requiredCapability == nil ? nil : "grant-\(requestId)",
            grantId: nil,
            createdAtMs: updatedAtMs - 500,
            updatedAtMs: updatedAtMs,
            auditRef: "audit-\(requestId)"
        )

        return SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .run_command,
            toolCall: nil,
            toolSummary: "swift test",
            actionURL: "x-terminal://project/project-alpha"
        )
    }
}
