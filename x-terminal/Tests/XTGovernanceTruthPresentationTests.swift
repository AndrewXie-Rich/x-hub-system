import Testing
@testable import XTerminal

struct XTGovernanceTruthPresentationTests {
    @Test
    func truthLineShowsConfiguredVsEffectivePairs() throws {
        let line = try #require(
            XTGovernanceTruthPresentation.truthLine(
                configuredExecutionTier: AXProjectExecutionTier.a1Plan.rawValue,
                effectiveExecutionTier: AXProjectExecutionTier.a2RepoAuto.rawValue,
                configuredSupervisorTier: AXProjectSupervisorInterventionTier.s1MilestoneReview.rawValue,
                effectiveSupervisorTier: AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue,
                reviewPolicyMode: AXProjectReviewPolicyMode.periodic.rawValue,
                progressHeartbeatSeconds: 900,
                reviewPulseSeconds: 1800,
                brainstormReviewSeconds: 0
            )
        )

        #expect(line == "治理真相：预设 A1/S1 · 当前生效 A2/S2 · 审查 Periodic · 节奏 心跳 15m / 脉冲 30m / 脑暴 off。")
    }

    @Test
    func truthLineFallsBackToEffectiveOnlyWhenConfiguredMatches() throws {
        let line = try #require(
            XTGovernanceTruthPresentation.truthLine(
                configuredExecutionTier: AXProjectExecutionTier.a2RepoAuto.rawValue,
                effectiveExecutionTier: AXProjectExecutionTier.a2RepoAuto.rawValue,
                configuredSupervisorTier: AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue,
                effectiveSupervisorTier: AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue,
                reviewPolicyMode: AXProjectReviewPolicyMode.hybrid.rawValue,
                progressHeartbeatSeconds: 1800,
                reviewPulseSeconds: 3600,
                brainstormReviewSeconds: 0
            )
        )

        #expect(line == "治理真相：当前生效 A2/S2 · 审查 Hybrid · 节奏 心跳 30m / 脉冲 1h / 脑暴 off。")
    }

    @Test
    func truthLineSurfacesFallbackCompatSourceWhenProjectStillUsesCompatibilityBridge() throws {
        let line = try #require(
            XTGovernanceTruthPresentation.truthLine(
                configuredExecutionTier: AXProjectExecutionTier.a2RepoAuto.rawValue,
                effectiveExecutionTier: AXProjectExecutionTier.a2RepoAuto.rawValue,
                configuredSupervisorTier: AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue,
                effectiveSupervisorTier: AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue,
                reviewPolicyMode: AXProjectReviewPolicyMode.hybrid.rawValue,
                progressHeartbeatSeconds: 900,
                reviewPulseSeconds: 1800,
                brainstormReviewSeconds: 0,
                compatSource: AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue
            )
        )

        #expect(line == "治理真相：当前生效 A2/S2 · 审查 Hybrid · 节奏 心跳 15m / 脉冲 30m / 脑暴 off · 来源 兼容旧执行面预设。")
    }
}
