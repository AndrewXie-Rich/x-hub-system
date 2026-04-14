import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct AXProjectContextAssemblyDiagnosticsTests {
    @Test
    func doctorSummaryUsesLatestCoderUsageExplainability() throws {
        let root = try makeProjectRoot(named: "project-context-diag")
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 20.0,
                "role": "coder",
                "stage": "chat_plan",
                "role_aware_memory_mode": "project_ai",
                "project_memory_resolution_trigger": "manual_review_request",
                "memory_v1_source": "hub_memory_v1_grpc",
                "configured_recent_project_dialogue_profile": "standard_12_pairs",
                "recommended_recent_project_dialogue_profile": "deep_20_pairs",
                "effective_recent_project_dialogue_profile": "deep_20_pairs",
                "recent_project_dialogue_profile": "standard_12_pairs",
                "recent_project_dialogue_selected_pairs": 12,
                "recent_project_dialogue_floor_pairs": 8,
                "recent_project_dialogue_floor_satisfied": true,
                "recent_project_dialogue_source": "recent_context",
                "recent_project_dialogue_low_signal_dropped": 1,
                "configured_project_context_depth": "balanced",
                "recommended_project_context_depth": "deep",
                "effective_project_context_depth": "deep",
                "project_context_depth": "balanced",
                "effective_project_serving_profile": "m2_plan_review",
                "a_tier_memory_ceiling": "m3_deep_dive",
                "project_memory_ceiling_hit": false,
                "workflow_present": true,
                "execution_evidence_present": false,
                "review_guidance_present": true,
                "cross_link_hints_selected": 0,
                "personal_memory_excluded_reason": "project_ai_default_scopes_to_project_memory_only",
            ],
            for: ctx
        )
        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 30.0,
                "role": "coder",
                "stage": "chat_plan",
                "role_aware_memory_mode": "project_ai",
                "project_memory_resolution_trigger": "manual_full_scan_request",
                "memory_v1_source": "local_project_memory_v1",
                "memory_v1_freshness": "ttl_cache",
                "memory_v1_cache_hit": true,
                "memory_v1_remote_snapshot_cache_scope": "mode=project_chat project_id=proj-alpha",
                "memory_v1_remote_snapshot_cached_at_ms": 1_774_000_000_000 as Int64,
                "memory_v1_remote_snapshot_age_ms": 6000,
                "memory_v1_remote_snapshot_ttl_remaining_ms": 9000,
                "configured_recent_project_dialogue_profile": "extended_40_pairs",
                "recommended_recent_project_dialogue_profile": "extended_40_pairs",
                "effective_recent_project_dialogue_profile": "extended_40_pairs",
                "recent_project_dialogue_profile": "extended_40_pairs",
                "recent_project_dialogue_selected_pairs": 18,
                "recent_project_dialogue_floor_pairs": 8,
                "recent_project_dialogue_floor_satisfied": true,
                "recent_project_dialogue_source": "xt_cache",
                "recent_project_dialogue_low_signal_dropped": 3,
                "configured_project_context_depth": "full",
                "recommended_project_context_depth": "full",
                "effective_project_context_depth": "full",
                "project_context_depth": "full",
                "effective_project_serving_profile": "m4_full_scan",
                "a_tier_memory_ceiling": "m4_full_scan",
                "project_memory_ceiling_hit": false,
                "memory_assembly_resolution": [
                    "schema_version": XTMemoryAssemblyResolution.currentSchemaVersion,
                    "role": XTMemoryAssemblyRole.projectAI.rawValue,
                    "dominant_mode": "project_ai",
                    "trigger": "manual_full_scan_request",
                    "configured_depth": "full",
                    "recommended_depth": "full",
                    "effective_depth": "full",
                    "ceiling_from_tier": "m4_full_scan",
                    "ceiling_hit": false,
                    "selected_slots": ["recent_project_dialogue", "project_anchor", "execution_evidence"],
                    "selected_planes": ["project_dialogue_plane", "project_anchor_plane", "execution_evidence_plane"],
                    "selected_serving_objects": [
                        "recent_project_dialogue",
                        "focused_project_anchor_pack",
                        "execution_evidence_pack",
                    ],
                    "excluded_blocks": [],
                    "budget_summary": "recent_dialogue=18 evidence=on",
                    "audit_ref": "test://project-context-diag/latest-resolution",
                ],
                "workflow_present": true,
                "execution_evidence_present": true,
                "review_guidance_present": true,
                "cross_link_hints_selected": 2,
                "personal_memory_excluded_reason": "project_ai_default_scopes_to_project_memory_only",
            ],
            for: ctx
        )

        let summary = AXProjectContextAssemblyDiagnosticsStore.doctorSummary(for: ctx)

        #expect(summary.latestEvent?.memoryV1Source == "local_project_memory_v1")
        #expect(summary.latestEvent?.recentProjectDialogueProfile == "extended_40_pairs")
        #expect(summary.latestEvent?.recentProjectDialogueFloorSatisfied == true)
        #expect(summary.memoryAssemblyReadiness.ready == true)
        #expect(summary.memoryAssemblyReadiness.issueCodes.isEmpty)
        #expect(summary.detailLines.contains("project_context_diagnostics_source=latest_coder_usage"))
        #expect(summary.detailLines.contains("role_aware_memory_mode=project_ai"))
        #expect(summary.detailLines.contains("project_memory_resolution_trigger=manual_full_scan_request"))
        #expect(summary.detailLines.contains("memory_v1_freshness=ttl_cache"))
        #expect(summary.detailLines.contains("memory_v1_cache_hit=true"))
        #expect(summary.detailLines.contains("memory_v1_remote_snapshot_cache_scope=mode=project_chat project_id=proj-alpha"))
        #expect(summary.detailLines.contains("memory_v1_remote_snapshot_age_ms=6000"))
        #expect(summary.detailLines.contains("memory_v1_remote_snapshot_ttl_remaining_ms=9000"))
        #expect(summary.detailLines.contains("configured_recent_project_dialogue_profile=extended_40_pairs"))
        #expect(summary.detailLines.contains("recommended_recent_project_dialogue_profile=extended_40_pairs"))
        #expect(summary.detailLines.contains("effective_recent_project_dialogue_profile=extended_40_pairs"))
        #expect(summary.detailLines.contains("recent_project_dialogue_selected_pairs=18"))
        #expect(summary.detailLines.contains("recent_project_dialogue_floor_satisfied=true"))
        #expect(summary.detailLines.contains("configured_project_context_depth=full"))
        #expect(summary.detailLines.contains("recommended_project_context_depth=full"))
        #expect(summary.detailLines.contains("effective_project_context_depth=full"))
        #expect(summary.detailLines.contains("project_context_depth=full"))
        #expect(summary.detailLines.contains("effective_project_serving_profile=m4_full_scan"))
        #expect(summary.detailLines.contains("a_tier_memory_ceiling=m4_full_scan"))
        #expect(summary.detailLines.contains("project_memory_ceiling_hit=false"))
    }

    @Test
    func doctorSummaryFallsBackToConfigWhenNoUsageExplainabilityExists() throws {
        let root = try makeProjectRoot(named: "project-context-config-fallback")
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingProjectContextAssembly(
                projectRecentDialogueProfile: .deep20Pairs,
                projectContextDepthProfile: .deep
            )

        let summary = AXProjectContextAssemblyDiagnosticsStore.doctorSummary(
            for: ctx,
            config: config
        )

        #expect(summary.latestEvent == nil)
        #expect(summary.memoryAssemblyReadiness.ready == false)
        #expect(summary.memoryAssemblyReadiness.issueCodes == ["project_memory_usage_missing"])
        #expect(summary.detailLines.contains("project_context_diagnostics_source=config_only"))
        #expect(summary.detailLines.contains("configured_recent_project_dialogue_profile=deep_20_pairs"))
        #expect(summary.detailLines.contains("configured_project_context_depth=deep"))
        #expect(summary.detailLines.contains("recommended_recent_project_dialogue_profile=standard_12_pairs"))
        #expect(summary.detailLines.contains("effective_recent_project_dialogue_profile=deep_20_pairs"))
        #expect(summary.detailLines.contains("recommended_project_context_depth=lean"))
        #expect(summary.detailLines.contains("effective_project_context_depth=balanced"))
        #expect(summary.detailLines.contains("a_tier_memory_ceiling=m2_plan_review"))
        #expect(summary.detailLines.contains("project_memory_ceiling_hit=true"))
        #expect(summary.detailLines.contains("project_context_diagnostics=no_recent_coder_usage"))
    }

    @Test
    @MainActor
    func doctorSummaryReadsStructuredProjectMemoryExplainabilityFromRuntimeUsage() async throws {
        let root = try makeProjectRoot(named: "project-context-structured-runtime")
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let session = ChatSessionModel()
        session.messages = [
            AXChatMessage(role: .user, content: "继续修当前编译错误。", createdAt: 10),
            AXChatMessage(role: .assistant, content: "我先检查当前项目状态。", createdAt: 11),
        ]
        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingHubMemoryPreference(enabled: false)
        let fields = await session.projectMemoryUsageFieldsForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nKeep the build green.",
            userText: "继续修当前编译错误",
            config: config
        )

        var usage: [String: Any] = [
            "type": "ai_usage",
            "created_at": 40.0,
            "role": "coder",
            "stage": "chat_plan",
        ]
        for (key, value) in fields {
            usage[key] = value
        }
        AXProjectStore.appendUsage(usage, for: ctx)

        let summary = AXProjectContextAssemblyDiagnosticsStore.doctorSummary(for: ctx)

        #expect(summary.latestEvent?.memoryV1Source == XTProjectMemoryGovernance.localProjectMemorySource)
        #expect(summary.latestEvent?.projectMemoryPolicy?.schemaVersion == XTProjectMemoryPolicySnapshot.currentSchemaVersion)
        #expect(summary.latestEvent?.policyMemoryAssemblyResolution?.schemaVersion == XTMemoryAssemblyResolution.currentSchemaVersion)
        #expect(summary.latestEvent?.memoryAssemblyResolution?.schemaVersion == XTMemoryAssemblyResolution.currentSchemaVersion)
        #expect(summary.latestEvent?.policyMemoryAssemblyResolution?.selectedPlanes.contains("workflow_plane") == true)
        #expect(summary.latestEvent?.policyMemoryAssemblyResolution?.selectedPlanes.contains("cross_link_plane") == true)
        #expect(summary.latestEvent?.memoryAssemblyResolution?.selectedPlanes.contains("project_dialogue_plane") == true)
        #expect(summary.latestEvent?.memoryAssemblyResolution?.selectedPlanes.contains("project_anchor_plane") == true)
        #expect(summary.memoryAssemblyReadiness.ready == false)
        #expect(summary.memoryAssemblyReadiness.issueCodes.contains("memory_resolution_projection_drift"))
        #expect(summary.latestEvent?.memoryAssemblyResolution?.selectedPlanes.contains("workflow_plane") == false)
        #expect(summary.latestEvent?.memoryAssemblyResolution?.selectedPlanes.contains("cross_link_plane") == false)
        #expect(summary.latestEvent?.memoryAssemblyResolution?.selectedServingObjects.contains("focused_project_anchor_pack") == true)
        #expect(summary.latestEvent?.memoryAssemblyResolution?.selectedServingObjects.contains("active_workflow") == false)
        #expect(summary.latestEvent?.memoryAssemblyIssueCodes.contains("memory_resolution_projection_drift") == true)
        #expect(summary.latestEvent?.workflowPresent == false)
        #expect(summary.latestEvent?.executionEvidencePresent == false)
        #expect(summary.latestEvent?.reviewGuidancePresent == false)
        #expect(summary.latestEvent?.heartbeatDigestWorkingSetPresent == false)
        #expect(summary.detailLines.contains(where: { $0.hasPrefix("project_memory_policy_json=") }))
        #expect(summary.detailLines.contains(where: { $0.hasPrefix("project_memory_policy_resolution_json=") }))
        #expect(summary.detailLines.contains(where: { $0.hasPrefix("project_memory_assembly_resolution_json=") }))
        #expect(summary.detailLines.contains("project_memory_issue_codes=memory_resolution_projection_drift"))
        #expect(summary.detailLines.contains("project_memory_heartbeat_digest_present=false"))
        #expect(
            summary.detailLines.contains(where: {
                $0.hasPrefix("project_memory_issue_memory_resolution_projection_drift=")
                    && $0.contains("policy_selected_planes=project_dialogue_plane,project_anchor_plane,workflow_plane,cross_link_plane")
                    && $0.contains("actual_selected_planes=project_dialogue_plane,project_anchor_plane")
            })
        )
        #expect(summary.detailLines.contains("project_memory_selected_planes=project_dialogue_plane,project_anchor_plane"))
    }

    @Test
    func doctorSummaryCarriesAutomationContinuityFieldsFromRuntimeUsage() throws {
        let verificationContract: [String: Any] = [
            "expected_state": "post_change_verification_passes",
            "verify_method": "project_verify_commands",
            "retry_policy": "retry_failed_verify_commands_within_budget",
            "hold_policy": "hold_for_retry_or_replan",
            "evidence_required": true,
            "trigger_action_ids": ["action-verify"],
            "verify_commands": ["swift test --filter SmokeTests"],
        ]
        let retryVerificationContract: [String: Any] = [
            "expected_state": "post_change_verification_passes",
            "verify_method": "project_verify_commands_override",
            "retry_policy": "manual_retry_or_replan",
            "hold_policy": "hold_for_retry_or_replan",
            "evidence_required": false,
            "trigger_action_ids": ["retry-action-verify"],
            "verify_commands": ["swift test --filter RetrySmokeTests"],
        ]
        let root = try makeProjectRoot(named: "project-context-automation-runtime")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 60.0,
                "role": "coder",
                "stage": "reply",
                "role_aware_memory_mode": "project_ai",
                "project_memory_resolution_trigger": "retry_execution",
                "memory_v1_source": "local_project_memory_v1",
                "configured_recent_project_dialogue_profile": "standard_12_pairs",
                "recommended_recent_project_dialogue_profile": "deep_20_pairs",
                "effective_recent_project_dialogue_profile": "standard_12_pairs",
                "recent_project_dialogue_profile": "standard_12_pairs",
                "recent_project_dialogue_selected_pairs": 10,
                "recent_project_dialogue_floor_pairs": 8,
                "recent_project_dialogue_floor_satisfied": true,
                "recent_project_dialogue_source": "recent_context",
                "recent_project_dialogue_low_signal_dropped": 0,
                "configured_project_context_depth": "balanced",
                "recommended_project_context_depth": "deep",
                "effective_project_context_depth": "balanced",
                "project_context_depth": "balanced",
                "effective_project_serving_profile": "m2_plan_review",
                "a_tier_memory_ceiling": "m3_deep_dive",
                "project_memory_ceiling_hit": false,
                "workflow_present": false,
                "execution_evidence_present": false,
                "review_guidance_present": false,
                "cross_link_hints_selected": 0,
                "memory_assembly_resolution": [
                    "schema_version": XTMemoryAssemblyResolution.currentSchemaVersion,
                    "role": XTMemoryAssemblyRole.projectAI.rawValue,
                    "trigger": "retry_execution",
                    "configured_depth": "balanced",
                    "recommended_depth": "deep",
                    "effective_depth": "balanced",
                    "ceiling_from_tier": "m3_deep_dive",
                    "ceiling_hit": false,
                    "selected_slots": [
                        "recent_project_dialogue_window",
                        "focused_project_anchor_pack",
                        "current_step",
                        "verification_state",
                        "blocker_state",
                        "retry_reason",
                    ],
                    "selected_planes": [
                        "project_dialogue_plane",
                        "project_anchor_plane",
                        "execution_state_plane",
                    ],
                    "selected_serving_objects": [
                        "recent_project_dialogue_window",
                        "focused_project_anchor_pack",
                        "current_step",
                        "verification_state",
                        "blocker_state",
                        "retry_reason",
                    ],
                    "excluded_blocks": [
                        "active_workflow",
                        "selected_cross_link_hints",
                        "execution_evidence",
                        "guidance",
                    ],
                    "budget_summary": "source=local_project_memory_v1 · used=256 · budget=1024",
                    "audit_ref": "test://project-context-automation-runtime/resolution",
                ],
                "project_memory_automation_context_source": "checkpoint+execution_report+retry_package",
                "project_memory_automation_run_id": "run-step-memory-1",
                "project_memory_automation_run_state": XTAutomationRunState.blocked.rawValue,
                "project_memory_automation_attempt": 2,
                "project_memory_automation_retry_after_seconds": 45,
                "project_memory_automation_recovery_selection": XTAutomationRecoveryCandidateSelection.latestRecoverableUnsuperseded.rawValue,
                "project_memory_automation_recovery_reason": XTAutomationRecoveryCandidateReason.latestVisibleRetryWait.rawValue,
                "project_memory_automation_recovery_decision": XTAutomationRestartRecoveryAction.hold.rawValue,
                "project_memory_automation_recovery_hold_reason": "retry_after_not_elapsed",
                "project_memory_automation_recovery_retry_after_remaining_seconds": 25,
                "project_memory_automation_current_step_present": true,
                "project_memory_automation_current_step_id": "step-verify",
                "project_memory_automation_current_step_title": "Verify focused smoke tests",
                "project_memory_automation_current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                "project_memory_automation_current_step_summary": "Waiting before retrying the reduced verify set.",
                "project_memory_automation_verification_present": true,
                "project_memory_automation_verification_required": true,
                "project_memory_automation_verification_executed": true,
                "project_memory_automation_verification_command_count": 3,
                "project_memory_automation_verification_passed_command_count": 1,
                "project_memory_automation_verification_hold_reason": "automation_verify_failed",
                "project_memory_automation_verification_contract": verificationContract,
                "project_memory_automation_blocker_present": true,
                "project_memory_automation_blocker_code": "automation_verify_failed",
                "project_memory_automation_blocker_summary": "Smoke tests are still red.",
                "project_memory_automation_blocker_stage": XTAutomationBlockerStage.verification.rawValue,
                "project_memory_automation_retry_reason_present": true,
                "project_memory_automation_retry_reason_code": "retry_verify_scope",
                "project_memory_automation_retry_reason_summary": "Retry with a reduced verify set",
                "project_memory_automation_retry_reason_strategy": "shrink_verify_scope",
                "project_memory_automation_retry_verification_contract": retryVerificationContract,
            ],
            for: ctx
        )

        let summary = AXProjectContextAssemblyDiagnosticsStore.doctorSummary(for: ctx)

        #expect(summary.latestEvent?.automationContextSource == "checkpoint+execution_report+retry_package")
        #expect(summary.latestEvent?.automationRunID == "run-step-memory-1")
        #expect(summary.latestEvent?.automationRunState == XTAutomationRunState.blocked.rawValue)
        #expect(summary.latestEvent?.automationAttempt == 2)
        #expect(summary.latestEvent?.automationRetryAfterSeconds == 45)
        #expect(summary.latestEvent?.automationRecoverySelection == XTAutomationRecoveryCandidateSelection.latestRecoverableUnsuperseded.rawValue)
        #expect(summary.latestEvent?.automationRecoveryReason == XTAutomationRecoveryCandidateReason.latestVisibleRetryWait.rawValue)
        #expect(summary.latestEvent?.automationRecoveryDecision == XTAutomationRestartRecoveryAction.hold.rawValue)
        #expect(summary.latestEvent?.automationRecoveryHoldReason == "retry_after_not_elapsed")
        #expect(summary.latestEvent?.automationRecoveryRetryAfterRemainingSeconds == 25)
        #expect(summary.latestEvent?.automationCurrentStepPresent == true)
        #expect(summary.latestEvent?.automationCurrentStepTitle == "Verify focused smoke tests")
        #expect(summary.latestEvent?.automationVerificationPresent == true)
        #expect(summary.latestEvent?.automationVerificationContract?.verifyMethod == "project_verify_commands")
        #expect(summary.latestEvent?.automationBlockerPresent == true)
        #expect(summary.latestEvent?.automationRetryReasonPresent == true)
        #expect(summary.latestEvent?.automationRetryVerificationContract?.verifyMethod == "project_verify_commands_override")
        #expect(summary.latestEvent?.memoryAssemblyResolution?.selectedPlanes.contains("execution_state_plane") == true)
        #expect(summary.latestEvent?.memoryAssemblyResolution?.selectedServingObjects.contains("current_step") == true)
        #expect(summary.latestEvent?.memoryAssemblyResolution?.selectedServingObjects.contains("verification_state") == true)
        #expect(summary.detailLines.contains("project_memory_automation_context_source=checkpoint+execution_report+retry_package"))
        #expect(summary.detailLines.contains("project_memory_automation_recovery_reason=latest_visible_retry_wait"))
        #expect(summary.detailLines.contains("project_memory_automation_recovery_hold_reason=retry_after_not_elapsed"))
        #expect(summary.detailLines.contains("project_memory_automation_current_step_title=Verify focused smoke tests"))
        #expect(summary.detailLines.contains("project_memory_automation_verification_command_count=3"))
        #expect(summary.detailLines.contains(where: { $0.hasPrefix("project_memory_automation_verification_contract_json=") && $0.contains("\"verify_method\":\"project_verify_commands\"") }))
        #expect(summary.detailLines.contains("project_memory_automation_blocker_stage=verification"))
        #expect(summary.detailLines.contains("project_memory_automation_retry_reason_strategy=shrink_verify_scope"))
        #expect(summary.detailLines.contains(where: { $0.hasPrefix("project_memory_automation_retry_verification_contract_json=") && $0.contains("\"verify_method\":\"project_verify_commands_override\"") }))
        #expect(summary.detailLines.contains("project_memory_selected_planes=project_dialogue_plane,project_anchor_plane,execution_state_plane"))
    }

    @Test
    @MainActor
    func doctorSummaryCarriesHeartbeatDigestInjectionTruthFromRuntimeUsage() async throws {
        let root = try makeProjectRoot(named: "project-context-heartbeat-digest-runtime")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let session = ChatSessionModel()
        session.messages = [
            AXChatMessage(role: .user, content: "继续推进当前实现。", createdAt: 50),
            AXChatMessage(role: .assistant, content: "我会结合 heartbeat 和记忆状态继续推进。", createdAt: 51),
        ]
        _ = try #require(
            writeHeartbeatProjection(
                ctx: ctx,
                projectId: AXProjectRegistryStore.projectId(forRoot: root),
                projectName: "Heartbeat Runtime",
                visibility: .shown,
                reasonCodes: ["project_memory_attention"],
                whatChangedText: "Project AI memory truth still needs attention.",
                whyImportantText: "Doctor 还不能确认最近一轮 coder 真正吃到了哪些 project memory。",
                systemNextStepText: "系统会继续等待下一轮 recent coder usage 补齐 machine-readable truth。",
                weakReasons: ["project_memory_attention"],
                projectMemoryReadiness: XTProjectMemoryAssemblyReadiness(
                    ready: false,
                    statusLine: "attention:project_memory_usage_missing",
                    issues: [
                        XTProjectMemoryAssemblyIssue(
                            code: "project_memory_usage_missing",
                            severity: .warning,
                            summary: "尚未捕获 Project AI 的最近一次 memory 装配真相",
                            detail: "Doctor 当前只有配置基线，还没有 recent coder usage 来证明本轮 Project AI 实际拿到了哪些 memory objects / planes。"
                        )
                    ]
                )
            )
        )

        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingHubMemoryPreference(enabled: false)
        let fields = await session.projectMemoryUsageFieldsForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nKeep memory continuity explainable.",
            userText: "继续推进当前实现",
            config: config
        )

        var usage: [String: Any] = [
            "type": "ai_usage",
            "created_at": 60.0,
            "role": "coder",
            "stage": "chat_plan",
        ]
        for (key, value) in fields {
            usage[key] = value
        }
        AXProjectStore.appendUsage(usage, for: ctx)

        let summary = AXProjectContextAssemblyDiagnosticsStore.doctorSummary(for: ctx)

        #expect(summary.latestEvent?.heartbeatDigestWorkingSetPresent == true)
        #expect(summary.latestEvent?.heartbeatDigestVisibility == "shown")
        #expect(summary.latestEvent?.heartbeatDigestReasonCodes == ["project_memory_attention"])
        #expect(summary.detailLines.contains("project_memory_heartbeat_digest_present=true"))
        #expect(summary.detailLines.contains("project_memory_heartbeat_digest_visibility=shown"))
        #expect(summary.detailLines.contains("project_memory_heartbeat_digest_reason_codes=project_memory_attention"))
    }

    @Test
    func memoryReadinessFlagsRecentDialogueFloorRegression() throws {
        let root = try makeProjectRoot(named: "project-context-floor-regression")
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 50.0,
                "role": "coder",
                "stage": "chat_plan",
                "recent_project_dialogue_profile": "standard_12_pairs",
                "recent_project_dialogue_selected_pairs": 4,
                "recent_project_dialogue_floor_pairs": 8,
                "recent_project_dialogue_floor_satisfied": false,
                "recent_project_dialogue_source": "recent_context",
                "recent_project_dialogue_low_signal_dropped": 5,
                "project_context_depth": "balanced",
                "memory_v1_source": "hub_memory_v1_grpc",
                "memory_assembly_resolution": [
                    "schema_version": XTMemoryAssemblyResolution.currentSchemaVersion,
                    "role": XTRoleAwareMemoryRole.projectAI.rawValue,
                    "trigger": "guided_execution",
                    "configured_depth": AXProjectContextDepthProfile.balanced.rawValue,
                    "recommended_depth": AXProjectContextDepthProfile.balanced.rawValue,
                    "effective_depth": AXProjectContextDepthProfile.balanced.rawValue,
                    "ceiling_from_tier": XTMemoryServingProfile.m2PlanReview.rawValue,
                    "ceiling_hit": false,
                    "selected_slots": ["recent_project_dialogue_window"],
                    "selected_planes": ["project_dialogue_plane"],
                    "selected_serving_objects": ["recent_project_dialogue_window"],
                    "excluded_blocks": []
                ]
            ],
            for: ctx
        )

        let summary = AXProjectContextAssemblyDiagnosticsStore.doctorSummary(for: ctx)

        #expect(summary.memoryAssemblyReadiness.ready == false)
        #expect(summary.memoryAssemblyReadiness.issueCodes.contains("project_recent_dialogue_floor_not_met"))
        #expect(summary.memoryAssemblyReadiness.topIssue?.detail.contains("selected_pairs=4") == true)
    }
}

