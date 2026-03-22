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
                pendingGrantCount: supervisorManager.pendingHubGrants.count,
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

        let intakeStatus: StatusExplanation
        let blockerStatus: StatusExplanation
        let plannerExplain: String

        if input.pendingGrantCount > 0 || input.topLaunchDenyCode == "grant_required" || oneShotState == .awaitingGrant {
            intakeStatus = StatusExplanation(
                state: .grantRequired,
                headline: "one-shot intake 已接收，但等待风险授权",
                whatHappened: oneShotSummary.isEmpty ? "Cockpit 发现授权链仍未完成，runtime policy 保持 fail-closed，不放行高风险 lane。" : oneShotSummary,
                whyItHappened: "grant_required 来自 AI-2 runtime 合同、one-shot run state 与 lane launch deny 决策；未授权前不会越过 grant gate。",
                userAction: directedResumeSummary ?? "先审批风险授权，再继续当前 one-shot intake。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "grant_fail_closed must remain visible",
                highlights: [
                    contractSummary,
                    "human_touchpoints=\(input.humanTouchpointCount)",
                    "denied_launches=\(input.deniedLaunchCount)",
                    "owner=\(oneShotOwner)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .grantRequired,
                headline: "Top blocker: \(oneShotTopBlocker == "none" ? "grant_required" : oneShotTopBlocker)",
                whatHappened: "当前主 blocker 是 grant chain 未完成，auto-launch 被显式 deny。",
                whyItHappened: "AI-2 的 `oneShotAutonomyPolicy` 与 `laneLaunchDecisions` 明确要求保持 fail-closed。",
                userAction: directedResumeSummary ?? "在 grant center 完成审批，然后回到当前 intake。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "high-risk path remains fail-closed",
                highlights: [input.grantGateMode.map { "grant_gate_mode=\($0)" } ?? "", "next_target=\(oneShotNextTarget)"]
                    .filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。one-shot intake → planner explain → blocker triage → delivery freeze。当前停在 awaiting_grant；grant gate 未绿前不会自动继续。"
        } else if input.topLaunchDenyCode == "permission_denied" || oneShotTopBlocker == "permission_denied" {
            intakeStatus = StatusExplanation(
                state: .permissionDenied,
                headline: "runtime patch 检出 permission_denied，自动启动保持关闭",
                whatHappened: "lane launch 决策返回 permission_denied，当前链路不会被 UI 包装成可继续。",
                whyItHappened: "AI-2 在 runtime deny 决策里显式发出了 `permission_denied`，属于必须可见的 fail-closed 状态。",
                userAction: directedResumeSummary ?? "先修复权限或授权配置，再重新发起 intake / resume。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "permission_denied remains explicit",
                highlights: [contractSummary, "top_launch_deny_code=permission_denied"].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .permissionDenied,
                headline: "Top blocker: permission_denied",
                whatHappened: "当前主 blocker 是权限链路拒绝。",
                whyItHappened: "runtime deny note 会在 UI 中保持可见，避免误导用户为普通等待态。",
                userAction: directedResumeSummary ?? "先处理权限问题，再回到当前复杂任务。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "authz must stay fail-closed",
                highlights: ["denied_launches=\(input.deniedLaunchCount)"]
            )
            plannerExplain = "\(contractSummary)。当前停在 permission_denied；lane launch deny 已把权限问题前移到 cockpit。"
        } else if input.topLaunchDenyCode == "scope_expansion" || freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty {
            let blockedItems = input.scopeFreezeBlockedExpansionItems.joined(separator: ",")
            let nextAction = input.scopeFreezeNextActions.first ?? "drop_scope_expansion"
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "validated scope freeze 拒绝 scope expansion",
                whatHappened: "delivery scope freeze 标记为 `\(freezeDecision)`，且存在超出 validated mainline 的扩 scope 项。",
                whyItHappened: "AI-2 的 `xt.delivery_scope_freeze.v1` 已明确 no-go / blocked expansion，UI 继续保持 fail-closed。",
                userAction: nextAction,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "scope_not_validated must remain visible",
                highlights: [contractSummary, blockedItems.isEmpty ? "" : "blocked_expansion=\(blockedItems)"].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "Top blocker: scope_expansion",
                whatHappened: "当前主 blocker 是请求范围超出 validated scope。",
                whyItHappened: "scope freeze 已落下 no-go 决策，因此不能继续对外或对内暗示已验证。",
                userAction: nextAction,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "validated-mainline-only stays enforced",
                highlights: ["validated_scope=\(input.scopeFreezeValidatedScope.joined(separator: ","))"].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 scope_expansion；需先回退到 validated mainline，再重新计算 delivery freeze。"
        } else if input.releaseBlockedByDoctorWithoutReport != 0 {
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "Cockpit 等待 Doctor 预检证据",
                whatHappened: "当前缺少可用的 Doctor release 证据，因此 release 相关动作仍保持阻断。",
                whyItHappened: "secret scrub、diagnostics 与 fail-closed 口径要求先有机读报告，再允许 UI 提示可继续。",
                userAction: "运行 Doctor 预检，确认阻断项与建议卡后再 review delivery。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "diagnostic_required remains visible",
                highlights: [contractSummary, "doctor_suggestions=\(input.doctorSuggestionCount)"].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "Top blocker: diagnostic_required",
                whatHappened: "当前主 blocker 是 Doctor 证据链未就绪。",
                whyItHappened: "缺少 Doctor 报告时，release line 不能被 UI 包装成已放行。",
                userAction: "先运行 diagnostics，再回到 review delivery。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "release stays fail-closed without doctor report",
                highlights: ["release_blocked_by_doctor_without_report=\(input.releaseBlockedByDoctorWithoutReport)"]
            )
            plannerExplain = "\(contractSummary)。当前停在 diagnostic_required，因为 Doctor / secret scrub 证据尚未齐备。"
        } else if oneShotState == .failedClosed {
            let recommendation = directedResumeSummary ?? input.scopeFreezeNextActions.first ?? "先修复 fail-closed blocker，再重新发起当前 one-shot。"
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "one-shot runtime 已 fail-closed",
                whatHappened: oneShotSummary.isEmpty ? "运行时没有继续假装可恢复，而是明确停在 fail-closed。" : oneShotSummary,
                whyItHappened: "真实 one-shot run state 已进入 failed_closed；cockpit 必须直出 blocker，而不是退回泛化的 planning / ready 文案。",
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
                headline: "Top blocker: \(oneShotTopBlocker)",
                whatHappened: "当前主 blocker 来自 one-shot runtime fail-closed。",
                whyItHappened: "执行链已经做出 fail-closed 判定，所以 UI 不能回退成普通等待态。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "runtime blocker stays explicit",
                highlights: [input.oneShotRuntimeState.map { "one_shot_state=\($0)" } ?? ""].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 failed_closed；需先消除 blocker=\(oneShotTopBlocker)，再允许重试当前 one-shot 主链。"
        } else if oneShotState == .blocked || input.laneSummary.failed > 0 || input.laneSummary.stalled > 0 || input.laneSummary.blocked > 0 {
            let abnormalStatus = input.abnormalLaneStatus ?? "lane_health_abnormal"
            let recommendation = directedResumeSummary ?? input.abnormalLaneRecommendation ?? "查看 lane 健康态与阻塞原因，按 next action 续推。"
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "one-shot run 已进入执行，但当前存在 blocker",
                whatHappened: oneShotSummary.isEmpty ? "lane snapshot 显示 blocked/stalled/failed，且可选 directed resume baton 已可消费。" : oneShotSummary,
                whyItHappened: "冻结契约要求 Supervisor cockpit 清楚暴露 blocker、resume baton 与 next action，而不是只显示聊天流水。",
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
                headline: "Top blocker: \(oneShotTopBlocker == "none" ? abnormalStatus : oneShotTopBlocker)",
                whatHappened: oneShotState == .blocked ? "当前主 blocker 已被 one-shot runtime 直接声明。" : "当前主 blocker 来自 lane health abnormal。",
                whyItHappened: "planner 不会隐藏上游依赖或 runtime blocker；已有 baton 时也只允许 directed resume。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "upstream blocker stays explicit",
                highlights: [
                    directedResumeSummary ?? "",
                    "xt_ready_status=\(input.xtReadyStatus)"
                ].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。one-shot intake → planner explain → blocker triage → delivery freeze。当前停在 blocked_waiting_upstream；如 baton 已发出，则只允许 directed resume。"
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
                whatHappened: oneShotSummary.isEmpty ? "Cockpit 发现 planner 正在归一化任务、分配 lane，并带着 AI-2 runtime policy / freeze / replay 合同推进。" : oneShotSummary,
                whyItHappened: "XT-W3-27-D 现已绑定真实 runtime 数据，不再只依赖 mock 状态映射。",
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
                headline: input.directedUnblockBatonCount > 0 ? "Top blocker: directed_resume_available" : "Top blocker: none",
                whatHappened: input.directedUnblockBatonCount > 0 ? "当前没有新硬阻塞，但已存在 directed resume baton 可供续推。" : "当前没有 grant / doctor / lane 异常硬阻塞。",
                whyItHappened: input.directedUnblockBatonCount > 0 ? "AI-2 的 baton 路由已把 resume scope 收敛到 continue_current_task_only。" : "执行仍在进行，但没有额外 fail-closed blocker 需要立刻人工干预。",
                userAction: directedResumeSummary ?? "继续观察 planner explain，并在需要时 review delivery。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "scope freeze still applies",
                highlights: ["xt_ready_status=\(input.xtReadyStatus)", "owner=\(oneShotOwner)"]
            )
            plannerExplain = "\(contractSummary)。one-shot intake → planner explain → blocker triage → delivery freeze。当前处于 \(input.oneShotRuntimeState ?? "planning_or_running")，并附带 replay=\(replayStatus)、freeze=\(freezeDecision) 的解释上下文。"
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
            let deliveryBlockerHeadline = memoryUnderfed ? "Top blocker: memory_context_underfed" : "Top blocker: review_delivery"
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
                ? "\(contractSummary)。当前停在 memory_context_underfed；需先补齐 strategic review memory，再进入可信的 delivery review。"
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
                headline: "Top blocker: \(topIssue)",
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
            plannerExplain = "\(contractSummary)。当前停在 \(topIssue)；需要先把 strategic memory 从 underfed 拉回 review-ready，才适合继续推进纠偏或评审。"
        } else {
            intakeStatus = StatusExplanation(
                state: .ready,
                headline: "提交 one-shot intake 以开始复杂任务",
                whatHappened: "Cockpit 已把 one-shot intake、planner explain、blocker、resume baton 与 validated scope freeze 组合成首个可运行入口。",
                whyItHappened: "AI-3 当前已消费 AI-2 runtime 合同，不等待整包验证恢复后才展示真实状态语义。",
                userAction: directedResumeSummary ?? "点击“提交 one-shot intake”，输入目标 / 约束 / 交付物 / 风险。",
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
                headline: input.directedUnblockBatonCount > 0 ? "Top blocker: directed_resume_available" : "Top blocker: none",
                whatHappened: input.directedUnblockBatonCount > 0 ? "当前存在可执行的 directed resume baton。" : "当前没有显式 blocker；下一步由 one-shot intake 驱动 planner。",
                whyItHappened: input.directedUnblockBatonCount > 0 ? "baton 已把恢复动作收敛到继续当前任务，不允许 scope expand。" : "冻结契约要求 UI 在 ready 态也明确 next action，而不是显示空白。",
                userAction: directedResumeSummary ?? "提交 one-shot intake，随后观察 planner explain 与 blocker card。",
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
            headline: "validated-mainline-only / delivery scope freeze (\(freezeDecision))",
            whatHappened: "Cockpit 明确只围绕 \(validatedScope.joined(separator: " → ")) 的 validated mainline 展示与复盘；对外文案只消费 allowlist。",
            whyItHappened: "R1 不扩 scope，不把未验证 surface 重新拉回当前 claim；AI-2 的 freeze 与 replay 摘要已成为 UI 真实数据源。",
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
                subtitle: directedResumeSummary ?? "把复杂任务送入 planner，并保留 what happened / why / next action",
                systemImage: "paperplane.circle.fill",
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "approve_risk",
                title: "审批风险授权",
                subtitle: input.grantGateMode.map { "grant_required 时先走授权（\($0)）" } ?? "grant_required 时先走授权，不越过 fail-closed 边界",
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
            oneShotTopBlocker == "none" ? nil : "blocker=\(oneShotTopBlocker)"
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
                        : "请求已被 intake 接收并写入 runtime contract。",
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
        if input.topLaunchDenyCode == "permission_denied" || oneShotTopBlocker == "permission_denied" {
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

        if input.pendingGrantCount > 0 || input.topLaunchDenyCode == "grant_required" || oneShotState == .awaitingGrant {
            return SupervisorRuntimeStageItemPresentation(
                id: "access",
                title: "授权",
                detail: "风险授权仍未完成，grant gate 保持 fail-closed。",
                progress: .active,
                surfaceState: .grantRequired,
                actionID: "resolve_access",
                actionLabel: "打开授权"
            )
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
            detail: "等待 risk gate / permission gate 决议。",
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
        switch oneShotState {
        case .planning, .launching, .running, .resuming, .mergeback:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: oneShotSummary.isEmpty
                    ? "active_lanes=\(input.oneShotRuntimeActiveLaneCount) · planner / launch / mergeback 正在推进。"
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
                    ? "runtime 当前阻塞于 \(oneShotTopBlocker)。"
                    : oneShotSummary,
                progress: .blocked,
                surfaceState: .blockedWaitingUpstream,
                actionID: hasDirectedResume ? "directed_resume" : nil,
                actionLabel: hasDirectedResume ? "继续泳道" : nil
            )
        case .failedClosed:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: oneShotSummary.isEmpty
                    ? "runtime 已 fail-closed，blocker=\(oneShotTopBlocker)。"
                    : oneShotSummary,
                progress: .blocked,
                surfaceState: oneShotTopBlocker == "permission_denied" ? .permissionDenied : .blockedWaitingUpstream,
                actionID: nil,
                actionLabel: nil
            )
        case .deliveryFreeze, .completed:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: "主执行链已结束，进入 freeze / completion 收口。",
                progress: .completed,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        case .awaitingGrant:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: "等待 access gate 放行后才会真正执行。",
                progress: .pending,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        case .intakeNormalized, nil:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "执行",
                detail: "等待 planner / launcher 接手当前 one-shot。",
                progress: .pending,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        }
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
                    ? "validated scope freeze 当前为 \(freezeDecision)。"
                    : "blocked_expansion=\(input.scopeFreezeBlockedExpansionItems.joined(separator: ","))",
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
                    : "交付冻结进行中，等待 strict evidence / review delivery。",
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
                    ? "validated mainline 已完成执行，但 release freeze 仍需补齐 strategic memory。"
                    : "validated mainline 已完成冻结收口。",
                progress: .completed,
                surfaceState: memoryNeedsReview ? .diagnosticRequired : .releaseFrozen,
                actionID: "review_delivery",
                actionLabel: "查看报告"
            )
        default:
            return SupervisorRuntimeStageItemPresentation(
                id: "freeze",
                title: "冻结",
                detail: "当前尚未进入 delivery freeze。",
                progress: .pending,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        }
    }
}
