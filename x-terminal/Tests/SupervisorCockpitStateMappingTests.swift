import Foundation
import Testing
@testable import XTerminal

struct SupervisorCockpitStateMappingTests {
    @Test
    func grantRequiredMapsToExplainableBlockerAndValidatedScope() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 1,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "awaiting_grant",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json"
            )
        )

        #expect(presentation.intakeStatus.state == .grantRequired)
        #expect(presentation.blockerStatus.headline.contains("Hub 授权未完成"))
        #expect(presentation.blockerStatus.headline.contains("grant_required"))
        #expect(presentation.releaseFreezeStatus.state == .releaseFrozen)
        #expect(presentation.actions.first?.id == "submit_intake")
        #expect(presentation.consumedFrozenFields.contains("xt.one_shot_run_state.v1.state"))
        #expect(stage(presentation, id: "access")?.progress == .active)
        #expect(stage(presentation, id: "runtime")?.progress == .pending)
        #expect(stage(presentation, id: "access")?.actionID == "resolve_access")
        #expect(presentation.actions.first(where: { $0.id == "approve_risk" })?.subtitle?.contains("grant_required") == false)
    }

    @Test
    func blockedAndReadyStatesPreservePlannerExplainAndNextAction() {
        let blocked = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: LaneHealthSummary(
                    total: 3,
                    running: 0,
                    blocked: 1,
                    stalled: 1,
                    failed: 0,
                    waiting: 1,
                    recovering: 0,
                    completed: 0
                ),
                abnormalLaneStatus: "blocked",
                abnormalLaneRecommendation: "先处理上游授权，再按 next action 续推。",
                xtReadyStatus: "blocked_waiting_upstream",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json"
            )
        )
        #expect(blocked.intakeStatus.state == .blockedWaitingUpstream)
        #expect(blocked.blockerStatus.userAction.contains("续推"))
        #expect(blocked.plannerExplain.contains("blocked_waiting_upstream"))

        let ready = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json"
            )
        )
        #expect(ready.intakeStatus.state == .ready)
        #expect(ready.blockerStatus.headline == "Top blocker: none")
        #expect(ready.plannerExplain.contains("当前处于 ready"))
    }

    @Test
    func memoryUnderfedPreventsReviewReadyAndFreezePromotion() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ok",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                memoryAssemblyReady: false,
                memoryAssemblyIssueCount: 2,
                memoryAssemblyStatusLine: "underfed:memory_review_floor_not_met,memory_focus_evidence_missing",
                memoryAssemblyTopIssueCode: "memory_review_floor_not_met",
                oneShotRuntimeState: OneShotRunStateStatus.completed.rawValue,
                oneShotRuntimeOwner: "xt_l2",
                oneShotRuntimeTopBlocker: "none",
                oneShotRuntimeSummary: "主执行链已完成，但 strategic review memory 仍需补齐。",
                oneShotRuntimeNextTarget: "review_delivery",
                oneShotRuntimeActiveLaneCount: 0
            )
        )

        #expect(presentation.intakeStatus.state == .diagnosticRequired)
        #expect(presentation.intakeStatus.headline.contains("strategic memory"))
        #expect(presentation.blockerStatus.headline.contains("memory_context_underfed"))
        #expect(presentation.plannerExplain.contains("memory_context_underfed"))
        #expect(stage(presentation, id: "freeze")?.surfaceState == .diagnosticRequired)
    }

    @Test
    func reviewMemorySummarySurfacesAsIndependentCockpitTruth() {
        let summary = SupervisorMemoryAssemblyCompactSummary(
            headlineText: "Review Memory · Deep Dive / ceiling Deep Dive",
            detailText: "Recent Raw Context Deep · 12 pairs · configured/recommended Plan Review/Deep Dive · purpose Portfolio Review",
            helpText: "S-Tier 只提供 Supervisor 的 review-memory ceiling；Recent Raw Context 和 Review Memory Depth 仍由 role-aware resolver 单独计算。"
        )

        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                reviewMemorySummary: summary
            )
        )

        #expect(presentation.intakeStatus.state == .ready)
        #expect(presentation.reviewMemorySummary?.headlineText == summary.headlineText)
        #expect(presentation.reviewMemorySummary?.detailText == summary.detailText)
        #expect(presentation.reviewMemorySummary?.helpText.contains("S-Tier 只提供 Supervisor 的 review-memory ceiling") == true)
    }

    @Test
    func oneShotAwaitingGrantMapsGrantRequiredWithoutPendingGrantSnapshot() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                oneShotRuntimeState: OneShotRunStateStatus.awaitingGrant.rawValue,
                oneShotRuntimeOwner: "xt_l2",
                oneShotRuntimeTopBlocker: "grant_required",
                oneShotRuntimeSummary: "one-shot intake 已被授权门拦住，需先完成 voice / grant 审批。",
                oneShotRuntimeNextTarget: "grant_center",
                oneShotRuntimeActiveLaneCount: 0
            )
        )

        #expect(presentation.intakeStatus.state == .grantRequired)
        #expect(presentation.intakeStatus.whatHappened.contains("授权门"))
        #expect(presentation.blockerStatus.headline.contains("Hub 授权未完成"))
        #expect(presentation.blockerStatus.headline.contains("grant_required"))
        #expect(presentation.plannerExplain.contains("awaiting_grant"))
        #expect(stage(presentation, id: "access")?.surfaceState == .grantRequired)
        #expect(stage(presentation, id: "runtime")?.progress == .pending)
        #expect(stage(presentation, id: "access")?.actionLabel == "打开授权")
        #expect(presentation.runtimeStageRail.summary.contains("Hub 授权未完成"))
    }

    @Test
    func oneShotRunningTakesPrecedenceOverIdleLaneSummary() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                oneShotRuntimeState: OneShotRunStateStatus.running.rawValue,
                oneShotRuntimeOwner: "xt_l2",
                oneShotRuntimeTopBlocker: "none",
                oneShotRuntimeSummary: "XT-L2 正在真实执行已授权的一次性复杂任务。",
                oneShotRuntimeNextTarget: "mergeback_gate",
                oneShotRuntimeActiveLaneCount: 2
            )
        )

        #expect(presentation.intakeStatus.state == .inProgress)
        #expect(presentation.intakeStatus.headline.contains("真实执行"))
        #expect(presentation.blockerStatus.headline == "Top blocker: none")
        #expect(presentation.plannerExplain.contains("当前处于 running"))
        #expect(stage(presentation, id: "intake")?.progress == .completed)
        #expect(stage(presentation, id: "runtime")?.progress == .active)
        #expect(stage(presentation, id: "runtime")?.surfaceState == .inProgress)
        #expect(stage(presentation, id: "intake")?.actionID == "submit_intake")
    }

    @Test
    func oneShotFailedClosedSurfacesExplicitRuntimeBlocker() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                oneShotRuntimeState: OneShotRunStateStatus.failedClosed.rawValue,
                oneShotRuntimeOwner: "xt_l2",
                oneShotRuntimeTopBlocker: "bridge_route_unavailable",
                oneShotRuntimeSummary: "Bridge / tool route 缺失，session runtime 已 fail-closed。",
                oneShotRuntimeNextTarget: "repair_bridge_tool_route",
                oneShotRuntimeActiveLaneCount: 0
            )
        )

        #expect(presentation.intakeStatus.state == .blockedWaitingUpstream)
        #expect(presentation.intakeStatus.headline.contains("fail-closed"))
        #expect(presentation.blockerStatus.headline.contains("bridge_route_unavailable"))
        #expect(presentation.plannerExplain.contains("failed_closed"))
        #expect(stage(presentation, id: "runtime")?.progress == .blocked)
        #expect(stage(presentation, id: "runtime")?.detail?.contains("fail-closed") == true)
        #expect(stage(presentation, id: "runtime")?.actionID == nil)
    }

    @Test
    func oneShotBlockedWithDirectedResumeExposesContinueLaneAction() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: LaneHealthSummary(
                    total: 2,
                    running: 0,
                    blocked: 1,
                    stalled: 0,
                    failed: 0,
                    waiting: 1,
                    recovering: 0,
                    completed: 0
                ),
                abnormalLaneStatus: "blocked",
                abnormalLaneRecommendation: "继续当前 lane，不要扩 scope。",
                xtReadyStatus: "blocked_waiting_upstream",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                directedUnblockBatonCount: 1,
                nextDirectedResumeAction: "continue_current_task_only",
                nextDirectedResumeLane: "XT-W3-29-E-L2",
                oneShotRuntimeState: OneShotRunStateStatus.blocked.rawValue,
                oneShotRuntimeOwner: "xt_l2",
                oneShotRuntimeTopBlocker: "awaiting_instruction",
                oneShotRuntimeSummary: "上游依赖已解锁，但当前 lane 仍需按 baton 约束续推。",
                oneShotRuntimeNextTarget: "XT-W3-29-E-L2",
                oneShotRuntimeActiveLaneCount: 1
            )
        )

        #expect(stage(presentation, id: "runtime")?.progress == .blocked)
        #expect(stage(presentation, id: "runtime")?.actionID == "directed_resume")
        #expect(stage(presentation, id: "runtime")?.actionLabel == "继续泳道")
    }

    @Test
    func supervisorGrantBlockerPromotesGovernanceRepairInCockpit() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "blocked_waiting_upstream",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                oneShotRuntimeState: OneShotRunStateStatus.blocked.rawValue,
                oneShotRuntimeOwner: "supervisor",
                oneShotRuntimeTopBlocker: "device_permission_owner_missing",
                oneShotRuntimeSummary: "",
                oneShotRuntimeNextTarget: "project_governance",
                oneShotRuntimeActiveLaneCount: 0
            )
        )

        #expect(stage(presentation, id: "access")?.surfaceState == .permissionDenied)
        #expect(stage(presentation, id: "access")?.actionID == "resolve_access")
        #expect(stage(presentation, id: "access")?.actionLabel == "检查治理")
        #expect(stage(presentation, id: "runtime")?.surfaceState == .permissionDenied)
        #expect(stage(presentation, id: "runtime")?.actionID == "resolve_access")
        #expect(stage(presentation, id: "runtime")?.actionLabel == "检查治理")
        #expect(stage(presentation, id: "runtime")?.detail?.contains("grant / governance 面还没就绪") == true)
    }

    @Test
    func supervisorRouteBlockerPromotesRouteRepairInCockpit() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "blocked_waiting_upstream",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                oneShotRuntimeState: OneShotRunStateStatus.blocked.rawValue,
                oneShotRuntimeOwner: "supervisor",
                oneShotRuntimeTopBlocker: "preferred_device_offline",
                oneShotRuntimeSummary: "",
                oneShotRuntimeNextTarget: "pair_hub",
                oneShotRuntimeActiveLaneCount: 0
            )
        )

        #expect(stage(presentation, id: "access")?.surfaceState == .blockedWaitingUpstream)
        #expect(stage(presentation, id: "access")?.actionID == "pair_hub")
        #expect(stage(presentation, id: "access")?.actionLabel == "检查路由")
        #expect(stage(presentation, id: "runtime")?.surfaceState == .blockedWaitingUpstream)
        #expect(stage(presentation, id: "runtime")?.actionID == "pair_hub")
        #expect(stage(presentation, id: "runtime")?.actionLabel == "检查路由")
        #expect(stage(presentation, id: "runtime")?.detail?.contains("route plane is not ready") == false)
    }


    @Test
    func runtimeContractsMapPermissionDenyScopeFreezeAndReplay() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                autoConfirmPolicy: "safe_plus_low_risk",
                autoLaunchPolicy: "mainline_only",
                grantGateMode: "fail_closed",
                humanTouchpointCount: 3,
                directedUnblockBatonCount: 1,
                nextDirectedResumeAction: "continue_current_task_only",
                nextDirectedResumeLane: "XT-W3-26-F",
                scopeFreezeDecision: "no_go",
                scopeFreezeValidatedScope: ["XT-W3-23", "XT-W3-24", "XT-W3-25"],
                allowedPublicStatementCount: 3,
                scopeFreezeBlockedExpansionItems: ["future_ui_productization"],
                scopeFreezeNextActions: ["drop_scope_expansion"],
                deniedLaunchCount: 1,
                topLaunchDenyCode: "permission_denied",
                replayPass: false,
                replayScenarioCount: 4,
                replayFailClosedScenarioCount: 4,
                replayEvidenceRefs: ["build/reports/xt_w3_26_h_replay_regression_evidence.v1.json"]
            )
        )

        #expect(presentation.intakeStatus.state == .permissionDenied)
        #expect(presentation.blockerStatus.headline.contains("权限链路拒绝"))
        #expect(presentation.blockerStatus.headline.contains("permission_denied"))
        #expect(presentation.releaseFreezeStatus.state == .blockedWaitingUpstream)
        #expect(presentation.plannerExplain.contains("auto_launch=mainline_only"))
        #expect(presentation.plannerExplain.contains("freeze=no_go"))
        #expect(presentation.consumedFrozenFields.contains("xt.unblock_baton.v1.next_action"))
        #expect(presentation.consumedFrozenFields.contains("xt.one_shot_replay_regression.v1.scenarios"))
        #expect(stage(presentation, id: "access")?.actionID == "resolve_access")
        #expect(stage(presentation, id: "freeze")?.actionID == "review_delivery")
        #expect(presentation.actions.first(where: { $0.id == "approve_risk" })?.subtitle?.contains("grant_required") == false)
    }

    @Test
    func launchDenyTaxonomyMapsCockpitToModelHubAndConnectivityRepairEntrypoints() {
        let modelNotReady = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                deniedLaunchCount: 1,
                topLaunchDenyCode: "provider_not_ready"
            )
        )
        #expect(modelNotReady.intakeStatus.state == .diagnosticRequired)
        #expect(modelNotReady.intakeStatus.headline.contains("模型或 provider 未就绪"))
        #expect(modelNotReady.blockerStatus.headline.contains("模型或 provider 未就绪"))
        #expect(modelNotReady.blockerStatus.headline.contains("model_not_ready"))
        #expect(stage(modelNotReady, id: "access")?.surfaceState == .diagnosticRequired)
        #expect(stage(modelNotReady, id: "access")?.actionID == "open_model_route_readiness")
        #expect(stage(modelNotReady, id: "access")?.actionLabel == "检查模型")

        let connectorScopeBlocked = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                deniedLaunchCount: 1,
                topLaunchDenyCode: "grant_required;deny_code=remote_export_blocked"
            )
        )
        #expect(connectorScopeBlocked.intakeStatus.state == .diagnosticRequired)
        #expect(connectorScopeBlocked.intakeStatus.headline.contains("远端导出或 connector scope 被阻断"))
        #expect(connectorScopeBlocked.blockerStatus.headline.contains("远端导出或 connector scope 被阻断"))
        #expect(connectorScopeBlocked.blockerStatus.headline.contains("connector_scope_blocked"))
        #expect(stage(connectorScopeBlocked, id: "access")?.surfaceState == .diagnosticRequired)
        #expect(stage(connectorScopeBlocked, id: "access")?.actionID == "open_hub_recovery")
        #expect(stage(connectorScopeBlocked, id: "access")?.actionLabel == "检查 Hub Recovery")

        let paidModelBlocked = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                deniedLaunchCount: 1,
                topLaunchDenyCode: "device_paid_model_not_allowed"
            )
        )
        #expect(paidModelBlocked.intakeStatus.state == .diagnosticRequired)
        #expect(paidModelBlocked.intakeStatus.headline.contains("付费模型访问受阻"))
        #expect(stage(paidModelBlocked, id: "access")?.actionID == "open_model_route_readiness")
        #expect(stage(paidModelBlocked, id: "access")?.actionLabel == "检查付费模型")

        let connectivityBlocked = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                deniedLaunchCount: 1,
                topLaunchDenyCode: "grpc_unavailable"
            )
        )
        #expect(connectivityBlocked.intakeStatus.state == .blockedWaitingUpstream)
        #expect(connectivityBlocked.intakeStatus.headline.contains("连接修复型阻塞"))
        #expect(stage(connectivityBlocked, id: "access")?.surfaceState == .blockedWaitingUpstream)
        #expect(stage(connectivityBlocked, id: "access")?.actionID == "pair_hub")
        #expect(stage(connectivityBlocked, id: "access")?.actionLabel == "检查 Hub")
    }

    @Test
    func failedClosedRuntimeTaxonomyPromotesIssueSpecificRepairAction() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: .empty,
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "ready",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                oneShotRuntimeState: OneShotRunStateStatus.failedClosed.rawValue,
                oneShotRuntimeOwner: "xt_l2",
                oneShotRuntimeTopBlocker: "provider_not_ready",
                oneShotRuntimeSummary: "远端 provider 尚未 ready，当前 one-shot 已 fail-closed。",
                oneShotRuntimeNextTarget: "model_route_readiness",
                oneShotRuntimeActiveLaneCount: 0
            )
        )

        #expect(stage(presentation, id: "runtime")?.surfaceState == .diagnosticRequired)
        #expect(stage(presentation, id: "runtime")?.actionID == "open_model_route_readiness")
        #expect(stage(presentation, id: "runtime")?.actionLabel == "检查模型")
    }

    @Test
    func cockpitHumanizesRuntimeFallbackDetailAndGrantActionSubtitle() {
        let presentation = SupervisorCockpitPresentation.map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: false,
                pendingGrantCount: 0,
                hasFreshPendingGrantSnapshot: true,
                doctorStatusLine: "Doctor 已通过（0 个告警）",
                doctorSuggestionCount: 0,
                releaseBlockedByDoctorWithoutReport: 0,
                laneSummary: LaneHealthSummary(
                    total: 1,
                    running: 0,
                    blocked: 1,
                    stalled: 0,
                    failed: 0,
                    waiting: 0,
                    recovering: 0,
                    completed: 0
                ),
                abnormalLaneStatus: nil,
                abnormalLaneRecommendation: nil,
                xtReadyStatus: "blocked_waiting_upstream",
                xtReadyStrictE2EReady: true,
                xtReadyIssueCount: 0,
                xtReadyReportPath: "build/xt_ready_gate_e2e_report.json",
                grantGateMode: "fail_closed",
                oneShotRuntimeState: OneShotRunStateStatus.blocked.rawValue,
                oneShotRuntimeOwner: "xt_l2",
                oneShotRuntimeTopBlocker: "provider_not_ready",
                oneShotRuntimeSummary: "",
                oneShotRuntimeNextTarget: "model_route_readiness",
                oneShotRuntimeActiveLaneCount: 1
            )
        )

        #expect(stage(presentation, id: "runtime")?.detail?.contains("provider 尚未 ready") == true)
        #expect(presentation.runtimeStageRail.summary.contains("当前阻塞：provider 尚未 ready"))
        #expect(presentation.actions.first(where: { $0.id == "approve_risk" })?.subtitle?.contains("Hub 授权阻塞") == true)
        #expect(presentation.actions.first(where: { $0.id == "approve_risk" })?.subtitle?.contains("grant_required") == false)
    }

    @Test
    func runtimeCaptureWritesXTW327DEvidenceWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_27_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let base = URL(fileURLWithPath: captureDir)
        let input = SupervisorCockpitPresentationInput(
            isProcessing: true,
            pendingGrantCount: 0,
            hasFreshPendingGrantSnapshot: true,
            doctorStatusLine: "Doctor 已通过（0 个告警）",
            doctorSuggestionCount: 0,
            releaseBlockedByDoctorWithoutReport: 0,
            laneSummary: LaneHealthSummary(
                total: 2,
                running: 1,
                blocked: 0,
                stalled: 0,
                failed: 0,
                waiting: 0,
                recovering: 1,
                completed: 0
            ),
            abnormalLaneStatus: nil,
            abnormalLaneRecommendation: nil,
            xtReadyStatus: "running",
            xtReadyStrictE2EReady: true,
            xtReadyIssueCount: 0,
            xtReadyReportPath: "build/xt_ready_gate_e2e_report.json"
        )
        let evidence = XTW327DSupervisorCockpitEvidence(
            claim: "XT-W3-27-D",
            input: input,
            presentation: SupervisorCockpitPresentation.map(input: input)
        )

        try writeJSON(evidence, to: base.appendingPathComponent("xt_w3_27_d_supervisor_cockpit_evidence.v1.json"))
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("xt_w3_27_d_supervisor_cockpit_evidence.v1.json").path))
    }

    private struct XTW327DSupervisorCockpitEvidence: Codable, Equatable {
        let claim: String
        let input: SupervisorCockpitPresentationInput
        let presentation: SupervisorCockpitPresentation
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    private func stage(_ presentation: SupervisorCockpitPresentation, id: String) -> SupervisorRuntimeStageItemPresentation? {
        presentation.runtimeStageRail.items.first { $0.id == id }
    }
}
