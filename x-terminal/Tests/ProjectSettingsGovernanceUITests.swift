import Foundation
import Testing
@testable import XTerminal

@MainActor
struct ProjectSettingsGovernanceUITests {

    @Test
    func resolvedInvalidComboShowsFailClosedGovernanceState() {
        let root = makeProjectRoot(named: "governance-ui-invalid")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview
        )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: makePermissionReadiness(
                accessibility: .granted,
                automation: .granted,
                screenRecording: .granted
            )
        )
        let presentation = ProjectGovernancePresentation(resolved: resolved)

        #expect(!presentation.invalidMessages.isEmpty)
        #expect(presentation.effectiveExecutionTier == .a0Observe)
        #expect(presentation.effectiveSupervisorInterventionTier == .s0SilentAudit)
        #expect(presentation.statusSummary.contains("治理组合无效"))
    }

    @Test
    func a4PresentationExplainsTrustedAutomationReadinessClampWithoutDowngradingTier() {
        let root = makeProjectRoot(named: "governance-ui-readiness")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.clipboard.read", "device.browser.control"],
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
        )
        config = config.settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            ttlSeconds: 600,
            updatedAt: Date()
        )
        config = config.settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: makePermissionReadiness(
                accessibility: .granted,
                automation: .missing,
                screenRecording: .missing
            )
        )
        let presentation = ProjectGovernancePresentation(resolved: resolved)

        #expect(presentation.effectiveExecutionTier == nil)
        #expect(presentation.capabilityLabels.contains("device.tools"))
        #expect(presentation.clampSummary.contains("受治理自动化就绪检查"))
    }

    @Test
    func draftPresentationWarnsAboutUnsafeTierCombinationBeforeCreate() {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )

        #expect(!presentation.invalidMessages.isEmpty)
        #expect(presentation.statusSummary.contains("当前组合无效"))
        #expect(presentation.clampSummary.contains("未连接运行时收束"))
    }

    @Test
    func executionTierMetadataSupportsDedicatedATierEditor() {
        #expect(AXProjectExecutionTier.allCases.map(\.displayName) == [
            "A0 Observe",
            "A1 Plan",
            "A2 Repo Auto",
            "A3 Deliver Auto",
            "A4 Agent"
        ])
        #expect(AXProjectExecutionTier.a0Observe.allowedHighlights.contains("读项目记忆"))
        #expect(AXProjectExecutionTier.a1Plan.oneLineSummary.contains("工单 / 计划"))
        #expect(AXProjectExecutionTier.a2RepoAuto.defaultBudgetSummary.contains("45m run"))
        #expect(
            AXProjectExecutionTier.a4OpenClaw.blockedHighlights.contains(
                where: { $0.contains("TTL") && $0.contains("紧急回收") && $0.contains("审计轨迹") }
            )
        )
    }

    @Test
    func supervisorTierMetadataSupportsDedicatedSTierEditor() {
        #expect(AXProjectSupervisorInterventionTier.allCases.map(\.displayName) == [
            "S0 Silent Audit",
            "S1 Milestone Review",
            "S2 Periodic Review",
            "S3 Strategic Coach",
            "S4 Tight Supervision"
        ])
        #expect(AXProjectSupervisorInterventionTier.s0SilentAudit.behaviorHighlights.contains("默认 observe only"))
        #expect(AXProjectSupervisorInterventionTier.s2PeriodicReview.typicalUseCases.contains("A2 Repo Auto"))
        #expect(AXProjectSupervisorInterventionTier.s3StrategicCoach.oneLineSummary.contains("replan"))
        #expect(AXProjectSupervisorInterventionTier.s4TightSupervision.defaultAckSummary == "Required")
    }

    @Test
    func reviewPolicyMetadataSupportsDedicatedHeartbeatReviewEditor() {
        #expect(AXProjectReviewPolicyMode.off.oneLineSummary.contains("手动请求"))
        #expect(!AXProjectReviewPolicyMode.off.supportsPulseCadence)
        #expect(!AXProjectReviewPolicyMode.periodic.supportsBrainstormCadence)
        #expect(AXProjectReviewPolicyMode.hybrid.supportsBrainstormCadence)
        #expect(AXProjectReviewPolicyMode.aggressive.supportsEventDrivenReview)
    }

    @Test
    func contextAssemblyProfilesExposeIndependentContinuityAndDepthMetadata() {
        #expect(XTSupervisorRecentRawContextProfile.allCases.map(\.displayName) == [
            "Floor",
            "Standard",
            "Deep",
            "Extended",
            "Auto Max"
        ])
        #expect(AXProjectRecentDialogueProfile.deep20Pairs.shortLabel == "20 pairs")
        #expect(AXProjectContextDepthProfile.balanced.summary.contains("默认档"))
        #expect(AXProjectContextDepthProfile.full.summary.contains("retrieval"))
    }

    @Test
    func mandatoryAndOptionalTriggerSetsStaySeparatedForHeartbeatReviewPage() {
        #expect(AXProjectExecutionTier.a0Observe.defaultEventReviewTriggers == [.manualRequest])
        #expect(AXProjectExecutionTier.a0Observe.mandatoryReviewTriggers == [.preDoneSummary])
        #expect(AXProjectExecutionTier.a4OpenClaw.mandatoryReviewTriggers == [
            .blockerDetected,
            .preHighRiskAction,
            .preDoneSummary
        ])
        #expect(AXProjectReviewTrigger.governanceOptionalSelectableCases == [
            .failureStreak,
            .blockerDetected,
            .planDrift,
            .preHighRiskAction,
            .preDoneSummary
        ])
    }

    @Test
    func draftPresentationSurfacesCustomEventTriggerLabels() {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.planDrift, .preDoneSummary]
        )

        #expect(presentation.eventReviewTriggerLabels == ["plan drift", "pre-done"])
    }

    private func makeProjectRoot(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}

private func makePermissionReadiness(
    accessibility: AXTrustedAutomationPermissionStatus,
    automation: AXTrustedAutomationPermissionStatus,
    screenRecording: AXTrustedAutomationPermissionStatus
) -> AXTrustedAutomationPermissionOwnerReadiness {
    AXTrustedAutomationPermissionOwnerReadiness(
        schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
        ownerID: "test-owner",
        ownerType: "test",
        bundleID: "com.xterminal.tests",
        installState: "installed",
        mode: "test",
        accessibility: accessibility,
        automation: automation,
        screenRecording: screenRecording,
        fullDiskAccess: .granted,
        inputMonitoring: .granted,
        canPromptUser: false,
        managedByMDM: false,
        overallState: "ready",
        openSettingsActions: [],
        auditRef: "audit-governance-ui-tests"
    )
}
