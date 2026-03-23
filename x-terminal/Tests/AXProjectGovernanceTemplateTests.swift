import Foundation
import Testing
@testable import XTerminal

struct AXProjectGovernanceTemplateTests {
    @Test
    func legacyDefaultProjectStillPresentsAsConservative() throws {
        let root = try makeProjectRoot(named: "switchboard-legacy-conservative")
        let config = AXProjectConfig.default(forProjectRoot: root)
        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: readyPermissionReadiness()
        )

        let presentation = xtProjectGovernanceTemplatePresentation(
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
    func agentTemplateAppliesCanonicalSettings() throws {
        let root = try makeProjectRoot(named: "switchboard-full-apply")
        let config = AXProjectConfig
            .default(forProjectRoot: root)
            .settingGovernanceTemplate(
                .agent,
                projectRoot: root,
                now: Date(timeIntervalSince1970: 1_773_900_000)
            )

        #expect(config.executionTier == .a4OpenClaw)
        #expect(config.supervisorInterventionTier == .s3StrategicCoach)
        #expect(config.reviewPolicyMode == .hybrid)
        #expect(config.runtimeSurfaceMode == .trustedOpenClawMode)
        #expect(config.governedAutoApproveLocalToolCalls)
        #expect(config.preferHubMemory)
        #expect(config.runtimeSurfaceHubOverrideMode == .none)
    }

    @Test
    func agentTemplateWithoutTrustedAutomationKeepsConfiguredAgentButEffectiveDeviceAuthorityOff() throws {
        let root = try makeProjectRoot(named: "switchboard-full-without-binding")
        let config = AXProjectConfig
            .default(forProjectRoot: root)
            .settingGovernanceTemplate(
                .agent,
                projectRoot: root,
                now: Date(timeIntervalSince1970: 1_773_900_000)
            )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: readyPermissionReadiness()
        )
        let presentation = xtProjectGovernanceTemplatePresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )

