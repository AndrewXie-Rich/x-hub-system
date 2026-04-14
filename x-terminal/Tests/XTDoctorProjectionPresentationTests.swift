import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTDoctorProjectionPresentationTests {
    @Test
    func routeTruthSummaryMakesPartialProjectionBoundaryExplicit() {
        let summary = XTDoctorRouteTruthPresentation.summary(
            projection: AXModelRouteTruthProjection(
                projectionSource: "xt_model_route_diagnostics_summary",
                completeness: "partial_xt_projection",
                requestSnapshot: AXModelRouteTruthRequestSnapshot(
                    jobType: "unknown",
                    mode: "unknown",
                    projectIDPresent: "true",
                    sensitivity: "unknown",
                    trustLevel: "paired_terminal",
                    budgetClass: "paid_only",
                    remoteAllowedByPolicy: "unknown",
                    killSwitchState: "unknown"
                ),
                resolutionChain: [],
                winningProfile: AXModelRouteTruthWinningProfile(
                    resolvedProfileID: "unknown",
                    scopeKind: "unknown",
                    scopeRefRedacted: "unknown",
                    selectionStrategy: "unknown",
                    policyVersion: "unknown",
                    disabled: "unknown"
                ),
                winningBinding: AXModelRouteTruthWinningBinding(
                    bindingKind: "unknown",
                    bindingKey: "unknown",
                    provider: "mlx",
                    modelID: "mlx.qwen",
                    selectedByUser: "unknown"
                ),
                routeResult: AXModelRouteTruthRouteResult(
                    routeSource: "local_fallback_after_remote_error",
                    routeReasonCode: "remote_unreachable",
                    fallbackApplied: "true",
                    fallbackReason: "remote_unreachable",
                    remoteAllowed: "unknown",
                    auditRef: "audit-1",
                    denyCode: "unknown"
                ),
                constraintSnapshot: AXModelRouteTruthConstraintSnapshot(
                    remoteAllowedAfterUserPref: "true",
                    remoteAllowedAfterPolicy: "false",
                    budgetClass: "paid_only",
                    budgetBlocked: "false",
                    policyBlockedRemote: "true"
                )
            )
        )

        #expect(summary.title == "这次实际路由")
        #expect(summary.lines.contains("你设定的目标：Hub 还没把完整路由记录带下来；XT 目前只拿到结果投影，最近一次可见绑定是 mlx -> mlx.qwen。"))
        #expect(summary.lines.contains("这次实际命中：mlx -> mlx.qwen [local_fallback_after_remote_error]"))
        #expect(summary.lines.contains("没按预期走的原因：远端链路不可达（remote_unreachable）"))
        #expect(summary.lines.contains("当前状态说明：远端尝试没有稳定成功，当前先由本地接住；更像上游远端不可用、provider 未 ready，或执行链失败，不是 XT 静默改成本地。"))
        #expect(summary.lines.contains("明确拦截原因：这次没有明确拦截原因"))
        #expect(summary.lines.contains("远端额度与导出状态：设备信任 paired_terminal · 预算档位 paid_only · 系统策略 已拦截 · 用户偏好 已允许"))
        #expect(summary.lines.contains("数据来源：来源 xt_model_route_diagnostics_summary · 完整度 部分"))
    }

    @Test
    func routeTruthSummaryPreservesExplicitDenyCode() {
        let summary = XTDoctorRouteTruthPresentation.summary(
            projection: AXModelRouteTruthProjection(
                projectionSource: "hub_route_truth",
                completeness: "full",
                requestSnapshot: AXModelRouteTruthRequestSnapshot(
                    jobType: "chat",
                    mode: "remote",
                    projectIDPresent: "true",
                    sensitivity: "normal",
                    trustLevel: "paired_terminal",
                    budgetClass: "paid_only",
                    remoteAllowedByPolicy: "true",
                    killSwitchState: "off"
                ),
                resolutionChain: [],
                winningProfile: AXModelRouteTruthWinningProfile(
                    resolvedProfileID: "profile-1",
                    scopeKind: "project",
                    scopeRefRedacted: "project-alpha",
                    selectionStrategy: "direct",
                    policyVersion: "v1",
                    disabled: "false"
                ),
                winningBinding: AXModelRouteTruthWinningBinding(
                    bindingKind: "role",
                    bindingKey: "coder",
                    provider: "openai",
                    modelID: "gpt-5.4",
                    selectedByUser: "true"
                ),
                routeResult: AXModelRouteTruthRouteResult(
                    routeSource: "remote_error",
                    routeReasonCode: "remote_export_blocked",
                    fallbackApplied: "false",
                    fallbackReason: "none",
                    remoteAllowed: "false",
                    auditRef: "audit-2",
                    denyCode: "device_remote_export_denied"
                ),
                constraintSnapshot: AXModelRouteTruthConstraintSnapshot(
                    remoteAllowedAfterUserPref: "true",
                    remoteAllowedAfterPolicy: "false",
                    budgetClass: "paid_only",
                    budgetBlocked: "false",
                    policyBlockedRemote: "true"
                )
            )
        )

        #expect(summary.lines.contains("你设定的目标：openai -> gpt-5.4"))
        #expect(summary.lines.contains("没按预期走的原因：这次还没进入回退；最近停在 Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(summary.lines.contains("明确拦截原因：当前设备不允许远端 export（device_remote_export_denied）"))
    }

    @Test
    func routeTruthSummaryUsesFallbackReasonWhenRouteReasonCodeIsMissing() {
        let summary = XTDoctorRouteTruthPresentation.summary(
            projection: AXModelRouteTruthProjection(
                projectionSource: "hub_route_truth",
                completeness: "full",
                requestSnapshot: AXModelRouteTruthRequestSnapshot(
                    jobType: "chat",
                    mode: "remote",
                    projectIDPresent: "true",
                    sensitivity: "normal",
                    trustLevel: "paired_terminal",
                    budgetClass: "paid_only",
                    remoteAllowedByPolicy: "true",
                    killSwitchState: "off"
                ),
                resolutionChain: [],
                winningProfile: AXModelRouteTruthWinningProfile(
                    resolvedProfileID: "profile-1",
                    scopeKind: "project",
                    scopeRefRedacted: "project-alpha",
                    selectionStrategy: "direct",
                    policyVersion: "v1",
                    disabled: "false"
                ),
                winningBinding: AXModelRouteTruthWinningBinding(
                    bindingKind: "role",
                    bindingKey: "coder",
                    provider: "openai",
                    modelID: "gpt-5.4",
                    selectedByUser: "true"
                ),
                routeResult: AXModelRouteTruthRouteResult(
                    routeSource: "remote_error",
                    routeReasonCode: "",
                    fallbackApplied: "false",
                    fallbackReason: "grant_required;deny_code=remote_export_blocked",
                    remoteAllowed: "false",
                    auditRef: "audit-3",
                    denyCode: ""
                ),
                constraintSnapshot: AXModelRouteTruthConstraintSnapshot(
                    remoteAllowedAfterUserPref: "true",
                    remoteAllowedAfterPolicy: "false",
                    budgetClass: "paid_only",
                    budgetBlocked: "false",
                    policyBlockedRemote: "true"
                )
            )
        )

        #expect(summary.lines.contains("没按预期走的原因：这次还没进入回退；最近停在 Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(summary.lines.contains("当前状态说明：当前远端导出或策略边界还没放行，所以路由停在失败态。"))
        #expect(summary.lines.contains("明确拦截原因：这次没有明确拦截原因"))
    }

    @Test
    func durableCandidateMirrorSummaryExplainsBoundary() {
        let summary = XTDoctorDurableCandidateMirrorPresentation.summary(
            projection: XTUnifiedDoctorDurableCandidateMirrorProjection(
                status: .localOnly,
                target: XTSupervisorDurableCandidateMirror.mirrorTarget,
                attempted: true,
                errorCode: "remote_route_not_preferred",
                localStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
            )
        )

        #expect(summary.title == "记忆候选镜像")
        #expect(summary.lines.contains("当前状态：当前只保留 XT 本地候选"))
        #expect(summary.lines.contains("镜像目标：Hub 候选容器（影子线程）"))
        #expect(summary.lines.contains("本地存储角色：cache|fallback|edit_buffer"))
        #expect(summary.lines.contains("边界说明：XT 本地候选只作为缓存、兜底和编辑缓冲；真正的持久写入仍走 Hub Writer + Gate。"))
        #expect(summary.lines.contains("当前原因：当前远端路径不是首选"))
    }

    @Test
    func governanceRuntimeReadinessSummaryMakesConfiguredAndRuntimeReadySplitExplicit() throws {
        let summary = try #require(
            XTDoctorGovernanceRuntimeReadinessPresentation.summary(
                detailLines: [
                    "project_governance_runtime_readiness_schema_version=xhub.project_governance_runtime_readiness.v1",
                    "project_governance_configured_execution_tier=a4_openclaw",
                    "project_governance_effective_execution_tier=a4_openclaw",
                    "project_governance_configured_runtime_surface_mode=trusted_openclaw_mode",
                    "project_governance_effective_runtime_surface_mode=trusted_openclaw_mode",
                    "project_governance_runtime_surface_override_mode=none",
                    "project_governance_trusted_automation_state=blocked",
                    "project_governance_requires_a4_runtime_ready=true",
                    "project_governance_runtime_ready=false",
                    "project_governance_runtime_readiness_state=blocked",
                    "project_governance_missing_readiness=trusted_automation_not_ready,permission_owner_not_ready",
                    "project_governance_runtime_readiness_summary=A4 Agent 已配置，但 runtime ready 还没完成。",
                    "project_governance_runtime_readiness_missing_summary=缺口：受治理自动化未就绪 / 权限宿主未就绪"
                ]
            )
        )

        #expect(summary.title == "Governance Runtime Ready")
        #expect(summary.lines.contains("A-Tier 配置：a4_openclaw · 生效 a4_openclaw"))
        #expect(summary.lines.contains("Runtime Surface：配置 trusted_openclaw_mode · 生效 trusted_openclaw_mode · 收束 none"))
        #expect(summary.lines.contains("Trusted Automation：blocked"))
        #expect(summary.lines.contains("Effective Surface：device / browser / connector / extension"))
        #expect(summary.lines.contains("Runtime Ready：runtime ready：未就绪"))
        #expect(summary.lines.contains("route ready：已就绪 · A4 执行面路由已指向 trusted_openclaw_mode。"))
        #expect(summary.lines.contains("capability ready：已就绪 · A4 基线执行能力已打开；当前 surface：device / browser / connector / extension。"))
        #expect(summary.lines.contains("grant ready：未就绪 · 当前还缺 受治理自动化未就绪 / 权限宿主未就绪。"))
        #expect(summary.lines.contains("checkpoint/recovery ready：已就绪 · checkpoint / recovery 预算与自动恢复能力已就绪。"))
        #expect(summary.lines.contains("evidence/export ready：已就绪 · evidence / export 合同已要求证据闭环与 pre-done 收口。"))
        #expect(summary.lines.contains("结论：A4 Agent 已配置，但 runtime ready 还没完成。"))
        #expect(summary.lines.contains("缺口：受治理自动化未就绪 / 权限宿主未就绪"))
    }

    @Test
    func supervisorGuidanceContinuitySummaryExplainsAckAndSafePoint() throws {
        let projection = try #require(
            XTUnifiedDoctorSupervisorGuidanceContinuityProjection.from(
                detailLines: [
                    "supervisor_review_guidance_carrier_present=true",
                    "supervisor_memory_latest_review_note_available=true",
                    "supervisor_memory_latest_review_note_actualized=true",
                    "supervisor_memory_latest_guidance_available=true",
                    "supervisor_memory_latest_guidance_actualized=true",
                    "supervisor_memory_latest_guidance_ack_status=deferred",
                    "supervisor_memory_latest_guidance_ack_required=true",
                    "supervisor_memory_latest_guidance_delivery_mode=priority_insert",
                    "supervisor_memory_latest_guidance_intervention_mode=suggest_next_safe_point",
                    "supervisor_memory_latest_guidance_safe_point_policy=next_tool_boundary",
                    "supervisor_memory_pending_ack_guidance_available=true",
                    "supervisor_memory_pending_ack_guidance_actualized=true",
                    "supervisor_memory_pending_ack_guidance_ack_status=pending",
                    "supervisor_memory_pending_ack_guidance_ack_required=true",
                    "supervisor_memory_pending_ack_guidance_delivery_mode=replan_request",
                    "supervisor_memory_pending_ack_guidance_intervention_mode=replan_next_safe_point",
                    "supervisor_memory_pending_ack_guidance_safe_point_policy=next_step_boundary",
                    "Review / Guidance：latest review carried · latest guidance carried [ack=deferred · required · safe_point=next_tool_boundary] · pending guidance carried [ack=pending · required · safe_point=next_step_boundary]"
                ]
            )
        )
        let summary = XTDoctorSupervisorGuidanceContinuityPresentation.summary(
            projection: projection
        )

        #expect(summary.title == "Supervisor Review / Guidance")
        #expect(summary.lines.contains("连续性载体：本次 Supervisor memory 装配已带上 review / guidance carrier"))
        #expect(summary.lines.contains("最近 Review：已发现 latest review note，且这次已带入 Supervisor memory"))
        #expect(summary.lines.contains("最近 Guidance：已带入 Supervisor memory · ack 已暂缓 · 需要 ack · 投递 优先插入 · 介入 安全点建议 · safe point 下一个工具边界"))
        #expect(summary.lines.contains("待确认 Guidance：已带入 Supervisor memory · ack 待确认 · 需要 ack · 投递 请求重规划 · 介入 安全点重规划 · safe point 下一步边界"))
        #expect(summary.lines.contains("实际挂载引用：latest review note、latest guidance、pending guidance"))
        #expect(summary.lines.contains("结论：latest review carried · latest guidance carried [ack=deferred · required · safe_point=next_tool_boundary] · pending guidance carried [ack=pending · required · safe_point=next_step_boundary]"))
    }

    @Test
    func supervisorSafePointTimelineSummaryExplainsDeliveryBoundaryAndPausePosture() throws {
        let projection = try #require(
            XTUnifiedDoctorSupervisorSafePointTimelineProjection.from(
                detailLines: [
                    "supervisor_safe_point_pending_guidance_available=true",
                    "supervisor_safe_point_pending_guidance_injection_id=guidance-next-tool",
                    "supervisor_safe_point_pending_guidance_delivery_mode=priority_insert",
                    "supervisor_safe_point_pending_guidance_intervention_mode=suggest_next_safe_point",
                    "supervisor_safe_point_pending_guidance_safe_point_policy=next_tool_boundary",
                    "supervisor_safe_point_live_state_source=pending_tool_approval",
                    "supervisor_safe_point_flow_step=1",
                    "supervisor_safe_point_tool_results_count=1",
                    "supervisor_safe_point_verify_run_index=0",
                    "supervisor_safe_point_finalize_only=false",
                    "supervisor_safe_point_checkpoint_reached=false",
                    "supervisor_safe_point_prompt_visible_now=false",
                    "supervisor_safe_point_visible_from_pre_run_memory=false",
                    "supervisor_safe_point_pause_recorded=false",
                    "supervisor_safe_point_deliverable_now=true",
                    "supervisor_safe_point_should_pause_tool_batch_after_boundary=true",
                    "supervisor_safe_point_delivery_state=deliverable_now",
                    "supervisor_safe_point_execution_gate=normal",
                    "Safe Point：pending guidance 当前可立即投递 · execution_gate=normal · pause_after_tool_boundary"
                ]
            )
        )
        let summary = XTDoctorSupervisorSafePointTimelinePresentation.summary(
            projection: projection
        )

        #expect(summary.title == "Supervisor Safe Point")
        #expect(summary.lines.contains("状态来源：当前根据 pending tool approval 恢复 live safe-point state"))
        #expect(summary.lines.contains("待投递 Guidance：injection guidance-next-tool · 投递 优先插入 · 介入 安全点建议 · safe point 下一个工具边界"))
        #expect(summary.lines.contains("当前执行位置：step 1 · tool 结果 1 · verify 0 · 非 finalize-only · checkpoint 未到"))
        #expect(summary.lines.contains("投递姿态：当前 prompt 还不可见 · 当前可投递 · 工具边界后应暂停剩余 batch"))
        #expect(summary.lines.contains("当前判定：当前已经到达 safe point，可以立刻把 guidance 投递给 Project AI"))
        #expect(summary.lines.contains("执行闸门：normal"))
        #expect(summary.lines.contains("结论：pending guidance 当前可立即投递 · execution_gate=normal · pause_after_tool_boundary"))
    }

    @Test
    func supervisorReviewTriggerSummaryExplainsPolicyCandidateQueueAndLatestReview() {
        let summary = XTDoctorSupervisorReviewTriggerPresentation.summary(
            projection: XTUnifiedDoctorSupervisorReviewTriggerProjection(
                reviewPolicyMode: AXProjectReviewPolicyMode.hybrid.rawValue,
                eventDrivenReviewEnabled: true,
                eventFollowUpCadenceLabel: "cadence=active · blocker cooldown≈300s",
                mandatoryReviewTriggers: [
                    AXProjectReviewTrigger.blockerDetected.rawValue,
                    AXProjectReviewTrigger.planDrift.rawValue,
                    AXProjectReviewTrigger.preDoneSummary.rawValue
                ],
                effectiveEventReviewTriggers: [
                    AXProjectReviewTrigger.blockerDetected.rawValue,
                    AXProjectReviewTrigger.planDrift.rawValue,
                    AXProjectReviewTrigger.preDoneSummary.rawValue
                ],
                derivedReviewTriggers: [
                    SupervisorReviewTrigger.manualRequest.rawValue,
                    SupervisorReviewTrigger.userOverride.rawValue,
                    SupervisorReviewTrigger.periodicPulse.rawValue,
                    SupervisorReviewTrigger.noProgressWindow.rawValue
                ],
                activeCandidateAvailable: true,
                activeCandidateTrigger: SupervisorReviewTrigger.blockerDetected.rawValue,
                activeCandidateRunKind: SupervisorReviewRunKind.eventDriven.rawValue,
                activeCandidateReviewLevel: SupervisorReviewLevel.r2Strategic.rawValue,
                activeCandidatePriority: 310,
                activeCandidatePolicyReason: "event_trigger=blocker_detected quality=weak anomalies=none repeat=0 depth=execution_ready",
                activeCandidateQueued: true,
                queuedReviewTrigger: SupervisorReviewTrigger.blockerDetected.rawValue,
                queuedReviewRunKind: SupervisorReviewRunKind.eventDriven.rawValue,
                queuedReviewLevel: SupervisorReviewLevel.r2Strategic.rawValue,
                latestReviewSource: "review_note_store",
                latestReviewTrigger: SupervisorReviewTrigger.preDoneSummary.rawValue,
                latestReviewLevel: SupervisorReviewLevel.r3Rescue.rawValue,
                latestReviewAtMs: 1_773_900_300_000,
                lastPulseReviewAtMs: 1_773_899_700_000,
                lastBrainstormReviewAtMs: 1_773_899_100_000,
                summaryLine: "Review Trigger：当前候选 blocker_detected / r2_strategic / event_driven · 已进入治理排队 · review_policy=hybrid · event_driven=true · latest_review=pre_done_summary"
            )
        )

        #expect(summary.title == "Supervisor Review Trigger")
        #expect(summary.lines.contains("Review Policy：混合 · event-driven 开启"))
        #expect(summary.lines.contains("事件跟进节奏：active · blocker cooldown≈300s"))
        #expect(summary.lines.contains("硬检查点：发现阻塞、计划漂移、完成前审查"))
        #expect(summary.lines.contains("事件触发：发现阻塞、计划漂移、完成前审查"))
        #expect(summary.lines.contains("派生触发：手动请求、用户覆盖、周期脉冲审查、进展停滞"))
        #expect(summary.lines.contains("当前候选：发现阻塞 · 事件触发 · 一次战略复盘 · priority 310 · 已进入治理排队"))
        #expect(summary.lines.contains("最近落盘 Review：review note store · 完成前审查 · 一次救援复盘 · at 1773900300000 ms"))
        #expect(summary.lines.contains("节奏足迹：pulse 1773899700000 ms · brainstorm 1773899100000 ms"))
        #expect(summary.lines.contains("结论：当前候选 blocker_detected / r2_strategic / event_driven · 已进入治理排队 · review_policy=hybrid · event_driven=true · latest_review=pre_done_summary"))
    }

    @Test
    func skillDoctorTruthSummarySurfacesTypedReadinessAndProfileBands() {
        let summary = XTDoctorSkillDoctorTruthPresentation.summary(
            projection: sampleSkillDoctorTruthProjection()
        )

        #expect(summary.title == "技能 Doctor Truth")
        #expect(summary.lines.contains("项目能力画像：执行层级 a4_openclaw · runtime surface paired_hub · Hub 覆盖 inherit · 本地自动批准关闭 · trusted automation 已就绪"))
        #expect(summary.lines.contains("当前可直接运行：observe_only"))
        #expect(summary.lines.contains("能力分层：runnable observe_only · grant browser_research · local approval browser_operator · blocked delivery"))
        #expect(summary.lines.contains("技能计数：已安装 4 · 已就绪 1 · 待 Hub grant 1 · 待本地确认 1 · 阻塞 1 · 降级 0"))
        #expect(summary.lines.contains("待 Hub grant：tavily-websearch（grant required） · profiles browser_research · grant floor readonly still pending · grant=readonly · approval=hub_grant · unblock=request_hub_grant"))
        #expect(summary.lines.contains("待本地确认：browser-operator（local approval required） · profiles browser_operator · local approval still pending · approval=local_approval · unblock=request_local_approval"))
        #expect(summary.lines.contains("当前阻塞：delivery-runner（policy clamped） · profiles delivery · project capability bundle blocks repo.delivery · grant=privileged · approval=hub_grant_plus_local_approval · unblock=raise_execution_tier"))
        #expect(summary.lines.contains("边界说明：这里只是 XT 基于 project effective skill profile + typed readiness 生成的 doctor 投影，不替代 Hub grant / revocation / registry 主真相。"))
    }

    @Test
    func heartbeatGovernanceSummaryIncludesLocalizedRecoveryDecisionExplainability() {
        let summary = XTDoctorHeartbeatGovernancePresentation.summary(
            projection: XTUnifiedDoctorHeartbeatGovernanceProjection(
                projectId: "project-alpha",
                projectName: "Alpha",
                statusDigest: "Done candidate waiting for review",
                currentStateSummary: "Validation is wrapping up for release",
                nextStepSummary: "",
                blockerSummary: "",
                lastHeartbeatAtMs: 1_773_900_000_000,
                latestQualityBand: HeartbeatQualityBand.weak.rawValue,
                latestQualityScore: 38,
                weakReasons: ["completion_confidence_low"],
                openAnomalyTypes: [HeartbeatAnomalyType.weakDoneClaim.rawValue],
                projectPhase: HeartbeatProjectPhase.release.rawValue,
                executionStatus: HeartbeatExecutionStatus.doneCandidate.rawValue,
                riskTier: HeartbeatRiskTier.high.rawValue,
                digestVisibility: XTHeartbeatDigestVisibilityDecision.shown.rawValue,
                digestReasonCodes: ["weak_done_claim", "review_candidate_active"],
                digestWhatChangedText: "项目已接近完成，但完成声明证据偏弱。",
                digestWhyImportantText: "完成声明证据偏弱，系统不能把“快做完了”直接当成真实完成。",
                digestSystemNextStepText: "系统会先基于事件触发 · pre-done 信号排队一次救援复盘，并在下一个 safe point 注入 guidance。",
                progressHeartbeat: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.progressHeartbeat.rawValue,
                    configuredSeconds: 600,
                    recommendedSeconds: 180,
                    effectiveSeconds: 180,
                    effectiveReasonCodes: ["adjusted_for_project_phase_release"]
                ),
                reviewPulse: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.reviewPulse.rawValue,
                    configuredSeconds: 1_200,
                    recommendedSeconds: 600,
                    effectiveSeconds: 600,
                    effectiveReasonCodes: ["tightened_for_done_candidate_status"]
                ),
                brainstormReview: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.brainstormReview.rawValue,
                    configuredSeconds: 2_400,
                    recommendedSeconds: 1_200,
                    effectiveSeconds: 1_200,
                    effectiveReasonCodes: ["adjusted_for_project_phase_release"]
                ),
                nextReviewDue: XTUnifiedDoctorHeartbeatNextReviewDueProjection(
                    kind: SupervisorCadenceDimension.reviewPulse.rawValue,
                    due: true,
                    atMs: 1_773_900_600_000,
                    reasonCodes: ["pulse_review_window_elapsed"]
                ),
                recoveryDecision: XTUnifiedDoctorHeartbeatRecoveryProjection(
                    action: HeartbeatRecoveryAction.queueStrategicReview.rawValue,
                    urgency: HeartbeatRecoveryUrgency.urgent.rawValue,
                    reasonCode: "heartbeat_or_lane_signal_requires_governance_review",
                    summary: "Queue a deeper governance review before resuming autonomous execution.",
                    sourceSignals: [
                        "anomaly:weak_done_claim",
                        "review_candidate:pre_done_summary:r3_rescue:event_driven"
                    ],
                    anomalyTypes: [HeartbeatAnomalyType.weakDoneClaim.rawValue],
                    blockedLaneReasons: [],
                    blockedLaneCount: 0,
                    stalledLaneCount: 0,
                    failedLaneCount: 0,
                    recoveringLaneCount: 0,
                    requiresUserAction: false,
                    queuedReviewTrigger: SupervisorReviewTrigger.preDoneSummary.rawValue,
                    queuedReviewLevel: SupervisorReviewLevel.r3Rescue.rawValue,
                    queuedReviewRunKind: SupervisorReviewRunKind.eventDriven.rawValue
                )
            )
        )

        let recoveryLine = summary.lines.first { $0.hasPrefix("恢复决策：") }
        #expect(summary.title == "Heartbeat 治理")
        #expect(summary.lines.contains("项目态势：Done candidate waiting for review · 阶段 发布 · 执行态 完成候选 · 风险 高"))
        #expect(summary.lines.contains("最近质量：偏弱（38 分） · 异常 完成声明证据偏弱 · 弱项 完成把握偏低 · 最近心跳 1773900000000 ms"))
        #expect(summary.lines.contains("Digest 决策：这条 digest 会显示给用户 · 原因 完成声明证据偏弱、当前有待执行复盘候选"))
        #expect(summary.lines.contains("脉冲复盘：配置 1200s / 建议 600s / 实际 600s · 原因 因进入 done candidate 而进一步收紧完成前复核"))
        #expect(summary.lines.contains("下一次 Review：脉冲复盘 · 已到期 · at 1773900600000 ms · 原因 脉冲复盘窗口已到"))
        #expect(recoveryLine?.contains("动作 排队治理复盘") == true)
        #expect(recoveryLine?.contains("救援复盘") == true)
        #expect(recoveryLine?.contains("紧急处理") == true)
        #expect(recoveryLine?.contains("heartbeat 或 lane 信号要求先做治理复盘") == true)
        #expect(recoveryLine?.contains("复盘候选 pre-done 信号 / 一次救援复盘 / 事件触发") == true)
        #expect(recoveryLine?.contains("异常 完成声明证据偏弱") == true)
        #expect(recoveryLine?.contains("Queue a deeper governance review") == false)
    }

    @Test
    func heartbeatGovernanceSummaryExplainsSuppressedDigestDecision() {
        let summary = XTDoctorHeartbeatGovernancePresentation.summary(
            projection: XTUnifiedDoctorHeartbeatGovernanceProjection(
                projectId: "project-gamma",
                projectName: "Gamma",
                statusDigest: "Stable verification run",
                currentStateSummary: "Validation remains on track",
                nextStepSummary: "Wait for a meaningful project delta before notifying the user",
                blockerSummary: "",
                lastHeartbeatAtMs: 1_773_920_000_000,
                latestQualityBand: HeartbeatQualityBand.usable.rawValue,
                latestQualityScore: 82,
                weakReasons: [],
                openAnomalyTypes: [],
                projectPhase: HeartbeatProjectPhase.verify.rawValue,
                executionStatus: HeartbeatExecutionStatus.active.rawValue,
                riskTier: HeartbeatRiskTier.medium.rawValue,
                digestVisibility: XTHeartbeatDigestVisibilityDecision.suppressed.rawValue,
                digestReasonCodes: ["stable_runtime_update_suppressed"],
                digestWhatChangedText: "Validation remains on track",
                digestWhyImportantText: "当前没有新的高风险或高优先级治理信号，所以这条 digest 被压制。",
                digestSystemNextStepText: "系统会继续观察当前项目，有实质变化再生成用户 digest。",
                progressHeartbeat: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.progressHeartbeat.rawValue,
                    configuredSeconds: 600,
                    recommendedSeconds: 300,
                    effectiveSeconds: 300,
                    effectiveReasonCodes: ["adjusted_for_verification_phase"]
                ),
                reviewPulse: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.reviewPulse.rawValue,
                    configuredSeconds: 1_200,
                    recommendedSeconds: 1_200,
                    effectiveSeconds: 1_200,
                    effectiveReasonCodes: ["configured_equals_recommended"]
                ),
                brainstormReview: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.brainstormReview.rawValue,
                    configuredSeconds: 2_400,
                    recommendedSeconds: 2_400,
                    effectiveSeconds: 2_400,
                    effectiveReasonCodes: ["configured_equals_recommended"]
                ),
                nextReviewDue: XTUnifiedDoctorHeartbeatNextReviewDueProjection(
                    kind: SupervisorCadenceDimension.reviewPulse.rawValue,
                    due: false,
                    atMs: 1_773_921_200_000,
                    reasonCodes: ["waiting_for_review_window"]
                ),
                recoveryDecision: nil
            )
        )

        let digestLine = summary.lines.first { $0.hasPrefix("Digest 决策：") }
        let whyLine = summary.lines.first { $0.hasPrefix("为什么会看到 / 看不到：") }
        let nextStepLine = summary.lines.first { $0.hasPrefix("系统准备怎么做：") }

        #expect(summary.title == "Heartbeat 治理")
        #expect(digestLine?.contains("当前会被压制") == true)
        #expect(digestLine?.contains("当前只是稳定运行更新，暂不打扰用户") == true)
        #expect(whyLine?.contains("digest 被压制") == true)
        #expect(nextStepLine?.contains("有实质变化再生成用户 digest") == true)
        #expect(summary.lines.contains("脉冲复盘：配置 1200s / 建议 1200s / 实际 1200s · 原因 当前配置已经等于协议建议值"))
        #expect(summary.lines.contains("下一次 Review：脉冲复盘 · 未到期 · at 1773921200000 ms · 原因 当前 review 窗口尚未走完"))
        #expect(summary.lines.contains(where: { $0.hasPrefix("恢复决策：") }) == false)
    }

    @Test
    func heartbeatGovernanceSummaryMarksUserActionRequirementForGrantFollowUpRecovery() {
        let summary = XTDoctorHeartbeatGovernancePresentation.summary(
            projection: XTUnifiedDoctorHeartbeatGovernanceProjection(
                projectId: "project-beta",
                projectName: "Beta",
                statusDigest: "Waiting for repo write grant",
                currentStateSummary: "Automation is paused on grant review",
                nextStepSummary: "",
                blockerSummary: "",
                lastHeartbeatAtMs: 1_773_910_000_000,
                latestQualityBand: HeartbeatQualityBand.usable.rawValue,
                latestQualityScore: 71,
                weakReasons: [],
                openAnomalyTypes: [],
                projectPhase: HeartbeatProjectPhase.build.rawValue,
                executionStatus: HeartbeatExecutionStatus.blocked.rawValue,
                riskTier: HeartbeatRiskTier.medium.rawValue,
                digestVisibility: XTHeartbeatDigestVisibilityDecision.shown.rawValue,
                digestReasonCodes: ["recovery_decision_active"],
                digestWhatChangedText: "当前项目状态没有新的高信号变化。",
                digestWhyImportantText: "系统已判断需要恢复或补救动作，不能把当前状态当成正常推进。",
                digestSystemNextStepText: "系统会先发起所需 grant 跟进，待放行后再继续恢复执行。",
                progressHeartbeat: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.progressHeartbeat.rawValue,
                    configuredSeconds: 300,
                    recommendedSeconds: 300,
                    effectiveSeconds: 300,
                    effectiveReasonCodes: []
                ),
                reviewPulse: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.reviewPulse.rawValue,
                    configuredSeconds: 900,
                    recommendedSeconds: 900,
                    effectiveSeconds: 900,
                    effectiveReasonCodes: []
                ),
                brainstormReview: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.brainstormReview.rawValue,
                    configuredSeconds: 1_800,
                    recommendedSeconds: 1_800,
                    effectiveSeconds: 1_800,
                    effectiveReasonCodes: []
                ),
                nextReviewDue: XTUnifiedDoctorHeartbeatNextReviewDueProjection(
                    kind: SupervisorCadenceDimension.reviewPulse.rawValue,
                    due: false,
                    atMs: 1_773_910_900_000,
                    reasonCodes: ["waiting_for_review_window"]
                ),
                recoveryDecision: XTUnifiedDoctorHeartbeatRecoveryProjection(
                    action: HeartbeatRecoveryAction.requestGrantFollowUp.rawValue,
                    urgency: HeartbeatRecoveryUrgency.active.rawValue,
                    reasonCode: "grant_follow_up_required",
                    summary: "Request the required grant follow-up before resuming autonomous execution.",
                    sourceSignals: ["lane_blocked_reason:grant_pending", "lane_blocked_count:1"],
                    anomalyTypes: [],
                    blockedLaneReasons: [LaneBlockedReason.grantPending.rawValue],
                    blockedLaneCount: 1,
                    stalledLaneCount: 0,
                    failedLaneCount: 0,
                    recoveringLaneCount: 0,
                    requiresUserAction: true,
                    queuedReviewTrigger: nil,
                    queuedReviewLevel: nil,
                    queuedReviewRunKind: nil
                )
            )
        )

        let recoveryLine = summary.lines.first { $0.hasPrefix("恢复决策：") }
        #expect(recoveryLine?.contains("动作 grant / 授权跟进") == true)
        #expect(recoveryLine?.contains("发起所需 grant 跟进") == true)
        #expect(recoveryLine?.contains("主动处理") == true)
        #expect(recoveryLine?.contains("需要用户动作") == true)
        #expect(recoveryLine?.contains("阻塞原因 等待授权") == true)
        #expect(recoveryLine?.contains("信号 阻塞 lane 1 条") == true)
        #expect(recoveryLine?.contains("Queue a deeper governance review") == false)
    }

    @Test
    func heartbeatGovernanceSummaryExplainsReplayFollowUpRecovery() {
        let summary = XTDoctorHeartbeatGovernancePresentation.summary(
            projection: XTUnifiedDoctorHeartbeatGovernanceProjection(
                projectId: "project-replay",
                projectName: "Replay",
                statusDigest: "Queue stalled during drain recovery",
                currentStateSummary: "Execution queue is stalled during drain recovery",
                nextStepSummary: "",
                blockerSummary: "Drain replay pending",
                lastHeartbeatAtMs: 1_773_915_000_000,
                latestQualityBand: HeartbeatQualityBand.weak.rawValue,
                latestQualityScore: 54,
                weakReasons: [],
                openAnomalyTypes: [HeartbeatAnomalyType.queueStall.rawValue],
                projectPhase: HeartbeatProjectPhase.verify.rawValue,
                executionStatus: HeartbeatExecutionStatus.blocked.rawValue,
                riskTier: HeartbeatRiskTier.medium.rawValue,
                digestVisibility: XTHeartbeatDigestVisibilityDecision.shown.rawValue,
                digestReasonCodes: ["recovery_decision_active"],
                digestWhatChangedText: "当前项目没有新的高信号进展，但 follow-up 恢复动作已经激活。",
                digestWhyImportantText: "系统已判断当前要先修复挂起的续跑链，不能把状态当成正常推进。",
                digestSystemNextStepText: "系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链，再确认执行是否恢复。",
                progressHeartbeat: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.progressHeartbeat.rawValue,
                    configuredSeconds: 300,
                    recommendedSeconds: 300,
                    effectiveSeconds: 300,
                    effectiveReasonCodes: []
                ),
                reviewPulse: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.reviewPulse.rawValue,
                    configuredSeconds: 900,
                    recommendedSeconds: 900,
                    effectiveSeconds: 900,
                    effectiveReasonCodes: []
                ),
                brainstormReview: XTUnifiedDoctorHeartbeatCadenceDimensionProjection(
                    dimension: SupervisorCadenceDimension.brainstormReview.rawValue,
                    configuredSeconds: 1_800,
                    recommendedSeconds: 1_800,
                    effectiveSeconds: 1_800,
                    effectiveReasonCodes: []
                ),
                nextReviewDue: XTUnifiedDoctorHeartbeatNextReviewDueProjection(
                    kind: SupervisorCadenceDimension.reviewPulse.rawValue,
                    due: false,
                    atMs: 1_773_915_900_000,
                    reasonCodes: ["waiting_for_review_window"]
                ),
                recoveryDecision: XTUnifiedDoctorHeartbeatRecoveryProjection(
                    action: HeartbeatRecoveryAction.replayFollowUp.rawValue,
                    urgency: HeartbeatRecoveryUrgency.active.rawValue,
                    reasonCode: "restart_drain_requires_follow_up_replay",
                    summary: "Replay the pending follow-up or recovery chain after the current drain finishes.",
                    sourceSignals: [
                        "anomaly:queue_stall",
                        "lane_blocked_reason:restart_drain",
                        "lane_blocked_count:1"
                    ],
                    anomalyTypes: [HeartbeatAnomalyType.queueStall.rawValue],
                    blockedLaneReasons: [LaneBlockedReason.restartDrain.rawValue],
                    blockedLaneCount: 1,
                    stalledLaneCount: 0,
                    failedLaneCount: 0,
                    recoveringLaneCount: 0,
                    requiresUserAction: false,
                    queuedReviewTrigger: SupervisorReviewTrigger.blockerDetected.rawValue,
                    queuedReviewLevel: SupervisorReviewLevel.r2Strategic.rawValue,
                    queuedReviewRunKind: SupervisorReviewRunKind.eventDriven.rawValue
                )
            )
        )

        let recoveryLine = summary.lines.first { $0.hasPrefix("恢复决策：") }
        #expect(recoveryLine?.contains("动作 重放 follow-up / 续跑链") == true)
        #expect(recoveryLine?.contains("重放挂起的 follow-up") == true)
        #expect(recoveryLine?.contains("主动处理") == true)
        #expect(recoveryLine?.contains("当前 drain 收口后需要重放 follow-up") == true)
        #expect(recoveryLine?.contains("异常 队列停滞") == true)
        #expect(recoveryLine?.contains("阻塞原因 等待 drain 恢复") == true)
        #expect(recoveryLine?.contains("信号 阻塞 lane 1 条") == true)
        #expect(recoveryLine?.contains("Replay the pending follow-up") == false)
    }
}

