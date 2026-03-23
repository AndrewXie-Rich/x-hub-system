import SwiftUI

enum UIFirstRunStepKind: String, CaseIterable, Codable, Sendable {
    case pairHub = "pair_hub"
    case chooseModel = "choose_model"
    case resolveGrant = "resolve_grant"
    case runSmoke = "run_smoke"
    case verifyReadiness = "verify_readiness"
    case startFirstTask = "start_first_task"
}

struct UIFirstRunStep: Identifiable, Codable, Equatable, Sendable {
    let kind: UIFirstRunStepKind
    let title: String
    let summary: String
    let state: XTUISurfaceState
    let repairEntry: UITroubleshootDestination

    var id: String { kind.rawValue }
}

struct UIFirstRunJourneyPlan: Codable, Equatable, Sendable {
    let badge: ValidatedScopePresentation
    let primaryStatus: StatusExplanation
    let releaseStatus: StatusExplanation
    let actions: [PrimaryActionRailAction]
    let steps: [UIFirstRunStep]
    let configuredModelRoles: Int
    let totalModelRoles: Int
    let currentFailureIssue: UITroubleshootIssue?
    let smokeReady: Bool
    let consumedFrozenFields: [String]
}

struct HubSetupWizardState: Codable, Equatable, Sendable {
    let localConnected: Bool
    let remoteConnected: Bool
    let linking: Bool
    let configuredModelRoles: Int
    let totalModelRoles: Int
    let failureCode: String
    let runtime: UIFailClosedRuntimeSnapshot
    let doctor: XTUnifiedDoctorReport

    init(
        localConnected: Bool,
        remoteConnected: Bool,
        linking: Bool,
        configuredModelRoles: Int,
        totalModelRoles: Int,
        failureCode: String,
        runtime: UIFailClosedRuntimeSnapshot,
        doctor: XTUnifiedDoctorReport = .empty
    ) {
        self.localConnected = localConnected
        self.remoteConnected = remoteConnected
        self.linking = linking
        self.configuredModelRoles = configuredModelRoles
        self.totalModelRoles = totalModelRoles
        self.failureCode = failureCode
        self.runtime = runtime
        self.doctor = doctor
    }
}

struct UIFailClosedRuntimeSnapshot: Codable, Equatable, Sendable {
    let scopeDecision: String
    let validatedScope: [String]
    let allowedPublicStatements: [String]
    let scopeNextActions: [String]
    let blockedExpansionItems: [String]
    let launchDenyCodes: [String]
    let launchNotes: [String]
    let failClosedLaunchCount: Int
    let nextDirectedAction: String
    let directedDeadlineHintUTC: String
    let directedMustNotDo: [String]
    let replayPass: Bool?
    let replayScenarioResults: [String]
    let replayDenyCodes: [String]
    let policyGrantGateMode: String
    let policyAutoLaunch: String
    let consumedContracts: [String]

    static let empty = UIFailClosedRuntimeSnapshot(
        scopeDecision: "",
        validatedScope: [],
        allowedPublicStatements: [],
        scopeNextActions: [],
        blockedExpansionItems: [],
        launchDenyCodes: [],
        launchNotes: [],
        failClosedLaunchCount: 0,
        nextDirectedAction: "",
        directedDeadlineHintUTC: "",
        directedMustNotDo: [],
        replayPass: nil,
        replayScenarioResults: [],
        replayDenyCodes: [],
        policyGrantGateMode: "",
        policyAutoLaunch: "",
        consumedContracts: []
    )

    static func capture(
        policy: OneShotAutonomyPolicy?,
        freeze: DeliveryScopeFreeze?,
        launchDecisions: [OneShotLaunchDecision],
        directedUnblockBatons: [DirectedUnblockBaton],
        replayReport: OneShotReplayReport?
    ) -> UIFailClosedRuntimeSnapshot {
        let orderedLaunchDecisions = launchDecisions.sorted { lhs, rhs in
            if lhs.failClosed == rhs.failClosed {
                return lhs.laneID < rhs.laneID
            }
            return lhs.failClosed && !rhs.failClosed
        }
        let orderedBatons = directedUnblockBatons.sorted { $0.emittedAtMs > $1.emittedAtMs }
        let leadBaton = orderedBatons.first

        return UIFailClosedRuntimeSnapshot(
            scopeDecision: freeze?.decision.rawValue ?? "",
            validatedScope: freeze?.validatedScope ?? [],
            allowedPublicStatements: freeze?.allowedPublicStatements ?? [],
            scopeNextActions: freeze?.nextActions ?? [],
            blockedExpansionItems: freeze?.blockedExpansionItems ?? [],
            launchDenyCodes: orderedUnique(orderedLaunchDecisions.map(\.denyCode)),
            launchNotes: orderedUnique(orderedLaunchDecisions.map(\.note)),
            failClosedLaunchCount: orderedLaunchDecisions.filter(\.failClosed).count,
            nextDirectedAction: leadBaton?.nextAction ?? "",
            directedDeadlineHintUTC: leadBaton?.deadlineHintUTC ?? "",
            directedMustNotDo: leadBaton?.mustNotDo ?? [],
            replayPass: replayReport?.pass,
            replayScenarioResults: replayReport?.scenarios.map { scenario in
                let state = scenario.pass ? "pass" : "fail"
                let denyCode = scenario.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(scenario.scenario.rawValue)=\(state)|deny=\(denyCode.isEmpty ? "none" : denyCode)"
            } ?? [],
            replayDenyCodes: orderedUnique(replayReport?.scenarios.map(\.denyCode) ?? []),
            policyGrantGateMode: policy?.grantGateMode ?? "",
            policyAutoLaunch: policy?.autoLaunchPolicy.rawValue ?? "",
            consumedContracts: orderedUnique([
                freeze?.schemaVersion,
                policy?.schemaVersion,
                replayReport?.schemaVersion,
                orderedBatons.isEmpty ? nil : "xt.unblock_baton.v1"
            ].compactMap { $0 })
        )
    }

