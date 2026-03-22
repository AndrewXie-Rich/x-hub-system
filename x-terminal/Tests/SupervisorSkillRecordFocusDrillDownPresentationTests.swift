import Foundation
import Testing
@testable import XTerminal

struct SupervisorSkillRecordFocusDrillDownPresentationTests {

    @Test
    func resolvePrefersMatchedRecentActivity() {
        let activity = recentSkillActivity(requestId: "req-1")
        let resolution = SupervisorFocusPresentation.SkillRecordResolution(
            selectedProjectId: "project-alpha",
            boardAnchorID: SupervisorFocusPresentation.recentSupervisorSkillActivityBoardAnchorID,
            highlightedSkillActivityRequestId: "req-1",
            matchedActivity: activity,
            fallbackProjectId: nil,
            fallbackRequestId: "req-1",
            refreshRecentSkillActivities: false
        )

        let outcome = SupervisorSkillRecordFocusDrillDownPresentation.resolve(
            resolution: resolution,
            fallbackProjectName: "Project Alpha",
            fallbackRecord: fallbackRecord(requestId: "req-1")
        )

        #expect(outcome == .recentActivity(activity))
    }

    @Test
    func resolveFallsBackToFullRecordWhenRecentActivityMissing() {
        let record = fallbackRecord(requestId: "req-fallback")
        let resolution = SupervisorFocusPresentation.SkillRecordResolution(
            selectedProjectId: "project-fallback",
            boardAnchorID: SupervisorFocusPresentation.recentSupervisorSkillActivityBoardAnchorID,
            highlightedSkillActivityRequestId: "req-fallback",
            matchedActivity: nil,
            fallbackProjectId: "project-fallback",
            fallbackRequestId: "req-fallback",
            refreshRecentSkillActivities: false
        )

        let outcome = SupervisorSkillRecordFocusDrillDownPresentation.resolve(
            resolution: resolution,
            fallbackProjectName: "Project Fallback",
            fallbackRecord: record
        )

        #expect(outcome == .fallbackRecord(
            projectId: "project-fallback",
            projectName: "Project Fallback",
            record: record
        ))
    }

    @Test
    func resolveRequestsRefreshWhenNoRecentActivityOrFallbackRecordExists() {
        let resolution = SupervisorFocusPresentation.SkillRecordResolution(
            selectedProjectId: "project-refresh",
            boardAnchorID: SupervisorFocusPresentation.recentSupervisorSkillActivityBoardAnchorID,
            highlightedSkillActivityRequestId: "req-refresh",
            matchedActivity: nil,
            fallbackProjectId: "project-refresh",
            fallbackRequestId: "req-refresh",
            refreshRecentSkillActivities: true
        )

        let outcome = SupervisorSkillRecordFocusDrillDownPresentation.resolve(
            resolution: resolution,
            fallbackProjectName: "Project Refresh",
            fallbackRecord: nil
        )

        #expect(outcome == .refreshNeeded)
    }

    @Test
    func resolveReturnsNoMatchWhenRefreshIsNotNeededAndNoRecordExists() {
        let resolution = SupervisorFocusPresentation.SkillRecordResolution(
            selectedProjectId: "project-idle",
            boardAnchorID: SupervisorFocusPresentation.recentSupervisorSkillActivityBoardAnchorID,
            highlightedSkillActivityRequestId: "req-idle",
            matchedActivity: nil,
            fallbackProjectId: "project-idle",
            fallbackRequestId: "req-idle",
            refreshRecentSkillActivities: false
        )

        let outcome = SupervisorSkillRecordFocusDrillDownPresentation.resolve(
            resolution: resolution,
            fallbackProjectName: nil,
            fallbackRecord: nil
        )

        #expect(outcome == .noMatch)
    }

    private func fallbackRecord(requestId: String) -> SupervisorSkillFullRecord {
        SupervisorSkillFullRecord(
            requestID: requestId,
            projectName: "Project Fallback",
            title: "Supervisor skill completed",
            latestStatus: "completed",
            latestStatusLabel: "Completed",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            supervisorEvidenceJSON: nil
        )
    }

    private func recentSkillActivity(requestId: String) -> SupervisorManager.SupervisorRecentSkillActivity {
        SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: requestId,
                projectId: "project-alpha",
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .completed,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "done",
                denyCode: "",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open dashboard",
            actionURL: nil,
            governance: nil
        )
    }
}
