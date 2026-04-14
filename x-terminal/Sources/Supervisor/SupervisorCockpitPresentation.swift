struct SupervisorCockpitPresentationInput: Codable, Equatable {
    let isProcessing: Bool
    let pendingGrantCount: Int
    let hasFreshPendingGrantSnapshot: Bool
    let doctorStatusLine: String
    let doctorSuggestionCount: Int
    let releaseBlockedByDoctorWithoutReport: Int
    let laneSummary: LaneHealthSummary
    let abnormalLaneStatus: String?
    let abnormalLaneRecommendation: String?
    let xtReadyStatus: String
    let xtReadyStrictE2EReady: Bool
    let xtReadyIssueCount: Int
    let xtReadyReportPath: String
    let reviewMemorySummary: SupervisorMemoryAssemblyCompactSummary?
    let memoryAssemblyReady: Bool
    let memoryAssemblyIssueCount: Int
    let memoryAssemblyStatusLine: String
    let memoryAssemblyTopIssueCode: String?
    let autoConfirmPolicy: String?
    let autoLaunchPolicy: String?
    let grantGateMode: String?
    let humanTouchpointCount: Int
    let directedUnblockBatonCount: Int
    let nextDirectedResumeAction: String?
    let nextDirectedResumeLane: String?
    let scopeFreezeDecision: String?
    let scopeFreezeValidatedScope: [String]
    let allowedPublicStatementCount: Int
    let scopeFreezeBlockedExpansionItems: [String]
    let scopeFreezeNextActions: [String]
    let deniedLaunchCount: Int
    let topLaunchDenyCode: String?
    let replayPass: Bool?
    let replayScenarioCount: Int
    let replayFailClosedScenarioCount: Int
    let replayEvidenceRefs: [String]
    let oneShotRuntimeState: String?
    let oneShotRuntimeOwner: String?
    let oneShotRuntimeTopBlocker: String?
    let oneShotRuntimeSummary: String?
    let oneShotRuntimeNextTarget: String?
    let oneShotRuntimeActiveLaneCount: Int

    init(
        isProcessing: Bool,
        pendingGrantCount: Int,
        hasFreshPendingGrantSnapshot: Bool,
        doctorStatusLine: String,
        doctorSuggestionCount: Int,
        releaseBlockedByDoctorWithoutReport: Int,
        laneSummary: LaneHealthSummary,
        abnormalLaneStatus: String?,
        abnormalLaneRecommendation: String?,
        xtReadyStatus: String,
        xtReadyStrictE2EReady: Bool,
        xtReadyIssueCount: Int,
        xtReadyReportPath: String,
        reviewMemorySummary: SupervisorMemoryAssemblyCompactSummary? = nil,
        memoryAssemblyReady: Bool = true,
        memoryAssemblyIssueCount: Int = 0,
        memoryAssemblyStatusLine: String = "ready",
        memoryAssemblyTopIssueCode: String? = nil,
        autoConfirmPolicy: String? = nil,
        autoLaunchPolicy: String? = nil,
        grantGateMode: String? = nil,
        humanTouchpointCount: Int = 0,
        directedUnblockBatonCount: Int = 0,
        nextDirectedResumeAction: String? = nil,
        nextDirectedResumeLane: String? = nil,
        scopeFreezeDecision: String? = nil,
        scopeFreezeValidatedScope: [String] = [],
        allowedPublicStatementCount: Int = 0,
        scopeFreezeBlockedExpansionItems: [String] = [],
        scopeFreezeNextActions: [String] = [],
        deniedLaunchCount: Int = 0,
        topLaunchDenyCode: String? = nil,
        replayPass: Bool? = nil,
        replayScenarioCount: Int = 0,
        replayFailClosedScenarioCount: Int = 0,
        replayEvidenceRefs: [String] = [],
        oneShotRuntimeState: String? = nil,
        oneShotRuntimeOwner: String? = nil,
        oneShotRuntimeTopBlocker: String? = nil,
        oneShotRuntimeSummary: String? = nil,
        oneShotRuntimeNextTarget: String? = nil,
        oneShotRuntimeActiveLaneCount: Int = 0
    ) {
        self.isProcessing = isProcessing
        self.pendingGrantCount = pendingGrantCount
        self.hasFreshPendingGrantSnapshot = hasFreshPendingGrantSnapshot
        self.doctorStatusLine = doctorStatusLine
        self.doctorSuggestionCount = doctorSuggestionCount
        self.releaseBlockedByDoctorWithoutReport = releaseBlockedByDoctorWithoutReport
        self.laneSummary = laneSummary
        self.abnormalLaneStatus = abnormalLaneStatus
        self.abnormalLaneRecommendation = abnormalLaneRecommendation
        self.xtReadyStatus = xtReadyStatus
        self.xtReadyStrictE2EReady = xtReadyStrictE2EReady
        self.xtReadyIssueCount = xtReadyIssueCount
        self.xtReadyReportPath = xtReadyReportPath
        self.reviewMemorySummary = reviewMemorySummary
        self.memoryAssemblyReady = memoryAssemblyReady
        self.memoryAssemblyIssueCount = memoryAssemblyIssueCount
        self.memoryAssemblyStatusLine = memoryAssemblyStatusLine
        self.memoryAssemblyTopIssueCode = memoryAssemblyTopIssueCode
        self.autoConfirmPolicy = autoConfirmPolicy
        self.autoLaunchPolicy = autoLaunchPolicy
        self.grantGateMode = grantGateMode
        self.humanTouchpointCount = humanTouchpointCount
        self.directedUnblockBatonCount = directedUnblockBatonCount
        self.nextDirectedResumeAction = nextDirectedResumeAction
        self.nextDirectedResumeLane = nextDirectedResumeLane
        self.scopeFreezeDecision = scopeFreezeDecision
        self.scopeFreezeValidatedScope = scopeFreezeValidatedScope
        self.allowedPublicStatementCount = allowedPublicStatementCount
        self.scopeFreezeBlockedExpansionItems = scopeFreezeBlockedExpansionItems
        self.scopeFreezeNextActions = scopeFreezeNextActions
        self.deniedLaunchCount = deniedLaunchCount
        self.topLaunchDenyCode = topLaunchDenyCode
        self.replayPass = replayPass
        self.replayScenarioCount = replayScenarioCount
        self.replayFailClosedScenarioCount = replayFailClosedScenarioCount
        self.replayEvidenceRefs = replayEvidenceRefs
        self.oneShotRuntimeState = oneShotRuntimeState
        self.oneShotRuntimeOwner = oneShotRuntimeOwner
        self.oneShotRuntimeTopBlocker = oneShotRuntimeTopBlocker
        self.oneShotRuntimeSummary = oneShotRuntimeSummary
        self.oneShotRuntimeNextTarget = oneShotRuntimeNextTarget
        self.oneShotRuntimeActiveLaneCount = oneShotRuntimeActiveLaneCount
    }

    enum CodingKeys: String, CodingKey {
        case isProcessing = "is_processing"
        case pendingGrantCount = "pending_grant_count"
        case hasFreshPendingGrantSnapshot = "has_fresh_pending_grant_snapshot"
        case doctorStatusLine = "doctor_status_line"
        case doctorSuggestionCount = "doctor_suggestion_count"
        case releaseBlockedByDoctorWithoutReport = "release_blocked_by_doctor_without_report"
        case laneSummary = "lane_summary"
        case abnormalLaneStatus = "abnormal_lane_status"
        case abnormalLaneRecommendation = "abnormal_lane_recommendation"
        case xtReadyStatus = "xt_ready_status"
        case xtReadyStrictE2EReady = "xt_ready_strict_e2e_ready"
        case xtReadyIssueCount = "xt_ready_issue_count"
        case xtReadyReportPath = "xt_ready_report_path"
        case reviewMemorySummary = "review_memory_summary"
        case memoryAssemblyReady = "memory_assembly_ready"
        case memoryAssemblyIssueCount = "memory_assembly_issue_count"
        case memoryAssemblyStatusLine = "memory_assembly_status_line"
        case memoryAssemblyTopIssueCode = "memory_assembly_top_issue_code"
        case autoConfirmPolicy = "auto_confirm_policy"
        case autoLaunchPolicy = "auto_launch_policy"
        case grantGateMode = "grant_gate_mode"
        case humanTouchpointCount = "human_touchpoint_count"
        case directedUnblockBatonCount = "directed_unblock_baton_count"
        case nextDirectedResumeAction = "next_directed_resume_action"
        case nextDirectedResumeLane = "next_directed_resume_lane"
        case scopeFreezeDecision = "scope_freeze_decision"
        case scopeFreezeValidatedScope = "scope_freeze_validated_scope"
        case allowedPublicStatementCount = "allowed_public_statement_count"
        case scopeFreezeBlockedExpansionItems = "scope_freeze_blocked_expansion_items"
        case scopeFreezeNextActions = "scope_freeze_next_actions"
        case deniedLaunchCount = "denied_launch_count"
        case topLaunchDenyCode = "top_launch_deny_code"
        case replayPass = "replay_pass"
        case replayScenarioCount = "replay_scenario_count"
        case replayFailClosedScenarioCount = "replay_fail_closed_scenario_count"
        case replayEvidenceRefs = "replay_evidence_refs"
        case oneShotRuntimeState = "one_shot_runtime_state"
        case oneShotRuntimeOwner = "one_shot_runtime_owner"
        case oneShotRuntimeTopBlocker = "one_shot_runtime_top_blocker"
        case oneShotRuntimeSummary = "one_shot_runtime_summary"
        case oneShotRuntimeNextTarget = "one_shot_runtime_next_target"
        case oneShotRuntimeActiveLaneCount = "one_shot_runtime_active_lane_count"
    }
}