    var primaryIssue: UITroubleshootIssue? {
        for value in launchDenyCodes + replayDenyCodes + launchNotes {
            if let issue = UITroubleshootKnowledgeBase.issue(forFailureCode: value) {
                return issue
            }
        }
        return nil
    }

    var firstLaunchSignal: String? {
        launchDenyCodes.first(where: { !$0.isEmpty })
            ?? launchNotes.first(where: { !$0.isEmpty })
            ?? replayDenyCodes.first(where: { !$0.isEmpty })
    }

    var allowsValidatedMainline: Bool {
        scopeDecision != DeliveryScopeFreezeDecision.noGo.rawValue
    }

    var replayBlocked: Bool {
        replayPass == false
    }

    var nextRepairAction: String? {
        firstNonEmpty(firstLaunchSignal, scopeNextActions.first)
    }

    var machineStatusSegment: String {
        [
            "scope_decision=\(scopeDecision.isEmpty ? "none" : scopeDecision)",
            "validated_scope=\(validatedScope.isEmpty ? "none" : validatedScope.joined(separator: ","))",
            "launch_deny=\(launchDenyCodes.first(where: { !$0.isEmpty }) ?? "none")",
            "fail_closed_launch_count=\(failClosedLaunchCount)",
            "directed_next=\(nextDirectedAction.isEmpty ? "none" : nextDirectedAction)",
            "replay_pass=\(replayPass.map(String.init(describing:)) ?? "unknown")",
            "grant_gate_mode=\(policyGrantGateMode.isEmpty ? "none" : policyGrantGateMode)"
        ].joined(separator: "; ")
    }

    var statusHighlights: [String] {
        Self.orderedUnique([
            "scope_decision=\(scopeDecision.isEmpty ? "none" : scopeDecision)",
            validatedScope.isEmpty ? nil : "validated_scope=\(validatedScope.joined(separator: ","))",
            allowedPublicStatements.first.map { "allowed_statement=\($0)" },
            launchDenyCodes.first(where: { !$0.isEmpty }).map { "deny_code=\($0)" },
            !nextDirectedAction.isEmpty ? "resume_baton=\(nextDirectedAction)" : nil,
            !directedDeadlineHintUTC.isEmpty ? "deadline_hint_utc=\(directedDeadlineHintUTC)" : nil,
            replayPass.map { "replay_pass=\($0)" },
            !policyAutoLaunch.isEmpty ? "auto_launch_policy=\(policyAutoLaunch)" : nil
        ].compactMap { $0 })
    }

    var diagnosticsLines: [String] {
        Self.orderedUnique([
            "delivery_scope_decision=\(scopeDecision.isEmpty ? "none" : scopeDecision)",
            validatedScope.isEmpty ? nil : "validated_scope=\(validatedScope.joined(separator: " | "))",
            allowedPublicStatements.isEmpty ? nil : "allowed_public_statements=\(allowedPublicStatements.joined(separator: " | "))",
            launchDenyCodes.first(where: { !$0.isEmpty }).map { "launch_deny_code=\($0)" },
            !nextDirectedAction.isEmpty ? "resume_baton=\(nextDirectedAction)" : nil,
            !directedDeadlineHintUTC.isEmpty ? "resume_deadline_utc=\(directedDeadlineHintUTC)" : nil,
            replayScenarioResults.isEmpty ? nil : "replay=\(replayScenarioResults.joined(separator: " ; "))"
        ].compactMap { $0 })
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for rawValue in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else { continue }
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.isEmpty == false })
    }
}

enum UIFirstRunJourneyPlanner {
    static let releaseScope = "XT-W3-23 -> XT-W3-24 -> XT-W3-25 mainline only"

