import Foundation
import Testing
@testable import XTerminal

struct SupervisorReviewPolicyEngineTests {
    @Test
    func heartbeatCandidatePrefersBlockerEventBeforePulseReview() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-blocker")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .planDrift, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveAutonomy: config.effectiveAutonomyPolicy()
        )
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(for: ctx, config: config, nowMs: 1_773_900_000_000)
        let schedule = SupervisorReviewScheduleStore.load(for: ctx)

        let candidate = try #require(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: true,
                nowMs: 1_773_900_000_000
            )
        )
        #expect(candidate.trigger == .blockerDetected)
        #expect(candidate.runKind == .eventDriven)
        #expect(candidate.reviewLevel == .r2Strategic)
    }

    @Test
    func heartbeatCandidateSuppressesEventReviewWhenEventDrivenIsDisabled() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-no-event")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .periodic,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false,
            eventReviewTriggers: [.blockerDetected, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveAutonomy: config.effectiveAutonomyPolicy()
        )
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(for: ctx, config: config, nowMs: 1_773_900_000_000)
        var schedule = SupervisorReviewScheduleStore.load(for: ctx)
        schedule.nextPulseReviewDueAtMs = 1_773_899_999_000

        let candidate = try #require(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: true,
                nowMs: 1_773_900_000_000
            )
        )
        #expect(candidate.trigger == .periodicPulse)
        #expect(candidate.runKind == .pulse)
    }

    @Test
    func resolveEscalatesAckForStrategicReviewUnderS3() {
        var config = AXProjectConfig.default(forProjectRoot: FileManager.default.temporaryDirectory)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )
        let governance = xtResolveProjectGovernance(
            projectRoot: FileManager.default.temporaryDirectory,
            config: config,
            effectiveAutonomy: config.effectiveAutonomyPolicy()
        )

        let decision = SupervisorReviewPolicyEngine.resolve(
            governance: governance,
            trigger: .blockerDetected,
            requestedReviewLevel: .r1Pulse,
            verdict: .watch,
            requestedDeliveryMode: .priorityInsert,
            requestedAckRequired: false,
            runKind: .eventDriven
        )

        #expect(decision.shouldReview)
        #expect(decision.reviewLevel == .r2Strategic)
        #expect(decision.ackRequired)
        #expect(decision.interventionMode == .suggestNextSafePoint)
        #expect(decision.safePointPolicy == .nextToolBoundary)
    }
}
