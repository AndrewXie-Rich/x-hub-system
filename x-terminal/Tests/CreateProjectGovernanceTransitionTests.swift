import Foundation
import Testing
@testable import XTerminal

struct CreateProjectGovernanceTransitionTests {
    @Test
    func executionTierTransitionPreservesReviewCadenceAndExistingSupervisorSelection() {
        let original = AXProjectGovernanceBundle(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s0SilentAudit,
            reviewPolicyMode: .aggressive,
            schedule: AXProjectGovernanceSchedule(
                progressHeartbeatSeconds: 420,
                reviewPulseSeconds: 840,
                brainstormReviewSeconds: 1260,
                eventDrivenReviewEnabled: true,
                eventReviewTriggers: [.manualRequest, .planDrift]
            )
        )

        let updated = original.applyingExecutionTierPreservingReviewConfiguration(.a4OpenClaw)

        #expect(updated.executionTier == .a4OpenClaw)
        #expect(updated.supervisorInterventionTier == .s0SilentAudit)
        #expect(updated.reviewPolicyMode == .aggressive)
        #expect(updated.schedule.progressHeartbeatSeconds == 420)
        #expect(updated.schedule.reviewPulseSeconds == 840)
        #expect(updated.schedule.brainstormReviewSeconds == 1260)
        #expect(updated.schedule.eventDrivenReviewEnabled)
        #expect(updated.schedule.eventReviewTriggers == [.manualRequest, .planDrift])
    }

    @Test
    func triggerNormalizationForExecutionTierTransitionPreservesSelectedOptionalTriggers() {
        let normalized = AXProjectReviewTrigger.normalizedSelectionForExecutionTierTransition(
            to: .a4OpenClaw,
            preserving: [.manualRequest, .planDrift, .preDoneSummary, .planDrift]
        )

        #expect(normalized == [
            .blockerDetected,
            .preHighRiskAction,
            .preDoneSummary,
            .planDrift
        ])
    }

    @Test
    func triggerNormalizationForObserveTierRestoresDefaultManualReviewEntry() {
        let normalized = AXProjectReviewTrigger.normalizedSelectionForExecutionTierTransition(
            to: .a0Observe,
            preserving: [.failureStreak]
        )

        #expect(normalized == [
            .preDoneSummary,
            .failureStreak,
            .manualRequest
        ])
    }
}