    static func plan(for state: HubSetupWizardState) -> UIFirstRunJourneyPlan {
        let badge = ValidatedScopePresentation.validatedMainlineOnly
        let connected = state.localConnected || state.remoteConnected
        let hasModel = state.configuredModelRoles > 0
        let failureIssue = UITroubleshootKnowledgeBase.issue(forFailureCode: state.failureCode) ?? state.runtime.primaryIssue
        let machineStatusRef = [
            "local_connected=\(state.localConnected)",
            "remote_connected=\(state.remoteConnected)",
            "linking=\(state.linking)",
            "configured_roles=\(state.configuredModelRoles)/\(state.totalModelRoles)",
            "failure_code=\(state.failureCode.isEmpty ? "none" : state.failureCode)",
            state.runtime.machineStatusSegment
        ].joined(separator: "; ")

        let primaryStatus: StatusExplanation
        if !connected {
            primaryStatus = StatusExplanation(
                state: failureIssue == .hubUnreachable ? .diagnosticRequired : .blockedWaitingUpstream,
                headline: "先 Pair Hub，再继续首用路径",
                whatHappened: "Hub truth source 尚未进入可交互状态，因此首用主链仍停在 pair / connect。",
                whyItHappened: "向导会在 Hub 未连接时明确显示阻塞原因，并把 freeze、replay 和恢复线索放到同一张状态卡里。",
                userAction: state.runtime.nextRepairAction ?? "先完成 One-Click Setup；如失败，按 grant / permission / hub_unreachable 的 3 步排障继续。",
                machineStatusRef: machineStatusRef,
                hardLine: "require-real / grant / scope boundary remain fail-closed",
                highlights: mergedHighlights([
                    "primary_cta=pair_hub",
                    "diagnostic_entrypoint=pairing_health"
                ], runtime: state.runtime)
            )
        } else if failureIssue == .grantRequired {
            primaryStatus = StatusExplanation(
                state: .grantRequired,
                headline: "模型已可见，但 grant 仍待放行",
                whatHappened: "首用路径已经到模型 / grant 这一段；当前 lane launch 或 replay 合同仍返回 fail-closed 的 grant_required 信号。",
                whyItHappened: "授权失败、说明和回放结果会被合并判断，修复入口也尽量限制在 3 步内。",
                userAction: state.runtime.nextRepairAction ?? "先去 Hub 授权、能力范围与配额入口修复，再回到 smoke。",
                machineStatusRef: machineStatusRef,
                hardLine: "grant_fail_closed must remain visible",
                highlights: mergedHighlights([
                    "repair_entry=Hub Settings → Grants & Permissions",
                    "next_step=run_smoke_after_grant"
                ], runtime: state.runtime)
            )
        } else if failureIssue == .permissionDenied {
            primaryStatus = StatusExplanation(
                state: .permissionDenied,
                headline: "权限或 policy 拒绝，需要先修复入口",
                whatHappened: "当前阻塞来自系统权限、device capability 或 Hub policy；对应 denyCode 已并入当前 UI 状态。",
                whyItHappened: "权限拒绝会直接显示出来，避免你在系统设置、Hub 和向导之间来回猜。",
                userAction: state.runtime.nextRepairAction ?? "先处理系统权限或设备信任，再回到首用路径继续。",
                machineStatusRef: machineStatusRef,
                hardLine: "permission blockers remain visible until repaired",
                highlights: mergedHighlights([
                    "repair_entry=system_permissions_or_hub_pairing",
                    "three_step_budget=true"
                ], runtime: state.runtime)
            )
        } else if state.runtime.replayBlocked {
            primaryStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "首用 smoke 仍处于 fail-closed，需要先看 replay 结果",
                whatHappened: "Hub 已接入且模型已配置，但 replay harness 仍未通过，当前不能把用户送入首个任务。",
                whyItHappened: "replay 会继续作为 smoke 的硬门槛；没通过前，不会把首个任务显示成可开始。",
                userAction: state.runtime.nextRepairAction ?? "先按 Diagnostics 查看 denyCode / replay scenario，再重新触发 reconnect smoke。",
                machineStatusRef: machineStatusRef,
                hardLine: "replay_fail_closed must block first task",
                highlights: mergedHighlights([
                    "primary_cta=run_smoke",
                    "diagnostic_entrypoint=audit_logs"
                ], runtime: state.runtime)
            )
        } else if hasModel {
            primaryStatus = StatusExplanation(
                state: .ready,
                headline: "首用路径已接近 smoke，可继续开始首个任务",
                whatHappened: "Pair Hub 与模型配置都已具备；若 replay / freeze 仍为 green，则可以转向 reconnect smoke 与首个任务入口。",
                whyItHappened: "这里会沿用同一套状态语义和发布范围判断，让你看到的进度与其他界面一致。",
                userAction: state.runtime.nextRepairAction ?? "先跑 Reconnect Smoke；通过后回 Home 查看项目汇总，或进入 Supervisor 窗口发起大任务。",
                machineStatusRef: machineStatusRef,
                hardLine: "validated-mainline-only remains the only release scope",
                highlights: mergedHighlights([
                    "primary_cta=run_smoke",
                    "follow_up=open_supervisor"
                ], runtime: state.runtime)
            )
        } else {
            primaryStatus = StatusExplanation(
                state: .inProgress,
                headline: "连接 Hub（Pair Hub）已完成，下一步是选择模型（Choose Model）",
                whatHappened: "Hub 已接入，但当前还没把首个任务需要的模型角色冻结到位。",
                whyItHappened: "首用路径要求先完成 Pair Hub，再选择模型，避免把模型缺失误判成 grant 问题。",
                userAction: "先为 coder / supervisor 至少配置一个 Hub 模型，再继续 grant 与 smoke。",
                machineStatusRef: machineStatusRef,
                hardLine: "model selection must precede smoke when empty",
                highlights: mergedHighlights([
                    "configured_roles=\(state.configuredModelRoles)",
                    "recommended_roles=coder,supervisor"
                ], runtime: state.runtime)
            )
        }