        #expect(presentation.configuredProfile == .agent)
        #expect(presentation.effectiveProfile == .custom)
        #expect(presentation.effectiveDeviceAuthorityPosture == .off)
        #expect(presentation.effectiveDeviationReasons.contains { $0.localizedCaseInsensitiveContains("trusted automation") })
    }

    @Test
    func agentTemplateUsesAgentCopyWhileKeepingLegacyRawValue() {
        #expect(AXProjectGovernanceTemplate.agent.rawValue == "full_autonomy")
        #expect(AXProjectGovernanceTemplate.agent.displayName == "Agent")
        #expect(AXProjectGovernanceTemplate.agent.shortDescription.contains("A4 Agent + S3"))
        #expect(AXProjectGovernanceTemplate.selectableTemplates == [.conservative, .safe, .agent])
    }

    @Test
    func customizedReviewCadencePromotesConfiguredProfileToCustom() throws {
        let root = try makeProjectRoot(named: "switchboard-custom-review")
        var config = AXProjectConfig
            .default(forProjectRoot: root)
            .settingGovernanceTemplate(
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
        let presentation = xtProjectGovernanceTemplatePresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )

        #expect(presentation.configuredProfile == .custom)
        #expect(!presentation.configuredDeviationReasons.isEmpty)
    }

    @Test
    @available(*, deprecated, message: "Compat coverage for legacy baseline helper.")
    func governanceTemplateBaselineAliasMatchesLegacyBaselineHelper() {
        #expect(xtGovernanceTemplateBaseline(for: .a1Plan) == xtAutonomyBaselineProfile(for: .a1Plan))
        #expect(xtGovernanceTemplateBaseline(for: .a3DeliverAuto) == xtAutonomyBaselineProfile(for: .a3DeliverAuto))
        #expect(xtGovernanceTemplateBaseline(for: .a4OpenClaw) == xtAutonomyBaselineProfile(for: .a4OpenClaw))
    }

    @Test
    func draftConfigKeepsSelectedBaselineSignalsWhileGovernanceDrifts() throws {
        let root = try makeProjectRoot(named: "switchboard-draft-baseline")
        let config = xtGovernanceTemplateDraftConfig(
            projectRoot: root,
            template: .agent,
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
        let presentation = xtProjectGovernanceTemplatePresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )

        #expect(presentation.configuredProfile == .custom)
        #expect(presentation.configuredDeviceAuthorityPosture == .deviceGoverned)
        #expect(presentation.configuredGrantPosture == .envelopeAuto)
    }

    @Test
    @available(*, deprecated, message: "Compat coverage for legacy draft config helper.")
    func governanceTemplateDraftConfigAliasMatchesLegacyDraftConfig() throws {
        let root = try makeProjectRoot(named: "switchboard-governance-template-draft")
        let legacy = xtAutonomySwitchboardDraftConfig(
            projectRoot: root,
            baselineProfile: .safe,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultProgressHeartbeatSeconds,
            reviewPulseSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultReviewPulseSeconds,
            brainstormReviewSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultBrainstormReviewSeconds,
            eventDrivenReviewEnabled: AXProjectExecutionTier.a3DeliverAuto.defaultEventDrivenReviewEnabled
        )
        let aliased = xtGovernanceTemplateDraftConfig(
            projectRoot: root,
            template: .safe,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultProgressHeartbeatSeconds,
            reviewPulseSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultReviewPulseSeconds,
            brainstormReviewSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultBrainstormReviewSeconds,
            eventDrivenReviewEnabled: AXProjectExecutionTier.a3DeliverAuto.defaultEventDrivenReviewEnabled
        )

        #expect(legacy.executionTier == aliased.executionTier)
        #expect(legacy.supervisorInterventionTier == aliased.supervisorInterventionTier)
        #expect(legacy.reviewPolicyMode == aliased.reviewPolicyMode)
        #expect(legacy.runtimeSurfaceMode == aliased.runtimeSurfaceMode)
        #expect(legacy.governedAutoApproveLocalToolCalls == aliased.governedAutoApproveLocalToolCalls)
        #expect(legacy.preferHubMemory == aliased.preferHubMemory)
    }

    @Test
    func draftConfigFallsBackToExecutionTierBaselineWhenNeeded() throws {
        let root = try makeProjectRoot(named: "switchboard-draft-fallback")
        let config = xtGovernanceTemplateDraftConfig(
            projectRoot: root,
            template: .custom,
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
        let presentation = xtProjectGovernanceTemplatePresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )

        #expect(presentation.configuredProfile == .safe)
        #expect(presentation.configuredSupervisorScope == .portfolio)
        #expect(presentation.configuredGrantPosture == .guidedAuto)
    }

    @Test
    func draftConfigPreservesCustomEventReviewTriggers() throws {
        let root = try makeProjectRoot(named: "governance-template-custom-triggers")
        let config = xtGovernanceTemplateDraftConfig(
            projectRoot: root,
            template: .safe,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultProgressHeartbeatSeconds,
            reviewPulseSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultReviewPulseSeconds,
            brainstormReviewSeconds: AXProjectExecutionTier.a3DeliverAuto.defaultBrainstormReviewSeconds,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.failureStreak, .planDrift, .preDoneSummary]
        )

        #expect(config.eventReviewTriggers == [.failureStreak, .planDrift, .preDoneSummary])

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: readyPermissionReadiness()
        )

        #expect(resolved.effectiveBundle.schedule.eventReviewTriggers == [
            .failureStreak,
            .planDrift,
            .preDoneSummary
        ])
    }

    @Test
    @available(*, deprecated, message: "Compat coverage for legacy presentation helper.")
    func governanceTemplatePresentationAliasMatchesLegacyPresentation() throws {
        let root = try makeProjectRoot(named: "switchboard-governance-template-presentation")
        let config = xtGovernanceTemplateDraftConfig(
            projectRoot: root,
            template: .agent,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: AXProjectExecutionTier.a4OpenClaw.defaultProgressHeartbeatSeconds,
            reviewPulseSeconds: AXProjectExecutionTier.a4OpenClaw.defaultReviewPulseSeconds,
            brainstormReviewSeconds: AXProjectExecutionTier.a4OpenClaw.defaultBrainstormReviewSeconds,
            eventDrivenReviewEnabled: AXProjectExecutionTier.a4OpenClaw.defaultEventDrivenReviewEnabled
        )
        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: readyPermissionReadiness()
        )

        let legacy = xtProjectAutonomySwitchboardPresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )
        let aliased = xtProjectGovernanceTemplatePresentation(
            projectRoot: root,
            config: config,
            resolved: resolved
        )

        #expect(legacy == aliased)
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