private func makeProjectRoot(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("xt-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func writeHeartbeatProjection(
    ctx: AXProjectContext,
    projectId: String,
    projectName: String,
    visibility: XTHeartbeatDigestVisibilityDecision,
    reasonCodes: [String],
    whatChangedText: String,
    whyImportantText: String,
    systemNextStepText: String,
    statusDigest: String = "build continues with fresh evidence",
    currentStateSummary: String = "Build is active",
    nextStepSummary: String = "Continue current implementation slice",
    blockerSummary: String = "",
    qualityBand: HeartbeatQualityBand = .strong,
    qualityScore: Int = 88,
    weakReasons: [String] = [],
    openAnomalyTypes: [HeartbeatAnomalyType] = [],
    projectPhase: HeartbeatProjectPhase? = .build,
    executionStatus: HeartbeatExecutionStatus? = .active,
    riskTier: HeartbeatRiskTier? = .low,
    recoveryDecision: HeartbeatRecoveryDecision? = nil,
    repeatCount: Int = 0,
    projectMemoryReadiness: XTProjectMemoryAssemblyReadiness? = nil
) -> XTHeartbeatMemoryProjectionArtifact? {
    let updatedAtMs: Int64 = 1_778_901_120_000
    let openAnomalies = openAnomalyTypes.enumerated().map { index, anomalyType in
        HeartbeatAnomalyNote(
            anomalyId: "anomaly-\(projectId)-\(index)-\(anomalyType.rawValue)",
            projectId: projectId,
            anomalyType: anomalyType,
            severity: .concern,
            confidence: 0.9,
            reason: anomalyType.displayName,
            evidenceRefs: [],
            detectedAtMs: updatedAtMs,
            recommendedEscalation: .pulseReview
        )
    }
    let schedule = SupervisorReviewScheduleState(
        schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
        projectId: projectId,
        updatedAtMs: updatedAtMs,
        lastHeartbeatAtMs: updatedAtMs,
        lastObservedProgressAtMs: updatedAtMs - 20_000,
        lastPulseReviewAtMs: 0,
        lastBrainstormReviewAtMs: 0,
        lastTriggerReviewAtMs: [:],
        nextHeartbeatDueAtMs: updatedAtMs + 300_000,
        nextPulseReviewDueAtMs: updatedAtMs + 900_000,
        nextBrainstormReviewDueAtMs: updatedAtMs + 1_800_000,
        latestQualitySnapshot: nil,
        openAnomalies: openAnomalies,
        lastHeartbeatFingerprint: "hb-\(projectId)",
        lastHeartbeatRepeatCount: repeatCount,
        latestProjectPhase: projectPhase,
        latestExecutionStatus: executionStatus,
        latestRiskTier: riskTier
    )
    let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
        projectId: projectId,
        projectName: projectName,
        statusDigest: statusDigest,
        currentStateSummary: currentStateSummary,
        nextStepSummary: nextStepSummary,
        blockerSummary: blockerSummary,
        lastHeartbeatAtMs: updatedAtMs,
        latestQualityBand: qualityBand,
        latestQualityScore: qualityScore,
        weakReasons: weakReasons,
        openAnomalyTypes: openAnomalyTypes,
        projectPhase: projectPhase,
        executionStatus: executionStatus,
        riskTier: riskTier,
        cadence: makeHeartbeatCadence(updatedAtMs: updatedAtMs),
        digestExplainability: XTHeartbeatDigestExplainability(
            visibility: visibility,
            reasonCodes: reasonCodes,
            whatChangedText: whatChangedText,
            whyImportantText: whyImportantText,
            systemNextStepText: systemNextStepText
        ),
        recoveryDecision: recoveryDecision,
        projectMemoryReadiness: projectMemoryReadiness
    )
    let canonical = SupervisorProjectHeartbeatCanonicalSync.record(
        snapshot: snapshot,
        generatedAtMs: updatedAtMs
    )
    return XTHeartbeatMemoryProjectionStore.record(
        ctx: ctx,
        snapshot: snapshot,
        schedule: schedule,
        canonicalRecord: canonical,
        generatedAtMs: updatedAtMs
    )
}