        let releaseDecision = state.runtime.scopeDecision
        let releaseState: XTUISurfaceState = releaseDecision == DeliveryScopeFreezeDecision.noGo.rawValue
            ? .blockedWaitingUpstream
            : releaseDecision == DeliveryScopeFreezeDecision.hold.rawValue
                ? .inProgress
                : .releaseFrozen
        let releaseHeadline: String
        if releaseDecision == DeliveryScopeFreezeDecision.noGo.rawValue {
            releaseHeadline = "请求超出已验证主链，当前继续 fail-closed"
        } else if releaseDecision == DeliveryScopeFreezeDecision.hold.rawValue {
            releaseHeadline = "已验证范围仍在 hold，先按冻结动作收口"
        } else {
            releaseHeadline = "已验证范围已冻结到 XT-W3-23 → XT-W3-24 → XT-W3-25"
        }
        let releaseWhatHappened = state.runtime.allowedPublicStatements.isEmpty
            ? "当前向导只服务已验证主链，不会把未验证路径说成已经进入发布口径。"
            : "对外只允许已验证表述：\(state.runtime.allowedPublicStatements.joined(separator: " | "))。"
        let releaseUserAction = state.runtime.scopeNextActions.first ?? "完成 Pair / Model / Grant / Smoke 后，也只会回到已验证主链的首个任务入口。"
        let releaseStatus = StatusExplanation(
            state: releaseState,
            headline: releaseHeadline,
            whatHappened: releaseWhatHappened,
            whyItHappened: "发布范围、允许对外表述和阻塞项都会在这里原样收口，避免界面对外说多。",
            userAction: releaseUserAction,
            machineStatusRef: [
                "current_release_scope=\(badge.currentReleaseScope)",
                "validated_paths=\((state.runtime.validatedScope.isEmpty ? badge.validatedPaths : state.runtime.validatedScope).joined(separator: ","))",
                "blocked_expansion=\(state.runtime.blockedExpansionItems.isEmpty ? "none" : state.runtime.blockedExpansionItems.joined(separator: ","))",
                "replay_pass=\(state.runtime.replayPass.map(String.init(describing:)) ?? "unknown")"
            ].joined(separator: "; "),
            hardLine: badge.hardLine,
            highlights: mergedHighlights([
                "no_scope_expansion=true",
                "no_unverified_claims=true"
            ], runtime: state.runtime)
        )

        let actions = [
            PrimaryActionRailAction(
                id: "pair_hub",
                title: "开始连接 Hub（Pair Hub）",
                subtitle: "discover / bootstrap / connect 一次走通",
                systemImage: "link.badge.plus",
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "run_smoke",
                title: "重连自检（Run Reconnect Smoke）",
                subtitle: runSmokeSubtitle(runtime: state.runtime),
                systemImage: "bolt.horizontal.circle",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "review_grants",
                title: "查看授权与排障",
                subtitle: reviewSubtitle(failureIssue: failureIssue, runtime: state.runtime),
                systemImage: "checkmark.shield",
                style: .diagnostic
            )
        ]

        let smokeReady = connected && hasModel && failureIssue == nil && state.runtime.allowsValidatedMainline && !state.runtime.replayBlocked
        let verifyReady = state.doctor.sections.isEmpty ? smokeReady : state.doctor.readyForFirstTask
        let resolveGrantState: XTUISurfaceState
        if failureIssue == .grantRequired {
            resolveGrantState = .grantRequired
        } else if failureIssue == .permissionDenied {
            resolveGrantState = .permissionDenied
        } else if state.runtime.failClosedLaunchCount > 0 {
            resolveGrantState = .diagnosticRequired
        } else {
            resolveGrantState = .ready
        }
        let runSmokeState: XTUISurfaceState
        if state.runtime.replayBlocked {
            runSmokeState = .diagnosticRequired
        } else if smokeReady {
            runSmokeState = .ready
        } else {
            runSmokeState = connected ? .diagnosticRequired : .blockedWaitingUpstream
        }
        let verifyState: XTUISurfaceState
        if state.doctor.sections.isEmpty {
            verifyState = smokeReady ? .ready : (connected ? .diagnosticRequired : .blockedWaitingUpstream)
        } else if state.doctor.readyForFirstTask {
            verifyState = .ready
        } else if state.doctor.overallState == .ready {
            verifyState = .inProgress
        } else {
            verifyState = state.doctor.overallState
        }
        let firstTaskState: XTUISurfaceState
        if verifyReady {
            firstTaskState = .ready
        } else if !state.runtime.allowsValidatedMainline {
            firstTaskState = .blockedWaitingUpstream
        } else {
            firstTaskState = .releaseFrozen
        }
        let steps = [
            UIFirstRunStep(
                kind: .pairHub,
                title: "连接 Hub（Pair Hub）",
                summary: "先把 discover / bootstrap / connect 路径打通。",
                state: connected ? .ready : (state.linking ? .inProgress : .blockedWaitingUpstream),
                repairEntry: .xtPairHub
            ),
            UIFirstRunStep(
                kind: .chooseModel,
                title: "选择模型（Choose Model）",
                summary: "先为首个任务配置 Hub 模型，避免误判 grant。",
                state: hasModel ? .ready : (connected ? .inProgress : .blockedWaitingUpstream),
                repairEntry: .xtChooseModel
            ),
            UIFirstRunStep(
                kind: .resolveGrant,
                title: "处理授权（Resolve Grant）",
                summary: "grant_required / permission_denied / fail-closed denyCode 都必须 3 步内定位到修复入口。",
                state: resolveGrantState,
                repairEntry: failureIssue == .permissionDenied ? .systemPermissions : .hubGrants
            ),
            UIFirstRunStep(
                kind: .runSmoke,
                title: "运行自检（Run Smoke）",
                summary: "通过 reconnect smoke 与 replay harness 确认 pair + model + grant 一起可用。",
                state: runSmokeState,
                repairEntry: .hubDiagnostics
            ),
            UIFirstRunStep(
                kind: .verifyReadiness,
                title: "核验就绪（Verify）",
                summary: "显式检查当前 transport、模型数、tool route 与 session runtime 是否都 ready。",
                state: verifyState,
                repairEntry: .xtDiagnostics
            ),
            UIFirstRunStep(
                kind: .startFirstTask,
                title: "开始首个任务（Start First Task）",
                summary: "只回到当前已验证主链的 Home / Supervisor 主入口。",
                state: firstTaskState,
                repairEntry: .homeSupervisor
            )
        ]

