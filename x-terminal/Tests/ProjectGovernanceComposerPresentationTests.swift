import Foundation
import Testing
@testable import XTerminal

struct ProjectGovernanceComposerPresentationTests {
    @Test
    func governanceEditorCasesStaySplitIntoThreeIndependentAxes() {
        #expect(XTProjectGovernanceDestination.editorCases == [
            .executionTier,
            .supervisorTier,
            .heartbeatReview
        ])
    }

    @Test
    func createProjectComposerPresentationKeepsAxisSpecificLabelsAndSelection() throws {
        let governancePresentation = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .preHighRiskAction, .preDoneSummary]
        )

        let presentation = ProjectGovernanceComposerPresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .hybrid,
            governancePresentation: governancePresentation,
            selectedDestination: .heartbeatReview
        )

        #expect(presentation.cards.map(\.destination) == XTProjectGovernanceDestination.editorCases)

        let executionCard = try #require(
            presentation.cards.first(where: { $0.destination == .executionTier })
        )
        #expect(executionCard.heading == "A-Tier")
        #expect(executionCard.title == "A4 代理")
        #expect(executionCard.summary == AXProjectExecutionTier.a4OpenClaw.oneLineSummary)
        #expect(executionCard.accentTone == .orange)
        #expect(!executionCard.isSelected)

        let supervisorCard = try #require(
            presentation.cards.first(where: { $0.destination == .supervisorTier })
        )
        #expect(supervisorCard.heading == "S-Tier")
        #expect(supervisorCard.title == "S1 里程碑审查")
        #expect(supervisorCard.summary == AXProjectSupervisorInterventionTier.s1MilestoneReview.oneLineSummary)
        #expect(supervisorCard.accentTone == .blue)
        #expect(!supervisorCard.isSelected)

        let heartbeatCard = try #require(
            presentation.cards.first(where: { $0.destination == .heartbeatReview })
        )
        #expect(heartbeatCard.heading == "Heartbeat / Review")
        #expect(heartbeatCard.title == "混合")
        #expect(heartbeatCard.summary == governancePresentation.reviewCadenceText)
        #expect(heartbeatCard.accentTone == .green)
        #expect(heartbeatCard.isSelected)
    }

    @Test
    func overviewSelectionDoesNotAliasIntoComposerCardSelection() {
        let presentation = ProjectGovernanceComposerPresentation(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .milestoneOnly,
            governancePresentation: ProjectGovernancePresentation(
                executionTier: .a1Plan,
                supervisorInterventionTier: .s2PeriodicReview,
                reviewPolicyMode: .milestoneOnly,
                progressHeartbeatSeconds: 1200,
                reviewPulseSeconds: 0,
                brainstormReviewSeconds: 0,
                eventDrivenReviewEnabled: true
            ),
            selectedDestination: .overview
        )

        #expect(presentation.cards.allSatisfy { !$0.isSelected })
    }

    @Test
    func sharedGovernanceAccentScaleStaysAlignedAcrossExecutionSupervisorAndReviewAxes() {
        #expect(ProjectGovernanceComposerAccentTone.forExecutionTier(.a0Observe) == .gray)
        #expect(ProjectGovernanceComposerAccentTone.forExecutionTier(.a4OpenClaw) == .orange)

        #expect(ProjectGovernanceComposerAccentTone.forSupervisorTier(.s0SilentAudit) == .gray)
        #expect(ProjectGovernanceComposerAccentTone.forSupervisorTier(.s3StrategicCoach) == .green)
        #expect(ProjectGovernanceComposerAccentTone.forSupervisorTier(.s4TightSupervision) == .orange)

        #expect(ProjectGovernanceComposerAccentTone.forReviewPolicy(.off) == .gray)
        #expect(ProjectGovernanceComposerAccentTone.forReviewPolicy(.periodic) == .teal)
        #expect(ProjectGovernanceComposerAccentTone.forReviewPolicy(.aggressive) == .orange)
    }
}
