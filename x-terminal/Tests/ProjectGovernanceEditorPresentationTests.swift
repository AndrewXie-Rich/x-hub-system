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
            ProjectGovernanceStatusBadge(label: "当前", tone: .current)
        ])
        #expect(current.accessibilityStateLabel == "当前")

        let effectiveOnly = ProjectExecutionTierCardPresentation(
            tier: .a4OpenClaw,
            configuredTier: .a3DeliverAuto,
            effectiveTier: .a4OpenClaw
        )
        #expect(effectiveOnly.statusBadges == [
            ProjectGovernanceStatusBadge(label: "生效中", tone: .effective)
        ])
        #expect(effectiveOnly.accessibilityStateLabel == "生效中")
    }

    @Test
    func supervisorTierCardPresentationIncludesRecommendationAndRiskMarkers() {
        let recommendedCurrent = ProjectSupervisorTierCardPresentation(
            tier: .s3StrategicCoach,
            currentExecutionTier: .a3DeliverAuto,
            configuredTier: .s3StrategicCoach,
            effectiveTier: .s3StrategicCoach
        )
        #expect(recommendedCurrent.statusBadges.contains(
            ProjectGovernanceStatusBadge(label: "当前", tone: .current)
        ))
        #expect(recommendedCurrent.statusBadges.contains(
            ProjectGovernanceStatusBadge(label: "推荐", tone: .recommended)
        ))

        let belowFloor = ProjectSupervisorTierCardPresentation(
            tier: .s0SilentAudit,
            currentExecutionTier: .a4OpenClaw,
            configuredTier: .s2PeriodicReview,
            effectiveTier: .s2PeriodicReview
        )
        #expect(belowFloor.statusBadges.contains(
            ProjectGovernanceStatusBadge(label: "高风险", tone: .belowSafeFloor)
        ))
        #expect(belowFloor.accessibilityStateLabel == "可用")
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
        #expect(presentation.baselineDecisionSummary.contains("脑暴节奏"))
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

    @Test
    func sceneParameterMatrixSeparatesProjectAndSupervisorContinuity() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("governance-parameter-matrix-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingGovernanceTemplate(.feature, projectRoot: root)
        config = config.settingProjectContextAssembly(
            projectRecentDialogueProfile: .deep20Pairs,
            projectContextDepthProfile: .full
        )

        let resolved = xtResolveProjectGovernance(projectRoot: root, config: config)
        let presentation = ProjectHeartbeatReviewEditorPresentation(
            configuredExecutionTier: .a2RepoAuto,
            configuredReviewPolicyMode: .hybrid,
            reviewPulseSeconds: config.reviewPulseSeconds,
            brainstormReviewSeconds: config.brainstormReviewSeconds,
            resolvedGovernance: resolved,
            projectConfig: config,
            configuredSupervisorRecentRawContextProfile: .extended40Pairs,
            configuredSupervisorReviewMemoryDepth: .auto,
            supervisorPrivacyMode: .tightenedContext
        )

        let continuityRows = presentation.sceneParameterMatrix.continuityRows
        #expect(continuityRows.count == 4)
        #expect(continuityRows[0].title == "Project AI 最近原文底线")
        #expect(continuityRows[0].configuredValue == "Deep · 20 pairs")
        #expect(continuityRows[0].recommendedValue == "Standard · 12 pairs")
        #expect(continuityRows[0].sourceSummary == "来源：用户手改")
        #expect(continuityRows[2].title == "Supervisor 最近原文底线")
        #expect(continuityRows[2].configuredValue == "Extended · 40 pairs")
        #expect(continuityRows[2].effectiveValue == "Standard · 12 pairs")
        #expect(continuityRows[2].sourceSummary == "来源：Supervisor 设置 + 隐私收束")
        #expect(continuityRows[3].title == "Supervisor 审查深度")
        #expect(continuityRows[3].sourceSummary == "来源：S-Tier / trigger 自动求值")
    }

    @Test
    func sceneParameterMatrixShowsRuntimeAdjustedExecutionEnvelope() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("governance-parameter-runtime-\(UUID().uuidString)", isDirectory: true)
        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingGovernanceTemplate(.highGovernance, projectRoot: root)
        let resolved = xtResolveProjectGovernance(projectRoot: root, config: config)
        let presentation = ProjectHeartbeatReviewEditorPresentation(
            configuredExecutionTier: .a4OpenClaw,
            configuredReviewPolicyMode: .hybrid,
            reviewPulseSeconds: config.reviewPulseSeconds,
            brainstormReviewSeconds: config.brainstormReviewSeconds,
            resolvedGovernance: resolved,
            projectConfig: config
        )

        let executionRows = presentation.sceneParameterMatrix.executionRows
        #expect(executionRows[0].title == "能力包")
        #expect(executionRows[0].configuredValue.contains("Agent Surface"))
        #expect(executionRows[0].effectiveValue == "Plan · Repo · Process + Restart · Delivery · Agent Surface · 17 capabilities")
        #expect(executionRows[0].sourceSummary == "来源：runtime capability 收束")
        #expect(executionRows[1].title == "执行预算")
        #expect(executionRows[1].configuredValue.contains("120m run"))
        #expect(executionRows[1].sourceSummary == "来源：高治理 A-Tier 默认")

        let closeoutRows = presentation.sceneParameterMatrix.closeoutRows
        #expect(closeoutRows[0].effectiveValue == "Required")
        #expect(closeoutRows[1].effectiveValue == "Required")
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
