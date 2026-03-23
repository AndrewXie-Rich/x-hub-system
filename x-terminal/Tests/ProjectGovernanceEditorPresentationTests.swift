import Foundation
import Testing
@testable import XTerminal

struct ProjectGovernanceEditorPresentationTests {
    @Test
    func executionTierCardPresentationSeparatesConfiguredAndEffectiveStates() {
        let current = ProjectExecutionTierCardPresentation(
            tier: .a3DeliverAuto,
            configuredTier: .a3DeliverAuto,
            effectiveTier: .a3DeliverAuto
        )
        #expect(current.statusBadges == [
            ProjectGovernanceStatusBadge(label: "Current", tone: .current)
        ])
        #expect(current.accessibilityStateLabel == "current")

        let effectiveOnly = ProjectExecutionTierCardPresentation(
            tier: .a4OpenClaw,
            configuredTier: .a3DeliverAuto,
            effectiveTier: .a4OpenClaw
        )
        #expect(effectiveOnly.statusBadges == [
            ProjectGovernanceStatusBadge(label: "Effective", tone: .effective)
        ])
        #expect(effectiveOnly.accessibilityStateLabel == "effective")
    }

    @Test
    func supervisorTierCardPresentationIncludesRecommendationAndSafetyMarkers() {
        let recommendedCurrent = ProjectSupervisorTierCardPresentation(
            tier: .s3StrategicCoach,
            currentExecutionTier: .a3DeliverAuto,
            configuredTier: .s3StrategicCoach,
            effectiveTier: .s3StrategicCoach
        )
        #expect(recommendedCurrent.statusBadges.contains(
            ProjectGovernanceStatusBadge(label: "Current", tone: .current)
        ))
        #expect(recommendedCurrent.statusBadges.contains(
            ProjectGovernanceStatusBadge(label: "Recommended", tone: .recommended)
        ))

        let belowFloor = ProjectSupervisorTierCardPresentation(
            tier: .s0SilentAudit,
            currentExecutionTier: .a4OpenClaw,
            configuredTier: .s2PeriodicReview,
            effectiveTier: .s2PeriodicReview
        )
        #expect(belowFloor.statusBadges.contains(
            ProjectGovernanceStatusBadge(label: "Below Safe Floor", tone: .belowSafeFloor)
        ))
        #expect(belowFloor.accessibilityStateLabel == "available")
    }

    @Test
    func heartbeatReviewPresentationSplitsMandatoryOptionalAndDerivedTriggers() {
        let presentation = ProjectHeartbeatReviewEditorPresentation(
            configuredExecutionTier: .a4OpenClaw,
            configuredReviewPolicyMode: .hybrid,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            resolvedGovernance: resolvedGovernance(
                executionTier: .a4OpenClaw,
                supervisorTier: .s3StrategicCoach,
                reviewPolicyMode: .hybrid,
                reviewPulseSeconds: 1200,
                brainstormReviewSeconds: 2400,
                eventDrivenReviewEnabled: true
            )
        )

        #expect(presentation.mandatoryTriggers == [.blockerDetected, .preHighRiskAction, .preDoneSummary])
        #expect(presentation.optionalTriggers == [.failureStreak, .planDrift])
        #expect(presentation.derivedTriggers == [.manualRequest, .userOverride, .periodicPulse, .noProgressWindow])
        #expect(presentation.baselineDecisionInput.trigger == .noProgressWindow)
        #expect(presentation.baselineDecisionInput.runKind == .brainstorm)
        #expect(presentation.baselineDecisionSummary.contains("brainstorm cadence"))
    }

    @Test
    func heartbeatReviewPresentationFallsBackToManualReviewWhenCadenceIsOff() {
        let presentation = ProjectHeartbeatReviewEditorPresentation(
            configuredExecutionTier: .a1Plan,
            configuredReviewPolicyMode: .off,
            reviewPulseSeconds: 0,
            brainstormReviewSeconds: 0,
            resolvedGovernance: resolvedGovernance(
                executionTier: .a1Plan,
                supervisorTier: .s1MilestoneReview,
                reviewPolicyMode: .off,
                reviewPulseSeconds: 0,
                brainstormReviewSeconds: 0,
                eventDrivenReviewEnabled: false
            )
        )

        #expect(presentation.derivedTriggers == [.manualRequest, .userOverride])
        #expect(presentation.baselineDecisionInput.trigger == .manualRequest)
        #expect(presentation.baselineDecisionInput.runKind == .manual)
        #expect(presentation.baselineDecision.reviewLevel == .r1Pulse)
    }

    private func resolvedGovernance(
        executionTier: AXProjectExecutionTier,
        supervisorTier: AXProjectSupervisorInterventionTier,
        reviewPolicyMode: AXProjectReviewPolicyMode,
        reviewPulseSeconds: Int,
        brainstormReviewSeconds: Int,
        eventDrivenReviewEnabled: Bool
    ) -> AXProjectResolvedGovernanceState {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("governance-editor-presentation-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: executionTier,
            supervisorInterventionTier: supervisorTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: executionTier.defaultProgressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled,
            eventReviewTriggers: executionTier.defaultEventReviewTriggers
        )
        return xtResolveProjectGovernance(projectRoot: root, config: config)
    }
}
