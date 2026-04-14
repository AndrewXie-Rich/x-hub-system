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
    func boardFocusSupportsMemoryBoardAnchor() {
        let request = AXSupervisorFocusRequest(
            nonce: 11,
            projectId: nil,
            subject: .board(anchorID: SupervisorFocusPresentation.memoryBoardAnchorID)
        )

        let resolution = SupervisorFocusPresentation.resolveBoard(
            request: request,
            anchorID: SupervisorFocusPresentation.memoryBoardAnchorID
        )

        #expect(resolution.selectedProjectId == nil)
        #expect(resolution.boardAnchorID == SupervisorFocusPresentation.memoryBoardAnchorID)
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
    func candidateReviewFocusResolvesProjectAndHighlightFromReviewQueue() {
        let request = AXSupervisorFocusRequest(
            nonce: 31,
            projectId: nil,
            subject: .candidateReview(requestId: "req-review-1")
        )
        let item = HubIPCClient.SupervisorCandidateReviewItem(
            schemaVersion: "v1",
            reviewId: "review-1",
            requestId: "req-review-1",
            evidenceRef: "audit://candidate/1",
            reviewState: "pending_review",
            durablePromotionState: "candidate_only",
            promotionBoundary: "project",
            deviceId: "device-1",
            userId: "user-1",
            appId: "xt",
            threadId: "thread-1",
            threadKey: "thread-key-1",
            projectId: "project-review",
            projectIds: [],
            scopes: ["project_memory"],
            recordTypes: ["canonical"],
            auditRefs: [],
            idempotencyKeys: [],
            candidateCount: 2,
            summaryLine: "归并了 2 条候选记忆",
            mirrorTarget: "xt_local_store",
            localStoreRole: "cache",
            carrierKind: "review_bundle",
            carrierSchemaVersion: "v1",
            pendingChangeId: "",
            pendingChangeStatus: "",
            editSessionId: "",
            docId: "",
            writebackRef: "",
            stageCreatedAtMs: 0,
            stageUpdatedAtMs: 0,
            latestEmittedAtMs: 1_000,
            createdAtMs: 900,
            updatedAtMs: 1_000
        )

        let resolution = SupervisorFocusPresentation.resolveCandidateReview(
            request: request,
            requestId: "req-review-1",
            candidateReviews: [item]
        )

        #expect(resolution.selectedProjectId == "project-review")
        #expect(resolution.boardAnchorID == SupervisorFocusPresentation.candidateReviewBoardAnchorID)
        #expect(resolution.highlightedCandidateReviewAnchor == SupervisorFocusPresentation.candidateReviewRowAnchor(item))
        #expect(resolution.matchedCandidateReview == item)
        #expect(!resolution.refreshCandidateReviews)
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
