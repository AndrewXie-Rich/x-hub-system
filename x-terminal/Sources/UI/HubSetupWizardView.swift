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
                whyItHappened: "冻结契约要求 UI 在 Hub 未连接时明确阻塞原因；本轮还把 AI-2 的 freeze / replay / baton 信号并入 machine status。",
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
                whyItHappened: "AI-4 直接消费 AI-2 的 denyCode / note / replay scenario，并继续把 grant_required 的修复入口限制在 3 步内。",
                userAction: state.runtime.nextRepairAction ?? "先去 Hub 授权与 quota 入口修复，再回到 smoke。",
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
                whyItHappened: "本轮把 permission_denied 直接绑定到 AI-2 fail-closed 合同，避免用户在多个页面猜。",
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
                whyItHappened: "AI-4 已直接消费 xt.one_shot_replay_regression.v1.pass / scenarios，并让 smoke gating 继续 fail-closed。",
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
                whyItHappened: "AI-4 继续复用 AI-3 的状态语义与 release scope badge，同时附带 AI-2 的运行时状态快照。",
                userAction: state.runtime.nextRepairAction ?? "先跑 Reconnect Smoke；通过后回 Home / Supervisor 开始大任务。",
                machineStatusRef: machineStatusRef,
                hardLine: "validated-mainline-only remains the only release scope",
                highlights: mergedHighlights([
                    "primary_cta=run_smoke",
                    "follow_up=start_big_task"
                ], runtime: state.runtime)
            )
        } else {
            primaryStatus = StatusExplanation(
                state: .inProgress,
                headline: "Pair Hub 已完成，下一步是 Choose Model",
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
            releaseHeadline = "请求超出 validated mainline，当前 release 继续 fail-closed"
        } else if releaseDecision == DeliveryScopeFreezeDecision.hold.rawValue {
            releaseHeadline = "Validated scope 仍在 hold，先按冻结动作收口"
        } else {
            releaseHeadline = "Validated scope 已冻结到 XT-W3-23 → XT-W3-24 → XT-W3-25"
        }
        let releaseWhatHappened = state.runtime.allowedPublicStatements.isEmpty
            ? "Setup Wizard 只服务 validated mainline，不向外暗示未验证路径已经进入发布口径。"
            : "对外只允许已验证表述：\(state.runtime.allowedPublicStatements.joined(separator: " | "))。"
        let releaseUserAction = state.runtime.scopeNextActions.first ?? "完成 Pair / Model / Grant / Smoke 后，也只把用户送回 validated mainline 的首个任务入口。"
        let releaseStatus = StatusExplanation(
            state: releaseState,
            headline: releaseHeadline,
            whatHappened: releaseWhatHappened,
            whyItHappened: "AI-4 已直接消费 xt.delivery_scope_freeze.v1.decision / validated_scope / allowed_public_statements，并保持对外口径 scope-frozen。",
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
                title: "开始 Pair Hub",
                subtitle: "discover / bootstrap / connect 一次走通",
                systemImage: "link.badge.plus",
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "run_smoke",
                title: "Run Reconnect Smoke",
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
                title: "Pair Hub",
                summary: "先把 discover / bootstrap / connect 路径打通。",
                state: connected ? .ready : (state.linking ? .inProgress : .blockedWaitingUpstream),
                repairEntry: .xtPairHub
            ),
            UIFirstRunStep(
                kind: .chooseModel,
                title: "Choose Model",
                summary: "先为首个任务配置 Hub 模型，避免误判 grant。",
                state: hasModel ? .ready : (connected ? .inProgress : .blockedWaitingUpstream),
                repairEntry: .xtChooseModel
            ),
            UIFirstRunStep(
                kind: .resolveGrant,
                title: "Resolve Grant",
                summary: "grant_required / permission_denied / fail-closed denyCode 都必须 3 步内定位到修复入口。",
                state: resolveGrantState,
                repairEntry: failureIssue == .permissionDenied ? .systemPermissions : .hubGrants
            ),
            UIFirstRunStep(
                kind: .runSmoke,
                title: "Run Smoke",
                summary: "通过 reconnect smoke 与 replay harness 确认 pair + model + grant 一起可用。",
                state: runSmokeState,
                repairEntry: .hubDiagnostics
            ),
            UIFirstRunStep(
                kind: .verifyReadiness,
                title: "Verify",
                summary: "显式检查当前 transport、模型数、tool route 与 session runtime 是否都 ready。",
                state: verifyState,
                repairEntry: .xtDiagnostics
            ),
            UIFirstRunStep(
                kind: .startFirstTask,
                title: "Start First Task",
                summary: "只回到 validated mainline 的 Home / Supervisor 主入口。",
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
        if let failureIssue {
            return "\(failureIssue.rawValue) → \(runtime.nextRepairAction ?? "open_repair_entry")"
        }
        if !runtime.nextDirectedAction.isEmpty {
            return "resume baton: \(runtime.nextDirectedAction)"
        }
        if let denyCode = runtime.launchDenyCodes.first(where: { !$0.isEmpty }) {
            return "fail_closed=\(denyCode)"
        }
        return "grant_required / permission_denied / hub_unreachable 统一从这里解释"
    }
}

