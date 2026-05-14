import Testing
@testable import XTerminal

@MainActor
struct XTReviewProjectionStoreTests {
    @Test
    func snapshotProjectsReviewQueues() {
        let manager = SupervisorManager.makeForTesting()
        manager.setPendingHubGrantsForTesting([pendingGrant()])
        manager.setPendingSupervisorSkillApprovalsForTesting([pendingApproval()])

        let snapshot = XTReviewSurfaceSnapshot.make(from: manager)

        #expect(snapshot.grants.map(\.id) == ["grant-1"])
        #expect(snapshot.approvals.map(\.id) == ["approval-1"])
        #expect(snapshot.candidateReviews.isEmpty)
    }

    @Test
    func storeIgnoresUnrelatedSupervisorMessageChanges() async {
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel.makeForTesting()
        let store = XTReviewProjectionStore()
        store.bind(supervisor: manager, appModel: appModel)

        manager.setPendingHubGrantsForTesting([pendingGrant()])
        await Task.yield()

        let snapshotAfterGrant = store.snapshot
        manager.messages = [
            SupervisorMessage(
                id: "chat-1",
                role: .assistant,
                content: "unrelated supervisor conversation change",
                isVoice: false,
                timestamp: 1
            )
        ]
        await Task.yield()

        #expect(store.snapshot == snapshotAfterGrant)
        #expect(store.snapshot.grants.count == 1)
    }

    private func pendingGrant() -> SupervisorManager.SupervisorPendingGrant {
        SupervisorManager.SupervisorPendingGrant(
            id: "grant-1",
            dedupeKey: "grant:key",
            grantRequestId: "grant-1",
            requestId: "request-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            capability: "browser.control",
            modelId: "gpt-5.4",
            reason: "browser automation requested",
            requestedTtlSec: 600,
            requestedTokenCap: 4000,
            createdAt: 940,
            actionURL: "x-terminal://supervisor?grant=grant-1",
            priorityRank: 1,
            priorityReason: "critical path",
            nextAction: "approve now"
        )
    }

    private func pendingApproval() -> SupervisorManager.SupervisorPendingSkillApproval {
        SupervisorManager.SupervisorPendingSkillApproval(
            id: "approval-1",
            requestId: "approval-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            tool: .deviceBrowserControl,
            toolSummary: "Open dashboard",
            reason: "browser control touches live admin surface",
            createdAt: 940,
            actionURL: "x-terminal://supervisor?approval=approval-1",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation",
            deltaApproval: nil,
            readiness: nil
        )
    }
}
