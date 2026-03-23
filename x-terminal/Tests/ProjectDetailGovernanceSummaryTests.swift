import Foundation
import Testing
@testable import XTerminal

struct ProjectDetailGovernanceSummaryTests {
    @Test
    func headerSummaryKeepsThreeAxisGovernanceVisible() {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .planDrift, .preDoneSummary],
            compatSource: AXProjectGovernanceCompatSource.explicitDualDial.rawValue
        )

        let summary = ProjectDetailGovernanceSummary(presentation: presentation)

        #expect(summary.headerSummary.contains("A3 Deliver Auto"))
        #expect(summary.headerSummary.contains("S3 Strategic Coach"))
        #expect(summary.headerSummary.contains("Review Hybrid"))
        #expect(summary.headerSummary.contains("Guidance"))
        #expect(summary.headerSummary.contains(presentation.homeStatusMessage))
    }

    @Test
    func summariesSurfaceEffectiveAndRecommendedTiersSeparately() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-detail-governance-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            projectAIStrengthProfile: AXProjectAIStrengthProfile(
                strengthBand: .weak,
                confidence: 0.91,
                recommendedSupervisorFloor: .s4TightSupervision,
                recommendedWorkOrderDepth: .stepLockedRescue,
                reasons: ["looping on failed attempts"]
            )
        )

        let summary = ProjectDetailGovernanceSummary(
            presentation: ProjectGovernancePresentation(resolved: resolved)
        )

        #expect(summary.executionTierSummary.contains("预设 A3"))
        #expect(summary.executionTierSummary.contains("当前生效 A3"))
        #expect(summary.supervisorTierSummary.contains("预设 S2"))
        #expect(summary.supervisorTierSummary.contains("当前生效 S4"))
        #expect(summary.supervisorTierSummary.contains("建议至少 S4"))
    }

    @Test
    func capabilityAndClampSummariesStayReadable() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-detail-governance-clamp-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.browser.control"],
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

        let summary = ProjectDetailGovernanceSummary(
            presentation: ProjectGovernancePresentation(resolved: resolved)
        )

        #expect(summary.capabilitySummary.contains("device.tools"))
        #expect(summary.clampSummary.contains("trusted automation readiness"))
        #expect(!summary.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        auditRef: "audit-project-detail-governance-summary-tests"
    )
}
