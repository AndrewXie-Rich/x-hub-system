import Foundation
import Testing
@testable import XTerminal

struct AXProjectAutonomySwitchboardTests {
    @Test
    func legacyDefaultProjectStillPresentsAsConservative() throws {
        let root = try makeProjectRoot(named: "switchboard-legacy-conservative")
        let config = AXProjectConfig.default(forProjectRoot: root)
        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: readyPermissionReadiness()
        )

        let presentation = xtProjectAutonomySwitchboardPresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )

        #expect(presentation.configuredProfile == .conservative)
        #expect(presentation.configuredDeviceAuthorityPosture == .off)
        #expect(presentation.configuredSupervisorScope == .focusedProject)
        #expect(presentation.configuredGrantPosture == .manualReview)
    }

    @Test
    func fullAutonomyProfileAppliesCanonicalSettings() throws {
        let root = try makeProjectRoot(named: "switchboard-full-apply")
        let config = AXProjectConfig
            .default(forProjectRoot: root)
            .settingAutonomySwitchboardProfile(
                .fullAutonomy,
                projectRoot: root,
                now: Date(timeIntervalSince1970: 1_773_900_000)
            )

        #expect(config.executionTier == .a4OpenClaw)
        #expect(config.supervisorInterventionTier == .s3StrategicCoach)
        #expect(config.reviewPolicyMode == .hybrid)
        #expect(config.autonomyMode == .trustedOpenClawMode)
        #expect(config.governedAutoApproveLocalToolCalls)
        #expect(config.preferHubMemory)
        #expect(config.autonomyHubOverrideMode == .none)
    }

    @Test
    func fullAutonomyWithoutTrustedAutomationKeepsConfiguredFullButEffectiveDeviceAuthorityOff() throws {
        let root = try makeProjectRoot(named: "switchboard-full-without-binding")
        let config = AXProjectConfig
            .default(forProjectRoot: root)
            .settingAutonomySwitchboardProfile(
                .fullAutonomy,
                projectRoot: root,
                now: Date(timeIntervalSince1970: 1_773_900_000)
            )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: readyPermissionReadiness()
        )
        let presentation = xtProjectAutonomySwitchboardPresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )

        #expect(presentation.configuredProfile == .fullAutonomy)
        #expect(presentation.effectiveProfile == .custom)
        #expect(presentation.effectiveDeviceAuthorityPosture == .off)
        #expect(presentation.effectiveDeviationReasons.contains { $0.localizedCaseInsensitiveContains("trusted automation") })
    }

    @Test
    func customizedReviewCadencePromotesConfiguredProfileToCustom() throws {
        let root = try makeProjectRoot(named: "switchboard-custom-review")
        var config = AXProjectConfig
            .default(forProjectRoot: root)
            .settingAutonomySwitchboardProfile(
                .safe,
                projectRoot: root,
                now: Date(timeIntervalSince1970: 1_773_900_000)
            )
        config = config.settingProjectGovernance(reviewPulseSeconds: 300)

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: readyPermissionReadiness()
        )
        let presentation = xtProjectAutonomySwitchboardPresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )

        #expect(presentation.configuredProfile == .custom)
        #expect(!presentation.configuredDeviationReasons.isEmpty)
    }

    @Test
    func draftConfigKeepsSelectedBaselineSignalsWhileGovernanceDrifts() throws {
        let root = try makeProjectRoot(named: "switchboard-draft-baseline")
        let config = xtAutonomySwitchboardDraftConfig(
            projectRoot: root,
            baselineProfile: .fullAutonomy,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: AXProjectExecutionTier.a4OpenClaw.defaultProgressHeartbeatSeconds,
            reviewPulseSeconds: 300,
            brainstormReviewSeconds: AXProjectExecutionTier.a4OpenClaw.defaultBrainstormReviewSeconds,
            eventDrivenReviewEnabled: AXProjectExecutionTier.a4OpenClaw.defaultEventDrivenReviewEnabled
        )
        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: readyPermissionReadiness()
        )
        let presentation = xtProjectAutonomySwitchboardPresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )

        #expect(presentation.configuredProfile == .custom)
        #expect(presentation.configuredDeviceAuthorityPosture == .deviceGoverned)
        #expect(presentation.configuredGrantPosture == .envelopeAuto)
    }

    @Test
    func draftConfigFallsBackToExecutionTierBaselineWhenNeeded() throws {
        let root = try makeProjectRoot(named: "switchboard-draft-fallback")
        let config = xtAutonomySwitchboardDraftConfig(
            projectRoot: root,
            baselineProfile: .custom,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultProgressHeartbeatSeconds,
            reviewPulseSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultReviewPulseSeconds,
            brainstormReviewSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultBrainstormReviewSeconds,
            eventDrivenReviewEnabled: AXProjectExecutionTier.a3DeliverAuto.defaultEventDrivenReviewEnabled
        )
        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: readyPermissionReadiness()
        )
        let presentation = xtProjectAutonomySwitchboardPresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )

        #expect(presentation.configuredProfile == .safe)
        #expect(presentation.configuredSupervisorScope == .portfolio)
        #expect(presentation.configuredGrantPosture == .guidedAuto)
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func readyPermissionReadiness() -> AXTrustedAutomationPermissionOwnerReadiness {
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
            auditRef: "audit-switchboard-tests"
        )
    }
}
