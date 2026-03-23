import Foundation
import Testing
@testable import XTerminal

struct ProjectGovernancePresentationSummaryTests {

    @Test
    func homeStatusMessagePrefersInvalidAndWarningBeforeGenericStatus() {
        let invalid = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )
        #expect(invalid.homeStatusMessage.contains("至少需要"))

        let warning = ProjectGovernancePresentation(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )
        #expect(warning.homeStatusMessage.contains("推荐"))

        let stable = ProjectGovernancePresentation(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: true
        )
        #expect(stable.homeStatusMessage == stable.statusSummary)
    }

    @Test
    func governanceSourceHintSurfacesCompatAndConservativeProjects() {
        let conservative = ProjectGovernancePresentation(
            executionTier: .a0Observe,
            supervisorInterventionTier: .s0SilentAudit,
            reviewPolicyMode: .milestoneOnly,
            progressHeartbeatSeconds: 1800,
            reviewPulseSeconds: 0,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false,
            compatSource: AXProjectGovernanceCompatSource.defaultConservative.rawValue
        )
        #expect(conservative.compatSourceLabel == "默认保守基线")
        #expect(conservative.homeStatusMessage.contains("还没有显式治理配置"))
        #expect(conservative.compactCalloutTone == .info)
        #expect(conservative.compactCalloutMessage?.contains("保守基线运行") == true)

        let migrated = ProjectGovernancePresentation(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: true,
            compatSource: AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue
        )
        #expect(migrated.compatSourceLabel == "兼容旧执行面预设")
        #expect(migrated.homeStatusMessage.contains("旧执行面预设映射"))
        #expect(migrated.compatSourceDetail?.contains("A-tier / S-tier") == true)

        let explicit = ProjectGovernancePresentation(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: true,
            compatSource: AXProjectGovernanceCompatSource.explicitDualDial.rawValue
        )
        #expect(explicit.compatSourceLabel == "A/S 档位显式配置")
        #expect(explicit.compatSourceDetail?.contains("已明确保存 A-tier / S-tier / Review Policy") == true)
        #expect(explicit.homeStatusMessage == explicit.statusSummary)
    }

    @Test
    func homeClampMessageSuppressesNoopClampButKeepsActionableClamp() {
        let draft = ProjectGovernancePresentation(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: true
        )
        #expect(draft.homeClampMessage == nil)

        let root = makeProjectRoot(named: "governance-presentation-clamp")
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
        let actionable = ProjectGovernancePresentation(resolved: resolved)

        #expect(actionable.homeClampMessage?.contains("trusted automation readiness") == true)
    }

    @Test
    func compactCalloutPrefersInvalidThenWarningThenClamp() {
        let invalid = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )
        #expect(invalid.compactCalloutTone == .invalid)
        #expect(invalid.compactCalloutMessage?.contains("至少需要") == true)

        let warning = ProjectGovernancePresentation(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )
        #expect(warning.compactCalloutTone == .warning)
        #expect(warning.compactCalloutMessage?.contains("推荐") == true)

        let root = makeProjectRoot(named: "governance-presentation-compact-clamp")
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
        let clampOnly = ProjectGovernancePresentation(resolved: resolved)
        #expect(clampOnly.compactCalloutTone == .info)
        #expect(clampOnly.compactCalloutMessage?.contains("trusted automation readiness") == true)
    }

    @Test
    func homeStatusMessageSurfacesAdaptiveSupervisorRaiseWhenPresent() {
        let root = makeProjectRoot(named: "governance-presentation-adaptive")
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
                confidence: 0.88,
                recommendedSupervisorFloor: .s4TightSupervision,
                recommendedWorkOrderDepth: .stepLockedRescue,
                reasons: ["recent task loops are unstable"]
            ),
            permissionReadiness: makePermissionReadiness(
                accessibility: .granted,
                automation: .granted,
                screenRecording: .granted
            )
        )
        let presentation = ProjectGovernancePresentation(resolved: resolved)

        #expect(presentation.homeStatusMessage.contains("Project AI 评估=weak"))
        #expect(presentation.homeStatusMessage.contains("Supervisor 已从 S2 抬到 S4"))
        #expect(presentation.recommendedSupervisorInterventionTier == .s4TightSupervision)
        #expect(presentation.effectiveWorkOrderDepth == .stepLockedRescue)
        #expect(presentation.followUpRhythmSummary?.contains("blocker cooldown≈90s") == true)
    }

    @Test
    func warningStillWinsWhenAssessmentIsOnlyObservational() {
        let root = makeProjectRoot(named: "governance-presentation-warning-observational")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            projectAIStrengthProfile: AXProjectAIStrengthProfile(
                strengthBand: .unknown,
                confidence: 0.32,
                recommendedSupervisorFloor: .s0SilentAudit,
                recommendedWorkOrderDepth: .brief,
                reasons: ["recent project evidence is still sparse"]
            ),
            permissionReadiness: makePermissionReadiness(
                accessibility: .granted,
                automation: .granted,
                screenRecording: .granted
            )
        )
        let presentation = ProjectGovernancePresentation(resolved: resolved)

        #expect(presentation.homeStatusMessage.contains("推荐搭配"))
        #expect(!presentation.homeStatusMessage.contains("证据仍不足"))
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
        auditRef: "audit-project-governance-presentation-summary-tests"
    )
}
