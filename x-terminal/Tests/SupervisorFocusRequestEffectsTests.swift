import Foundation
import Testing
@testable import XTerminal

struct SupervisorFocusRequestEffectsTests {

    @Test
    func boardPlanKeepsAnchorWithoutRefresh() {
        let request = AXSupervisorFocusRequest(
            nonce: 0,
            projectId: "project-board",
            subject: .board(anchorID: SupervisorFocusPresentation.laneHealthBoardAnchorID)
        )

        let plan = SupervisorFocusRequestEffects.board(
            request: request,
            anchorID: SupervisorFocusPresentation.laneHealthBoardAnchorID
        )

        #expect(plan.selectedProjectId == "project-board")
        #expect(plan.boardAnchorID == SupervisorFocusPresentation.laneHealthBoardAnchorID)
        #expect(plan.rowAnchorID == nil)
        #expect(plan.highlights.pendingHubGrantAnchor == nil)
        #expect(plan.highlights.pendingSupervisorSkillApprovalAnchor == nil)
        #expect(plan.highlights.recentSkillActivityRequestId == nil)
        #expect(plan.auditDrillDown == nil)
        #expect(plan.refresh == nil)
    }

    @Test
    func approvalPlanSelectsRowAndNoRefreshWhenApprovalMatches() {
        let request = AXSupervisorFocusRequest(
            nonce: 1,
            projectId: nil,
            subject: .approval(requestId: "approval-1")
        )
        let approval = pendingApproval(
            requestId: "approval-1",
            projectId: "project-alpha"
        )

        let plan = SupervisorFocusRequestEffects.approval(
            request: request,
            requestId: "approval-1",
            pendingApprovals: [approval]
        )

        #expect(plan.selectedProjectId == "project-alpha")
        #expect(plan.boardAnchorID == SupervisorFocusPresentation.pendingSupervisorSkillApprovalBoardAnchorID)
        #expect(plan.rowAnchorID == SupervisorFocusPresentation.pendingSupervisorSkillApprovalRowAnchor(approval))
        #expect(plan.highlights.pendingSupervisorSkillApprovalAnchor == plan.rowAnchorID)
        #expect(plan.highlights.pendingHubGrantAnchor == nil)
        #expect(plan.highlights.recentSkillActivityRequestId == nil)
        #expect(plan.auditDrillDown == nil)
        #expect(plan.refresh == nil)
    }

    @Test
    func resolveRoutesApprovalSubjectToApprovalPlan() {
        let request = AXSupervisorFocusRequest(
            nonce: 6,
            projectId: nil,
            subject: .approval(requestId: "approval-routed")
        )
        let approval = pendingApproval(
            requestId: "approval-routed",
            projectId: "project-routed"
        )

        let plan = SupervisorFocusRequestEffects.resolve(
            request: request,
            context: SupervisorFocusRequestEffects.Context(
                pendingHubGrants: [],
                pendingSupervisorSkillApprovals: [approval],
                recentSupervisorSkillActivities: []
            ),
            loadRecentSkillRecord: { _, _, _ in nil },
            loadFallbackSkillRecord: { _, _ in nil }
        )

        #expect(plan.selectedProjectId == "project-routed")
        #expect(plan.rowAnchorID == SupervisorFocusPresentation.pendingSupervisorSkillApprovalRowAnchor(approval))
        #expect(plan.refresh == nil)
    }

    @Test
    func grantPlanRequestsRefreshWhenGrantListIsEmpty() {
        let request = AXSupervisorFocusRequest(
            nonce: 2,
            projectId: "project-empty",
            subject: .grant(grantRequestId: "grant-1", capability: nil)
        )

        let plan = SupervisorFocusRequestEffects.grant(
            request: request,
            grantRequestId: "grant-1",
            capability: nil,
            pendingHubGrants: []
        )

        #expect(plan.selectedProjectId == "project-empty")
        #expect(plan.boardAnchorID == SupervisorFocusPresentation.pendingHubGrantBoardAnchorID)
        #expect(plan.rowAnchorID == nil)
        #expect(plan.highlights.pendingHubGrantAnchor == nil)
        #expect(plan.refresh == .pendingHubGrants)
    }