private func sampleSkillDoctorTruthProjection() -> XTUnifiedDoctorSkillDoctorTruthProjection {
    XTUnifiedDoctorSkillDoctorTruthProjection(
        effectiveProfileSnapshot: XTProjectEffectiveSkillProfileSnapshot(
            schemaVersion: XTProjectEffectiveSkillProfileSnapshot.currentSchemaVersion,
            projectId: "project-alpha",
            projectName: "Alpha",
            source: "xt_project_governance+hub_skill_registry",
            executionTier: "a4_openclaw",
            runtimeSurfaceMode: "paired_hub",
            hubOverrideMode: "inherit",
            legacyToolProfile: "openclaw",
            discoverableProfiles: ["observe_only", "browser_research", "browser_operator", "delivery"],
            installableProfiles: ["observe_only", "browser_research", "browser_operator", "delivery"],
            requestableProfiles: ["observe_only", "browser_research", "browser_operator", "delivery"],
            runnableNowProfiles: ["observe_only"],
            grantRequiredProfiles: ["browser_research"],
            approvalRequiredProfiles: ["browser_operator"],
            blockedProfiles: [
                XTProjectEffectiveSkillBlockedProfile(
                    profileID: "delivery",
                    reasonCode: "policy_clamped",
                    state: XTSkillExecutionReadinessState.policyClamped.rawValue,
                    source: "project_governance",
                    unblockActions: ["raise_execution_tier"]
                )
            ],
            ceilingCapabilityFamilies: ["skills.discover", "web.live", "browser.interact"],
            runnableCapabilityFamilies: ["skills.discover"],
            localAutoApproveEnabled: false,
            trustedAutomationReady: true,
            profileEpoch: "epoch-1",
            trustRootSetHash: "trust-root-1",
            revocationEpoch: "revocation-1",
            officialChannelSnapshotID: "channel-1",
            runtimeSurfaceHash: "surface-1",
            auditRef: "audit-xt-skill-profile-alpha"
        ),
        governanceEntries: [
            sampleSkillGovernanceEntry(
                skillID: "find-skills",
                executionReadiness: XTSkillExecutionReadinessState.ready.rawValue,
                capabilityProfiles: ["observe_only"],
                capabilityFamilies: ["skills.discover"]
            ),
            sampleSkillGovernanceEntry(
                skillID: "tavily-websearch",
                executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
                whyNotRunnable: "grant floor readonly still pending",
                grantFloor: XTSkillGrantFloor.readonly.rawValue,
                approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
                capabilityProfiles: ["browser_research"],
                capabilityFamilies: ["web.live"],
                unblockActions: ["request_hub_grant"]
            ),
            sampleSkillGovernanceEntry(
                skillID: "browser-operator",
                executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
                whyNotRunnable: "local approval still pending",
                grantFloor: XTSkillGrantFloor.none.rawValue,
                approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
                capabilityProfiles: ["browser_operator"],
                capabilityFamilies: ["browser.interact"],
                unblockActions: ["request_local_approval"]
            ),
            sampleSkillGovernanceEntry(
                skillID: "delivery-runner",
                executionReadiness: XTSkillExecutionReadinessState.policyClamped.rawValue,
                whyNotRunnable: "project capability bundle blocks repo.delivery",
                grantFloor: XTSkillGrantFloor.privileged.rawValue,
                approvalFloor: XTSkillApprovalFloor.hubGrantPlusLocalApproval.rawValue,
                capabilityProfiles: ["delivery"],
                capabilityFamilies: ["repo.delivery"],
                unblockActions: ["raise_execution_tier"]
            )
        ]
    )
}

