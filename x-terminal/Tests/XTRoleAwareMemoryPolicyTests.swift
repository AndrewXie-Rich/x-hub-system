import Foundation
import Testing
@testable import XTerminal

struct XTRoleAwareMemoryPolicyTests {

    @Test
    func projectPolicyClampsConfiguredFullDepthToATierCeiling() throws {
        let root = try makeProjectRoot(named: "role-aware-project-policy")
        defer { try? FileManager.default.removeItem(at: root) }

        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingProjectGovernance(
                executionTier: .a0Observe,
                supervisorInterventionTier: .s0SilentAudit
            )
            .settingProjectContextAssembly(
                projectRecentDialogueProfile: .autoMax,
                projectContextDepthProfile: .full
            )
        let governance = xtResolveProjectGovernance(projectRoot: root, config: config)

        let policy = XTRoleAwareMemoryPolicyResolver.resolveProject(
            config: config,
            governance: governance,
            userText: "请 full scan 当前项目，给我完整上下文后再给出修复方案",
            shouldExpandRecent: false,
            executionEvidencePresent: true,
            reviewGuidancePresent: false
        )

        #expect(policy.trigger == "manual_full_scan_request")
        #expect(policy.configuredRecentProjectDialogueProfile == .autoMax)
        #expect(policy.recommendedRecentProjectDialogueProfile == .extended40Pairs)
        #expect(policy.effectiveRecentProjectDialogueProfile == .extended40Pairs)
        #expect(policy.configuredProjectContextDepth == .full)
        #expect(policy.recommendedProjectContextDepth == .full)
        #expect(policy.effectiveProjectContextDepth == .balanced)
        #expect(policy.aTierMemoryCeiling == .m2PlanReview)
        #expect(policy.effectiveServingProfile == .m2PlanReview)
        #expect(policy.ceilingHit == true)
        #expect(policy.snapshot.schemaVersion == XTProjectMemoryPolicySnapshot.currentSchemaVersion)
        #expect(policy.resolution.selectedServingObjects.contains("execution_evidence"))
        #expect(policy.resolution.excludedBlocks.contains("guidance"))
        #expect(policy.resolution.excludedBlocks.contains("assistant_plane"))
    }

    @Test
    func projectPolicyPromotesExecutionStateObjectsWhenAutomationContinuityNeedsCarryForward() throws {
        let root = try makeProjectRoot(named: "role-aware-project-policy-automation")
        defer { try? FileManager.default.removeItem(at: root) }

        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
            .settingProjectContextAssembly(
                projectRecentDialogueProfile: .autoMax,
                projectContextDepthProfile: .balanced
            )
        let governance = xtResolveProjectGovernance(projectRoot: root, config: config)

        let policy = XTRoleAwareMemoryPolicyResolver.resolveProject(
            config: config,
            governance: governance,
            userText: "继续修当前编译错误",
            shouldExpandRecent: false,
            executionEvidencePresent: false,
            reviewGuidancePresent: false,
            automationCurrentStepPresent: true,
            automationVerificationPresent: true,
            automationVerificationAttentionPresent: true,
            automationBlockerPresent: true,
            automationRetryReasonPresent: true
        )

        #expect(policy.trigger == "retry_execution")
        #expect(policy.recommendedRecentProjectDialogueProfile == .deep20Pairs)
        #expect(policy.recommendedProjectContextDepth == .deep)
        #expect(policy.effectiveProjectContextDepth == .balanced)
        #expect(policy.aTierMemoryCeiling == .m3DeepDive)
        #expect(policy.resolution.selectedServingObjects.contains("current_step"))
        #expect(policy.resolution.selectedServingObjects.contains("verification_state"))
        #expect(policy.resolution.selectedServingObjects.contains("blocker_state"))
        #expect(policy.resolution.selectedServingObjects.contains("retry_reason"))
        #expect(policy.resolution.selectedPlanes.contains("execution_state_plane"))
    }