        return UIFirstRunJourneyPlan(
            badge: badge,
            primaryStatus: primaryStatus,
            releaseStatus: releaseStatus,
            actions: actions,
            steps: steps,
            configuredModelRoles: state.configuredModelRoles,
            totalModelRoles: state.totalModelRoles,
            currentFailureIssue: failureIssue,
            smokeReady: smokeReady,
            consumedFrozenFields: [
                "xt.ui_information_architecture.v1",
                "xt.ui_design_token_bundle.v1",
                "xt.ui_surface_state_contract.v1",
                "xt.ui_release_scope_badge.v1",
                "xt.one_shot_run_state.v1.state",
                "xt.delivery_scope_freeze.v1.validated_scope",
                "xt.unblock_baton.v1",
                "xt.delivery_scope_freeze.v1",
                "xt.one_shot_autonomy_policy.v1",
                "xt.one_shot_replay_regression.v1"
            ]
        )
    }

    private static func mergedHighlights(_ highlights: [String], runtime: UIFailClosedRuntimeSnapshot) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for highlight in highlights + runtime.statusHighlights + runtime.consumedContracts.map({ "runtime_contract=\($0)" }) {
            let value = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else { continue }
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }

    private static func runSmokeSubtitle(runtime: UIFailClosedRuntimeSnapshot) -> String {
        if runtime.replayPass == true {
            return "replay regression PASS；验证 pair + model + grant 已连通"
        }
        if runtime.replayPass == false {
            return "replay fail-closed；先看 denyCode / diagnostics"
        }
        return "验证 pair + model + grant 已连通"
    }

    private static func reviewSubtitle(failureIssue: UITroubleshootIssue?, runtime: UIFailClosedRuntimeSnapshot) -> String {
        if !runtime.nextDirectedAction.isEmpty {
            return "resume baton: \(runtime.nextDirectedAction)"
        }
        if let failureIssue {
            return "\(failureIssue.rawValue) → \(runtime.nextRepairAction ?? "open_repair_entry")"
        }
        if let denyCode = runtime.launchDenyCodes.first(where: { !$0.isEmpty }) {
            return "fail_closed=\(denyCode)"
        }
        return "grant_required / permission_denied / hub_unreachable 统一从这里解释"
    }
}

