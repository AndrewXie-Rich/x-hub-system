import Foundation
import Testing
@testable import XTerminal

@MainActor
struct ProjectGovernanceResolverTests {

    @Test
    func legacyAutonomyModeDecodeBackfillsGovernanceFields() throws {
        let data = Data(
            """
            {
              "schemaVersion": 9,
              "autonomyMode": "guided",
              "autonomyAllowBrowserRuntime": true,
              "autonomyAllowDeviceTools": false,
              "autonomyAllowConnectorActions": false,
              "autonomyAllowExtensions": false
            }
            """.utf8
        )

        let config = try JSONDecoder().decode(AXProjectConfig.self, from: data)

        #expect(config.governanceCompatSource == .legacyAutonomyMode)
        #expect(config.executionTier == .a1Plan)
        #expect(config.supervisorInterventionTier == .s1MilestoneReview)
        #expect(config.reviewPolicyMode == .periodic)
    }

    @Test
    func highRiskA4S1ComboStaysSelectedAndShowsWarning() {
        let root = URL(fileURLWithPath: "/tmp/project-governance-high-risk-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview
        )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: makeGovernancePermissionReadiness()
        )

        #expect(!resolved.validation.shouldFailClosed)
        #expect(resolved.validation.invalidReasons.isEmpty)
        #expect(resolved.validation.warningReasons.count == 1)
        #expect(resolved.effectiveBundle.executionTier == .a4OpenClaw)
        #expect(resolved.effectiveBundle.supervisorInterventionTier == .s1MilestoneReview)
        #expect(resolved.capabilityBundle == AXProjectExecutionTier.a4OpenClaw.baseCapabilityBundle)
    }

    @Test
    func warningComboKeepsConfiguredBundleAndExportsDebugSnapshot() {
        let root = URL(fileURLWithPath: "/tmp/project-governance-warning-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: makeGovernancePermissionReadiness()
        )
        let snapshot = resolved.debugSnapshot()

        #expect(!resolved.validation.shouldFailClosed)
        #expect(resolved.validation.warningReasons.count == 1)
        #expect(snapshot["execution_tier"] == .string("a3_deliver_auto"))
        #expect(snapshot["supervisor_intervention_tier"] == .string("s2_periodic_review"))
        #expect(snapshot["runtime_surface_effective_mode"] == .string("manual"))
        #expect(snapshot["runtime_surface_kill_switch_engaged"] == .bool(false))
        #expect(snapshot["effective_autonomy_mode"] == snapshot["runtime_surface_effective_mode"])
        #expect(snapshot["should_fail_closed"] == .bool(false))
    }

    @Test
    func legacyAutonomyModeSyncsGovernanceBundleWhileStillInCompatMode() {
        let root = URL(fileURLWithPath: "/tmp/project-governance-legacy-runtime-surface-sync-\(UUID().uuidString)", isDirectory: true)
        let config = AXProjectConfig.default(forProjectRoot: root).settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            updatedAt: Date(timeIntervalSince1970: 1_773_900_000)
        )

        #expect(config.governanceCompatSource == .legacyAutonomyMode)
        #expect(config.executionTier == .a4OpenClaw)
        #expect(config.supervisorInterventionTier == .s3StrategicCoach)
        #expect(config.reviewPolicyMode == .hybrid)
    }

    @Test
    func explicitGovernanceRemainsAuthoritativeWhenLegacyAutonomyModeChanges() {
        let root = URL(fileURLWithPath: "/tmp/project-governance-legacy-runtime-surface-explicit-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )
        config = config.settingRuntimeSurfacePolicy(
            mode: .guided,
            updatedAt: Date(timeIntervalSince1970: 1_773_900_100)
        )

        #expect(config.governanceCompatSource == .explicitDualDial)
        #expect(config.executionTier == .a4OpenClaw)
        #expect(config.supervisorInterventionTier == .s2PeriodicReview)
        #expect(config.autonomyMode == .guided)
    }

    @Test
    func legacyAutonomyShadowIsOnlyConsumedForCompatSources() {
        let root = URL(fileURLWithPath: "/tmp/project-governance-compat-shadow-\(UUID().uuidString)", isDirectory: true)
        let defaultConfig = AXProjectConfig.default(forProjectRoot: root)

        #expect(defaultConfig.governanceCompatSource == .defaultConservative)
        #expect(defaultConfig.consumesLegacyAutonomyLevelResolverInput == false)
        #expect(defaultConfig.governanceResolverLegacyAutonomyLevel(.fullAuto) == nil)

        let compatConfig = defaultConfig.settingRuntimeSurfacePolicy(
            mode: .guided,
            updatedAt: Date(timeIntervalSince1970: 1_773_900_200)
        )

        #expect(compatConfig.governanceCompatSource == .legacyAutonomyMode)
        #expect(compatConfig.consumesLegacyAutonomyLevelResolverInput)
        #expect(compatConfig.governanceResolverLegacyAutonomyLevel(.fullAuto) == .fullAuto)

        let explicitConfig = compatConfig.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )

        #expect(explicitConfig.governanceCompatSource == .explicitDualDial)
        #expect(explicitConfig.consumesLegacyAutonomyLevelResolverInput == false)
        #expect(explicitConfig.governanceResolverLegacyAutonomyLevel(.fullAuto) == nil)
    }

    @Test
    func applyingExecutionTierPreservesReviewAxesAndExistingSupervisorSelection() {
        let original = AXProjectGovernanceBundle(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s0SilentAudit,
            reviewPolicyMode: .aggressive,
            schedule: AXProjectGovernanceSchedule(
                progressHeartbeatSeconds: 3600,
                reviewPulseSeconds: 5400,
                brainstormReviewSeconds: 7200,
                eventDrivenReviewEnabled: false,
                eventReviewTriggers: [.manualRequest, .preDoneSummary]
            )
        )

        let updated = original.applyingExecutionTierPreservingReviewConfiguration(.a4OpenClaw)

        #expect(updated.executionTier == .a4OpenClaw)
        #expect(updated.supervisorInterventionTier == .s0SilentAudit)
        #expect(updated.reviewPolicyMode == .aggressive)
        #expect(updated.schedule == original.schedule)
    }

    @Test
    func weakProjectAIRaisesEffectiveSupervisorTierAndWorkOrderDepth() {
        let root = URL(fileURLWithPath: "/tmp/project-governance-weak-ai-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let strength = AXProjectAIStrengthProfile(
            strengthBand: .weak,
            confidence: 0.92,
            recommendedSupervisorFloor: .s4TightSupervision,
            recommendedWorkOrderDepth: .stepLockedRescue,
            reasons: [
                "failure streak remains elevated",
                "recent regressions required repeated correction"
            ]
        )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            projectAIStrengthProfile: strength,
            permissionReadiness: makeGovernancePermissionReadiness()
        )
        let snapshot = resolved.debugSnapshot()

        #expect(!resolved.validation.shouldFailClosed)
        #expect(resolved.configuredBundle.supervisorInterventionTier == .s2PeriodicReview)
        #expect(resolved.supervisorAdaptation.recommendedSupervisorTier == .s4TightSupervision)
        #expect(resolved.effectiveBundle.supervisorInterventionTier == .s4TightSupervision)
        #expect(resolved.supervisorAdaptation.recommendedWorkOrderDepth == .stepLockedRescue)
        #expect(resolved.supervisorAdaptation.effectiveWorkOrderDepth == .stepLockedRescue)
        #expect(resolved.effectiveRuntimeSurface.effectiveMode == .manual)
        #expect(snapshot["recommended_supervisor_intervention_tier"] == .string("s4_tight_supervision"))
        #expect(snapshot["effective_supervisor_work_order_depth"] == .string("step_locked_rescue"))
    }

    @Test
    func manualOnlyAdaptationKeepsConfiguredTierWhileExposingRecommendations() {
        let root = URL(fileURLWithPath: "/tmp/project-governance-manual-adapt-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let strength = AXProjectAIStrengthProfile(
            strengthBand: .unknown,
            confidence: 0.35,
            recommendedSupervisorFloor: .s4TightSupervision,
            recommendedWorkOrderDepth: .executionReady,
            reasons: ["new model route has not yet proven stable on this project"]
        )
        let policy = AXProjectSupervisorAdaptationPolicy(
            adaptationMode: .manualOnly,
            allowAutoRelax: false,
            stabilityWindowMinutes: 180,
            failureStreakRaiseThreshold: 3,
            insufficientEvidenceRaiseThreshold: 2,
            incidentRaiseEnabled: true
        )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            projectAIStrengthProfile: strength,
            adaptationPolicy: policy,
            permissionReadiness: makeGovernancePermissionReadiness()
        )

        #expect(resolved.supervisorAdaptation.recommendedSupervisorTier == .s4TightSupervision)
        #expect(resolved.effectiveBundle.supervisorInterventionTier == .s2PeriodicReview)
        #expect(resolved.supervisorAdaptation.recommendedWorkOrderDepth == .stepLockedRescue)
        #expect(resolved.supervisorAdaptation.effectiveWorkOrderDepth == .milestoneContract)
    }
}

private func makeGovernancePermissionReadiness() -> AXTrustedAutomationPermissionOwnerReadiness {
    AXTrustedAutomationPermissionOwnerReadiness(
        schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
        ownerID: "test-owner",
        ownerType: "test",
        bundleID: "com.xterminal.tests",
        installState: "installed",
        mode: "test",
        accessibility: .granted,
        automation: .granted,
        screenRecording: .granted,
        fullDiskAccess: .granted,
        inputMonitoring: .granted,
        canPromptUser: false,
        managedByMDM: false,
        overallState: "ready",
        openSettingsActions: [],
        auditRef: "audit-governance-tests"
    )
}