    @Test
    func projectPolicyFreezesPromptFloorSeparateFromXtLocalHotWindow() throws {
        let root = try makeProjectRoot(named: "role-aware-project-policy-continuity-contract")
        defer { try? FileManager.default.removeItem(at: root) }

        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingProjectGovernance(
                executionTier: .a1Plan,
                supervisorInterventionTier: .s1MilestoneReview
            )
            .settingProjectContextAssembly(
                projectRecentDialogueProfile: .standard12Pairs,
                projectContextDepthProfile: .balanced
            )
        let governance = xtResolveProjectGovernance(projectRoot: root, config: config)

        let policy = XTRoleAwareMemoryPolicyResolver.resolveProject(
            config: config,
            governance: governance,
            userText: "继续当前计划",
            shouldExpandRecent: false,
            executionEvidencePresent: false,
            reviewGuidancePresent: false
        )

        #expect(policy.promptContinuityContract.promptFloorTurns == 16)
        #expect(policy.promptContinuityContract.promptTargetTurns == 24)
        #expect(policy.promptContinuityContract.xtLocalWindowTurnLimit == 30)
        #expect(policy.promptContinuityContract.xtLocalWindowStorageRole == .hotContinuityCache)
        #expect(policy.promptContinuityContract.promptFloorSeparatedFromLocalHotWindow == true)
    }

    @Test
    func projectPolicyUpgradesGuidanceAndEvidenceFollowUpToDedicatedTrigger() throws {
        let root = try makeProjectRoot(named: "role-aware-project-policy-guidance-follow-up")
        defer { try? FileManager.default.removeItem(at: root) }

        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s3StrategicCoach
            )
            .settingProjectContextAssembly(
                projectRecentDialogueProfile: .autoMax,
                projectContextDepthProfile: .balanced
            )
        let governance = xtResolveProjectGovernance(projectRoot: root, config: config)

        let policy = XTRoleAwareMemoryPolicyResolver.resolveProject(
            config: config,
            governance: governance,
            userText: "继续按最新 guidance 推进，并核对刚才的证据",
            shouldExpandRecent: false,
            executionEvidencePresent: true,
            reviewGuidancePresent: true
        )