struct HubSetupWizardView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UIThemeTokens.sectionSpacing) {
                headerSection
                ValidatedScopeBadge(presentation: journeyPlan.badge)
                StatusExplanationCard(explanation: journeyPlan.primaryStatus)
                firstRunPathSection
                modelSelectionSection
                setupProgressSection
                verifyReadinessSection
                PrimaryActionRail(title: "首用动作", actions: journeyPlan.actions, onTap: handleAction)
                StatusExplanationCard(explanation: journeyPlan.releaseStatus)
                troubleshootSection
                logSection
            }
            .padding(16)
        }
        .frame(minWidth: 780, minHeight: 720)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hub 首次连接向导")
                .font(UIThemeTokens.sectionFont())
            Text("AI-4 直接复用 AI-3 冻结的 state / badge / action contracts，把 Pair Hub → Choose Model → Resolve Grant → Smoke → Verify 收成一条主链。")
                .font(UIThemeTokens.bodyFont())
                .foregroundStyle(.secondary)
        }
    }

    private var firstRunPathSection: some View {
        GroupBox("首用主链") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("冻结路径：pair Hub → choose model → resolve grant → smoke → verify → start first task")
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
        GroupBox("Choose Model") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("已配置模型角色：\(journeyPlan.configuredModelRoles)/\(journeyPlan.totalModelRoles)")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(journeyPlan.configuredModelRoles > 0 ? "ready" : "needs_model")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(journeyPlan.configuredModelRoles > 0 ? UIThemeTokens.color(for: .ready) : UIThemeTokens.color(for: .inProgress))
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Role")
                            .foregroundStyle(.secondary)
                        Text("Hub Model")
                            .foregroundStyle(.secondary)
                    }
                    .font(UIThemeTokens.monoFont())

                    ForEach(AXRole.allCases) { role in
                        GridRow {
                            Text(role.displayName)
                                .frame(width: 120, alignment: .leading)
                            TextField("model id", text: bindingModel(role))
                                .textFieldStyle(.roundedBorder)
                                .font(UIThemeTokens.monoFont())
                        }
                    }
                }

                Text("建议至少先配置 coder / supervisor；grant 相关问题则直接走下方 TroubleshootPanel 的 Hub 授权入口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var setupProgressSection: some View {
        GroupBox("Pair Progress") {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Pairing Port")
                            .frame(width: 130, alignment: .leading)
                        TextField("50052", value: pairingPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    GridRow {
                        Text("gRPC Port")
                            .frame(width: 130, alignment: .leading)
                        TextField("50051", value: grpcPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    GridRow {
                        Text("Internet Host")
                            .frame(width: 130, alignment: .leading)
                        TextField("hub.example.com", text: internetHostBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("axhubctl Path")
                            .frame(width: 130, alignment: .leading)
                        TextField("auto detect", text: axhubctlPathBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                ProgressView(value: progressValue, total: 3.0)
                stepRow(title: "Discover", subtitle: "发现 Hub（局域网优先）", state: appModel.hubSetupDiscoverState)
                stepRow(title: "Bootstrap", subtitle: "配对 + 凭据下发", state: appModel.hubSetupBootstrapState)
                stepRow(title: "Connect", subtitle: "建立连接并启用自动重连", state: appModel.hubSetupConnectState)

                if !appModel.hubPortAutoDetectMessage.isEmpty {
                    Text(appModel.hubPortAutoDetectMessage)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                }
                if !appModel.hubRemoteSummary.isEmpty {
                    Text("Summary: \(appModel.hubRemoteSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var verifyReadinessSection: some View {
        GroupBox("Verify Runtime Readiness") {
            VStack(alignment: .leading, spacing: 10) {
                Text("在一个面板里直接看当前 transport、Pairing Port / gRPC Port / Internet Host、模型可见性、tool route、session runtime 与 skills compatibility。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                XTUnifiedDoctorSummaryView(report: doctorReport)
            }
            .padding(8)
        }
    }

    private var troubleshootSection: some View {
        GroupBox("Resolve Grant / Permission / Reachability") {
            VStack(alignment: .leading, spacing: 10) {
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
                        Text("AI-2 runtime contracts")
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
                TroubleshootPanel(title: "高频问题 3 步修复", issues: [.grantRequired, .permissionDenied, .hubUnreachable])
            }
            .padding(8)
        }
    }

    private var logSection: some View {
        GroupBox("Connection Log") {
            ScrollView {
                Text(appModel.hubRemoteLog.isEmpty ? "No log yet." : appModel.hubRemoteLog)
                    .font(UIThemeTokens.monoFont())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 180)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
}
