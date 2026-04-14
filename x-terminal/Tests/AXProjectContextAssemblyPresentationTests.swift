import Foundation
import Testing
@testable import XTerminal

struct AXProjectContextAssemblyPresentationTests {
    @Test
    func latestCoderUsagePresentationExplainsRuntimeAssembly() throws {
        let summary = AXProjectContextAssemblyDiagnosticsSummary(
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

        let presentation = try #require(AXProjectContextAssemblyPresentation.from(summary: summary))

        #expect(presentation.sourceKind == .latestCoderUsage)
        #expect(presentation.sourceBadge == "Latest Usage")
        #expect(presentation.projectLabel == "Snake")
        #expect(presentation.dialogueMetric.contains("Extended"))
        #expect(presentation.dialogueMetric.contains("selected 18p"))
        #expect(presentation.depthMetric.contains("Full"))
        #expect(presentation.depthMetric.contains("m4_full_scan"))
        #expect(presentation.depthMetric.contains("Hub 快照 + 本地 overlay"))
        #expect(presentation.coverageMetric == "wf yes · ev yes · gd no · xlink 2")
        #expect(presentation.boundaryMetric == "personal excluded")
        #expect(presentation.statusLine.contains("用户要求完整扫描项目上下文"))
        #expect(presentation.statusLine.contains("manual_full_scan_request"))
        #expect(presentation.dialogueLine.contains("configured Deep · 20 pairs"))
        #expect(presentation.dialogueLine.contains("recommended Extended · 40 pairs"))
        #expect(presentation.dialogueLine.contains("effective Extended · 40 pairs"))
        #expect(presentation.depthLine.contains("configured Full"))
        #expect(presentation.depthLine.contains("recommended Full"))
        #expect(presentation.depthLine.contains("effective Full"))
        #expect(presentation.depthLine.contains("ceiling m4_full_scan"))
        #expect(presentation.dialogueLine.contains("floor 8 已满足"))
        #expect(presentation.recentDialogueSource == "xt_cache")
        #expect(presentation.recentDialogueSourceLabel == "本地缓存")
        #expect(presentation.recentDialogueSourceClass == "local_cache")
        #expect(presentation.memorySource == "hub_memory_v1_grpc")
        #expect(presentation.memorySourceLabel == "Hub 快照 + 本地 overlay")
        #expect(presentation.memorySourceClass == "hub_snapshot_plus_local_overlay")
        #expect(presentation.depthLine.contains("Hub 快照 + 本地 overlay"))
        #expect(presentation.userSourceBadge == "实际运行")
        #expect(presentation.userStatusLine.contains("Hub 快照 + 本地 overlay（快照拼接，非 durable 真相）") == true)
        #expect(presentation.userStatusLine.contains("Writer + Gate") == true)
        #expect(presentation.userDialogueMetric == "Extended · 40 pairs")
        #expect(presentation.userDepthMetric == "Full")
        #expect(presentation.userCoverageSummary == "已带工作流、执行证据和关联线索")
        #expect(presentation.userPlaneSummary == "实际启用项目对话面、项目锚点面和证据面")
        #expect(presentation.userAssemblySummary == "实际带入最近项目对话、项目锚点和执行证据")
        #expect(presentation.userOmissionSummary == "本轮未带活动工作流和Supervisor 指导")
        #expect(presentation.userBudgetSummary == "source Hub 快照 + 本地 overlay · used 512 tok · budget 2048 tok")
        #expect(presentation.planeLine == "Active Planes：项目对话面、项目锚点面和证据面")
        #expect(presentation.assemblyLine == "Actual Assembly：最近项目对话、项目锚点和执行证据")
        #expect(presentation.omissionLine == "Omitted Blocks：活动工作流和Supervisor 指导")
        #expect(presentation.budgetLine == "Budget：source Hub 快照 + 本地 overlay · used 512 tok · budget 2048 tok")
        #expect(presentation.userBoundarySummary == "默认不读取你的个人记忆")
        #expect(presentation.userDialogueLine.contains("configured Deep · 20 pairs"))
        #expect(presentation.userDepthLine.contains("A-tier ceiling m4_full_scan"))
        #expect(presentation.userDialogueLine.contains("本轮实际选中 18 组对话"))

        let compactSummary = presentation.compactSummary
        #expect(compactSummary.headlineText == "实际运行 · Extended · 40 pairs / Full")
        #expect(compactSummary.detailText == "实际带入最近项目对话、项目锚点和执行证据 · 本轮未带活动工作流和Supervisor 指导")
        #expect(compactSummary.helpText.contains("A-Tier 只提供 Project AI 的 project-memory ceiling"))
        #expect(compactSummary.helpText.contains("默认不读取你的个人记忆"))
        #expect(compactSummary.helpText.contains("source Hub 快照 + 本地 overlay · used 512 tok · budget 2048 tok"))
    }

    @Test
    func latestCoderUsagePresentationExplainsExecutionStateContinuity() throws {
        let summary = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=ExecutionScope",
                "project_memory_resolution_trigger=retry_execution",
                "project_memory_v1_source=local_project_memory_v1",
                "configured_recent_project_dialogue_profile=standard_12_pairs",
                "recommended_recent_project_dialogue_profile=deep_20_pairs",
                "effective_recent_project_dialogue_profile=standard_12_pairs",
                "recent_project_dialogue_profile=standard_12_pairs",
                "recent_project_dialogue_selected_pairs=10",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=recent_context",
                "recent_project_dialogue_low_signal_dropped=0",
                "configured_project_context_depth=balanced",
                "recommended_project_context_depth=deep",
                "effective_project_context_depth=balanced",
                "project_context_depth=balanced",
                "effective_project_serving_profile=m2_plan_review",
                "a_tier_memory_ceiling=m3_deep_dive",
                "project_memory_ceiling_hit=false",
                "workflow_present=false",
                "execution_evidence_present=true",
                "review_guidance_present=false",
                "cross_link_hints_selected=0",
                "project_memory_selected_planes=project_dialogue_plane,project_anchor_plane,execution_state_plane,evidence_plane",
                "project_memory_selected_serving_objects=recent_project_dialogue_window,focused_project_anchor_pack,current_step,verification_state,blocker_state,retry_reason,execution_evidence",
                "project_memory_automation_recovery_reason=latest_visible_retry_wait",
                "project_memory_automation_recovery_hold_reason=retry_after_not_elapsed",
                "project_memory_automation_recovery_retry_after_remaining_seconds=25",
                "project_memory_automation_current_step_present=true",
                "project_memory_automation_current_step_title=Verify focused smoke tests",
                "project_memory_automation_current_step_state=retry_wait",
                "project_memory_automation_current_step_summary=Waiting before retrying the reduced verify set.",
                "project_memory_automation_verification_present=true",
                "project_memory_automation_verification_required=true",
                "project_memory_automation_verification_executed=true",
                "project_memory_automation_verification_command_count=3",
                "project_memory_automation_verification_passed_command_count=1",
                "project_memory_automation_verification_hold_reason=automation_verify_failed",
                "project_memory_automation_blocker_present=true",
                "project_memory_automation_blocker_summary=Smoke tests are still red.",
                "project_memory_automation_blocker_stage=verification",
                "project_memory_automation_retry_reason_present=true",
                "project_memory_automation_retry_reason_summary=Retry with a reduced verify set",
                "project_memory_automation_retry_reason_strategy=shrink_verify_scope"
            ]
        )

