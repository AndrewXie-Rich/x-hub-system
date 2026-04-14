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

        #expect(summary.headerSummary.contains("A3 交付自动推进"))
        #expect(summary.headerSummary.contains("S3 战略教练"))
        #expect(summary.headerSummary.contains("审查 混合"))
        #expect(summary.headerSummary.contains("指导"))
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

        let summary = ProjectDetailGovernanceSummary(
            presentation: ProjectGovernancePresentation(resolved: resolved)
        )

        #expect(summary.capabilitySummary.contains("Browser / Device / Connector"))
        #expect(summary.capabilitySummary.contains("可 browser / connector / extension；device / low-risk local auto-approve 仍受限"))
        #expect(summary.clampSummary.contains("受治理自动化就绪检查"))
        #expect(summary.runtimeReadinessSummary?.contains("runtime ready：未就绪") == true)
        #expect(summary.runtimeReadinessSummary?.contains("受治理自动化未就绪") == true)
        #expect(!summary.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func contextAssemblySummaryKeepsRuntimeAssemblySeparateFromATierCeiling() throws {
        let presentation = try #require(
            AXProjectContextAssemblyPresentation.from(
                summary: AXProjectContextAssemblyDiagnosticsSummary(
                    latestEvent: nil,
                    detailLines: [
                        "project_context_diagnostics_source=latest_coder_usage",
                        "project_context_project=Snake",
                        "role_aware_memory_mode=project_ai",
                        "project_memory_resolution_trigger=manual_full_scan_request",
                        "project_memory_v1_source=hub_memory_v1_grpc",
                        "configured_recent_project_dialogue_profile=deep_20_pairs",
                        "recommended_recent_project_dialogue_profile=extended_40_pairs",
                        "effective_recent_project_dialogue_profile=extended_40_pairs",
                        "recent_project_dialogue_profile=extended_40_pairs",
                        "recent_project_dialogue_selected_pairs=18",
                        "recent_project_dialogue_floor_pairs=8",
                        "recent_project_dialogue_floor_satisfied=true",
                        "recent_project_dialogue_source=xt_cache",
                        "recent_project_dialogue_low_signal_dropped=3",
                        "configured_project_context_depth=full",
                        "recommended_project_context_depth=full",
                        "effective_project_context_depth=full",
                        "project_context_depth=full",
                        "effective_project_serving_profile=m4_full_scan",
                        "a_tier_memory_ceiling=m4_full_scan",
                        "project_memory_ceiling_hit=false",
                        "workflow_present=true",
                        "execution_evidence_present=true",
                        "review_guidance_present=false",
                        "cross_link_hints_selected=2",
                        "project_memory_selected_planes=project_dialogue_plane,project_anchor_plane,evidence_plane",
                        "project_memory_selected_serving_objects=recent_project_dialogue_window,focused_project_anchor_pack,execution_evidence",
                        "project_memory_excluded_blocks=active_workflow,guidance",
                        "project_memory_budget_summary=source=hub_memory_v1_grpc · used=512 · budget=2048",
                        "personal_memory_excluded_reason=project_ai_default_scopes_to_project_memory_only"
                    ]
                )
            )
        )

        let summary = ProjectDetailContextAssemblySummary(presentation: presentation)

        #expect(summary.sourceBadge == "实际运行")
        #expect(summary.recentDialogueMetric == "Extended · 40 pairs")
        #expect(summary.contextDepthMetric == "Full")
        #expect(summary.recentDialogueCardSummary.contains("最近一次实际组装"))
        #expect(summary.contextDepthCardSummary.contains("最近一次实际喂给 project AI"))
        #expect(summary.recentDialogueLine.contains("本轮实际选中 18 组对话"))
        #expect(summary.contextDepthLine.contains("A-tier ceiling m4_full_scan"))
        #expect(summary.coverageSummary == "已带工作流、执行证据和关联线索")
        #expect(summary.planeSummary == "实际启用项目对话面、项目锚点面和证据面")
        #expect(summary.assemblySummary == "实际带入最近项目对话、项目锚点和执行证据")
        #expect(summary.omissionSummary == "本轮未带活动工作流和Supervisor 指导")
        #expect(summary.budgetSummary == "source Hub 快照 + 本地 overlay · used 512 tok · budget 2048 tok")
        #expect(summary.boundarySummary == "默认不读取你的个人记忆")
        #expect(summary.governanceReminder.contains("A-Tier 只提供 Project AI 的 project-memory ceiling"))
    }

    @Test
    func contextAssemblySummaryFallsBackToConfigBaselineBeforeRuntimeUsage() throws {
        let presentation = try #require(
            AXProjectContextAssemblyPresentation.from(
                summary: AXProjectContextAssemblyDiagnosticsSummary(
                    latestEvent: nil,
                    detailLines: [
                        "project_context_diagnostics_source=config_only",
                        "project_context_project=Bright",
                        "configured_recent_project_dialogue_profile=deep_20_pairs",
                        "recommended_recent_project_dialogue_profile=standard_12_pairs",
                        "effective_recent_project_dialogue_profile=deep_20_pairs",
                        "configured_project_context_depth=deep",
                        "recommended_project_context_depth=lean",
                        "effective_project_context_depth=balanced",
                        "a_tier_memory_ceiling=m2_plan_review",
                        "project_memory_ceiling_hit=true",
                        "project_context_diagnostics=no_recent_coder_usage"
                    ]
                )
            )
        )

        let summary = ProjectDetailContextAssemblySummary(presentation: presentation)

        #expect(summary.sourceBadge == "配置基线")
        #expect(summary.recentDialogueMetric == "Deep · 20 pairs")
        #expect(summary.contextDepthMetric == "Deep")
        #expect(summary.recentDialogueCardSummary.contains("当前配置解析"))
        #expect(summary.contextDepthCardSummary.contains("当前配置解析"))
        #expect(summary.recentDialogueLine.contains("configured / recommended / effective"))
        #expect(summary.contextDepthLine.contains("A-tier ceiling m2_plan_review"))
        #expect(summary.coverageSummary == nil)
        #expect(summary.assemblySummary == nil)
        #expect(summary.omissionSummary == nil)
        #expect(summary.budgetSummary == nil)
        #expect(summary.boundarySummary == nil)
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