private func sampleSkillGovernanceEntry(
    skillID: String,
    executionReadiness: String,
    whyNotRunnable: String = "",
    grantFloor: String = XTSkillGrantFloor.none.rawValue,
    approvalFloor: String = XTSkillApprovalFloor.none.rawValue,
    capabilityProfiles: [String],
    capabilityFamilies: [String],
    unblockActions: [String] = []
) -> AXSkillGovernanceSurfaceEntry {
    let readinessState = XTSkillCapabilityProfileSupport.readinessState(from: executionReadiness)
    let tone: AXSkillGovernanceTone = {
        switch readinessState {
        case .ready:
            return .ready
        case .grantRequired, .localApprovalRequired, .degraded:
            return .warning
        default:
            return .blocked
        }
    }()

    return AXSkillGovernanceSurfaceEntry(
        skillID: skillID,
        name: skillID,
        version: "1.0.0",
        riskLevel: "medium",
        packageSHA256: "sha-\(skillID)",
        publisherID: "publisher.test",
        sourceID: "source.test",
        policyScope: "project",
        tone: tone,
        stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(executionReadiness),
        intentFamilies: ["test.intent"],
        capabilityFamilies: capabilityFamilies,
        capabilityProfiles: capabilityProfiles,
        grantFloor: grantFloor,
        approvalFloor: approvalFloor,
        discoverabilityState: "discoverable",
        installabilityState: "installable",
        requestabilityState: "requestable",
        executionReadiness: executionReadiness,
        whyNotRunnable: whyNotRunnable,
        unblockActions: unblockActions,
        trustRootValue: "trusted",
        pinnedVersionValue: "1.0.0",
        runnerRequirementValue: "xt_builtin",
        compatibilityStatusValue: "compatible",
        preflightResultValue: "ready",
        note: "",
        installHint: ""
    )
}