    @Test
    func skillRecordPlanUsesRecentActivityAuditSelectionWhenPresent() {
        let request = AXSupervisorFocusRequest(
            nonce: 3,
            projectId: nil,
            subject: .skillRecord(requestId: "req-1")
        )
        let activity = recentSkillActivity(
            requestId: "req-1",
            projectId: "project-beta",
            projectName: "Project Beta"
        )
        let fullRecord = skillFullRecord(
            requestId: "req-1",
            projectName: "Project Beta"
        )

        let plan = SupervisorFocusRequestEffects.skillRecord(
            request: request,
            requestId: "req-1",
            recentActivities: [activity],
            loadRecentSkillRecord: { projectId, projectName, requestId in
                #expect(projectId == "project-beta")
                #expect(projectName == "Project Beta")
                #expect(requestId == "req-1")
                return fullRecord
            },
            loadFallbackSkillRecord: { _, _ in
                Issue.record("fallback loader should not be used when recent activity matches")
                return nil
            }
        )

        #expect(plan.selectedProjectId == "project-beta")
        #expect(plan.boardAnchorID == SupervisorFocusPresentation.recentSupervisorSkillActivityBoardAnchorID)
        #expect(plan.rowAnchorID == SupervisorFocusPresentation.recentSkillActivityRowAnchor(activity))
        #expect(plan.highlights.recentSkillActivityRequestId == "req-1")
        #expect(plan.refresh == nil)
        #expect(plan.auditDrillDown?.source == .recentSkillActivity(activity))
        #expect(plan.auditDrillDown?.fullRecord == fullRecord)
    }

    @Test
    func skillRecordPlanFallsBackToProjectAuditRecord() {
        let request = AXSupervisorFocusRequest(
            nonce: 4,
            projectId: "project-fallback",
            subject: .skillRecord(requestId: "req-fallback")
        )
        let fullRecord = skillFullRecord(
            requestId: "req-fallback",
            projectName: "Project Fallback"
        )

        let plan = SupervisorFocusRequestEffects.skillRecord(
            request: request,
            requestId: "req-fallback",
            recentActivities: [],
            loadRecentSkillRecord: { _, _, _ in
                Issue.record("recent record loader should not be used for fallback-only path")
                return nil
            },
            loadFallbackSkillRecord: { projectId, requestId in
                #expect(projectId == "project-fallback")
                #expect(requestId == "req-fallback")
                return SupervisorFocusRequestEffects.FallbackSkillRecord(
                    projectName: "Project Fallback",
                    record: fullRecord
                )
            }
        )

        #expect(plan.selectedProjectId == "project-fallback")
        #expect(plan.rowAnchorID == nil)
        #expect(plan.highlights.recentSkillActivityRequestId == "req-fallback")
        #expect(plan.refresh == nil)
        #expect(plan.auditDrillDown?.source == .fullRecordFallback(
            projectId: "project-fallback",
            projectName: "Project Fallback",
            record: fullRecord
        ))
        #expect(plan.auditDrillDown?.fullRecord == fullRecord)
    }

    @Test
    func skillRecordPlanRequestsRefreshWhenNoRecentActivityOrFallbackExists() {
        let request = AXSupervisorFocusRequest(
            nonce: 5,
            projectId: "project-refresh",
            subject: .skillRecord(requestId: "req-refresh")
        )

        let plan = SupervisorFocusRequestEffects.skillRecord(
            request: request,
            requestId: "req-refresh",
            recentActivities: [],
            loadRecentSkillRecord: { _, _, _ in nil },
            loadFallbackSkillRecord: { _, _ in nil }
        )

        #expect(plan.selectedProjectId == "project-refresh")
        #expect(plan.rowAnchorID == nil)
        #expect(plan.highlights.recentSkillActivityRequestId == "req-refresh")
        #expect(plan.auditDrillDown == nil)
        #expect(plan.refresh == .recentSupervisorSkillActivities)
    }

    private func pendingApproval(
        requestId: String,
        projectId: String
    ) -> SupervisorManager.SupervisorPendingSkillApproval {
        SupervisorManager.SupervisorPendingSkillApproval(
            id: requestId,
            requestId: requestId,
            projectId: projectId,
            projectName: projectId,
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            tool: .deviceBrowserControl,
            toolSummary: "open dashboard",
            reason: "test",
            createdAt: 1,
            actionURL: nil
        )
    }

    private func recentSkillActivity(
        requestId: String,
        projectId: String,
        projectName: String
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
                skillId: "summarize",
                toolName: ToolName.summarize.rawValue,
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
            tool: .summarize,
            toolCall: nil,
            toolSummary: "summarize spec",
            actionURL: nil,
            governance: nil
        )
    }

    private func skillFullRecord(
        requestId: String,
        projectName: String
    ) -> SupervisorSkillFullRecord {
        SupervisorSkillFullRecord(
            requestID: requestId,
            projectName: projectName,
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
}
