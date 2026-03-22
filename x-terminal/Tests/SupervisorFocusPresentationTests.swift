import Foundation
import Testing
@testable import XTerminal

struct SupervisorFocusPresentationTests {

    @Test
    func boardFocusKeepsAnchorAndOptionalProjectSelection() {
        let request = AXSupervisorFocusRequest(
            nonce: 1,
            projectId: "project-board",
            subject: .board(anchorID: SupervisorFocusPresentation.laneHealthBoardAnchorID)
        )

        let resolution = SupervisorFocusPresentation.resolveBoard(
            request: request,
            anchorID: SupervisorFocusPresentation.laneHealthBoardAnchorID
        )

        #expect(resolution.selectedProjectId == "project-board")
        #expect(resolution.boardAnchorID == SupervisorFocusPresentation.laneHealthBoardAnchorID)
    }

    @Test
    func approvalFocusResolvesProjectAndHighlightFromPendingApproval() {
        let request = AXSupervisorFocusRequest(
            nonce: 1,
            projectId: nil,
            subject: .approval(requestId: "approval-1")
        )
        let approval = SupervisorManager.SupervisorPendingSkillApproval(
            id: "approval-1",
            requestId: "approval-1",
            projectId: "project-beta",
            projectName: "Project Beta",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            tool: .deviceBrowserControl,
            toolSummary: "open https://example.com",
            reason: "browser open",
            createdAt: 10,
            actionURL: nil
        )

        let resolution = SupervisorFocusPresentation.resolveApproval(
            request: request,
            requestId: "approval-1",
            pendingApprovals: [approval]
        )

        #expect(resolution.selectedProjectId == "project-beta")
        #expect(
            resolution.boardAnchorID == SupervisorFocusPresentation.pendingSupervisorSkillApprovalBoardAnchorID
        )
        #expect(resolution.highlightedApprovalAnchor == "supervisor.pendingSupervisorSkillApproval.approval-1")
        #expect(resolution.matchedApproval == approval)
        #expect(!resolution.refreshPendingApprovals)
    }

    @Test
    func grantFocusResolvesUniqueCapabilityWithoutExplicitProject() {
        let request = AXSupervisorFocusRequest(
            nonce: 2,
            projectId: nil,
            subject: .grant(grantRequestId: nil, capability: "web.fetch")
        )
        let grant = pendingGrant(
            id: "grant-1",
            projectId: "project-alpha",
            capability: "web.fetch"
        )

        let resolution = SupervisorFocusPresentation.resolveGrant(
            request: request,
            grantRequestId: nil,
            capability: "web.fetch",
            pendingHubGrants: [grant]
        )

        #expect(resolution.selectedProjectId == "project-alpha")
        #expect(resolution.boardAnchorID == SupervisorFocusPresentation.pendingHubGrantBoardAnchorID)
        #expect(resolution.highlightedGrantAnchor == "supervisor.pendingHubGrant.grant-1")
        #expect(resolution.matchedGrant == grant)
        #expect(!resolution.refreshPendingHubGrants)
    }

    @Test
    func grantFocusDoesNotMisrouteWhenCapabilityIsAmbiguous() {
        let request = AXSupervisorFocusRequest(
            nonce: 3,
            projectId: nil,
            subject: .grant(grantRequestId: nil, capability: "web.fetch")
        )
        let grants = [
            pendingGrant(id: "grant-1", projectId: "project-alpha", capability: "web.fetch"),
            pendingGrant(id: "grant-2", projectId: "project-beta", capability: "web.fetch")
        ]

        let resolution = SupervisorFocusPresentation.resolveGrant(
            request: request,
            grantRequestId: nil,
            capability: "web.fetch",
            pendingHubGrants: grants
        )

        #expect(resolution.selectedProjectId == nil)
        #expect(resolution.highlightedGrantAnchor == nil)
        #expect(resolution.matchedGrant == nil)
        #expect(!resolution.refreshPendingHubGrants)
    }

    @Test
    func skillRecordFocusHighlightsRecentActivityWhenPresent() {
        let request = AXSupervisorFocusRequest(
            nonce: 4,
            projectId: nil,
            subject: .skillRecord(requestId: "req-1")
        )
        let activity = recentSkillActivity(
            projectId: "project-record",
            requestId: "req-1"
        )

        let resolution = SupervisorFocusPresentation.resolveSkillRecord(
            request: request,
            requestId: "req-1",
            recentActivities: [activity]
        )

        #expect(resolution.selectedProjectId == "project-record")
        #expect(
            resolution.boardAnchorID == SupervisorFocusPresentation.recentSupervisorSkillActivityBoardAnchorID
        )
        #expect(resolution.highlightedSkillActivityRequestId == "req-1")
        #expect(resolution.matchedActivity == activity)
        #expect(resolution.fallbackProjectId == nil)
        #expect(!resolution.refreshRecentSkillActivities)
    }

    @Test
    func skillRecordFocusUsesFallbackProjectAndRequestsRefreshWhenRecentListEmpty() {
        let request = AXSupervisorFocusRequest(
            nonce: 5,
            projectId: "project-explicit",
            subject: .skillRecord(requestId: "req-missing")
        )

        let resolution = SupervisorFocusPresentation.resolveSkillRecord(
            request: request,
            requestId: "req-missing",
            recentActivities: []
        )

        #expect(resolution.selectedProjectId == "project-explicit")
        #expect(resolution.highlightedSkillActivityRequestId == "req-missing")
        #expect(resolution.matchedActivity == nil)
        #expect(resolution.fallbackProjectId == "project-explicit")
        #expect(resolution.fallbackRequestId == "req-missing")
        #expect(resolution.refreshRecentSkillActivities)
    }

    private func pendingGrant(
        id: String,
        projectId: String,
        capability: String
    ) -> SupervisorManager.SupervisorPendingGrant {
        SupervisorManager.SupervisorPendingGrant(
            id: id,
            dedupeKey: id,
            grantRequestId: id,
            requestId: "req-\(id)",
            projectId: projectId,
            projectName: projectId,
            capability: capability,
            modelId: "gpt-5.4",
            reason: "test",
            requestedTtlSec: 3600,
            requestedTokenCap: 8000,
            createdAt: 10,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "test",
            nextAction: "approve"
        )
    }

    private func recentSkillActivity(
        projectId: String,
        requestId: String
    ) -> SupervisorManager.SupervisorRecentSkillActivity {
        SupervisorManager.SupervisorRecentSkillActivity(
            projectId: projectId,
            projectName: projectId,
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
}
