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
        #expect(decision.interventionMode == .replanNextSafePoint)
        #expect(decision.safePointPolicy == .nextStepBoundary)
    }

    @Test
    func heartbeatCandidateRunsBrainstormOnlyAfterObservedNoProgressWindow() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-brainstorm-window")
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
        let nowMs: Int64 = 1_773_900_000_000
        let staleProgressAtMs = nowMs - 3_000_000
        let schedule = try SupervisorReviewScheduleStore.touchHeartbeat(
            for: ctx,
            config: config,
            observedProgressAtMs: staleProgressAtMs,
            nowMs: nowMs
        )

        let candidate = try #require(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: false,
                nowMs: nowMs
            )
        )
        #expect(schedule.lastObservedProgressAtMs == staleProgressAtMs)
        #expect(schedule.nextBrainstormReviewDueAtMs == staleProgressAtMs + 2_400_000)
        #expect(candidate.trigger == .noProgressWindow)
        #expect(candidate.runKind == .brainstorm)
        #expect(candidate.reviewLevel == .r2Strategic)
    }

    @Test
    func touchHeartbeatRebasesBrainstormWindowWhenObservedProgressAdvances() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-brainstorm-rebase")
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
        let nowMs: Int64 = 1_773_900_000_000
        let staleProgressAtMs = nowMs - 3_000_000
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(
            for: ctx,
            config: config,
            observedProgressAtMs: staleProgressAtMs,
            nowMs: nowMs
        )

        let refreshedNowMs = nowMs + 60_000
        let freshProgressAtMs = refreshedNowMs - 120_000
        let rebased = try SupervisorReviewScheduleStore.touchHeartbeat(
            for: ctx,
            config: config,
            observedProgressAtMs: freshProgressAtMs,
            nowMs: refreshedNowMs
        )

        #expect(rebased.lastObservedProgressAtMs == freshProgressAtMs)
        #expect(rebased.nextBrainstormReviewDueAtMs == freshProgressAtMs + 2_400_000)
        #expect(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: rebased,
                blockerDetected: false,
                nowMs: refreshedNowMs
            ) == nil
        )
    }

    @Test
    func resolveExecutionReadyDepthPromotesStructuredReplanEvenAtS2() {
        var config = AXProjectConfig.default(forProjectRoot: FileManager.default.temporaryDirectory)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        let strength = AXProjectAIStrengthProfile(
            strengthBand: .weak,
            confidence: 0.84,
            recommendedSupervisorFloor: .s2PeriodicReview,
            recommendedWorkOrderDepth: .executionReady,
            reasons: ["project AI still needs explicit execution-ready work orders"],
            assessedAtMs: 1_773_900_000_000,
            auditRef: "audit-strength-execution-ready"
        )
        let governance = xtResolveProjectGovernance(
            projectRoot: FileManager.default.temporaryDirectory,
            config: config,
            effectiveAutonomy: config.effectiveAutonomyPolicy(),
            projectAIStrengthProfile: strength
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

        #expect(governance.effectiveBundle.supervisorInterventionTier == .s2PeriodicReview)
        #expect(governance.supervisorAdaptation.effectiveWorkOrderDepth == .executionReady)
        #expect(decision.reviewLevel == .r2Strategic)
        #expect(decision.ackRequired)
        #expect(decision.interventionMode == .replanNextSafePoint)
        #expect(decision.safePointPolicy == .nextStepBoundary)
        #expect(decision.policyReason.contains("depth=execution_ready"))
    }

    @Test
    func heartbeatCandidateRaisesBlockerReviewToR3ForStepLockedRescueDepth() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-step-locked-depth")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 3600,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let strength = AXProjectAIStrengthProfile(
            strengthBand: .weak,
            confidence: 0.91,
            recommendedSupervisorFloor: .s2PeriodicReview,
            recommendedWorkOrderDepth: .stepLockedRescue,
            reasons: ["project AI needs step-locked rescue sequencing"],
            assessedAtMs: 1_773_900_000_000,
            auditRef: "audit-strength-step-locked"
        )
        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveAutonomy: config.effectiveAutonomyPolicy(),
            projectAIStrengthProfile: strength
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

        #expect(governance.effectiveBundle.supervisorInterventionTier == .s2PeriodicReview)
        #expect(governance.supervisorAdaptation.effectiveWorkOrderDepth == .stepLockedRescue)
        #expect(candidate.trigger == .blockerDetected)
        #expect(candidate.reviewLevel == .r3Rescue)
        #expect(candidate.priority == 350)
        #expect(candidate.policyReason.contains("depth=step_locked_rescue"))
    }

    @Test
    func heartbeatCandidateExtendsCooldownForStrongProjectAIUnderLightSupervision() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-strong-cooldown")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 600,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let strength = AXProjectAIStrengthProfile(
            strengthBand: .strong,
            confidence: 0.93,
            recommendedSupervisorFloor: .s1MilestoneReview,
            recommendedWorkOrderDepth: .brief,
            reasons: ["project AI can drive anchored execution with light supervision"],
            assessedAtMs: 1_773_900_000_000,
            auditRef: "audit-strength-strong-cooldown"
        )
        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveAutonomy: config.effectiveAutonomyPolicy(),
            projectAIStrengthProfile: strength
        )
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(for: ctx, config: config, nowMs: 1_773_900_000_000)
        var schedule = SupervisorReviewScheduleStore.load(for: ctx)
        schedule.lastTriggerReviewAtMs[SupervisorReviewTrigger.blockerDetected.rawValue] = 1_773_899_300_000

        #expect(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: true,
                nowMs: 1_773_900_000_000
            ) == nil
        )
    }

    @Test
    func heartbeatCandidateShortensCooldownForWeakProjectAIUnderPeriodicReview() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-weak-cooldown")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let strength = AXProjectAIStrengthProfile(
            strengthBand: .weak,
            confidence: 0.88,
            recommendedSupervisorFloor: .s2PeriodicReview,
            recommendedWorkOrderDepth: .milestoneContract,
            reasons: ["project AI still needs closer blocker follow-up"],
            assessedAtMs: 1_773_900_000_000,
            auditRef: "audit-strength-weak-cooldown"
        )
        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveAutonomy: config.effectiveAutonomyPolicy(),
            projectAIStrengthProfile: strength
        )
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(for: ctx, config: config, nowMs: 1_773_900_000_000)
        var schedule = SupervisorReviewScheduleStore.load(for: ctx)
        schedule.lastTriggerReviewAtMs[SupervisorReviewTrigger.blockerDetected.rawValue] = 1_773_899_600_000

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
}
