import Foundation
import Testing
@testable import XTerminal

struct SplitProposalPanelActionResolverTests {

    @Test
    func generateDescriptorRequiresNonEmptyDraft() {
        let disabled = SplitProposalPanelActionResolver.generateDescriptor(
            context: context(draftTaskDescription: "   ")
        )
        let enabled = SplitProposalPanelActionResolver.generateDescriptor(
            context: context(draftTaskDescription: " build shipping workflow ")
        )

        #expect(disabled.isEnabled == false)
        #expect(enabled.isEnabled)
    }

    @Test
    func generateProposalTrimsDraftBeforeProposing() {
        let plan = SplitProposalPanelActionResolver.resolve(
            .generateProposal,
            context: context(draftTaskDescription: "  build shipping workflow  ")
        )

        #expect(plan?.effects == [.proposeSplit("build shipping workflow")])
    }

    @Test
    func lanePresentationMarksFocusedHighRiskHardSplit() {
        let presentation = SplitProposalPanelActionResolver.lanePresentation(
            for: highRiskHardLane(),
            focusedLaneID: "lane-2"
        )

        #expect(presentation.isFocused)
        #expect(presentation.overrideLabel == "改为轻执行")
        #expect(presentation.focusLabel == "取消定位")
        #expect(presentation.needsHighRiskSoftConfirmation)
    }

    @Test
    func highRiskHardToSoftRequestsExplicitConfirmation() {
        let plan = SplitProposalPanelActionResolver.resolve(
            .toggleLaneMaterialization(highRiskHardLane()),
            context: context()
        )

        #expect(plan?.effects == [.showHighRiskSoftOverrideConfirmation(highRiskHardLane())])
    }

    @Test
    func lowRiskToggleBuildsImmediateOverride() {
        let lane = lowRiskSoftLane()

        let plan = SplitProposalPanelActionResolver.resolve(
            .toggleLaneMaterialization(lane),
            context: context()
        )

        #expect(plan?.effects.count == 1)
        if case .applyOverride(let override, let reason)? = plan?.effects.first {
            #expect(override.laneId == "lane-1")
            #expect(override.createChildProject == true)
            #expect(override.note == "ui_toggle_materialization")
            #expect(override.confirmHighRiskHardToSoft == nil)
            #expect(reason == "ui_lane_materialization_override")
        } else {
            Issue.record("Expected applyOverride effect")
        }
    }

    @Test
    func confirmHighRiskSoftOverrideWritesConfirmedOverride() {
        let lane = highRiskHardLane()

        let plan = SplitProposalPanelActionResolver.resolve(
            .confirmHighRiskSoftOverride(lane),
            context: context()
        )

        #expect(plan?.effects.count == 1)
        if case .applyOverride(let override, let reason)? = plan?.effects.first {
            #expect(override.laneId == "lane-2")
            #expect(override.createChildProject == false)
            #expect(override.note == "ui_confirmed_high_risk_hard_to_soft")
            #expect(override.confirmHighRiskHardToSoft == true)
            #expect(reason == "ui_lane_materialization_override")
        } else {
            Issue.record("Expected applyOverride effect")
        }
    }

    @Test
    func toggleLaneFocusClearsExistingFocus() {
        let plan = SplitProposalPanelActionResolver.resolve(
            .toggleLaneFocus(highRiskHardLane()),
            context: context(focusedLaneID: "lane-2")
        )

        #expect(plan?.effects == [.setFocusedLane(nil)])
    }

    @Test
    func displayLanesMovesFocusedLaneToTop() {
        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: UUID(),
            planVersion: 1,
            complexityScore: 52,
            lanes: [lowRiskSoftLane(), highRiskHardLane()],
            recommendedConcurrency: 2,
            tokenBudgetTotal: 12_000,
            estimatedWallTimeMs: 9_000,
            sourceTaskDescription: "ship",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let lanes = SplitProposalPanelActionResolver.displayLanes(
            from: proposal,
            focusedLaneID: "lane-2"
        )

        #expect(lanes.map(\.laneId) == ["lane-2", "lane-1"])
    }

    @Test
    func footerDescriptorsRespectReplayAndResetAvailability() {
        let disabled = SplitProposalPanelActionResolver.footerDescriptors(
            context: context(hasActiveProposal: false, hasBaseSnapshot: false)
        )
        let enabled = SplitProposalPanelActionResolver.footerDescriptors(
            context: context(hasActiveProposal: true, hasBaseSnapshot: true)
        )

        #expect(disabled.first(where: { $0.label == "回放校验" })?.isEnabled == false)
        #expect(disabled.first(where: { $0.label == "重置" })?.isEnabled == false)
        #expect(enabled.first(where: { $0.label == "回放校验" })?.isEnabled == true)
        #expect(enabled.first(where: { $0.label == "启动多泳道" })?.isEnabled == true)
    }

    private func context(
        draftTaskDescription: String = "",
        focusedLaneID: String? = nil,
        hasActiveProposal: Bool = true,
        hasBaseSnapshot: Bool = false
    ) -> SplitProposalPanelActionResolver.Context {
        SplitProposalPanelActionResolver.Context(
            draftTaskDescription: draftTaskDescription,
            focusedLaneID: focusedLaneID,
            hasActiveProposal: hasActiveProposal,
            hasBaseSnapshot: hasBaseSnapshot
        )
    }

    private func lowRiskSoftLane() -> SplitLaneProposal {
        SplitLaneProposal(
            laneId: "lane-1",
            goal: "Draft UI spec",
            dependsOn: [],
            riskTier: .low,
            budgetClass: .standard,
            createChildProject: false,
            expectedArtifacts: ["spec.md"],
            dodChecklist: ["reviewed"],
            estimatedEffortMs: 1_000,
            tokenBudget: 4_000,
            sourceTaskId: nil,
            notes: []
        )
    }

    private func highRiskHardLane() -> SplitLaneProposal {
        SplitLaneProposal(
            laneId: "lane-2",
            goal: "Deploy migration",
            dependsOn: ["lane-1"],
            riskTier: .high,
            budgetClass: .premium,
            createChildProject: true,
            expectedArtifacts: ["migration.sql"],
            dodChecklist: ["rollback"],
            estimatedEffortMs: 2_000,
            tokenBudget: 8_000,
            sourceTaskId: nil,
            notes: []
        )
    }
}
