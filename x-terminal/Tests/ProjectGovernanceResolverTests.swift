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
    func invalidA4S1ComboFailsClosedInResolver() {
        let root = URL(fileURLWithPath: "/tmp/project-governance-invalid-\(UUID().uuidString)", isDirectory: true)
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

        #expect(resolved.validation.shouldFailClosed)
        #expect(resolved.effectiveBundle.executionTier == .a0Observe)
        #expect(resolved.effectiveBundle.supervisorInterventionTier == .s0SilentAudit)
        #expect(resolved.capabilityBundle == .observeOnly)
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
        #expect(snapshot["should_fail_closed"] == .bool(false))
    }

    @Test
    func autonomyModeSyncsGovernanceBundleWhileStillInCompatMode() {
        let root = URL(fileURLWithPath: "/tmp/project-governance-autonomy-sync-\(UUID().uuidString)", isDirectory: true)
        let config = AXProjectConfig.default(forProjectRoot: root).settingAutonomyPolicy(
            mode: .trustedOpenClawMode,
            updatedAt: Date(timeIntervalSince1970: 1_773_900_000)
        )

        #expect(config.governanceCompatSource == .legacyAutonomyMode)
        #expect(config.executionTier == .a4OpenClaw)
        #expect(config.supervisorInterventionTier == .s3StrategicCoach)
        #expect(config.reviewPolicyMode == .hybrid)
    }

    @Test
    func explicitGovernanceRemainsAuthoritativeWhenAutonomyModeChanges() {
        let root = URL(fileURLWithPath: "/tmp/project-governance-autonomy-explicit-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )
        config = config.settingAutonomyPolicy(
            mode: .guided,
            updatedAt: Date(timeIntervalSince1970: 1_773_900_100)
        )

        #expect(config.governanceCompatSource == .explicitDualDial)
        #expect(config.executionTier == .a4OpenClaw)
        #expect(config.supervisorInterventionTier == .s2PeriodicReview)
        #expect(config.autonomyMode == .guided)
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
