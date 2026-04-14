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
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
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
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
        )
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(for: ctx, config: config, nowMs: 1_773_900_000_000)
        var schedule = SupervisorReviewScheduleStore.load(for: ctx)
        schedule.lastHeartbeatAtMs = 1_773_897_900_000
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
    func heartbeatCandidateUsesEffectiveCadenceInsteadOfStoredNextDueTimestamp() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-effective-cadence")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 1800,
            reviewPulseSeconds: 2400,
            brainstormReviewSeconds: 4800,
            eventDrivenReviewEnabled: false,
            eventReviewTriggers: [.preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy(),
            projectAIStrengthProfile: AXProjectAIStrengthProfile(
                strengthBand: .weak,
                confidence: 0.41,
                recommendedSupervisorFloor: .s4TightSupervision,
                recommendedWorkOrderDepth: .stepLockedRescue,
                reasons: ["effective cadence should tighten before trusting stale stored next-due timestamps"],
                assessedAtMs: 1_773_900_000_000,
                auditRef: "audit-effective-cadence"
            )
        )

        let nowMs: Int64 = 1_773_900_000_000
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: governance.projectId,
            updatedAtMs: nowMs,
            lastHeartbeatAtMs: nowMs - 5 * 60_000,
            lastObservedProgressAtMs: nowMs - 5 * 60_000,
            lastPulseReviewAtMs: nowMs - 12 * 60_000,
            lastBrainstormReviewAtMs: nowMs - 60 * 60_000,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: nowMs + 30 * 60_000,
            nextPulseReviewDueAtMs: nowMs + 30 * 60_000,
            nextBrainstormReviewDueAtMs: nowMs + 30 * 60_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 42,
                computedAtMs: nowMs - 60_000
            ),
            openAnomalies: [
                anomaly(
                    projectId: governance.projectId,
                    type: .weakBlocker,
                    severity: .concern,
                    detectedAtMs: nowMs - 60_000,
                    escalation: .pulseReview
                )
            ],
            lastHeartbeatFingerprint: "still trying same route",
            lastHeartbeatRepeatCount: 1
        )

        let cadence = SupervisorReviewPolicyEngine.cadenceExplainability(
            governance: governance,
            schedule: schedule,
            nowMs: nowMs
        )

        #expect(cadence.reviewPulse.configuredSeconds == 2400)
        #expect(cadence.reviewPulse.recommendedSeconds == 1200)
        #expect(cadence.reviewPulse.effectiveSeconds == 600)
        #expect(cadence.reviewPulse.isDue)
        #expect(cadence.reviewPulse.nextDueAtMs == nowMs - 2 * 60_000)

        let candidate = try #require(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: false,
                nowMs: nowMs
            )
        )

        #expect(candidate.trigger == .periodicPulse)
        #expect(candidate.runKind == .pulse)
        #expect(candidate.policyReason.contains("heartbeat_anomaly=weak_blocker"))
    }

    @Test
    func heartbeatCandidateEscalatesStrategicWeakBlockerAsBlockerReview() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-weak-blocker")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1_200,
            brainstormReviewSeconds: 2_400,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
        )
        let nowMs: Int64 = 1_773_900_000_000
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: governance.projectId,
            updatedAtMs: nowMs,
            lastHeartbeatAtMs: nowMs - 10 * 60_000,
            lastObservedProgressAtMs: nowMs - 40 * 60_000,
            lastPulseReviewAtMs: nowMs - 20 * 60_000,
            lastBrainstormReviewAtMs: nowMs - 90 * 60_000,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: nowMs + 5 * 60_000,
            nextPulseReviewDueAtMs: nowMs + 10 * 60_000,
            nextBrainstormReviewDueAtMs: nowMs + 15 * 60_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 38,
                computedAtMs: nowMs - 60_000
            ),
            openAnomalies: [
                anomaly(
                    projectId: governance.projectId,
                    type: .weakBlocker,
                    severity: .high,
                    detectedAtMs: nowMs - 60_000,
                    escalation: .strategicReview
                )
            ],
            lastHeartbeatFingerprint: "blocked | still waiting | continue current task | stuck",
            lastHeartbeatRepeatCount: 2,
            latestProjectPhase: .build,
            latestExecutionStatus: .blocked,
            latestRiskTier: .high
        )

        let candidate = try #require(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: false,
                nowMs: nowMs
            )
        )

        #expect(candidate.trigger == .blockerDetected)
        #expect(candidate.runKind == .eventDriven)
        #expect(candidate.reviewLevel == .r2Strategic)
        #expect(candidate.policyReason.contains("heartbeat_anomaly=weak_blocker"))
    }

    @Test
    func heartbeatCandidatePromotesConcernMissingHeartbeatToPulseReview() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-missing-heartbeat-pulse")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 300,
            reviewPulseSeconds: 1_200,
            brainstormReviewSeconds: 3_600,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
        )
        let nowMs: Int64 = 1_773_900_000_000
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: governance.projectId,
            updatedAtMs: nowMs - 10 * 60_000,
            lastHeartbeatAtMs: nowMs - 10 * 60_000,
            lastObservedProgressAtMs: nowMs - 10 * 60_000,
            lastPulseReviewAtMs: nowMs - 8 * 60_000,
            lastBrainstormReviewAtMs: nowMs - 30 * 60_000,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: nowMs - 5 * 60_000,
            nextPulseReviewDueAtMs: nowMs + 12 * 60_000,
            nextBrainstormReviewDueAtMs: nowMs + 30 * 60_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 40,
                computedAtMs: nowMs - 10 * 60_000
            ),
            openAnomalies: [],
            lastHeartbeatFingerprint: "previous heartbeat",
            lastHeartbeatRepeatCount: 0,
            latestProjectPhase: .build,
            latestExecutionStatus: .active,
            latestRiskTier: .medium
        )

        let candidate = try #require(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: false,
                nowMs: nowMs
            )
        )

        #expect(candidate.trigger == .periodicPulse)
        #expect(candidate.runKind == .pulse)
        #expect(candidate.policyReason.contains("heartbeat_anomaly=missing_heartbeat"))
    }

    @Test
    func heartbeatCandidatePromotesHighMissingHeartbeatToBrainstormReview() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-missing-heartbeat-brainstorm")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 300,
            reviewPulseSeconds: 1_200,
            brainstormReviewSeconds: 3_600,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
        )
        let nowMs: Int64 = 1_773_900_000_000
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: governance.projectId,
            updatedAtMs: nowMs - 20 * 60_000,
            lastHeartbeatAtMs: nowMs - 20 * 60_000,
            lastObservedProgressAtMs: nowMs - 20 * 60_000,
            lastPulseReviewAtMs: nowMs - 2 * 60_000,
            lastBrainstormReviewAtMs: nowMs - 30 * 60_000,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: nowMs - 15 * 60_000,
            nextPulseReviewDueAtMs: nowMs + 18 * 60_000,
            nextBrainstormReviewDueAtMs: nowMs + 40 * 60_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 38,
                computedAtMs: nowMs - 20 * 60_000
            ),
            openAnomalies: [],
            lastHeartbeatFingerprint: "stale heartbeat",
            lastHeartbeatRepeatCount: 1,
            latestProjectPhase: .build,
            latestExecutionStatus: .active,
            latestRiskTier: .medium
        )

        let candidate = try #require(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: false,
                nowMs: nowMs
            )
        )

        #expect(candidate.trigger == .noProgressWindow)
        #expect(candidate.runKind == .brainstorm)
        #expect(candidate.reviewLevel == .r2Strategic)
        #expect(candidate.policyReason.contains("heartbeat_anomaly=missing_heartbeat"))
    }

    @Test
    func cadenceExplainabilityAdjustsForReleasePhaseHighRiskAndDoneCandidate() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-release-phase-cadence")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 1_800,
            reviewPulseSeconds: 2_400,
            brainstormReviewSeconds: 4_800,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
        )
        let nowMs: Int64 = 1_773_900_000_000
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: governance.projectId,
            updatedAtMs: nowMs,
            lastHeartbeatAtMs: nowMs - 4 * 60_000,
            lastObservedProgressAtMs: nowMs - 4 * 60_000,
            lastPulseReviewAtMs: nowMs - 20 * 60_000,
            lastBrainstormReviewAtMs: nowMs - 45 * 60_000,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: nowMs + 30 * 60_000,
            nextPulseReviewDueAtMs: nowMs + 30 * 60_000,
            nextBrainstormReviewDueAtMs: nowMs + 30 * 60_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .strong,
                overallScore: 84,
                computedAtMs: nowMs - 60_000
            ),
            openAnomalies: [],
            lastHeartbeatFingerprint: "release ready|verify checklist|ship|",
            lastHeartbeatRepeatCount: 0,
            latestProjectPhase: .release,
            latestExecutionStatus: .doneCandidate,
            latestRiskTier: .high
        )

        let cadence = SupervisorReviewPolicyEngine.cadenceExplainability(
            governance: governance,
            schedule: schedule,
            nowMs: nowMs
        )

        #expect(cadence.progressHeartbeat.recommendedSeconds == 180)
        #expect(cadence.progressHeartbeat.effectiveSeconds == 180)
        #expect(cadence.reviewPulse.recommendedSeconds == 600)
        #expect(cadence.reviewPulse.effectiveSeconds == 600)
        #expect(cadence.brainstormReview.recommendedSeconds == 1_200)
        #expect(cadence.brainstormReview.effectiveSeconds == 1_200)
        #expect(cadence.progressHeartbeat.effectiveReasonCodes.contains("adjusted_for_project_phase_release"))
        #expect(cadence.reviewPulse.effectiveReasonCodes.contains("adjusted_for_project_phase_release"))
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
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
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
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
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
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
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
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy(),
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
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy(),
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
        #expect(candidate.priority == 360)
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
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy(),
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
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy(),
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

    @Test
    func heartbeatCandidateEscalatesWeakDoneClaimToPreDoneSummary() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-weak-done-claim")
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
            eventReviewTriggers: [.blockerDetected, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-alpha",
            updatedAtMs: 1_773_900_000_000,
            lastHeartbeatAtMs: 1_773_900_000_000,
            lastObservedProgressAtMs: 1_773_899_700_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_773_900_600_000,
            nextPulseReviewDueAtMs: 1_773_901_200_000,
            nextBrainstormReviewDueAtMs: 1_773_902_400_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 38,
                computedAtMs: 1_773_900_000_000
            ),
            openAnomalies: [
                anomaly(
                    projectId: governance.projectId,
                    type: .weakDoneClaim,
                    severity: .high,
                    detectedAtMs: 1_773_900_000_000,
                    escalation: .rescueReview
                )
            ],
            lastHeartbeatFingerprint: "done|ready to ship||",
            lastHeartbeatRepeatCount: 0
        )

        let candidate = try #require(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: false,
                nowMs: 1_773_900_000_000
            )
        )

        #expect(candidate.trigger == .preDoneSummary)
        #expect(candidate.runKind == .eventDriven)
        #expect(candidate.reviewLevel == .r3Rescue)
        #expect(candidate.policyReason.contains("weak_done_claim"))
    }

    @Test
    func heartbeatCandidatePromotesHollowProgressToBrainstormBeforeTimerDue() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-hollow-progress")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 3600,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-alpha",
            updatedAtMs: 1_773_900_000_000,
            lastHeartbeatAtMs: 1_773_900_000_000,
            lastObservedProgressAtMs: 1_773_897_000_000,
            lastPulseReviewAtMs: 1_773_899_000_000,
            lastBrainstormReviewAtMs: 1_773_899_100_000,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_773_900_600_000,
            nextPulseReviewDueAtMs: 1_773_901_800_000,
            nextBrainstormReviewDueAtMs: 1_773_903_600_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .hollow,
                overallScore: 24,
                computedAtMs: 1_773_900_000_000
            ),
            openAnomalies: [
                anomaly(
                    projectId: governance.projectId,
                    type: .staleRepeat,
                    severity: .high,
                    detectedAtMs: 1_773_900_000_000,
                    escalation: .strategicReview
                ),
                anomaly(
                    projectId: governance.projectId,
                    type: .hollowProgress,
                    severity: .concern,
                    detectedAtMs: 1_773_900_000_000,
                    escalation: .pulseReview
                )
            ],
            lastHeartbeatFingerprint: "continue current task",
            lastHeartbeatRepeatCount: 3
        )

        let candidate = try #require(
            SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: false,
                nowMs: 1_773_900_000_000
            )
        )

        #expect(candidate.trigger == .noProgressWindow)
        #expect(candidate.runKind == .brainstorm)
        #expect(candidate.reviewLevel == .r2Strategic)
        #expect(candidate.policyReason.contains("heartbeat_anomaly=stale_repeat"))
    }

    @Test
    func recoveryDecisionPrefersGrantFollowUpWhenLaneNeedsGrant() throws {
        let reviewCandidate = SupervisorHeartbeatReviewCandidate(
            projectId: "project-alpha",
            trigger: .blockerDetected,
            runKind: .eventDriven,
            reviewLevel: .r2Strategic,
            priority: 310,
            policyReason: "event_trigger=blocker_detected"
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-alpha",
            updatedAtMs: 1_773_900_000_000,
            lastHeartbeatAtMs: 1_773_900_000_000,
            lastObservedProgressAtMs: 1_773_899_700_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_773_900_600_000,
            nextPulseReviewDueAtMs: 1_773_901_200_000,
            nextBrainstormReviewDueAtMs: 1_773_902_400_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 42,
                computedAtMs: 1_773_900_000_000
            ),
            openAnomalies: [
                anomaly(
                    projectId: "project-alpha",
                    type: .weakBlocker,
                    severity: .concern,
                    detectedAtMs: 1_773_900_000_000,
                    escalation: .strategicReview
                )
            ],
            lastHeartbeatFingerprint: "blocked waiting for grant",
            lastHeartbeatRepeatCount: 1,
            latestProjectPhase: .build,
            latestExecutionStatus: .blocked,
            latestRiskTier: .high
        )

        let decision = try #require(
            SupervisorReviewPolicyEngine.recoveryDecision(
                schedule: schedule,
                laneSnapshot: laneSnapshot(
                    lane(
                        laneID: "lane-grant",
                        status: .blocked,
                        blockedReason: .grantPending,
                        recommendation: "notify_user"
                    )
                ),
                reviewCandidate: reviewCandidate
            )
        )

        #expect(decision.action == .requestGrantFollowUp)
        #expect(decision.requiresUserAction)
        #expect(decision.reasonCode == "grant_follow_up_required")
        #expect(decision.blockedLaneReasons == [.grantPending])
        #expect(decision.queuedReviewTrigger == .blockerDetected)
        #expect(decision.queuedReviewLevel == .r2Strategic)
    }

    @Test
    func recoveryDecisionKeepsHoldForUserWhenLaneAwaitsInstruction() throws {
        let reviewCandidate = SupervisorHeartbeatReviewCandidate(
            projectId: "project-alpha",
            trigger: .blockerDetected,
            runKind: .eventDriven,
            reviewLevel: .r2Strategic,
            priority: 310,
            policyReason: "event_trigger=blocker_detected"
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-alpha",
            updatedAtMs: 1_773_900_000_000,
            lastHeartbeatAtMs: 1_773_900_000_000,
            lastObservedProgressAtMs: 1_773_899_700_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_773_900_600_000,
            nextPulseReviewDueAtMs: 1_773_901_200_000,
            nextBrainstormReviewDueAtMs: 1_773_902_400_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 42,
                computedAtMs: 1_773_900_000_000
            ),
            openAnomalies: [
                anomaly(
                    projectId: "project-alpha",
                    type: .weakBlocker,
                    severity: .concern,
                    detectedAtMs: 1_773_900_000_000,
                    escalation: .strategicReview
                )
            ],
            lastHeartbeatFingerprint: "blocked waiting for operator instruction",
            lastHeartbeatRepeatCount: 1,
            latestProjectPhase: .build,
            latestExecutionStatus: .blocked,
            latestRiskTier: .high
        )

        let decision = try #require(
            SupervisorReviewPolicyEngine.recoveryDecision(
                schedule: schedule,
                laneSnapshot: laneSnapshot(
                    lane(
                        laneID: "lane-guidance",
                        status: .blocked,
                        blockedReason: .awaitingInstruction,
                        recommendation: "await_operator"
                    )
                ),
                reviewCandidate: reviewCandidate
            )
        )

        #expect(decision.action == .holdForUser)
        #expect(decision.requiresUserAction)
        #expect(decision.reasonCode == "awaiting_user_or_operator_instruction")
        #expect(decision.blockedLaneReasons == [.awaitingInstruction])
        #expect(decision.queuedReviewTrigger == .blockerDetected)
        #expect(decision.queuedReviewLevel == .r2Strategic)
    }

    @Test
    func recoveryDecisionPrefersReplayFollowUpForQueueDrainSignals() throws {
        let reviewCandidate = SupervisorHeartbeatReviewCandidate(
            projectId: "project-alpha",
            trigger: .blockerDetected,
            runKind: .eventDriven,
            reviewLevel: .r2Strategic,
            priority: 320,
            policyReason: "heartbeat_anomaly=queue_stall"
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-alpha",
            updatedAtMs: 1_773_900_000_000,
            lastHeartbeatAtMs: 1_773_900_000_000,
            lastObservedProgressAtMs: 1_773_899_700_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_773_900_600_000,
            nextPulseReviewDueAtMs: 1_773_901_200_000,
            nextBrainstormReviewDueAtMs: 1_773_902_400_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 45,
                computedAtMs: 1_773_900_000_000
            ),
            openAnomalies: [
                anomaly(
                    projectId: "project-alpha",
                    type: .queueStall,
                    severity: .concern,
                    detectedAtMs: 1_773_900_000_000,
                    escalation: .strategicReview
                )
            ],
            lastHeartbeatFingerprint: "queue stalled waiting for drain replay",
            lastHeartbeatRepeatCount: 1,
            latestProjectPhase: .verify,
            latestExecutionStatus: .blocked,
            latestRiskTier: .medium
        )

        let decision = try #require(
            SupervisorReviewPolicyEngine.recoveryDecision(
                schedule: schedule,
                laneSnapshot: laneSnapshot(
                    lane(
                        laneID: "lane-drain",
                        status: .blocked,
                        blockedReason: .restartDrain,
                        recommendation: "wait_drain_recover"
                    )
                ),
                reviewCandidate: reviewCandidate
            )
        )

        #expect(decision.action == .replayFollowUp)
        #expect(decision.reasonCode == "restart_drain_requires_follow_up_replay")
        #expect(decision.requiresUserAction == false)
        #expect(decision.blockedLaneReasons == [.restartDrain])
        #expect(decision.sourceSignals.contains("anomaly:queue_stall"))
        #expect(decision.queuedReviewTrigger == .blockerDetected)
        #expect(decision.queuedReviewLevel == .r2Strategic)
    }

    @Test
    func recoveryDecisionPrefersRouteRepairBeforeResumeForRouteSignals() throws {
        let reviewCandidate = SupervisorHeartbeatReviewCandidate(
            projectId: "project-alpha",
            trigger: .blockerDetected,
            runKind: .eventDriven,
            reviewLevel: .r2Strategic,
            priority: 310,
            policyReason: "event_trigger=blocker_detected"
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-alpha",
            updatedAtMs: 1_773_900_000_000,
            lastHeartbeatAtMs: 1_773_900_000_000,
            lastObservedProgressAtMs: 1_773_899_640_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_773_900_600_000,
            nextPulseReviewDueAtMs: 1_773_901_200_000,
            nextBrainstormReviewDueAtMs: 1_773_902_400_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 40,
                computedAtMs: 1_773_900_000_000
            ),
            openAnomalies: [
                anomaly(
                    projectId: "project-alpha",
                    type: .routeFlaky,
                    severity: .high,
                    detectedAtMs: 1_773_900_000_000,
                    escalation: .strategicReview
                )
            ],
            lastHeartbeatFingerprint: "route unstable",
            lastHeartbeatRepeatCount: 1,
            latestProjectPhase: .build,
            latestExecutionStatus: .blocked,
            latestRiskTier: .high
        )

        let decision = try #require(
            SupervisorReviewPolicyEngine.recoveryDecision(
                schedule: schedule,
                laneSnapshot: laneSnapshot(
                    lane(
                        laneID: "lane-route",
                        status: .blocked,
                        blockedReason: .routeOriginUnavailable,
                        recommendation: "fallback_same_origin"
                    )
                ),
                reviewCandidate: reviewCandidate
            )
        )

        #expect(decision.action == .repairRoute)
        #expect(decision.reasonCode == "route_flaky_requires_repair")
        #expect(decision.blockedLaneReasons == [.routeOriginUnavailable])
        #expect(decision.sourceSignals.contains("anomaly:route_flaky"))
        #expect(decision.queuedReviewLevel == .r2Strategic)
    }

    @Test
    func runtimeOpenAnomaliesSynthesizesMissingHeartbeatForDoctorAndRecovery() throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-review-policy-missing-heartbeat")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 300,
            reviewPulseSeconds: 1_200,
            brainstormReviewSeconds: 2_400,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let governance = xtResolveProjectGovernance(
            projectRoot: fixture.root,
            config: config,
            effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
        )
        let nowMs: Int64 = 1_773_900_000_000
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: governance.projectId,
            updatedAtMs: nowMs - 20 * 60_000,
            lastHeartbeatAtMs: nowMs - 20 * 60_000,
            lastObservedProgressAtMs: nowMs - 20 * 60_000,
            lastPulseReviewAtMs: nowMs - 5 * 60_000,
            lastBrainstormReviewAtMs: nowMs - 20 * 60_000,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: nowMs - 15 * 60_000,
            nextPulseReviewDueAtMs: nowMs + 5 * 60_000,
            nextBrainstormReviewDueAtMs: nowMs + 10 * 60_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 40,
                computedAtMs: nowMs - 20 * 60_000
            ),
            openAnomalies: [],
            lastHeartbeatFingerprint: "previous heartbeat",
            lastHeartbeatRepeatCount: 0,
            latestProjectPhase: .build,
            latestExecutionStatus: .active,
            latestRiskTier: .medium
        )

        let cadence = SupervisorReviewPolicyEngine.cadenceExplainability(
            governance: governance,
            schedule: schedule,
            nowMs: nowMs
        )
        let runtimeAnomalies = SupervisorReviewPolicyEngine.runtimeOpenAnomalies(
            governance: governance,
            schedule: schedule,
            nowMs: nowMs,
            cadence: cadence
        )

        let missingHeartbeat = try #require(
            runtimeAnomalies.first { $0.anomalyType == .missingHeartbeat }
        )
        #expect(missingHeartbeat.severity == .high || missingHeartbeat.severity == .critical)

        let decision = try #require(
            SupervisorReviewPolicyEngine.recoveryDecision(
                schedule: schedule,
                laneSnapshot: nil,
                reviewCandidate: nil,
                openAnomalies: runtimeAnomalies
            )
        )

        #expect(decision.action == .resumeRun)
        #expect(decision.requiresUserAction == false)
        #expect(decision.sourceSignals.contains("anomaly:missing_heartbeat"))
    }

    @Test
    func recoveryDecisionQueuesStrategicReviewWhenHeartbeatNeedsRescueReview() throws {
        let reviewCandidate = SupervisorHeartbeatReviewCandidate(
            projectId: "project-alpha",
            trigger: .preDoneSummary,
            runKind: .eventDriven,
            reviewLevel: .r3Rescue,
            priority: 340,
            policyReason: "heartbeat_anomaly=weak_done_claim"
        )
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-alpha",
            updatedAtMs: 1_773_900_000_000,
            lastHeartbeatAtMs: 1_773_900_000_000,
            lastObservedProgressAtMs: 1_773_899_700_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_773_900_600_000,
            nextPulseReviewDueAtMs: 1_773_901_200_000,
            nextBrainstormReviewDueAtMs: 1_773_902_400_000,
            latestQualitySnapshot: qualitySnapshot(
                overallBand: .weak,
                overallScore: 38,
                computedAtMs: 1_773_900_000_000
            ),
            openAnomalies: [
                anomaly(
                    projectId: "project-alpha",
                    type: .weakDoneClaim,
                    severity: .high,
                    detectedAtMs: 1_773_900_000_000,
                    escalation: .rescueReview
                )
            ],
            lastHeartbeatFingerprint: "done candidate waiting for review",
            lastHeartbeatRepeatCount: 0,
            latestProjectPhase: .release,
            latestExecutionStatus: .doneCandidate,
            latestRiskTier: .high
        )

        let decision = try #require(
            SupervisorReviewPolicyEngine.recoveryDecision(
                schedule: schedule,
                laneSnapshot: nil,
                reviewCandidate: reviewCandidate
            )
        )

        #expect(decision.action == .queueStrategicReview)
        #expect(decision.urgency == .urgent)
        #expect(decision.queuedReviewTrigger == .preDoneSummary)
        #expect(decision.queuedReviewLevel == .r3Rescue)
        #expect(decision.sourceSignals.contains("review_candidate:pre_done_summary:r3_rescue:event_driven"))
    }

    private func qualitySnapshot(
        overallBand: HeartbeatQualityBand,
        overallScore: Int,
        computedAtMs: Int64
    ) -> HeartbeatQualitySnapshot {
        HeartbeatQualitySnapshot(
            overallScore: overallScore,
            overallBand: overallBand,
            freshnessScore: max(0, min(100, overallScore)),
            deltaSignificanceScore: max(0, min(100, overallScore)),
            evidenceStrengthScore: max(0, min(100, overallScore)),
            blockerClarityScore: max(0, min(100, overallScore)),
            nextActionSpecificityScore: max(0, min(100, overallScore)),
            executionVitalityScore: max(0, min(100, overallScore)),
            completionConfidenceScore: max(0, min(100, overallScore)),
            weakReasons: [],
            computedAtMs: computedAtMs
        )
    }

    private func anomaly(
        projectId: String,
        type: HeartbeatAnomalyType,
        severity: HeartbeatAnomalySeverity,
        detectedAtMs: Int64,
        escalation: HeartbeatAnomalyEscalation
    ) -> HeartbeatAnomalyNote {
        HeartbeatAnomalyNote(
            anomalyId: "anomaly-\(type.rawValue)-\(detectedAtMs)",
            projectId: projectId,
            anomalyType: type,
            severity: severity,
            confidence: 0.9,
            reason: type.displayName,
            evidenceRefs: [],
            detectedAtMs: detectedAtMs,
            recommendedEscalation: escalation
        )
    }

    private func laneSnapshot(
        _ lanes: SupervisorLaneHealthLaneState...
    ) -> SupervisorLaneHealthSnapshot {
        SupervisorLaneHealthSnapshot(
            generatedAtMs: 1_773_900_000_000,
            summary: LaneHealthSummary(
                total: lanes.count,
                running: lanes.filter { $0.status == .running }.count,
                blocked: lanes.filter { $0.status == .blocked }.count,
                stalled: lanes.filter { $0.status == .stalled }.count,
                failed: lanes.filter { $0.status == .failed }.count,
                waiting: lanes.filter { $0.status == .waiting }.count,
                recovering: lanes.filter { $0.status == .recovering }.count,
                completed: lanes.filter { $0.status == .completed }.count
            ),
            lanes: lanes
        )
    }

    private func lane(
        laneID: String,
        status: LaneHealthStatus,
        blockedReason: LaneBlockedReason? = nil,
        recommendation: String
    ) -> SupervisorLaneHealthLaneState {
        SupervisorLaneHealthLaneState(
            state: LaneRuntimeState(
                laneID: laneID,
                taskId: UUID(),
                projectId: nil,
                agentProfile: "coder",
                status: status,
                blockedReason: blockedReason,
                nextActionRecommendation: recommendation
            )
        )
    }
}
