import Foundation
import Testing
@testable import XTerminal

struct ProjectGovernancePresentationSummaryTests {

    @Test
    func homeStatusMessagePrefersHighRiskAndWarningBeforeGenericStatus() {
        let highRisk = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )
        #expect(highRisk.homeStatusMessage.contains("高风险组合"))

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
        #expect(conservative.compatSourceLabel == "默认 Observe 起步")
        #expect(conservative.homeStatusMessage.contains("还没有显式治理配置"))
        #expect(conservative.compactCalloutTone == .info)
        #expect(conservative.compactCalloutMessage?.contains("Observe 起步") == true)

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
        #expect(migrated.compatSourceDetail?.contains("A-Tier / S-Tier") == true)

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
        #expect(explicit.compatSourceDetail?.contains("已明确保存 A-Tier / S-Tier / Heartbeat / Review") == true)
        #expect(explicit.homeStatusMessage == explicit.statusSummary)
    }

    @Test
    func reviewCadenceTextUsesLocalizedLabels() {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 2700,
            eventDrivenReviewEnabled: true
        )

        #expect(presentation.reviewCadenceText.contains("心跳"))
        #expect(presentation.reviewCadenceText.contains("脉冲"))
        #expect(presentation.reviewCadenceText.contains("脑暴"))
        #expect(presentation.guidanceSummary.contains("安全点"))
    }

    @Test
    func capabilityBoundarySummaryExplainsRepoRuntimeAndReleaseEdges() {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )

        #expect(presentation.capabilityBoundarySummary.contains("仓库写入：可 改文件 / apply patch / delete / move"))
        #expect(presentation.capabilityBoundarySummary.contains("Build / Test / 进程：可 build / test / managed process / auto-restart"))
        #expect(presentation.capabilityBoundarySummary.contains("Push / Release：可 commit / PR create / CI read；push / CI trigger 仍受限"))
        #expect(presentation.capabilityBoundarySummary.contains("Browser / Device / Connector：browser / device / connector / extension 全部受限"))
    }

    @Test
    func effectiveTruthLineIncludesCadenceAndFallbackCompatSource() throws {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: true,
            compatSource: AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue
        )

        let line = try #require(presentation.effectiveTruthLine)
        #expect(line == "治理真相：当前生效 A2/S2 · 审查 Hybrid · 节奏 心跳 15m / 脉冲 30m / 脑暴 off · 来源 兼容旧执行面预设。")
    }

    @Test
    func displayReviewPolicyHelpersStayLocalizedForVisibleSurfaces() throws {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: true,
            compatSource: AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue
        )

        #expect(presentation.displayReviewPolicyShortLabel == "混合")
        #expect(presentation.displayReviewPolicyName == "混合")
        #expect(presentation.reviewCadenceText.contains("脑暴 关闭"))
        let line = try #require(presentation.displayEffectiveTruthLine)
        #expect(line == "治理真相：当前生效 A2/S2 · 审查 混合 · 节奏 心跳 15m / 脉冲 30m / 脑暴 关闭 · 来源 兼容旧执行面预设。")
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
            workspaceBindingHash: "sha256:stale-binding"
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

        #expect(actionable.homeClampMessage?.contains("受治理自动化就绪检查") == true)
    }

    @Test
    func a4StatusSummarySeparatesConfiguredFromRuntimeReady() {
        let root = makeProjectRoot(named: "governance-runtime-ready-separation")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.browser.control"],
            workspaceBindingHash: "sha256:stale-binding"
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

        #expect(presentation.runtimeReadiness?.requiresA4RuntimeReady == true)
        #expect(presentation.runtimeReadiness?.runtimeReady == false)
        #expect(presentation.statusSummary.contains("runtime ready") == true)
        #expect(presentation.runtimeReadiness?.missingSummaryLine?.contains("受治理自动化未就绪") == true)
        #expect(presentation.runtimeReadiness?.missingSummaryLine?.contains("权限宿主未就绪") == true)
    }

    @Test
    func compactCalloutPrefersHighRiskThenWarningThenClamp() {
        let highRisk = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )
        #expect(highRisk.compactCalloutTone == .warning)
        #expect(highRisk.compactCalloutMessage?.contains("高风险组合") == true)

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
        #expect(clampOnly.compactCalloutMessage?.contains("受治理自动化就绪检查") == true)
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

        #expect(presentation.homeStatusMessage.contains("项目 AI 评估=weak"))
        #expect(presentation.homeStatusMessage.contains("Supervisor 已从 S2 抬到 S4"))
        #expect(presentation.recommendedSupervisorInterventionTier == .s4TightSupervision)
        #expect(presentation.effectiveWorkOrderDepth == .stepLockedRescue)
        #expect(presentation.followUpRhythmSummary?.contains("blocker cooldown≈90s") == true)
    }

    @Test
    func resolvedPresentationCarriesCadenceExplainabilityWhenScheduleProvided() {
        let root = makeProjectRoot(named: "governance-presentation-cadence")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 1800,
            reviewPulseSeconds: 2400,
            brainstormReviewSeconds: 4800,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .preDoneSummary]
        )

        let resolved = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            projectAIStrengthProfile: AXProjectAIStrengthProfile(
                strengthBand: .weak,
                confidence: 0.77,
                recommendedSupervisorFloor: .s4TightSupervision,
                recommendedWorkOrderDepth: .stepLockedRescue,
                reasons: ["cadence explainability should expose effective tightening"]
            ),
            permissionReadiness: makePermissionReadiness(
                accessibility: .granted,
                automation: .granted,
                screenRecording: .granted
            )
        )

        let nowMs: Int64 = 1_773_900_000_000
        let presentation = ProjectGovernancePresentation(
            resolved: resolved,
            scheduleState: SupervisorReviewScheduleState(
                schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
                projectId: "project-alpha",
                updatedAtMs: nowMs,
                lastHeartbeatAtMs: nowMs - 3 * 60_000,
                lastObservedProgressAtMs: nowMs - 25 * 60_000,
                lastPulseReviewAtMs: nowMs - 12 * 60_000,
                lastBrainstormReviewAtMs: nowMs - 60 * 60_000,
                lastTriggerReviewAtMs: [:],
                nextHeartbeatDueAtMs: nowMs + 30 * 60_000,
                nextPulseReviewDueAtMs: nowMs + 30 * 60_000,
                nextBrainstormReviewDueAtMs: nowMs + 30 * 60_000,
                latestQualitySnapshot: HeartbeatQualitySnapshot(
                    overallScore: 41,
                    overallBand: .weak,
                    freshnessScore: 45,
                    deltaSignificanceScore: 42,
                    evidenceStrengthScore: 40,
                    blockerClarityScore: 38,
                    nextActionSpecificityScore: 43,
                    executionVitalityScore: 41,
                    completionConfidenceScore: 36,
                    weakReasons: ["progress signal remains weak"],
                    computedAtMs: nowMs - 60_000
                ),
                openAnomalies: [],
                lastHeartbeatFingerprint: "same route",
                lastHeartbeatRepeatCount: 1
            ),
            nowMs: nowMs
        )

        let expectedConfigured = "心跳 30m · 脉冲 40m · 脑暴 80m"
        let expectedRecommended = "心跳 10m · 脉冲 20m · 脑暴 40m"
        let expectedEffective = "心跳 5m · 脉冲 10m · 脑暴 20m"

        #expect(presentation.cadenceConfiguredSummaryText == expectedConfigured)
        #expect(presentation.cadenceRecommendedSummaryText == expectedRecommended)
        #expect(presentation.cadenceEffectiveSummaryText == expectedEffective)
        #expect(presentation.cadenceReasonSummaryText?.contains("按当前 A/S 与治理态收紧到协议建议值") == true)
        #expect(presentation.cadenceDueSummaryText?.contains("脉冲：已到期") == true)
        #expect(presentation.cadenceDueSummaryText?.contains("脑暴：已到期") == true)
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

    @Test
    func watchlistCondensedMetaKeepsAxisLegendAndPrefersCalloutForWarningAndSourceHint() {
        let warningPresentation = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )
        let warningItems = ProjectGovernanceCompactMetaResolver.items(
            context: ProjectGovernanceCompactMetaResolver.context(
                presentation: warningPresentation,
                displayStyle: .watchlist
            ),
            showAxisLegend: true,
            showCallout: true,
            displayStyle: .watchlist
        )

        #expect(warningItems.count == 2)
        #expect(warningItems[0].kind == .axisLegend)
        #expect(warningItems[0].text == "三轴：A 管执行，S 管监督，节奏管 review")
        #expect(warningItems[1].kind == .callout)
        #expect(warningItems[1].text.contains("高风险组合"))

        let sourceHintPresentation = ProjectGovernancePresentation(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: true,
            compatSource: AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue
        )
        let sourceHintItems = ProjectGovernanceCompactMetaResolver.items(
            context: ProjectGovernanceCompactMetaResolver.context(
                presentation: sourceHintPresentation,
                displayStyle: .watchlist
            ),
            showAxisLegend: false,
            showCallout: true,
            displayStyle: .watchlist
        )

        #expect(sourceHintItems.count == 1)
        #expect(sourceHintItems[0].kind == .callout)
        #expect(sourceHintItems[0].text.contains("旧执行面预设映射"))
    }

    @Test
    func watchlistCondensedMetaFallsBackToTruthLineBeforeFollowUp() {
        let truthLine = "治理真相：当前生效 A2/S2。"
        let followUp = "自动跟进：blocker cooldown≈90s"

        let truthItems = ProjectGovernanceCompactMetaResolver.items(
            context: ProjectGovernanceCompactMetaContext(
                axisLegendText: "三轴：A 管执行，S 管监督，节奏管 review",
                governanceModelText: nil,
                calloutMessage: nil,
                shouldPreferCalloutInCondensedMeta: false,
                truthLine: truthLine,
                followUpText: followUp
            ),
            showAxisLegend: false,
            showCallout: true,
            displayStyle: .watchlist
        )

        #expect(truthItems.count == 1)
        #expect(truthItems[0].kind == .truthLine)
        #expect(truthItems[0].text == truthLine)

        let followUpItems = ProjectGovernanceCompactMetaResolver.items(
            context: ProjectGovernanceCompactMetaContext(
                axisLegendText: "三轴：A 管执行，S 管监督，节奏管 review",
                governanceModelText: nil,
                calloutMessage: nil,
                shouldPreferCalloutInCondensedMeta: false,
                truthLine: nil,
                followUpText: followUp
            ),
            showAxisLegend: false,
            showCallout: true,
            displayStyle: .watchlist
        )

        #expect(followUpItems.count == 1)
        #expect(followUpItems[0].kind == .followUp)
        #expect(followUpItems[0].text == followUp)
    }

    @Test
    func operationalDenseSurfaceConfigurationKeepsAxisLegendAndFullMetaStack() {
        let configuration = ProjectGovernanceCompactSummarySurfaceConfiguration.operationalDense
        #expect(configuration.showAxisLegend)
        #expect(configuration.displayStyle == .dense)

        let items = ProjectGovernanceCompactMetaResolver.items(
            context: ProjectGovernanceCompactMetaContext(
                axisLegendText: "三轴：A 管执行，S 管监督，节奏管 review",
                governanceModelText: "新版：双环治理 + 角色记忆",
                calloutMessage: "A4 当前组合允许保存，但低于 S2 风险参考线，属于高风险监督区。",
                shouldPreferCalloutInCondensedMeta: true,
                truthLine: "治理真相：当前生效 A4/S1。",
                followUpText: "自动跟进：blocker cooldown≈90s"
            ),
            showAxisLegend: configuration.showAxisLegend,
            showCallout: true,
            displayStyle: configuration.displayStyle
        )

        #expect(items.map(\.kind) == [.axisLegend, .governanceModel, .callout, .truthLine, .followUp])
        #expect(items[0].text == "三轴：A 管执行，S 管监督，节奏管 review")
        #expect(items[1].text.contains("双环治理"))
        #expect(items[2].text.contains("风险参考线"))
        #expect(items[3].text.contains("当前生效 A4/S1"))
        #expect(items[4].text == "自动跟进：blocker cooldown≈90s")
    }

    @Test
    func regularMetaContextIncludesLatestGovernedRuntimeAndRoleMemoryLine() {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )

        let context = ProjectGovernanceCompactMetaResolver.context(
            presentation: presentation,
            displayStyle: .regular
        )

        #expect(context.axisLegendText.contains("A 管手和脚"))
        #expect(context.governanceModelText?.contains("双环治理") == true)
        #expect(context.governanceModelText?.contains("角色记忆") == true)
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