struct SupervisorCockpitPresentation: Codable, Equatable {
    let badge: ValidatedScopePresentation
    let runtimeStageRail: SupervisorRuntimeStageRailPresentation
    let intakeStatus: StatusExplanation
    let blockerStatus: StatusExplanation
    let releaseFreezeStatus: StatusExplanation
    let reviewMemorySummary: SupervisorMemoryAssemblyCompactSummary?
    let plannerExplain: String
    let plannerMachineStatusRef: String
    let actions: [PrimaryActionRailAction]
    let reviewReportPath: String
    let consumedFrozenFields: [String]

    enum CodingKeys: String, CodingKey {
        case badge
        case runtimeStageRail = "runtime_stage_rail"
        case intakeStatus = "intake_status"
        case blockerStatus = "blocker_status"
        case releaseFreezeStatus = "release_freeze_status"
        case reviewMemorySummary = "review_memory_summary"
        case plannerExplain = "planner_explain"
        case plannerMachineStatusRef = "planner_machine_status_ref"
        case actions
        case reviewReportPath = "review_report_path"
        case consumedFrozenFields = "consumed_frozen_fields"
    }

    @MainActor
    static func fromRuntime(
        supervisorManager: SupervisorManager,
        orchestrator: SupervisorOrchestrator,
        monitor: ExecutionMonitor,
        xtReadySnapshot: SupervisorManager.XTReadyIncidentExportSnapshot? = nil
    ) -> SupervisorCockpitPresentation {
        let xtReadySnapshot = xtReadySnapshot ?? supervisorManager.xtReadyIncidentExportSnapshot(limit: 120)
        let memoryReadiness = supervisorManager.supervisorMemoryAssemblyReadiness
        let laneSnapshot = supervisorManager.supervisorLaneHealthSnapshot
        let abnormalLane = laneSnapshot?.lanes.first { lane in
            switch lane.status {
            case .blocked, .stalled, .failed:
                return true
            default:
                return false
            }
        }
        let runtimePolicy = orchestrator.oneShotAutonomyPolicy
        let scopeFreeze = orchestrator.latestDeliveryScopeFreeze
        let replayReport = orchestrator.latestReplayHarnessReport
        let deniedLaunches = orchestrator.laneLaunchDecisions.values
            .filter { $0.autoLaunchAllowed == false || $0.decision != .allow }
            .sorted { lhs, rhs in
                lhs.laneID.localizedCaseInsensitiveCompare(rhs.laneID) == .orderedAscending
            }
        let nextBaton = monitor.directedUnblockBatons.first
        let oneShotRunState = supervisorManager.oneShotRunState

        return map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: supervisorManager.isProcessing,
                pendingGrantCount: supervisorManager.frontstagePendingHubGrants.count,
                hasFreshPendingGrantSnapshot: supervisorManager.hasFreshPendingHubGrantSnapshot,
                doctorStatusLine: supervisorManager.doctorStatusLine,
                doctorSuggestionCount: supervisorManager.doctorSuggestionCards.count,
                releaseBlockedByDoctorWithoutReport: supervisorManager.releaseBlockedByDoctorWithoutReport,
                laneSummary: laneSnapshot?.summary ?? monitor.laneHealthSummary,
                abnormalLaneStatus: abnormalLane?.status.rawValue,
                abnormalLaneRecommendation: abnormalLane?.nextActionRecommendation,
                xtReadyStatus: xtReadySnapshot.status,
                xtReadyStrictE2EReady: xtReadySnapshot.strictE2EReady,
                xtReadyIssueCount: xtReadySnapshot.strictE2EIssues.count + xtReadySnapshot.missingIncidentCodes.count,
                xtReadyReportPath: xtReadySnapshot.reportPath,
                reviewMemorySummary: supervisorManager.supervisorMemoryAssemblySnapshot?.compactSummary,
                memoryAssemblyReady: memoryReadiness.ready,
                memoryAssemblyIssueCount: memoryReadiness.issues.count,
                memoryAssemblyStatusLine: memoryReadiness.statusLine,
                memoryAssemblyTopIssueCode: memoryReadiness.issues.first?.code,
                autoConfirmPolicy: runtimePolicy?.autoConfirmPolicy.rawValue,
                autoLaunchPolicy: runtimePolicy?.autoLaunchPolicy.rawValue,
                grantGateMode: runtimePolicy?.grantGateMode,
                humanTouchpointCount: runtimePolicy?.humanTouchpoints.count ?? 0,
                directedUnblockBatonCount: monitor.directedUnblockBatons.count,
                nextDirectedResumeAction: nextBaton?.nextAction,
                nextDirectedResumeLane: nextBaton?.blockedLane,
                scopeFreezeDecision: scopeFreeze?.decision.rawValue,
                scopeFreezeValidatedScope: scopeFreeze?.validatedScope ?? [],
                allowedPublicStatementCount: scopeFreeze?.allowedPublicStatements.count ?? 0,
                scopeFreezeBlockedExpansionItems: scopeFreeze?.blockedExpansionItems ?? [],
                scopeFreezeNextActions: scopeFreeze?.nextActions ?? [],
                deniedLaunchCount: deniedLaunches.count,
                topLaunchDenyCode: deniedLaunches.first?.denyCode,
                replayPass: replayReport?.pass,
                replayScenarioCount: replayReport?.scenarios.count ?? 0,
                replayFailClosedScenarioCount: replayReport?.scenarios.filter(\.failClosed).count ?? 0,
                replayEvidenceRefs: replayReport?.evidenceRefs ?? [],
                oneShotRuntimeState: oneShotRunState?.state.rawValue,
                oneShotRuntimeOwner: oneShotRunState?.currentOwner.rawValue,
                oneShotRuntimeTopBlocker: oneShotRunState?.topBlocker,
                oneShotRuntimeSummary: oneShotRunState?.userVisibleSummary,
                oneShotRuntimeNextTarget: oneShotRunState?.nextDirectedTarget,
                oneShotRuntimeActiveLaneCount: oneShotRunState?.activeLanes.count ?? 0
            )
        )
    }

    static func map(input: SupervisorCockpitPresentationInput) -> SupervisorCockpitPresentation {
        let badge = ValidatedScopePresentation.validatedMainlineOnly
        let freezeDecision = input.scopeFreezeDecision ?? "pending"
        let oneShotState = input.oneShotRuntimeState.flatMap(OneShotRunStateStatus.init(rawValue:))
        let oneShotOwner = input.oneShotRuntimeOwner ?? "none"
        let oneShotTopBlocker = input.oneShotRuntimeTopBlocker ?? "none"
        let oneShotSummary = input.oneShotRuntimeSummary ?? ""
        let oneShotNextTarget = input.oneShotRuntimeNextTarget ?? "none"
        let replayStatus: String
        if let replayPass = input.replayPass {
            replayStatus = replayPass ? "pass" : "fail"
        } else {
            replayStatus = "pending"
        }
        let plannerMachineStatusRef = "processing=\(input.isProcessing); pending_grants=\(input.pendingGrantCount); grant_snapshot_fresh=\(input.hasFreshPendingGrantSnapshot); lane_running=\(input.laneSummary.running); lane_blocked=\(input.laneSummary.blocked); lane_stalled=\(input.laneSummary.stalled); lane_failed=\(input.laneSummary.failed); xt_ready_status=\(input.xtReadyStatus); xt_ready_issues=\(input.xtReadyIssueCount); memory_ready=\(input.memoryAssemblyReady); memory_issues=\(input.memoryAssemblyIssueCount); memory_top_issue=\(input.memoryAssemblyTopIssueCode ?? "none"); one_shot_state=\(input.oneShotRuntimeState ?? "none"); one_shot_owner=\(oneShotOwner); one_shot_blocker=\(oneShotTopBlocker); one_shot_next=\(oneShotNextTarget); one_shot_active_lanes=\(input.oneShotRuntimeActiveLaneCount); auto_confirm=\(input.autoConfirmPolicy ?? "none"); auto_launch=\(input.autoLaunchPolicy ?? "none"); freeze=\(freezeDecision); denied_launches=\(input.deniedLaunchCount); batons=\(input.directedUnblockBatonCount); replay=\(replayStatus)"
        let runtimeStageRail = buildRuntimeStageRail(
            input: input,
            oneShotState: oneShotState,
            oneShotOwner: oneShotOwner,
            oneShotTopBlocker: oneShotTopBlocker,
            oneShotSummary: oneShotSummary,
            oneShotNextTarget: oneShotNextTarget,
            freezeDecision: freezeDecision,
            plannerMachineStatusRef: plannerMachineStatusRef
        )
        let contractSummary = [
            input.autoConfirmPolicy.map { "auto_confirm=\($0)" },
            input.autoLaunchPolicy.map { "auto_launch=\($0)" },
            input.grantGateMode.map { "grant_gate=\($0)" },
            "strategic_memory=\(input.memoryAssemblyReady ? "ready" : "underfed")",
            input.oneShotRuntimeState.map { "one_shot=\($0)" },
            "freeze=\(freezeDecision)",
            "replay=\(replayStatus)"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        let directedResumeSummary = input.nextDirectedResumeAction.map { action in
            let laneSuffix = input.nextDirectedResumeLane.map { " @ \($0)" } ?? ""
            return "directed_resume=\(action)\(laneSuffix)"
        }
        let normalizedTopLaunchDenyCode = input.topLaunchDenyCode.map(
            UITroubleshootKnowledgeBase.normalizedFailureCode
        )
        let topLaunchIssue = input.topLaunchDenyCode.flatMap(
            UITroubleshootKnowledgeBase.issue(forFailureCode:)
        )
        let topLaunchDenyHighlight = normalizedTopLaunchDenyCode.map {
            "top_launch_deny_code=\($0)"
        } ?? ""
        let topLaunchIssueHighlight = topLaunchIssue.map {
            "top_launch_issue=\($0.rawValue)"
        } ?? ""

        let intakeStatus: StatusExplanation
        let blockerStatus: StatusExplanation
        let plannerExplain: String

        if input.pendingGrantCount > 0 || topLaunchIssue == .grantRequired || oneShotState == .awaitingGrant {
            intakeStatus = StatusExplanation(
                state: .grantRequired,
                headline: "one-shot intake 已接收，但等待风险授权",
                whatHappened: oneShotSummary.isEmpty ? "授权链还没完成，所以系统继续挡住高风险 lane，不会直接放行。" : oneShotSummary,
                whyItHappened: "授权状态会综合运行时、当前 one-shot 状态和 lane 启动结果一起判断；没放行前不会越过 grant gate。",
                userAction: directedResumeSummary ?? "先审批风险授权，再回来继续当前任务。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "grant_fail_closed must remain visible",
                highlights: [
                    contractSummary,
                    topLaunchDenyHighlight,
                    topLaunchIssueHighlight,
                    "human_touchpoints=\(input.humanTouchpointCount)",
                    "denied_launches=\(input.deniedLaunchCount)",
                    "owner=\(oneShotOwner)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .grantRequired,
                headline: topBlockerHeadline(oneShotTopBlocker == "none" ? "grant_required" : oneShotTopBlocker),
                whatHappened: "当前主 blocker 是 grant chain 未完成，auto-launch 被显式 deny。",
                whyItHappened: "授权没完成前，这条路会继续被显式挡住，而不是悄悄回落成普通等待。",
                userAction: directedResumeSummary ?? "在 grant center 完成审批，然后回到当前 intake。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "high-risk path remains fail-closed",
                highlights: [
                    input.grantGateMode.map { "grant_gate_mode=\($0)" } ?? "",
                    topLaunchDenyHighlight,
                    topLaunchIssueHighlight,
                    "next_target=\(oneShotNextTarget)"
                ]
                    .filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前链路：任务接入 → 规划说明 → 阻塞分诊 → 交付冻结。现在停在 awaiting_grant；grant gate 未变绿前不会自动继续。"
        } else if topLaunchIssue == .permissionDenied || oneShotTopBlocker == "permission_denied" {
            intakeStatus = StatusExplanation(
                state: .permissionDenied,
                headline: "检测到权限链路拒绝，自动启动继续保持关闭",
                whatHappened: "lane 启动阶段返回了权限拒绝，所以当前链路不会被显示成可继续。",
                whyItHappened: "权限拒绝必须直接可见，不能被包装成普通等待。",
                userAction: directedResumeSummary ?? "先修复权限或授权配置，再重新发起 intake / resume。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "permission_denied remains explicit",
                highlights: [
                    contractSummary,
                    topLaunchDenyHighlight,
                    topLaunchIssueHighlight
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .permissionDenied,
                headline: topBlockerHeadline("permission_denied"),
                whatHappened: "当前主 blocker 是权限链路拒绝。",
                whyItHappened: "runtime deny note 会在 UI 中保持可见，避免误导用户为普通等待态。",
                userAction: directedResumeSummary ?? "先处理权限问题，再回到当前复杂任务。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "authz must stay fail-closed",
                highlights: [
                    topLaunchDenyHighlight,
                    topLaunchIssueHighlight,
                    "denied_launches=\(input.deniedLaunchCount)"
                ].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 \(displayBlockerLabel("permission_denied"))；lane launch deny 已把权限问题前移到 cockpit。"
        } else if topLaunchIssue == .modelNotReady {
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "检测到模型或 provider 未就绪，先收敛真实可执行模型",
                whatHappened: "lane launch deny 指向 provider 尚未 ready、上游仍在等待，或目标模型不在 Hub 真实可用清单里，而不是授权链已经收敛。",
                whyItHappened: "如果 cockpit 继续把这里显示成普通 access ready，用户会先去错入口，最后还是卡在 route truth。",
                userAction: directedResumeSummary ?? "先去 Supervisor 控制中心检查 AI 模型，再回 XT 设置 → 诊断核对 route truth。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "model_not_ready must remain visible",
                highlights: [
                    contractSummary,
                    topLaunchDenyHighlight,
                    topLaunchIssueHighlight,
                    "repair_entry=Supervisor 控制中心 · AI 模型"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: topBlockerHeadline("model_not_ready"),
                whatHappened: "当前主 blocker 是模型或 provider 还没 ready。",
                whyItHappened: "真实可执行模型没收敛前，cockpit 不能把当前 access 链路包成已就绪。",
                userAction: directedResumeSummary ?? "先核对 model_id、provider ready 和 Hub 实际可用清单。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "route truth must stay explicit",
                highlights: [topLaunchDenyHighlight, "next_target=\(oneShotNextTarget)"].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 \(displayBlockerLabel("model_not_ready"))；需先让 provider / model inventory 真实收敛，再继续 one-shot launch。"
        } else if topLaunchIssue == .connectorScopeBlocked {
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "检测到远端导出或 connector scope 被阻断，先检查 Hub Recovery",
                whatHappened: "lane launch deny 指向 remote export gate、设备远端导出策略、预算边界或用户远端偏好，当前 paid 远端不会被装成已可继续。",
                whyItHappened: "如果 cockpit 继续只显示授权未完成或权限链路拒绝，会把真正的 Hub Recovery 和边界修复入口藏掉。",
                userAction: directedResumeSummary ?? "先看 deny_code / audit_ref，再到 REL Flow Hub → 诊断与恢复检查 remote export gate。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "connector_scope_blocked must remain visible",
                highlights: [
                    contractSummary,
                    topLaunchDenyHighlight,
                    topLaunchIssueHighlight,
                    "repair_entry=REL Flow Hub → 诊断与恢复"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: topBlockerHeadline("connector_scope_blocked"),
                whatHappened: "当前主 blocker 是远端导出或 paid connector scope 被边界策略挡住。",
                whyItHappened: "export gate 没恢复前，自动启动不能继续把远端链路显示成可放行。",
                userAction: directedResumeSummary ?? "先修 remote export gate / 安全边界 / 预算，再回到当前 intake。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "remote export boundary stays fail-closed",
                highlights: [topLaunchDenyHighlight, "denied_launches=\(input.deniedLaunchCount)"].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 \(displayBlockerLabel("connector_scope_blocked"))；需先通过 Hub Recovery 还原 remote export gate / deny_code 对应边界。"
        } else if topLaunchIssue == .paidModelAccessBlocked {
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "检测到付费模型访问受阻，先回模型与预算入口",
                whatHappened: "lane launch deny 指向设备 paid policy、模型 allowlist 或预算边界，当前 paid model 不会被装成已准备好。",
                whyItHappened: "这类问题需要回真实模型与预算边界修复，不能被 cockpit 包成普通等待。",
                userAction: directedResumeSummary ?? "先去 Supervisor 控制中心和 Hub 模型入口核对 allowlist、预算与模型绑定。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "paid_model_access_blocked must remain visible",
                highlights: [
                    contractSummary,
                    topLaunchDenyHighlight,
                    topLaunchIssueHighlight,
                    "repair_entry=REL Flow Hub → 模型与付费访问"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: topBlockerHeadline("paid_model_access_blocked"),
                whatHappened: "当前主 blocker 是付费模型资格或预算没有放行。",
                whyItHappened: "paid model access 没恢复前，one-shot 入口不能继续暗示可自动启动。",
                userAction: directedResumeSummary ?? "先核对 paid model 资格、allowlist 和 token budget。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "paid access stays fail-closed",
                highlights: [topLaunchDenyHighlight, topLaunchIssueHighlight].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 \(displayBlockerLabel("paid_model_access_blocked"))；需先修复 paid model allowlist / budget，再继续 launch。"
        } else if topLaunchIssue == .pairingRepairRequired
            || topLaunchIssue == .multipleHubsAmbiguous
            || topLaunchIssue == .hubPortConflict
            || topLaunchIssue == .hubUnreachable {
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "检测到连接修复型阻塞，先恢复 Hub 连接事实",
                whatHappened: "lane launch deny 仍指向 Pair Hub、端口冲突、多 Hub 冲突或 Hub 不可达，所以 cockpit 不会把当前入口装成 access ready。",
                whyItHappened: "只要连接事实没恢复，Hub 真实可用状态和授权链都不能被继续消费。",
                userAction: directedResumeSummary ?? "先回 Pair Hub 或诊断入口修连接，再回来继续当前 one-shot。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "hub_connectivity_blockers must remain visible",
                highlights: [
                    contractSummary,
                    topLaunchDenyHighlight,
                    topLaunchIssueHighlight,
                    "repair_entry=Pair Hub"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: topBlockerHeadline(topLaunchIssue?.rawValue ?? "hub_connectivity_blocked"),
                whatHappened: "当前主 blocker 是 Hub 连接、配对或路由可达性没有恢复。",
                whyItHappened: "连接事实不成立时，cockpit 必须继续把 Pair Hub / diagnostics 摆在明面上。",
                userAction: directedResumeSummary ?? "先恢复 Pair Hub 与 gRPC 可达，再回到当前复杂任务。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "connectivity blockers stay explicit",
                highlights: [topLaunchDenyHighlight, topLaunchIssueHighlight].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 \(displayBlockerLabel(topLaunchIssue?.rawValue ?? "hub_connectivity_blocked"))；需先恢复 Pair Hub / gRPC 可达性，再继续 one-shot launch。"
        } else if normalizedTopLaunchDenyCode == "scope_expansion" || freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty {
            let blockedItems = input.scopeFreezeBlockedExpansionItems.joined(separator: ",")
            let nextAction = input.scopeFreezeNextActions.first ?? "先收回超范围请求"
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "已验证范围拒绝超范围请求",
                whatHappened: "当前发布范围为 \(freezeDecisionLabel(freezeDecision))，同时存在超出已验证主链的扩范围请求。",
                whyItHappened: "这类超范围请求会继续被挡住，直到回到已验证主链。",
                userAction: nextAction,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "scope_not_validated must remain visible",
                highlights: [contractSummary, blockedItems.isEmpty ? "" : "blocked_expansion=\(blockedItems)"].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: topBlockerHeadline("scope_expansion"),
                whatHappened: "当前主 blocker 是请求超出了已验证范围。",
                whyItHappened: "范围已经被判定为 no-go，所以不能继续对内对外暗示已验证。",
                userAction: nextAction,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "validated-mainline-only stays enforced",
                highlights: ["validated_scope=\(input.scopeFreezeValidatedScope.joined(separator: ","))"].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 \(displayBlockerLabel("scope_expansion"))；需先回退到已验证主链，再重新计算 delivery freeze。"
        } else if input.releaseBlockedByDoctorWithoutReport != 0 {
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "Cockpit 等待 Doctor 预检证据",
                whatHappened: "当前缺少可用的 Doctor release 证据，因此 release 相关动作仍保持阻断。",
                whyItHappened: "发布前需要先拿到可读的诊断证据，不能只靠猜测继续往下走。",
                userAction: "运行 Doctor 预检，确认阻断项与建议卡后再 review delivery。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "diagnostic_required remains visible",
                highlights: [contractSummary, "doctor_suggestions=\(input.doctorSuggestionCount)"].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: topBlockerHeadline("diagnostic_required"),
                whatHappened: "当前主 blocker 是 Doctor 证据链未就绪。",
                whyItHappened: "缺少 Doctor 报告时，release line 不能被 UI 包装成已放行。",
                userAction: "先运行 diagnostics，再回到 review delivery。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "release stays fail-closed without doctor report",
                highlights: ["release_blocked_by_doctor_without_report=\(input.releaseBlockedByDoctorWithoutReport)"]
            )
            plannerExplain = "\(contractSummary)。当前停在 \(displayBlockerLabel("diagnostic_required"))，因为 Doctor / secret scrub 证据尚未齐备。"
        } else if oneShotState == .failedClosed {
            let recommendation = directedResumeSummary ?? input.scopeFreezeNextActions.first ?? "先修复当前 blocker，再重新发起这次 one-shot。"
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "one-shot runtime 已 fail-closed",
                whatHappened: oneShotSummary.isEmpty ? "运行时已经明确停住，不会再假装可以自动恢复。" : oneShotSummary,
                whyItHappened: "这次 one-shot 已进入 failed_closed，所以 cockpit 必须直接把 blocker 摆出来。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "fail_closed must remain visible",
                highlights: [
                    contractSummary,
                    "owner=\(oneShotOwner)",
                    "top_blocker=\(oneShotTopBlocker)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: topBlockerHeadline(oneShotTopBlocker),
                whatHappened: "当前主 blocker 来自这次 one-shot 的 fail-closed 判定。",
                whyItHappened: "执行链已经明确挡住，所以 UI 不能回退成普通等待态。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "runtime blocker stays explicit",
                highlights: [input.oneShotRuntimeState.map { "one_shot_state=\($0)" } ?? ""].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 failed_closed；需先消除当前阻塞：\(displayBlockerLabel(oneShotTopBlocker))，再允许重试当前主链。"
        } else if oneShotState == .blocked || input.laneSummary.failed > 0 || input.laneSummary.stalled > 0 || input.laneSummary.blocked > 0 {
            let abnormalStatus = input.abnormalLaneStatus ?? "lane_health_abnormal"
            let recommendation = directedResumeSummary ?? input.abnormalLaneRecommendation ?? "查看 lane 健康态与阻塞原因，按 next action 续推。"
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "one-shot 已进入执行，但当前被阻塞",
                whatHappened: oneShotSummary.isEmpty ? "lane 快照显示 blocked/stalled/failed；如果已有 baton，也只会给当前允许的继续方向。" : oneShotSummary,
                whyItHappened: "Cockpit 需要直接显示 blocker、恢复约束和 next action，而不是只剩聊天流水。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "blocked_waiting_upstream must remain visible",
                highlights: [
                    contractSummary,
                    "lane_blocked=\(input.laneSummary.blocked)",
                    "batons=\(input.directedUnblockBatonCount)",
                    "owner=\(oneShotOwner)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: topBlockerHeadline(oneShotTopBlocker == "none" ? abnormalStatus : oneShotTopBlocker),
                whatHappened: oneShotState == .blocked ? "当前主 blocker 已被运行时直接标出来。" : "当前主 blocker 来自 lane 健康异常。",
                whyItHappened: "planner 不会隐藏上游依赖；如果已有 baton，也只能按指定方向恢复。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "upstream blocker stays explicit",
                highlights: [
                    directedResumeSummary ?? "",
                    "xt_ready_status=\(input.xtReadyStatus)"
                ].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前链路：任务接入 → 规划说明 → 阻塞分诊 → 交付冻结。现在停在 blocked_waiting_upstream；如 baton 已发出，则只允许 directed resume。"
        } else if input.isProcessing
            || input.laneSummary.running > 0
            || input.laneSummary.recovering > 0
            || oneShotState == .planning
            || oneShotState == .launching
            || oneShotState == .running
            || oneShotState == .resuming
            || oneShotState == .mergeback {
            intakeStatus = StatusExplanation(
                state: .inProgress,
                headline: oneShotState == .running || oneShotState == .mergeback ? "one-shot run 正在真实执行" : "one-shot intake 已进入 planning / running",
                whatHappened: oneShotSummary.isEmpty ? "planner 正在分配 lane 并推进当前任务，关键运行状态会同步显示。" : oneShotSummary,
                whyItHappened: "Cockpit 现在接的是实时运行数据，不再只是模拟状态。",
                userAction: directedResumeSummary ?? "保持关注 planner explain；如果出现授权提示，先处理授权再继续。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "validated-mainline-only stays visible during execution",
                highlights: [
                    contractSummary,
                    "replay_scenarios=\(input.replayScenarioCount)",
                    "allowed_public_statements=\(input.allowedPublicStatementCount)",
                    "active_lanes=\(input.oneShotRuntimeActiveLaneCount)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: input.directedUnblockBatonCount > 0 ? .inProgress : .ready,
                headline: input.directedUnblockBatonCount > 0 ? topBlockerHeadline("directed_resume_available") : topBlockerHeadline("none"),
                whatHappened: input.directedUnblockBatonCount > 0 ? "当前没有新硬阻塞，但已存在 directed resume baton 可供续推。" : "当前没有 grant / doctor / lane 异常硬阻塞。",
                whyItHappened: input.directedUnblockBatonCount > 0 ? "恢复范围已经收口到 continue_current_task_only。" : "执行还在进行，但没有需要立刻人工介入的硬阻塞。",
                userAction: directedResumeSummary ?? "继续观察 planner explain，并在需要时 review delivery。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "scope freeze still applies",
                highlights: ["xt_ready_status=\(input.xtReadyStatus)", "owner=\(oneShotOwner)"]
            )
            plannerExplain = "\(contractSummary)。当前链路：任务接入 → 规划说明 → 阻塞分诊 → 交付冻结。当前处于 \(input.oneShotRuntimeState ?? "planning_or_running")，并附带 replay=\(replayStatus)、freeze=\(freezeDecision) 的解释上下文。"
        } else if oneShotState == .deliveryFreeze || oneShotState == .completed || !input.xtReadyStrictE2EReady || input.xtReadyIssueCount > 0 {
            let memoryUnderfed = !input.memoryAssemblyReady || input.memoryAssemblyIssueCount > 0
            let deliveryHeadline = memoryUnderfed
                ? "交付冻结前仍需补齐 strategic memory"
                : "交付冻结前仍需 review delivery"
            let deliveryWhatHappened = if memoryUnderfed {
                oneShotSummary.isEmpty
                    ? "当前 review / freeze 阶段虽然已经接近交付，但 Supervisor memory assembly 仍存在 underfed 风险，因此不能把当前状态上提为可信的 strategic review。"
                    : oneShotSummary
            } else {
                oneShotSummary.isEmpty
                    ? "XT-Ready 还存在未清零问题，Cockpit 因此不把当前状态上提为已交付完成。"
                    : oneShotSummary
            }
            let deliveryWhyItHappened = memoryUnderfed
                ? "如果 strategic review 建立在 underfed memory 上，Supervisor 很容易因为缺少长期目标、关键决策来由和可靠依据而给出失真的纠偏。"
                : "delivery freeze 需要 strict e2e 与 incident 证据；问题未清零时继续保持 explainable hold。"
            let deliveryUserAction = if memoryUnderfed {
                "先刷新 Supervisor memory，并确认当前项目的深度记忆、长期目标、关键决策原因、当前卡点以及可作为依据的日志或结果都已补齐，再 review delivery。"
            } else {
                input.scopeFreezeNextActions.first ?? "先 review delivery，确认 XT-Ready issues 再决定是否推进。"
            }
            let deliveryBlockerHeadline = memoryUnderfed
                ? topBlockerHeadline("memory_context_underfed")
                : topBlockerHeadline("review_delivery")
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: deliveryHeadline,
                whatHappened: deliveryWhatHappened,
                whyItHappened: deliveryWhyItHappened,
                userAction: deliveryUserAction,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "delivery freeze requires strict evidence",
                highlights: [
                    contractSummary,
                    "xt_ready_issue_count=\(input.xtReadyIssueCount)",
                    "memory_issue_count=\(input.memoryAssemblyIssueCount)",
                    input.memoryAssemblyTopIssueCode.map { "memory_top_issue=\($0)" } ?? ""
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: deliveryBlockerHeadline,
                whatHappened: memoryUnderfed
                    ? "当前主 blocker 是 strategic review 的 memory 供给仍不可信。"
                    : "当前主 blocker 是交付冻结证据仍待复核。",
                whyItHappened: memoryUnderfed
                    ? "memory assembly 没有达到 review-ready 之前，Cockpit 不能把当前 freeze / completion 展示成可信的 release 收口。"
                    : "XT-Ready 未绿时，Cockpit 不能向外暗示 release 已完成。",
                userAction: memoryUnderfed
                    ? deliveryUserAction
                    : (input.scopeFreezeNextActions.first ?? "查看 delivery report 与 XT-Ready export，再决定下一步。"),
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "no release without strict evidence",
                highlights: [
                    "xt_ready_status=\(input.xtReadyStatus)",
                    "memory_status=\(input.memoryAssemblyStatusLine)"
                ]
            )
            plannerExplain = memoryUnderfed
                ? "\(contractSummary)。当前停在 \(displayBlockerLabel("memory_context_underfed"))；需先补齐 strategic review memory，再进入可信的 delivery review。"
                : "\(contractSummary)。当前停在 delivery review，原因是 XT-Ready 仍有未消化问题。"
        } else if !input.memoryAssemblyReady || input.memoryAssemblyIssueCount > 0 {
            let topIssue = input.memoryAssemblyTopIssueCode ?? "memory_context_underfed"
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "Strategic review 记忆仍未喂够",
                whatHappened: "当前没有 grant / lane / XT-Ready 的显式硬阻塞，但 Supervisor memory assembly 仍未达到可信的 review 供给线。",
                whyItHappened: "如果在这时直接做战略纠偏，Supervisor 会更容易受到浅层 working set 或局部噪声误导，而不是依据完整项目背景做判断。",
                userAction: "先刷新 Supervisor memory，并确认当前项目的深度记忆、长期目标、关键决策原因、当前卡点以及可作为依据的日志或结果都已补齐。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "strategic review must not run on underfed memory",
                highlights: [
                    contractSummary,
                    "memory_issue_count=\(input.memoryAssemblyIssueCount)",
                    "memory_status=\(input.memoryAssemblyStatusLine)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: topBlockerHeadline(topIssue),
                whatHappened: "当前主 blocker 是 Supervisor strategic memory 仍未准备好。",
                whyItHappened: "memory assembly 的锚点、层级或证据链不完整时，Cockpit 不应把状态包装成 ready。",
                userAction: "刷新 memory 并重做 focused strategic review 前的装配检查。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "memory readiness stays explicit before strategic review",
                highlights: [
                    "memory_ready=\(input.memoryAssemblyReady)",
                    "memory_top_issue=\(topIssue)"
                ]
            )
            plannerExplain = "\(contractSummary)。当前停在 \(displayBlockerLabel(topIssue))；需要先把 strategic memory 从 underfed 拉回 review-ready，才适合继续推进纠偏或评审。"
        } else {
            intakeStatus = StatusExplanation(
                state: .ready,
                headline: "提交 one-shot intake 以开始复杂任务",
                whatHappened: "Cockpit 已把任务接入、规划说明、阻塞卡和交付冻结收在同一个入口里。",
                whyItHappened: "新的复杂任务从这里发起，后续状态也会持续显式展示。",
                userAction: directedResumeSummary ?? "点击“提交 one-shot intake”，输入目标 / 约束 / 交付物 / 风险。默认先按功能开发场景起步；如果这是原型、产品开局或大型项目，也直接写出来。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "validated-mainline-only remains the only external scope",
                highlights: [
                    contractSummary,
                    "primary_cta=submit_intake",
                    "validated_paths=\((input.scopeFreezeValidatedScope.isEmpty ? badge.validatedPaths : input.scopeFreezeValidatedScope).joined(separator: ","))"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: input.directedUnblockBatonCount > 0 ? .inProgress : .ready,
                headline: input.directedUnblockBatonCount > 0 ? topBlockerHeadline("directed_resume_available") : topBlockerHeadline("none"),
                whatHappened: input.directedUnblockBatonCount > 0 ? "当前存在可执行的 directed resume baton。" : "当前没有显式 blocker；下一步会由这次 one-shot intake 启动 planner。",
                whyItHappened: input.directedUnblockBatonCount > 0 ? "baton 已把恢复动作收口到继续当前任务，不允许 scope expand。" : "就算现在是 ready，也会明确告诉你下一步，而不是留空。",
                userAction: directedResumeSummary ?? "提交 one-shot intake，默认先走功能开发场景；提交后继续看 planner explain 与 blocker card。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "grant / scope / secret blocker will still fail-closed once triggered",
                highlights: ["xt_ready_status=\(input.xtReadyStatus)"]
            )
            plannerExplain = "\(contractSummary)。当前处于 ready；一旦提交复杂任务，Cockpit 会把 planner explain、blocker、baton 与 next action 持续显式展示。"
        }

        let releaseFreezeState: XTUISurfaceState = (freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty) ? .blockedWaitingUpstream : .releaseFrozen
        let releaseNextAction = input.scopeFreezeNextActions.first ?? "review delivery 时只引用 validated refs；任何新 surface 另起切片。"
        let validatedScope = input.scopeFreezeValidatedScope.isEmpty ? badge.validatedPaths : input.scopeFreezeValidatedScope
        let replayRef = input.replayEvidenceRefs.first ?? input.xtReadyReportPath

        let releaseFreezeStatus = StatusExplanation(
            state: releaseFreezeState,
            headline: "已验证主链 / 交付冻结（\(freezeDecisionLabel(freezeDecision))）",
            whatHappened: "Cockpit 只围绕 \(validatedScope.joined(separator: " → ")) 这条已验证主链来展示与复盘；对外表述也只用允许的口径。",
            whyItHappened: "这一轮只沿已验证范围推进，不把未验证功能重新拉回当前界面。",
            userAction: releaseNextAction,
            machineStatusRef: "current_release_scope=\(badge.currentReleaseScope); validated_paths=\(validatedScope.joined(separator: ",")); decision=\(freezeDecision); allowed_public_statements=\(input.allowedPublicStatementCount); replay=\(replayStatus)",
            hardLine: "scope_not_validated must remain visible",
            highlights: [
                "release_statement_allowlist=validated_mainline_only",
                "allowed_public_statements=\(input.allowedPublicStatementCount)",
                "replay_fail_closed_scenarios=\(input.replayFailClosedScenarioCount)/\(input.replayScenarioCount)"
            ] + input.scopeFreezeBlockedExpansionItems.prefix(3).map { "blocked_item=\($0)" }
        )

        let actions = [
            PrimaryActionRailAction(
                id: "submit_intake",
                title: "提交 one-shot intake",
                subtitle: directedResumeSummary ?? "默认按功能开发场景起步，把复杂任务送进 planner，并持续显示发生了什么、为什么、下一步",
                systemImage: "paperplane.circle.fill",
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "approve_risk",
                title: "审批风险授权",
                subtitle: input.grantGateMode.map { "遇到 Hub 授权阻塞时先完成授权（\($0)）" } ?? "遇到 Hub 授权阻塞时先完成授权，不越过 fail-closed 边界",
                systemImage: "checkmark.shield",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "review_delivery",
                title: "查看交付冻结",
                subtitle: "freeze=\(freezeDecision) · replay=\(replayStatus) · refs=\(replayRef.isEmpty ? 0 : 1)",
                systemImage: "doc.text.magnifyingglass",
                style: .diagnostic
            )
        ]

        return SupervisorCockpitPresentation(
            badge: badge,
            runtimeStageRail: runtimeStageRail,
            intakeStatus: intakeStatus,
            blockerStatus: blockerStatus,
            releaseFreezeStatus: releaseFreezeStatus,
            reviewMemorySummary: input.reviewMemorySummary,
            plannerExplain: plannerExplain,
            plannerMachineStatusRef: plannerMachineStatusRef,
            actions: actions,
            reviewReportPath: replayRef,
            consumedFrozenFields: [
                "xt.ui_information_architecture.v1.primary_actions.xt.supervisor_cockpit",
                "xt.ui_surface_state_contract.v1.state_types",
                "xt.ui_release_scope_badge.v1.validated_paths",
                "xt.one_shot_run_state.v1.state",
                "xt.unblock_baton.v1.next_action",
                "xt.delivery_scope_freeze.v1.validated_scope",
                "xt.one_shot_autonomy_policy.v1.auto_launch_policy",
                "xt.one_shot_replay_regression.v1.scenarios"
            ]
        )
    }

    private static func topBlockerHeadline(_ raw: String) -> String {
        "Top blocker: \(displayBlockerLabel(raw))"
    }

    private static func displayBlockerLabel(_ raw: String) -> String {
        SupervisorBlockerPresentation.label(raw)
    }

    private static func freezeDecisionLabel(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "go":
            return "go（仅按已验证主链收口）"
        case "no_go":
            return "no-go（当前禁止扩范围）"
        case "pending":
            return "待确认（pending）"
        default:
            return raw
        }
    }

    private static func buildRuntimeStageRail(
        input: SupervisorCockpitPresentationInput,
        oneShotState: OneShotRunStateStatus?,
        oneShotOwner: String,
        oneShotTopBlocker: String,
        oneShotSummary: String,
        oneShotNextTarget: String,
        freezeDecision: String,
        plannerMachineStatusRef: String
    ) -> SupervisorRuntimeStageRailPresentation {
        let accessItem = runtimeAccessStage(input: input, oneShotState: oneShotState, oneShotTopBlocker: oneShotTopBlocker)
        let runtimeItem = runtimeExecutionStage(
            input: input,
            oneShotState: oneShotState,
            oneShotTopBlocker: oneShotTopBlocker,
            oneShotSummary: oneShotSummary
        )
        let freezeItem = runtimeFreezeStage(
            input: input,
            oneShotState: oneShotState,
            freezeDecision: freezeDecision
        )
        let summary = [
            "state=\(oneShotState?.rawValue ?? "none")",
            "owner=\(oneShotOwner)",
            "next=\(oneShotNextTarget)",
            oneShotTopBlocker == "none" ? nil : "当前阻塞：\(displayBlockerLabel(oneShotTopBlocker))"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        return SupervisorRuntimeStageRailPresentation(
            headline: "一键任务运行阶段",
            summary: summary.isEmpty ? "提交任务后会依次经过接入校验、执行推进和交付冻结。" : summary,
            items: [
                SupervisorRuntimeStageItemPresentation(
                    id: "intake",
                    title: "接入",
                    detail: oneShotState == nil
                        ? "等待提交复杂任务并冻结目标/约束/交付物。"
                        : "请求已被接入，并写入当前运行状态。",
                    progress: oneShotState == nil ? .active : .completed,
                    surfaceState: oneShotState == nil ? .ready : .inProgress,
                    actionID: "submit_intake",
                    actionLabel: "打开接入"
                ),
                accessItem,
                runtimeItem,
                freezeItem
            ],
            machineStatusRef: plannerMachineStatusRef
        )
    }

    private static func runtimeAccessStage(
        input: SupervisorCockpitPresentationInput,
        oneShotState: OneShotRunStateStatus?,
        oneShotTopBlocker: String
    ) -> SupervisorRuntimeStageItemPresentation {
        let topLaunchIssue = input.topLaunchDenyCode.flatMap(
            UITroubleshootKnowledgeBase.issue(forFailureCode:)
        )
        let supervisorRouteHint = supervisorRouteGovernanceHint(for: oneShotTopBlocker)

        if topLaunchIssue == .permissionDenied || oneShotTopBlocker == "permission_denied" {
            return SupervisorRuntimeStageItemPresentation(
                id: "access",
                title: "授权",
                detail: "权限链路拒绝，需先修复 trust / authz 配置。",
                progress: .blocked,
                surfaceState: .permissionDenied,
                actionID: "resolve_access",
                actionLabel: "打开修复"
            )
        }

        if input.pendingGrantCount > 0 || topLaunchIssue == .grantRequired || oneShotState == .awaitingGrant {
            return SupervisorRuntimeStageItemPresentation(
                id: "access",
                title: "授权",
                detail: "风险授权仍未完成，这条路会继续被挡住。",
                progress: .active,
                surfaceState: .grantRequired,
                actionID: "resolve_access",
                actionLabel: "打开授权"
            )
        }

        if topLaunchIssue == .modelNotReady || topLaunchIssue == .paidModelAccessBlocked {
            return SupervisorRuntimeStageItemPresentation(
                id: "access",
                title: "授权",
                detail: topLaunchIssue == .paidModelAccessBlocked
                    ? "付费模型资格、allowlist 或预算仍未收敛，需先回模型入口核对。"
                    : "模型 / provider 还没 ready，需先核对真实可执行模型与路由。",
                progress: .blocked,
                surfaceState: .diagnosticRequired,
                actionID: "open_model_route_readiness",
                actionLabel: topLaunchIssue == .paidModelAccessBlocked ? "检查付费模型" : "检查模型"
            )
        }

        if topLaunchIssue == .connectorScopeBlocked {
            return SupervisorRuntimeStageItemPresentation(
                id: "access",
                title: "授权",
                detail: "远端导出或 paid connector scope 被边界挡住，需先检查 Hub Recovery。",
                progress: .blocked,
                surfaceState: .diagnosticRequired,
                actionID: "open_hub_recovery",
                actionLabel: "检查 Hub Recovery"
            )
        }

        if topLaunchIssue == .pairingRepairRequired
            || topLaunchIssue == .multipleHubsAmbiguous
            || topLaunchIssue == .hubPortConflict
            || topLaunchIssue == .hubUnreachable {
            return SupervisorRuntimeStageItemPresentation(
                id: "access",
                title: "授权",
                detail: "Hub 连接或配对事实还没恢复，需先回 Pair Hub / diagnostics 修连接。",
                progress: .blocked,
                surfaceState: .blockedWaitingUpstream,
                actionID: "pair_hub",
                actionLabel: "检查 Hub"
            )
        }

        if let supervisorRouteHint {
            switch supervisorRouteHint.blockedPlane {
            case .grantReady:
                return SupervisorRuntimeStageItemPresentation(
                    id: "access",
                    title: "授权",
                    detail: supervisorRouteHint.summaryText,
                    progress: .blocked,
                    surfaceState: .permissionDenied,
                    actionID: "resolve_access",
                    actionLabel: "检查治理"
                )
            case .routeReady:
                return SupervisorRuntimeStageItemPresentation(
                    id: "access",
                    title: "授权",
                    detail: supervisorRouteHint.summaryText,
                    progress: .blocked,
                    surfaceState: .blockedWaitingUpstream,
                    actionID: "pair_hub",
                    actionLabel: "检查路由"
                )
            default:
                break
            }
        }

        if let oneShotState,
           oneShotState != .intakeNormalized {
            return SupervisorRuntimeStageItemPresentation(
                id: "access",
                title: "授权",
                detail: "授权链已验证通过，或当前路径无需额外授权。",
                progress: .completed,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        }

        return SupervisorRuntimeStageItemPresentation(
            id: "access",
            title: "授权",
            detail: "等待授权 / 权限决议。",
            progress: .pending,
            surfaceState: .ready,
            actionID: nil,
            actionLabel: nil
        )
    }

    private static func runtimeExecutionStage(
        input: SupervisorCockpitPresentationInput,
        oneShotState: OneShotRunStateStatus?,
        oneShotTopBlocker: String,
        oneShotSummary: String
    ) -> SupervisorRuntimeStageItemPresentation {
        let supervisorRouteHint = supervisorRouteGovernanceHint(for: oneShotTopBlocker)
        let blockerIssue = UITroubleshootKnowledgeBase.issue(forFailureCode: oneShotTopBlocker)
        let blockerRepairAction = cockpitRepairAction(
            for: blockerIssue,
            supervisorRouteHint: supervisorRouteHint
        )

        switch oneShotState {
        case .planning, .launching, .running, .resuming, .mergeback:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: oneShotSummary.isEmpty
                    ? "当前有 \(input.oneShotRuntimeActiveLaneCount) 条 lane 在推进，planner / launch / mergeback 正在运行。"
                    : oneShotSummary,
                progress: .active,
                surfaceState: .inProgress,
                actionID: nil,
                actionLabel: nil
            )
        case .blocked:
            let hasDirectedResume = input.directedUnblockBatonCount > 0
                && (input.nextDirectedResumeAction?.isEmpty == false)
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: oneShotSummary.isEmpty
                    ? runtimeBlockedSummary(
                        oneShotTopBlocker: oneShotTopBlocker,
                        supervisorRouteHint: supervisorRouteHint
                    )
                    : oneShotSummary,
                progress: .blocked,
                surfaceState: cockpitSurfaceState(
                    for: blockerIssue,
                    supervisorRouteHint: supervisorRouteHint
                ),
                actionID: hasDirectedResume ? "directed_resume" : blockerRepairAction?.id,
                actionLabel: hasDirectedResume ? "继续泳道" : blockerRepairAction?.label
            )
        case .failedClosed:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: oneShotSummary.isEmpty
                    ? failedClosedRuntimeSummary(
                        oneShotTopBlocker: oneShotTopBlocker,
                        supervisorRouteHint: supervisorRouteHint
                    )
                    : oneShotSummary,
                progress: .blocked,
                surfaceState: cockpitSurfaceState(
                    for: blockerIssue,
                    supervisorRouteHint: supervisorRouteHint
                ),
                actionID: blockerRepairAction?.id,
                actionLabel: blockerRepairAction?.label
            )
        case .deliveryFreeze, .completed:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: "主执行链已结束，正在做 freeze / completion 收口。",
                progress: .completed,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        case .awaitingGrant:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: "等待授权放行后才会真正执行。",
                progress: .pending,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        case .intakeNormalized, nil:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: "等待 planner / launcher 接手当前任务。",
                progress: .pending,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        }
    }

    private static func cockpitSurfaceState(
        for issue: UITroubleshootIssue?,
        supervisorRouteHint: XTSupervisorRouteGovernanceHint? = nil
    ) -> XTUISurfaceState {
        if let supervisorRouteHint {
            switch supervisorRouteHint.blockedPlane {
            case .grantReady:
                return .permissionDenied
            case .routeReady:
                return .blockedWaitingUpstream
            default:
                break
            }
        }

        switch issue {
        case .grantRequired:
            return .grantRequired
        case .permissionDenied:
            return .permissionDenied
        case .modelNotReady, .connectorScopeBlocked, .paidModelAccessBlocked:
            return .diagnosticRequired
        default:
            return .blockedWaitingUpstream
        }
    }

    private static func cockpitRepairAction(
        for issue: UITroubleshootIssue?,
        supervisorRouteHint: XTSupervisorRouteGovernanceHint? = nil
    ) -> (id: String, label: String)? {
        if let supervisorRouteHint {
            switch supervisorRouteHint.blockedPlane {
            case .grantReady:
                return ("resolve_access", "检查治理")
            case .routeReady:
                return ("pair_hub", "检查路由")
            default:
                break
            }
        }

        switch issue {
        case .grantRequired:
            return ("resolve_access", "打开授权")
        case .permissionDenied:
            return ("resolve_access", "打开修复")
        case .modelNotReady:
            return ("open_model_route_readiness", "检查模型")
        case .paidModelAccessBlocked:
            return ("open_model_route_readiness", "检查付费模型")
        case .connectorScopeBlocked:
            return ("open_hub_recovery", "检查 Hub Recovery")
        case .pairingRepairRequired, .multipleHubsAmbiguous, .hubPortConflict, .hubUnreachable:
            return ("pair_hub", "检查 Hub")
        case .none:
            return nil
        }
    }

    private static func supervisorRouteGovernanceHint(
        for blockerCode: String
    ) -> XTSupervisorRouteGovernanceHint? {
        XTRouteTruthPresentation.supervisorRouteGovernanceHint(
            routeReasonCode: blockerCode
        )
    }

    private static func runtimeBlockedSummary(
        oneShotTopBlocker: String,
        supervisorRouteHint: XTSupervisorRouteGovernanceHint?
    ) -> String {
        if let supervisorRouteHint {
            return supervisorRouteHint.summaryText
        }
        return "当前执行被\(displayBlockerLabel(oneShotTopBlocker))挡住。"
    }

    private static func failedClosedRuntimeSummary(
        oneShotTopBlocker: String,
        supervisorRouteHint: XTSupervisorRouteGovernanceHint?
    ) -> String {
        if let supervisorRouteHint {
            return "runtime 已 fail-closed。\(supervisorRouteHint.summaryText)"
        }
        return "runtime 已 fail-closed，当前阻塞：\(displayBlockerLabel(oneShotTopBlocker))。"
    }

    private static func runtimeFreezeStage(
        input: SupervisorCockpitPresentationInput,
        oneShotState: OneShotRunStateStatus?,
        freezeDecision: String
    ) -> SupervisorRuntimeStageItemPresentation {
        let memoryNeedsReview = !input.memoryAssemblyReady || input.memoryAssemblyIssueCount > 0
        if input.topLaunchDenyCode == "scope_expansion" || freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty {
            return SupervisorRuntimeStageItemPresentation(
                id: "freeze",
                title: "冻结",
                detail: input.scopeFreezeBlockedExpansionItems.isEmpty
                    ? "当前交付范围为 \(freezeDecisionLabel(freezeDecision))。"
                    : "超出已验证范围的项：\(input.scopeFreezeBlockedExpansionItems.joined(separator: "，"))",
                progress: .blocked,
                surfaceState: .blockedWaitingUpstream,
                actionID: "review_delivery",
                actionLabel: "打开复盘"
            )
        }

        switch oneShotState {
        case .deliveryFreeze:
            return SupervisorRuntimeStageItemPresentation(
                id: "freeze",
                title: "冻结",
                detail: memoryNeedsReview
                    ? "交付冻结进行中，但 strategic memory 仍需补齐后再 review delivery。"
                    : "交付冻结进行中，等待更完整的证据和 review delivery。",
                progress: .active,
                surfaceState: input.xtReadyStrictE2EReady && input.xtReadyIssueCount == 0 && !memoryNeedsReview ? .releaseFrozen : .diagnosticRequired,
                actionID: "review_delivery",
                actionLabel: "打开复盘"
            )
        case .completed:
            return SupervisorRuntimeStageItemPresentation(
                id: "freeze",
                title: "冻结",
                detail: memoryNeedsReview
                    ? "这条已验证主链已完成执行，但 release freeze 前还要补齐 strategic memory。"
                    : "这条已验证主链已经完成冻结收口。",
                progress: .completed,
                surfaceState: memoryNeedsReview ? .diagnosticRequired : .releaseFrozen,
                actionID: "review_delivery",
                actionLabel: "查看报告"
            )
        default:
            return SupervisorRuntimeStageItemPresentation(
                id: "freeze",
                title: "冻结",
                detail: "当前尚未进入交付冻结。",
                progress: .pending,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        }
    }
}