struct HubSetupWizardView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var supervisorManager = SupervisorManager.shared
    @State private var activeFocusRequest: XTHubSetupFocusRequest?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: UIThemeTokens.sectionSpacing) {
                    headerSection
                    ValidatedScopeBadge(presentation: journeyPlan.badge)
                    StatusExplanationCard(explanation: journeyPlan.primaryStatus)
                    firstRunPathSection
                        .id("first_run_path")
                    modelSelectionSection
                        .id("choose_model")
                    setupProgressSection
                        .id("pair_progress")
                    verifyReadinessSection
                        .id("verify_readiness")
                    PrimaryActionRail(title: "首用动作", actions: journeyPlan.actions, onTap: handleAction)
                    StatusExplanationCard(explanation: journeyPlan.releaseStatus)
                    troubleshootSection
                        .id("troubleshoot")
                    logSection
                        .id("connection_log")
                }
                .padding(16)
            }
            .onAppear {
                processHubSetupFocusRequest(proxy)
                appModel.maybeAutoFillHubSetupPathAndPorts(force: false)
            }
            .onChange(of: appModel.hubSetupFocusRequest?.nonce) { _ in
                processHubSetupFocusRequest(proxy)
            }
        }
        .frame(minWidth: 780, minHeight: 720)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hub 首次连接向导")
                .font(UIThemeTokens.sectionFont())
            Text("把连接 Hub（Pair Hub）→ 选择模型（Choose Model）→ 处理授权（Resolve Grant）→ 自检（Smoke）→ 核验（Verify）收成一条首用主链，先把第一次可用跑通。")
                .font(UIThemeTokens.bodyFont())
                .foregroundStyle(.secondary)
        }
    }

    private var firstRunPathSection: some View {
        GroupBox("首用主链") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("当前主链：连接 Hub（Pair Hub）→ 选择模型（Choose Model）→ 处理授权（Resolve Grant）→ 自检（Smoke）→ 核验（Verify）→ 开始首个任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("consumed_frozen_fields=\(journeyPlan.consumedFrozenFields.count)")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                }

                ForEach(journeyPlan.steps) { step in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: step.state.iconName)
                            .foregroundStyle(step.state.tint)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(step.title)
                                    .font(.headline)
                                Spacer()
                                Text(step.state.rawValue)
                                    .font(UIThemeTokens.monoFont())
                                    .foregroundStyle(step.state.tint)
                            }
                            Text(step.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("修复入口：\(step.repairEntry.label)")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var modelSelectionSection: some View {
        GroupBox("选择模型") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "choose_model") {
                    XTFocusContextCard(context: context)
                }
                HStack {
                    Text("已配置模型角色：\(journeyPlan.configuredModelRoles)/\(journeyPlan.totalModelRoles)")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(journeyPlan.configuredModelRoles > 0 ? "已就绪" : "待配模型")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(journeyPlan.configuredModelRoles > 0 ? UIThemeTokens.color(for: .ready) : UIThemeTokens.color(for: .inProgress))
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("角色")
                            .foregroundStyle(.secondary)
                        Text("Hub 模型")
                            .foregroundStyle(.secondary)
                    }
                    .font(UIThemeTokens.monoFont())

                    ForEach(AXRole.allCases) { role in
                        GridRow {
                            Text(role.displayName)
                                .frame(width: 120, alignment: .leading)
                            TextField("模型 ID", text: bindingModel(role))
                                .textFieldStyle(.roundedBorder)
                                .font(UIThemeTokens.monoFont())
                        }
                    }
                }

                if !chooseModelIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("即时提示")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(UIThemeTokens.color(for: .diagnosticRequired))
                        ForEach(chooseModelIssues) { issue in
                            HStack(alignment: .top, spacing: 10) {
                                Text(issue.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                if let suggestedModelId = issue.suggestedModelId {
                                    Button("改用推荐") {
                                        applySuggestedGlobalModel(
                                            role: issue.role,
                                            modelId: suggestedModelId
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("把 \(issue.role.displayName) 直接切到 `\(suggestedModelId)`。")
                                }
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(UIThemeTokens.stateBackground(for: .diagnosticRequired))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(UIThemeTokens.color(for: .diagnosticRequired).opacity(0.2), lineWidth: 1)
                    )
                }

                Text("建议至少先配置 coder / supervisor；如果卡在 Hub 授权、能力范围或配额，就直接走下方排障区的 Hub 授权入口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var setupProgressSection: some View {
        GroupBox("连接进度") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(appModel.hubPortAutoDetectRunning ? "探测中..." : "自动探测") {
                        appModel.maybeAutoFillHubSetupPathAndPorts(force: true)
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.hubRemoteLinking)

                    Button(appModel.hubRemoteLinking ? "重置中..." : "清除配对后重连") {
                        appModel.resetPairingStateAndOneClickSetup()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.hubRemoteLinking || appModel.hubPortAutoDetectRunning)

                    Spacer()

                    Text("进入页面会先自动探测一轮；失败后再手填。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("配对端口")
                            .frame(width: 130, alignment: .leading)
                        TextField("50052", value: pairingPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    GridRow {
                        Text("gRPC 端口")
                            .frame(width: 130, alignment: .leading)
                        TextField("50051", value: grpcPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    GridRow {
                        Text("公网地址")
                            .frame(width: 130, alignment: .leading)
                        TextField("hub.example.com", text: internetHostBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("axhubctl 路径")
                            .frame(width: 130, alignment: .leading)
                        TextField("自动探测", text: axhubctlPathBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                ProgressView(value: progressValue, total: 3.0)
                stepRow(title: "发现", subtitle: "发现 Hub（局域网优先）", state: appModel.hubSetupDiscoverState)
                stepRow(title: "配对", subtitle: "配对 + 凭据下发", state: appModel.hubSetupBootstrapState)
                stepRow(title: "连接", subtitle: "建立连接并启用自动重连", state: appModel.hubSetupConnectState)

                if !appModel.hubPortAutoDetectMessage.isEmpty {
                    Text(appModel.hubPortAutoDetectMessage)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                }
                HubDiscoveryCandidatesView(appModel: appModel)
                if !appModel.hubRemoteSummary.isEmpty {
                    Text("摘要：\(appModel.hubRemoteSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var verifyReadinessSection: some View {
        GroupBox("运行时核对") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "verify_readiness") {
                    XTFocusContextCard(context: context)
                }
                officialSkillsRecheckStatus
                Text("在一个面板里直接看当前传输方式、配对端口 / gRPC 端口 / 公网地址、模型可见性、工具路由、会话运行时与技能兼容性。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                XTUnifiedDoctorSummaryView(report: doctorReport)
                if !appModel.officialSkillChannelSummaryLine.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("官方技能通道")
                            Spacer()
                            Button("重查") {
                                appModel.recheckOfficialSkills(reason: "hub_setup_verify_readiness_manual")
                            }
                            .buttonStyle(.borderless)
                            Text(appModel.officialSkillChannelSummaryLine)
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(officialSkillChannelStatusColor)
                                .textSelection(.enabled)
                        }
                        if !appModel.officialSkillChannelDetailLine.isEmpty {
                            Text(appModel.officialSkillChannelDetailLine)
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if !appModel.officialSkillChannelTopBlockersLine.isEmpty {
                            if !appModel.officialSkillChannelTopBlockerSummaries.isEmpty {
                                XTOfficialSkillsBlockerListView(
                                    items: appModel.officialSkillChannelTopBlockerSummaries
                                )
                            } else {
                                Text(appModel.officialSkillChannelTopBlockersLine)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                if !appModel.skillsCompatibilitySnapshot.builtinGovernedSkills.isEmpty {
                    XTBuiltinGovernedSkillsListView(
                        items: appModel.skillsCompatibilitySnapshot.builtinGovernedSkills
                    )
                }
            }
            .padding(8)
        }
    }

    private var troubleshootSection: some View {
        GroupBox("授权 / 权限 / 连通性排障") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "troubleshoot") {
                    XTFocusContextCard(context: context)
                }
                officialSkillsRecheckStatus
                if let issue = journeyPlan.currentFailureIssue {
                    Text("当前优先排障：\(issue.title)")
                        .font(.subheadline.weight(.semibold))
                }
                if !appModel.hubSetupFailureCode.isEmpty {
                    Text("失败原因码：\(appModel.hubSetupFailureCode)")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.red)
                    if let hint = failureHint(for: appModel.hubSetupFailureCode) {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(UIThemeTokens.color(for: .grantRequired))
                    }
                }
                if !runtimeSnapshot.diagnosticsLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("运行时状态线索")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(runtimeSnapshot.diagnosticsLines.prefix(4), id: \.self) { line in
                            Text("• \(line)")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                if !routeRepairLogLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if routeRepairLogDigest.totalEvents > 0 {
                            Text("路由修复摘要")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(routeRepairLogDigest.headline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(routeRepairLogDigest.detailLines, id: \.self) { line in
                                Text("• \(line)")
                                    .font(UIThemeTokens.monoFont())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if let reminderStatus = currentProjectRouteReminderStatus {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("路由修复提醒")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                if appModel.selectedProjectId != nil {
                                    Button("查看路由") {
                                        openCurrentProjectRouteDiagnose()
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .help("切回当前项目聊天，并自动展开 route diagnose。")
                                }
                                if reminderStatus.quietingCurrentIssue,
                                   let projectId = appModel.selectedProjectId {
                                    Button("恢复提醒") {
                                        supervisorManager.clearRouteAttentionReminderState(projectId: projectId)
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .help("清掉当前静默状态；如果问题还在，下一次 timer 心跳会重新主动提醒。")
                                }
                            }
                            if let line = routeReminderLine(reminderStatus) {
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Text("最近路由修复记录")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(routeRepairLogLines, id: \.self) { line in
                            Text("• \(line)")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                TroubleshootPanel(title: "高频问题 3 步修复", issues: [.grantRequired, .permissionDenied, .hubUnreachable])
            }
            .padding(8)
        }
    }

    private var logSection: some View {
        GroupBox("连接日志") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "connection_log") {
                    XTFocusContextCard(context: context)
                }
                ScrollView {
                    Text(appModel.hubRemoteLog.isEmpty ? "还没有日志。" : appModel.hubRemoteLog)
                        .font(UIThemeTokens.monoFont())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 180)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(8)
        }
    }

    private var journeyPlan: UIFirstRunJourneyPlan {
        UIFirstRunJourneyPlanner.plan(for: wizardState)
    }

    private var wizardState: HubSetupWizardState {
        HubSetupWizardState(
            localConnected: appModel.hubConnected,
            remoteConnected: appModel.hubRemoteConnected,
            linking: appModel.hubRemoteLinking,
            configuredModelRoles: configuredModelRoles,
            totalModelRoles: AXRole.allCases.count,
            failureCode: appModel.hubSetupFailureCode,
            runtime: runtimeSnapshot,
            doctor: doctorReport
        )
    }

    private var doctorReport: XTUnifiedDoctorReport {
        appModel.unifiedDoctorReport
    }

    private var runtimeSnapshot: UIFailClosedRuntimeSnapshot {
        guard let orchestrator = appModel.supervisor.orchestrator else {
            return .empty
        }
        return UIFailClosedRuntimeSnapshot.capture(
            policy: orchestrator.oneShotAutonomyPolicy,
            freeze: orchestrator.latestDeliveryScopeFreeze,
            launchDecisions: Array(orchestrator.laneLaunchDecisions.values),
            directedUnblockBatons: orchestrator.executionMonitor.directedUnblockBatons,
            replayReport: orchestrator.latestReplayHarnessReport
        )
    }

    private var officialSkillChannelStatusColor: Color {
        switch appModel.skillsCompatibilitySnapshot.officialChannelStatus.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "healthy":
            return UIThemeTokens.color(for: .ready)
        case "stale":
            return UIThemeTokens.color(for: .inProgress)
        case "failed", "missing":
            return UIThemeTokens.color(for: .diagnosticRequired)
        default:
            return .secondary
        }
    }

    private var routeRepairLogLines: [String] {
        guard let ctx = appModel.projectContext else { return [] }
        return AXRouteRepairLogStore.userFacingSummaryLines(for: ctx, limit: 5)
    }

    private var routeRepairLogDigest: AXRouteRepairLogDigest {
        guard let ctx = appModel.projectContext else { return .empty }
        return AXRouteRepairLogStore.digest(for: ctx, limit: 50)
    }

    private var chooseModelIssues: [HubGlobalRoleModelIssue] {
        let snapshot = ModelStateSnapshot(
            models: appModel.modelsState.models,
            updatedAt: appModel.modelsState.updatedAt
        )
        return Array(
            AXRole.allCases.compactMap { role in
                HubModelSelectionAdvisor.globalAssignmentIssue(
                    for: role,
                    configuredModelId: appModel.settingsStore.settings.assignment(for: role).model,
                    snapshot: snapshot
                )
            }
            .prefix(3)
        )
    }

    private var currentProjectRouteReminderStatus: SupervisorManager.RouteAttentionReminderStatus? {
        guard let projectId = appModel.selectedProjectId,
              projectId != AXProjectRegistry.globalHomeId,
              let project = appModel.registry.project(for: projectId),
              let watchItem = AXRouteRepairLogStore.watchItems(for: [project], limit: 1).first else {
            return nil
        }
        return supervisorManager.routeAttentionReminderStatus(for: watchItem)
    }

    private var configuredModelRoles: Int {
        AXRole.allCases.filter { role in
            let model = appModel.settingsStore.settings.assignment(for: role).model ?? ""
            return !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private func handleAction(_ action: PrimaryActionRailAction) {
        switch action.id {
        case "pair_hub":
            appModel.startHubOneClickSetup()
        case "run_smoke":
            appModel.startHubReconnectOnly()
        case "review_grants":
            appModel.resetPairingStateAndOneClickSetup()
        default:
            break
        }
    }

    @ViewBuilder
    private func stepRow(title: String, subtitle: String, state: HubSetupStepState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: iconName(for: state))
                .foregroundStyle(iconColor(for: state))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(labelText(for: state))
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(iconColor(for: state))
        }
    }

    private var progressValue: Double {
        stepScore(appModel.hubSetupDiscoverState)
            + stepScore(appModel.hubSetupBootstrapState)
            + stepScore(appModel.hubSetupConnectState)
    }

    private func stepScore(_ state: HubSetupStepState) -> Double {
        switch state {
        case .idle:
            return 0.0
        case .running:
            return 0.4
        case .success, .failed, .skipped:
            return 1.0
        }
    }

    private func iconName(for state: HubSetupStepState) -> String {
        switch state {
        case .idle:
            return "circle"
        case .running:
            return "clock.arrow.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .skipped:
            return "arrow.right.circle.fill"
        }
    }

    private func iconColor(for state: HubSetupStepState) -> Color {
        switch state {
        case .idle:
            return .secondary
        case .running:
            return UIThemeTokens.color(for: .inProgress)
        case .success:
            return UIThemeTokens.color(for: .ready)
        case .failed:
            return UIThemeTokens.color(for: .permissionDenied)
        case .skipped:
            return .gray
        }
    }

    private func labelText(for state: HubSetupStepState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case .success:
            return "ok"
        case .failed:
            return "failed"
        case .skipped:
            return "skipped"
        }
    }

    private func routeReminderLine(
        _ status: SupervisorManager.RouteAttentionReminderStatus
    ) -> String? {
        guard let lastAlertAt = status.lastAlertAt else { return nil }
        let lastAlertText = relativeTimeText(lastAlertAt)
        if status.quietingCurrentIssue {
            let cooldownText = compactDurationText(status.cooldownRemainingSec)
            return "上次提醒：\(lastAlertText)；当前静默观察中，约 \(cooldownText) 后才会再次主动提醒。"
        }
        return "上次提醒：\(lastAlertText)。"
    }

    private func relativeTimeText(_ ts: Double) -> String {
        guard ts > 0 else { return "未知" }
        let elapsedSec = max(0, Int(Date().timeIntervalSince1970 - ts))
        if elapsedSec < 90 { return "刚刚" }
        let mins = elapsedSec / 60
        if mins < 60 { return "\(mins) 分钟前" }
        let hours = mins / 60
        if hours < 48 { return "\(hours) 小时前" }
        return "\(hours / 24) 天前"
    }

    private func compactDurationText(_ seconds: Int) -> String {
        let normalized = max(0, seconds)
        if normalized < 90 { return "1 分钟内" }
        let mins = normalized / 60
        if mins < 60 { return "\(mins) 分钟" }
        let hours = mins / 60
        if hours < 48 { return "\(hours) 小时" }
        return "\(hours / 24) 天"
    }

    private func openCurrentProjectRouteDiagnose() {
        guard let projectId = appModel.selectedProjectId,
              projectId != AXProjectRegistry.globalHomeId else { return }
        appModel.selectProject(projectId)
        appModel.setPane(.chat, for: projectId)
        appModel.requestProjectRouteDiagnoseFocus(projectId: projectId)
    }

    private func applySuggestedGlobalModel(role: AXRole, modelId: String) {
        let trimmedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelId.isEmpty else { return }
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: role,
            providerKind: .hub,
            model: trimmedModelId
        )
        appModel.settingsStore.save()
    }

    private func bindingModel(_ role: AXRole) -> Binding<String> {
        Binding(
            get: { appModel.settingsStore.settings.assignment(for: role).model ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                appModel.settingsStore.settings = appModel.settingsStore.settings.setting(role: role, providerKind: .hub, model: trimmed.isEmpty ? nil : trimmed)
                appModel.settingsStore.save()
            }
        )
    }

    private var pairingPortBinding: Binding<Int> {
        Binding(
            get: { appModel.hubPairingPort },
            set: { value in
                appModel.hubPairingPort = max(1, min(65_535, value))
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var grpcPortBinding: Binding<Int> {
        Binding(
            get: { appModel.hubGrpcPort },
            set: { value in
                appModel.hubGrpcPort = max(1, min(65_535, value))
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var internetHostBinding: Binding<String> {
        Binding(
            get: { appModel.hubInternetHost },
            set: { value in
                appModel.hubInternetHost = value
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private var axhubctlPathBinding: Binding<String> {
        Binding(
            get: { appModel.hubAxhubctlPath },
            set: { value in
                appModel.hubAxhubctlPath = value
                appModel.saveHubRemotePrefsNow()
            }
        )
    }

    private func failureHint(for rawCode: String) -> String? {
        if let issue = UITroubleshootKnowledgeBase.issue(forFailureCode: rawCode) {
            return UITroubleshootKnowledgeBase.guide(for: issue).steps.first?.instruction
        }
        return nil
    }

    private func processHubSetupFocusRequest(_ proxy: ScrollViewProxy) {
        guard let request = appModel.hubSetupFocusRequest else { return }
        activeFocusRequest = request
        if let refreshAction = request.context?.refreshAction {
            appModel.performSectionRefreshAction(
                refreshAction,
                reason: request.context?.refreshReason ?? "hub_setup_focus_request"
            )
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(request.sectionId, anchor: .top)
        }
        appModel.clearHubSetupFocusRequest(request)
        scheduleFocusContextClear(nonce: request.nonce)
    }

    private func focusContext(for sectionId: String) -> XTSectionFocusContext? {
        guard activeFocusRequest?.sectionId == sectionId else { return nil }
        return activeFocusRequest?.context
    }

    private func scheduleFocusContextClear(nonce: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if activeFocusRequest?.nonce == nonce {
                activeFocusRequest = nil
            }
        }
    }

    @ViewBuilder
    private var officialSkillsRecheckStatus: some View {
        let statusLine = appModel.officialSkillsRecheckStatusLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !statusLine.isEmpty {
            Text(statusLine)
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