        let presentation = try #require(AXProjectContextAssemblyPresentation.from(summary: summary))

        #expect(presentation.statusLine.contains("自动重试链继续上次执行") == true)
        #expect(presentation.statusLine.contains("retry_execution") == true)
        #expect(presentation.executionMetric == "step yes · verify yes · blocker yes · retry yes · recovery yes")
        #expect(presentation.executionLine?.contains("Verify focused smoke tests") == true)
        #expect(presentation.executionLine?.contains("等待重试") == true)
        #expect(presentation.executionLine?.contains("recovery retry window pending") == true)
        #expect(presentation.executionLine?.contains("hold retry after not elapsed") == true)
        #expect(presentation.executionLine?.contains("remaining 25s") == true)
        #expect(presentation.executionLine?.contains("verification 1/3 passed") == true)
        #expect(presentation.executionLine?.contains("hold automation verify failed") == true)
        #expect(presentation.executionLine?.contains("blocker 验证: Smoke tests are still red.") == true)
        #expect(presentation.executionLine?.contains("retry Retry with a reduced verify set -> shrink_verify_scope") == true)
        #expect(presentation.userExecutionSummary?.contains("当前停在“Verify focused smoke tests”（等待重试）") == true)
        #expect(presentation.userExecutionSummary?.contains("恢复链还在等重试窗口（剩余 25 秒）") == true)
        #expect(presentation.userExecutionSummary?.contains("验证通过 1/3") == true)
        #expect(presentation.userExecutionSummary?.contains("当前有验证阻塞") == true)
        #expect(presentation.userExecutionSummary?.contains("系统保留了重试原因") == true)
        #expect(presentation.userAssemblySummary?.contains("当前步骤") == true)
        #expect(presentation.userAssemblySummary?.contains("验证状态") == true)
        #expect(presentation.userAssemblySummary?.contains("结构化阻塞") == true)
        #expect(presentation.userAssemblySummary?.contains("重试原因") == true)
        #expect(presentation.userPlaneSummary?.contains("执行状态面") == true)
        #expect(presentation.compactSummary.detailText?.contains("当前停在“Verify focused smoke tests”（等待重试）") == true)
        #expect(presentation.compactSummary.helpText.contains("系统保留了重试原因") == true)
    }

    @Test
    func latestCoderUsagePresentationExplainsStableIdentityRecoveryFailure() throws {
        let summary = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=IdentityScope",
                "project_memory_resolution_trigger=restart_recovery",
                "project_memory_v1_source=local_project_memory_v1",
                "configured_recent_project_dialogue_profile=standard_12_pairs",
                "recommended_recent_project_dialogue_profile=deep_20_pairs",
                "effective_recent_project_dialogue_profile=standard_12_pairs",
                "recent_project_dialogue_profile=standard_12_pairs",
                "recent_project_dialogue_selected_pairs=9",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=recent_context",
                "recent_project_dialogue_low_signal_dropped=0",
                "configured_project_context_depth=balanced",
                "recommended_project_context_depth=deep",
                "effective_project_context_depth=balanced",
                "project_context_depth=balanced",
                "effective_project_serving_profile=m2_plan_review",
                "a_tier_memory_ceiling=m3_deep_dive",
                "project_memory_ceiling_hit=false",
                "workflow_present=false",
                "execution_evidence_present=true",
                "review_guidance_present=false",
                "cross_link_hints_selected=0",
                "project_memory_selected_planes=project_dialogue_plane,project_anchor_plane,execution_state_plane,evidence_plane",
                "project_memory_selected_serving_objects=recent_project_dialogue_window,focused_project_anchor_pack,current_step,execution_evidence",
                "project_memory_automation_recovery_reason=latest_visible_stable_identity_failed",
                "project_memory_automation_recovery_hold_reason=stable_identity_failed",
                "project_memory_automation_current_step_present=true",
                "project_memory_automation_current_step_title=Verify focused smoke tests",
                "project_memory_automation_current_step_state=blocked",
                "project_memory_automation_current_step_summary=Stable identity drifted before restart recovery."
            ]
        )

        let presentation = try #require(AXProjectContextAssemblyPresentation.from(summary: summary))

        #expect(presentation.statusLine.contains("恢复链需要重新接续当前 run") == true)
        #expect(presentation.statusLine.contains("restart_recovery") == true)
        #expect(presentation.executionMetric == "step yes · recovery yes")
        #expect(presentation.executionLine?.contains("Verify focused smoke tests") == true)
        #expect(presentation.executionLine?.contains("recovery stable identity failed") == true)
        #expect(presentation.executionLine?.contains("hold stable identity failed") == true)
        #expect(presentation.userExecutionSummary?.contains("当前停在“Verify focused smoke tests”（已阻塞）") == true)
        #expect(presentation.userExecutionSummary?.contains("恢复链身份校验失败，不能自动接续") == true)
        #expect(presentation.userAssemblySummary?.contains("当前步骤") == true)
        #expect(presentation.userPlaneSummary?.contains("执行状态面") == true)
        #expect(presentation.compactSummary.detailText?.contains("恢复链身份校验失败") == true)
    }

    @Test
    func configOnlyPresentationExplainsBaselineBeforeRuntimeUsage() throws {
        let summary = AXProjectContextAssemblyDiagnosticsSummary(
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

        let presentation = try #require(AXProjectContextAssemblyPresentation.from(summary: summary))

        #expect(presentation.sourceKind == .configOnly)
        #expect(presentation.sourceBadge == "Config Only")
        #expect(presentation.projectLabel == "Bright")
        #expect(presentation.dialogueMetric.contains("Deep"))
        #expect(presentation.dialogueMetric.contains("20 pairs"))
        #expect(presentation.depthMetric == "Deep")
        #expect(presentation.coverageMetric == nil)
        #expect(presentation.boundaryMetric == nil)
        #expect(presentation.statusLine.contains("配置基线"))
        #expect(presentation.statusLine.contains("收束到 Balanced"))
        #expect(presentation.dialogueLine.contains("recommended Standard · 12 pairs"))
        #expect(presentation.depthLine.contains("recommended Lean"))
        #expect(presentation.depthLine.contains("effective Balanced"))
        #expect(presentation.depthLine.contains("ceiling m2_plan_review"))
        #expect(presentation.depthLine.contains("ceiling hit"))
        #expect(presentation.userSourceBadge == "配置基线")
        #expect(presentation.userStatusLine.contains("还没有实际运行记录"))
        #expect(presentation.userDialogueLine.contains("configured / recommended / effective"))
        #expect(presentation.userDepthLine.contains("A-tier ceiling m2_plan_review"))
        #expect(presentation.userAssemblySummary == nil)
        #expect(presentation.userOmissionSummary == nil)
        #expect(presentation.userBudgetSummary == nil)

        let compactSummary = presentation.compactSummary
        #expect(compactSummary.headlineText == "配置基线 · Deep · 20 pairs / Deep")
        #expect(compactSummary.detailText == "还没有 recent coder usage explainability，当前先按配置基线显示")
        #expect(compactSummary.helpText.contains("Project AI"))
    }

    @Test
    func latestCoderUsagePresentationIncludesRemoteSnapshotCacheStatusWhenPresent() throws {
        let summary = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=CacheScope",
                "project_memory_resolution_trigger=normal_reply",
                "project_memory_v1_source=hub_memory_v1_grpc",
                "memory_v1_freshness=ttl_cache",
                "memory_v1_cache_hit=true",
                "memory_v1_remote_snapshot_cache_scope=mode=project_chat project_id=proj-cache",
                "memory_v1_remote_snapshot_age_ms=6000",
                "memory_v1_remote_snapshot_ttl_remaining_ms=9000",
                "configured_recent_project_dialogue_profile=standard_12_pairs",
                "recommended_recent_project_dialogue_profile=standard_12_pairs",
                "effective_recent_project_dialogue_profile=standard_12_pairs",
                "recent_project_dialogue_profile=standard_12_pairs",
                "recent_project_dialogue_selected_pairs=10",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=xt_cache",
                "recent_project_dialogue_low_signal_dropped=1",
                "configured_project_context_depth=balanced",
                "recommended_project_context_depth=balanced",
                "effective_project_context_depth=balanced",
                "project_context_depth=balanced",
                "effective_project_serving_profile=m2_plan_review",
                "a_tier_memory_ceiling=m2_plan_review",
                "project_memory_ceiling_hit=false",
                "workflow_present=false",
                "execution_evidence_present=false",
                "review_guidance_present=false",
                "cross_link_hints_selected=0"
            ]
        )

        let presentation = try #require(AXProjectContextAssemblyPresentation.from(summary: summary))

        #expect(presentation.statusLine.contains("普通项目回复") == true)
        #expect(presentation.statusLine.contains("normal_reply") == true)
        #expect(presentation.userStatusLine.contains("remote snapshot：TTL cache") == true)
        #expect(presentation.userStatusLine.contains("Hub truth via XT cache") == true)
        #expect(presentation.userStatusLine.contains("age 6s") == true)
        #expect(presentation.userStatusLine.contains("ttl 剩余 9s") == true)
        #expect(presentation.userStatusLine.contains("mode=project_chat project_id=proj-cache") == true)
        #expect(presentation.compactSummary.helpText.contains("TTL cache") == true)
    }

    @Test
    func latestCoderUsagePresentationHumanizesHeartbeatDigestWorkingSetTruth() throws {
        let summary = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=HeartbeatScope",
                "project_memory_resolution_trigger=normal_reply",
                "project_memory_v1_source=hub_memory_v1_grpc",
                "configured_recent_project_dialogue_profile=standard_12_pairs",
                "recommended_recent_project_dialogue_profile=standard_12_pairs",
                "effective_recent_project_dialogue_profile=standard_12_pairs",
                "recent_project_dialogue_profile=standard_12_pairs",
                "recent_project_dialogue_selected_pairs=9",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=xt_cache",
                "recent_project_dialogue_low_signal_dropped=0",
                "configured_project_context_depth=balanced",
                "recommended_project_context_depth=balanced",
                "effective_project_context_depth=balanced",
                "project_context_depth=balanced",
                "effective_project_serving_profile=m2_plan_review",
                "a_tier_memory_ceiling=m2_plan_review",
                "project_memory_ceiling_hit=false",
                "workflow_present=false",
                "execution_evidence_present=false",
                "review_guidance_present=false",
                "cross_link_hints_selected=0",
                "project_memory_heartbeat_digest_present=true",
                "project_memory_heartbeat_digest_visibility=shown",
                "project_memory_heartbeat_digest_reason_codes=project_memory_attention"
            ]
        )

        let presentation = try #require(AXProjectContextAssemblyPresentation.from(summary: summary))

        #expect(presentation.statusLine.contains("普通项目回复") == true)
        #expect(presentation.statusLine.contains("normal_reply") == true)
        #expect(
            presentation.heartbeatDigestLine
                == "Heartbeat Digest：heartbeat digest 已作为 working-set advisory 带入本轮 Project AI 上下文 · visibility shown · reason project_memory_attention"
        )
        #expect(
            presentation.userHeartbeatSummary
                == "heartbeat digest 已作为 working-set advisory 带入本轮 Project AI 上下文 · visibility shown · reason project_memory_attention"
        )
        #expect(
            presentation.compactSummary.detailText
                == "heartbeat digest 已作为 working-set advisory 带入本轮 Project AI 上下文 · visibility shown · reason project_memory_attention"
        )
        #expect(
            presentation.compactSummary.helpText.contains(
                "heartbeat digest 已作为 working-set advisory 带入本轮 Project AI 上下文 · visibility shown · reason project_memory_attention"
            )
        )
    }
}