private func makeHeartbeatCadence(
    updatedAtMs: Int64
) -> SupervisorCadenceExplainability {
    SupervisorCadenceExplainability(
        progressHeartbeat: SupervisorCadenceDimensionExplainability(
            dimension: .progressHeartbeat,
            configuredSeconds: 300,
            recommendedSeconds: 300,
            effectiveSeconds: 300,
            effectiveReasonCodes: ["configured"],
            nextDueAtMs: updatedAtMs + 300_000,
            nextDueReasonCodes: ["heartbeat_active"],
            isDue: false
        ),
        reviewPulse: SupervisorCadenceDimensionExplainability(
            dimension: .reviewPulse,
            configuredSeconds: 900,
            recommendedSeconds: 900,
            effectiveSeconds: 900,
            effectiveReasonCodes: ["configured"],
            nextDueAtMs: updatedAtMs + 900_000,
            nextDueReasonCodes: ["pulse_pending"],
            isDue: false
        ),
        brainstormReview: SupervisorCadenceDimensionExplainability(
            dimension: .brainstormReview,
            configuredSeconds: 1800,
            recommendedSeconds: 1800,
            effectiveSeconds: 1800,
            effectiveReasonCodes: ["configured"],
            nextDueAtMs: updatedAtMs + 1_800_000,
            nextDueReasonCodes: ["brainstorm_pending"],
            isDue: false
        ),
        eventFollowUpCooldownSeconds: 120
    )
}
