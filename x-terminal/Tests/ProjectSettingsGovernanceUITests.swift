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
        #expect(presentation.statusSummary.contains("configured combo 无效"))
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
        config = config.settingAutonomyPolicy(
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
        #expect(presentation.clampSummary.contains("trusted automation readiness"))
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
        #expect(presentation.clampSummary.contains("未连接 runtime clamp"))
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
