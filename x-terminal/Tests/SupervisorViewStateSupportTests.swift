import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorViewStateSupportTests {

    @Test
    func refreshedAuditDrillDownSelectionRefreshesRecentSkillActivityDetail() {
        let currentActivity = recentSkillActivity(
            requestId: "req-refresh-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            status: .running,
            resultSummary: "still running",
            updatedAtMs: 2_000
        )
        let updatedActivity = recentSkillActivity(
            requestId: "req-refresh-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            status: .completed,
            resultSummary: "finished successfully",
            updatedAtMs: 9_000
        )
        let oldRecord = fullRecord(
            requestId: "req-refresh-1",
            projectName: "Project Alpha",
            latestStatus: "running",
            latestStatusLabel: "Running"
        )
        let newRecord = fullRecord(
            requestId: "req-refresh-1",
            projectName: "Project Alpha",
            latestStatus: "completed",
            latestStatusLabel: "Completed"
        )

        let currentSelection = SupervisorAuditDrillDownSelection.recentSkillActivity(
            currentActivity,
            fullRecord: oldRecord
        )
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            builtinGovernedSkills: [],
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [updatedActivity],
            recentSupervisorEventLoopActivities: []
        )

        let refreshedSelection = SupervisorViewStateSupport.refreshedAuditDrillDownSelection(
            for: currentSelection.source,
            context: context
        ) { projectId, projectName, requestId in
            #expect(projectId == "project-alpha")
            #expect(projectName == "Project Alpha")
            #expect(requestId == "req-refresh-1")
            return newRecord
        }

        guard let refreshedSelection else {
            Issue.record("Expected refreshed audit drill-down selection")
            return
        }

        #expect(refreshedSelection.fullRecord == newRecord)
        #expect(refreshedSelection.presentation.statusLabel == "Completed")
        #expect(refreshedSelection.presentation.summary == "finished successfully")

        guard case .recentSkillActivity(let refreshedActivity) = refreshedSelection.source else {
            Issue.record("Expected recent skill activity source after refresh")
            return
        }
        #expect(refreshedActivity.status == "completed")
        #expect(refreshedActivity.resultSummary == "finished successfully")
        #expect(refreshedActivity.record.updatedAtMs == 9_000)
    }

    @Test
    func refreshedAuditDrillDownSelectionClearsMissingPendingGrant() {
        let currentSelection = SupervisorAuditDrillDownSelection.pendingHubGrant(
            pendingGrant(
                id: "grant-1",
                grantRequestId: "grant-req-1",
                requestId: "req-1"
            )
        )
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            builtinGovernedSkills: [],
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [],
            recentSupervisorEventLoopActivities: []
        )

        let refreshedSelection = SupervisorViewStateSupport.refreshedAuditDrillDownSelection(
            currentSelection: currentSelection,
            context: context
        ) { _, _, _ in
            nil
        }

        #expect(refreshedSelection == nil)
    }

    @Test
    func refreshedAuditDrillDownSelectionRefreshesEventLoopDetailAndRelatedRecord() {
        let currentEvent = eventLoopActivity(
            id: "event-1",
            dedupeKey: "grant_resolution:req-loop-1",
            resultSummary: "waiting for resolution",
            updatedAt: 2_000
        )
        let updatedEvent = eventLoopActivity(
            id: "event-1",
            dedupeKey: "grant_resolution:req-loop-1",
            resultSummary: "resolved and continued",
            updatedAt: 9_000
        )
        let relatedSkill = recentSkillActivity(
            requestId: "req-loop-1",
            projectId: "project-beta",
            projectName: "Project Beta",
            status: .completed,
            resultSummary: "continued successfully",
            updatedAtMs: 9_100
        )
        let oldRecord = fullRecord(
            requestId: "req-loop-1",
            projectName: "Project Beta",
            latestStatus: "running",
            latestStatusLabel: "Running"
        )
        let newRecord = fullRecord(
            requestId: "req-loop-1",
            projectName: "Project Beta",
            latestStatus: "completed",
            latestStatusLabel: "Completed"
        )

        let currentSelection = SupervisorAuditDrillDownSelection.eventLoop(
            currentEvent,
            relatedSkillActivity: nil,
            fullRecord: oldRecord
        )
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            builtinGovernedSkills: [],
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "running",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [relatedSkill],
            recentSupervisorEventLoopActivities: [updatedEvent]
        )

        let refreshedSelection = SupervisorViewStateSupport.refreshedAuditDrillDownSelection(
            currentSelection: currentSelection,
            context: context
        ) { projectId, projectName, requestId in
            #expect(projectId == "project-beta")
            #expect(projectName == "Project Beta")
            #expect(requestId == "req-loop-1")
            return newRecord
        }

        guard let refreshedSelection else {
            Issue.record("Expected refreshed event-loop audit drill-down selection")
            return
        }

        #expect(refreshedSelection.fullRecord == newRecord)
        #expect(refreshedSelection.presentation.requestId == "req-loop-1")
        #expect(refreshedSelection.presentation.sections.contains(where: { section in
            section.title == "Result" && section.fields.contains(where: { field in
                field.label == "Result Summary" && field.value.contains("resolved and continued")
            })
        }))

        guard case .eventLoop(let refreshedActivity) = refreshedSelection.source else {
            Issue.record("Expected event loop source after refresh")
            return
        }
        #expect(refreshedActivity.resultSummary == "resolved and continued")
        #expect(refreshedActivity.updatedAt == 9_000)
    }

    private func fullRecord(
        requestId: String,
        projectName: String,
        latestStatus: String,
        latestStatusLabel: String
    ) -> SupervisorSkillFullRecord {
        SupervisorSkillFullRecord(
            requestID: requestId,
            projectName: projectName,
            title: "Supervisor skill \(latestStatusLabel.lowercased())",
            latestStatus: latestStatus,
            latestStatusLabel: latestStatusLabel,
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

    private func recentSkillActivity(
        requestId: String,
        projectId: String,
        projectName: String,
        status: SupervisorSkillCallStatus,
        resultSummary: String,
        updatedAtMs: Int64
    ) -> SupervisorManager.SupervisorRecentSkillActivity {
        SupervisorManager.SupervisorRecentSkillActivity(
            projectId: projectId,
            projectName: projectName,
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: requestId,
                projectId: projectId,
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: status,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: resultSummary,
                denyCode: "",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: updatedAtMs,
                auditRef: "audit-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open dashboard",
            actionURL: nil,
            governance: nil
        )
    }

    private func eventLoopActivity(
        id: String,
        dedupeKey: String,
        resultSummary: String,
        updatedAt: Double
    ) -> SupervisorManager.SupervisorEventLoopActivity {
        SupervisorManager.SupervisorEventLoopActivity(
            id: id,
            createdAt: 1_000,
            updatedAt: updatedAt,
            triggerSource: "grant_resolution",
            status: "completed",
            reasonCode: "resolved",
            dedupeKey: dedupeKey,
            projectId: "project-beta",
            projectName: "Project Beta",
            triggerSummary: "grant resolved",
            resultSummary: resultSummary,
            policySummary: "policy ok"
        )
    }

    private func pendingGrant(
        id: String,
        grantRequestId: String,
        requestId: String
    ) -> SupervisorManager.SupervisorPendingGrant {
        SupervisorManager.SupervisorPendingGrant(
            id: id,
            dedupeKey: "grant:\(grantRequestId)",
            grantRequestId: grantRequestId,
            requestId: requestId,
            projectId: "project-alpha",
            projectName: "Project Alpha",
            capability: "browser.control",
            modelId: "gpt-5.4",
            reason: "browser automation requested",
            requestedTtlSec: 600,
            requestedTokenCap: 4000,
            createdAt: 1_000,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "critical path",
            nextAction: "approve now"
        )
    }
}