        #expect(policy.trigger == "review_guidance_follow_up")
        #expect(policy.recommendedRecentProjectDialogueProfile == .deep20Pairs)
        #expect(policy.recommendedProjectContextDepth == .deep)
        #expect(policy.effectiveProjectContextDepth == .balanced)
    }

    @Test
    func projectPolicyUsesRestartRecoveryTriggerWhenRecoveryStateNeedsCarryForward() throws {
        let root = try makeProjectRoot(named: "role-aware-project-policy-restart-recovery")
        defer { try? FileManager.default.removeItem(at: root) }

        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
            .settingProjectContextAssembly(
                projectRecentDialogueProfile: .autoMax,
                projectContextDepthProfile: .balanced
            )
        let governance = xtResolveProjectGovernance(projectRoot: root, config: config)

        let policy = XTRoleAwareMemoryPolicyResolver.resolveProject(
            config: config,
            governance: governance,
            userText: "继续接上刚才那轮恢复",
            shouldExpandRecent: false,
            executionEvidencePresent: false,
            reviewGuidancePresent: false,
            automationCurrentStepPresent: true,
            automationCurrentStepState: XTAutomationRunStepState.blocked.rawValue,
            automationRecoveryStatePresent: true,
            automationRecoveryReason: XTAutomationRecoveryCandidateReason.latestVisibleStableIdentityFailed.rawValue,
            automationRecoveryDecision: XTAutomationRestartRecoveryAction.hold.rawValue
        )

        #expect(policy.trigger == "restart_recovery")
        #expect(policy.recommendedRecentProjectDialogueProfile == .deep20Pairs)
        #expect(policy.recommendedProjectContextDepth == .deep)
        #expect(policy.resolution.selectedServingObjects.contains("current_step"))
        #expect(policy.resolution.selectedPlanes.contains("execution_state_plane"))
    }

    @Test
    func projectPolicyUsesStepFollowUpTriggerForActiveAutomationStep() throws {
        let root = try makeProjectRoot(named: "role-aware-project-policy-step-follow-up")
        defer { try? FileManager.default.removeItem(at: root) }

        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
            .settingProjectContextAssembly(
                projectRecentDialogueProfile: .autoMax,
                projectContextDepthProfile: .balanced
            )
        let governance = xtResolveProjectGovernance(projectRoot: root, config: config)

        let policy = XTRoleAwareMemoryPolicyResolver.resolveProject(
            config: config,
            governance: governance,
            userText: "继续当前 step",
            shouldExpandRecent: false,
            executionEvidencePresent: false,
            reviewGuidancePresent: false,
            automationCurrentStepPresent: true,
            automationCurrentStepState: XTAutomationRunStepState.inProgress.rawValue
        )

        #expect(policy.trigger == "execution_step_follow_up")
        #expect(policy.recommendedRecentProjectDialogueProfile == .deep20Pairs)
        #expect(policy.recommendedProjectContextDepth == .deep)
        #expect(policy.resolution.selectedServingObjects.contains("current_step"))
        #expect(policy.resolution.selectedPlanes.contains("execution_state_plane"))
    }

    @Test
    func supervisorPolicyClampsStrategicFullScanRequestToSTierCeiling() {
        let policy = XTRoleAwareMemoryPolicyResolver.resolveSupervisor(
            configuredSupervisorRecentRawContextProfile: .autoMax,
            reviewLevelHint: .r2Strategic,
            dominantMode: .projectFirst,
            focusedProjectSelected: true,
            userMessage: "请对这个项目做一次 full scan review",
            reviewMemoryCeiling: .m2PlanReview,
            privacyMode: .defaultMode
        )

        #expect(policy.trigger == "manual_full_scan_request")
        #expect(policy.assemblyPurpose == .governanceReview)
        #expect(policy.configuredReviewMemoryDepth == .auto)
        #expect(policy.recommendedReviewMemoryDepth == .deepDive)
        #expect(policy.effectiveReviewMemoryDepth == .planReview)
        #expect(policy.purposeCapApplied == false)
        #expect(policy.minimumRequiredReviewServingProfile == .m2PlanReview)
        #expect(policy.sTierReviewMemoryCeiling == .m2PlanReview)
        #expect(policy.effectiveServingProfile == .m2PlanReview)
        #expect(policy.ceilingHit == true)
        #expect(policy.snapshot.schemaVersion == XTSupervisorMemoryPolicySnapshot.currentSchemaVersion)
        #expect(policy.resolution.selectedServingObjects.contains("evidence_pack"))
        #expect(policy.resolution.excludedBlocks.isEmpty)
    }

    @Test
    func supervisorPolicyExpandsRawContextWhenAutoMaxAndHybrid() {
        let policy = XTRoleAwareMemoryPolicyResolver.resolveSupervisor(
            configuredSupervisorRecentRawContextProfile: .autoMax,
            reviewLevelHint: .r1Pulse,
            dominantMode: .hybrid,
            focusedProjectSelected: false,
            crossLinkContextAvailable: true,
            userMessage: "继续刚才那个项目和安排一起推进",
            reviewMemoryCeiling: nil,
            privacyMode: .defaultMode
        )

        #expect(policy.trigger == "user_turn")
        #expect(policy.recommendedSupervisorRecentRawContextProfile == .deep20Pairs)
        #expect(policy.effectiveSupervisorRecentRawContextProfile == .deep20Pairs)
        #expect(policy.effectiveReviewMemoryDepth == .compact)
        #expect(policy.resolution.selectedServingObjects.contains("cross_link_refs"))
    }

    @Test
    func supervisorPolicyDoesNotInventCrossLinkRefsWithoutRelevantTurnContext() {
        let policy = XTRoleAwareMemoryPolicyResolver.resolveSupervisor(
            configuredSupervisorRecentRawContextProfile: .standard12Pairs,
            reviewLevelHint: .r1Pulse,
            dominantMode: .projectFirst,
            focusedProjectSelected: true,
            crossLinkContextAvailable: false,
            userMessage: "继续推进这个项目，把 blocker 说清楚",
            reviewMemoryCeiling: .m2PlanReview,
            privacyMode: .defaultMode,
            assemblyPurpose: .projectAssist
        )

        #expect(policy.assemblyPurpose == .projectAssist)
        #expect(!policy.resolution.selectedServingObjects.contains("cross_link_refs"))
    }

    @Test
    func supervisorConversationPurposeKeepsReviewMemoryCompactEvenWithDeepConfiguredPreference() {
        let policy = XTRoleAwareMemoryPolicyResolver.resolveSupervisor(
            configuredSupervisorRecentRawContextProfile: .standard12Pairs,
            configuredReviewMemoryDepth: .fullScan,
            reviewLevelHint: .r1Pulse,
            dominantMode: .personalFirst,
            focusedProjectSelected: false,
            userMessage: "明天上午提醒我开会，再顺便总结一下今天安排",
            reviewMemoryCeiling: .m4FullScan,
            privacyMode: .defaultMode,
            assemblyPurpose: .conversation
        )

        #expect(policy.assemblyPurpose == .conversation)
        #expect(policy.recommendedReviewMemoryDepth == .compact)
        #expect(policy.effectiveReviewMemoryDepth == .compact)
        #expect(policy.purposeScopedReviewMemoryCap == .m1Execute)
        #expect(policy.purposeCapApplied == true)
        #expect(policy.effectiveServingProfile == .m1Execute)
        #expect(policy.ceilingHit == false)
    }

    @Test
    func supervisorProjectAssistPurposeCapsReviewMemoryAtPlanReview() {
        let policy = XTRoleAwareMemoryPolicyResolver.resolveSupervisor(
            configuredSupervisorRecentRawContextProfile: .standard12Pairs,
            configuredReviewMemoryDepth: .fullScan,
            reviewLevelHint: .r1Pulse,
            dominantMode: .projectFirst,
            focusedProjectSelected: true,
            userMessage: "继续推进这个项目，把下一步和 blocker 简单说清楚就行",
            reviewMemoryCeiling: .m4FullScan,
            privacyMode: .defaultMode,
            assemblyPurpose: .projectAssist
        )

        #expect(policy.assemblyPurpose == .projectAssist)
        #expect(policy.recommendedReviewMemoryDepth == .planReview)
        #expect(policy.effectiveReviewMemoryDepth == .planReview)
        #expect(policy.purposeScopedReviewMemoryCap == .m2PlanReview)
        #expect(policy.purposeCapApplied == true)
        #expect(policy.effectiveServingProfile == .m2PlanReview)
        #expect(policy.ceilingHit == false)
    }

    @Test
    func supervisorPolicyUsesHeartbeatPeriodicPulseResolutionTriggerForGovernanceReview() {
        let policy = XTRoleAwareMemoryPolicyResolver.resolveSupervisor(
            configuredSupervisorRecentRawContextProfile: .autoMax,
            configuredReviewMemoryDepth: .auto,
            reviewLevelHint: .r1Pulse,
            dominantMode: .projectFirst,
            focusedProjectSelected: true,
            userMessage: """
自动按 project governance 执行周期 review。
trigger=heartbeat
review_trigger=periodic_pulse
review_run_kind=pulse
""",
            triggerSource: "heartbeat",
            governanceReviewTrigger: .periodicPulse,
            governanceReviewRunKind: .pulse,
            reviewMemoryCeiling: .m2PlanReview,
            privacyMode: .defaultMode,
            assemblyPurpose: .governanceReview
        )

        #expect(policy.assemblyPurpose == .governanceReview)
        #expect(policy.trigger == "heartbeat_periodic_pulse_review")
        #expect(policy.recommendedReviewMemoryDepth == .compact)
        #expect(policy.effectiveReviewMemoryDepth == .planReview)
    }

    @Test
    func supervisorPolicyUsesHeartbeatNoProgressResolutionTriggerForBrainstormReview() {
        let policy = XTRoleAwareMemoryPolicyResolver.resolveSupervisor(
            configuredSupervisorRecentRawContextProfile: .autoMax,
            configuredReviewMemoryDepth: .auto,
            reviewLevelHint: .r2Strategic,
            dominantMode: .projectFirst,
            focusedProjectSelected: true,
            userMessage: """
heartbeat 检测到长时间无进展，进入 brainstorm review。
trigger=heartbeat
review_trigger=no_progress_window
review_run_kind=brainstorm
""",
            triggerSource: "heartbeat",
            governanceReviewTrigger: .noProgressWindow,
            governanceReviewRunKind: .brainstorm,
            reviewMemoryCeiling: .m3DeepDive,
            privacyMode: .defaultMode,
            assemblyPurpose: .governanceReview
        )

        #expect(policy.assemblyPurpose == .governanceReview)
        #expect(policy.trigger == "heartbeat_no_progress_review")
        #expect(policy.recommendedReviewMemoryDepth == .deepDive)
        #expect(policy.effectiveReviewMemoryDepth == .deepDive)
    }
}

private func makeProjectRoot(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("xt-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
