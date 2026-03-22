import Foundation
import Testing
@testable import XTerminal

struct SupervisorCockpitActionResolverTests {

    @Test
    func submitIntakePrefillsWhenConversationDraftIsEmpty() {
        let plan = SupervisorCockpitActionResolver.resolve(
            .primary(primaryAction("submit_intake")),
            context: context(inputText: "   ")
        )

        #expect(plan?.effects == [
            .setInputText("请开始一个复杂任务：目标 / 约束 / 交付物 / 风险"),
            .requestConversationFocus
        ])
    }

    @Test
    func reviewDeliveryPrefersReplayEvidenceBeforeDoctorFallback() {
        let plan = SupervisorCockpitActionResolver.resolve(
            .primary(primaryAction("review_delivery")),
            context: context(
                reviewReportPath: "/tmp/review.json",
                replayEvidencePath: "/tmp/replay.json"
            )
        )

        #expect(plan?.effects == [.openURL(.filePath("/tmp/replay.json"))])
    }

    @Test
    func reviewDeliveryRefreshesDoctorWhenNoEvidenceExists() {
        let plan = SupervisorCockpitActionResolver.resolve(
            .primary(primaryAction("review_delivery")),
            context: context()
        )

        #expect(plan?.effects == [.refreshSupervisorDoctorReport])
    }

    @Test
    func resolveAccessPrioritizesPendingGrantLink() {
        let plan = SupervisorCockpitActionResolver.resolve(
            .runtimeStage(runtimeStage("resolve_access")),
            context: context(
                firstPendingGrantActionURL: "xt://grant/1",
                firstPendingSkillApprovalActionURL: "xt://approval/1",
                runtimeAccessSurfaceState: .grantRequired
            )
        )

        #expect(plan?.effects == [.openURL(.absolute("xt://grant/1"))])
    }

    @Test
    func resolveAccessFallsBackToModelSettingsSheetWhenPermissionIsDenied() {
        let plan = SupervisorCockpitActionResolver.resolve(
            .runtimeStage(runtimeStage("resolve_access")),
            context: context(runtimeAccessSurfaceState: .permissionDenied)
        )

        #expect(plan?.effects == [.presentWindowSheet(.modelSettings)])
    }

    @Test
    func directedResumeUsesBatonToFocusLaneAndDraftResumeMessage() {
        let baton = DirectedUnblockBaton(
            schemaVersion: "xt.directed_unblock_baton.v1",
            projectID: "project-alpha",
            edgeID: "edge-1",
            blockedLane: "lane-42",
            resolvedBy: "supervisor",
            resolvedFact: "dependency_resolved",
            resumeScope: .continueCurrentTaskOnly,
            deadlineHintUTC: "2026-03-16T12:00:00Z",
            mustNotDo: ["scope_expand", "parallel_claim_new_lane"],
            evidenceRefs: [],
            emittedAtMs: 1_000,
            nextAction: "continue_current_task_only"
        )

        let plan = SupervisorCockpitActionResolver.resolve(
            .runtimeStage(runtimeStage("directed_resume")),
            context: context(directedUnblockBaton: baton)
        )

        #expect(plan?.effects == [
            .setFocusedSplitLane("lane-42"),
            .setInputText("请只继续当前任务，不要扩 scope，不要 claim 新 lane。 目标 lane=lane-42。 next_action=continue_current_task_only。 must_not_do=scope_expand,parallel_claim_new_lane。 基于现有 directed unblock baton 续推，并显式汇报 blocker 是否已解除。"),
            .requestConversationFocus
        ])
    }

    @Test
    func directedResumeFallsBackToClarifyingPromptWithoutBaton() {
        let plan = SupervisorCockpitActionResolver.resolve(
            .runtimeStage(runtimeStage("directed_resume")),
            context: context()
        )

        #expect(plan?.effects == [
            .setInputText("请先说明当前 blocker 和目标 lane，再决定是否继续当前任务。"),
            .requestConversationFocus
        ])
    }

    private func context(
        inputText: String = "",
        reviewReportPath: String? = nil,
        replayEvidencePath: String? = nil,
        firstPendingGrantActionURL: String? = nil,
        firstPendingSkillApprovalActionURL: String? = nil,
        runtimeAccessSurfaceState: XTUISurfaceState? = nil,
        directedUnblockBaton: DirectedUnblockBaton? = nil
    ) -> SupervisorCockpitActionResolver.Context {
        SupervisorCockpitActionResolver.Context(
            inputText: inputText,
            reviewReportPath: reviewReportPath,
            replayEvidencePath: replayEvidencePath,
            firstPendingGrantActionURL: firstPendingGrantActionURL,
            firstPendingSkillApprovalActionURL: firstPendingSkillApprovalActionURL,
            runtimeAccessSurfaceState: runtimeAccessSurfaceState,
            directedUnblockBaton: directedUnblockBaton
        )
    }

    private func primaryAction(_ id: String) -> PrimaryActionRailAction {
        PrimaryActionRailAction(
            id: id,
            title: id,
            subtitle: nil,
            systemImage: "bolt",
            style: .primary
        )
    }

    private func runtimeStage(_ actionID: String?) -> SupervisorRuntimeStageItemPresentation {
        SupervisorRuntimeStageItemPresentation(
            id: "runtime",
            title: "Runtime",
            detail: nil,
            progress: .active,
            surfaceState: .inProgress,
            actionID: actionID,
            actionLabel: nil
        )
    }
}
