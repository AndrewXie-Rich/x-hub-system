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
        let pairingContext = pairingContext(for: state)
        let connectedRouteSummary = connectedRouteSummary(for: state)
        let machineStatusRef = [
            "local_connected=\(state.localConnected)",
            "remote_connected=\(state.remoteConnected)",
            "linking=\(state.linking)",
            "configured_roles=\(state.configuredModelRoles)/\(state.totalModelRoles)",
            "failure_code=\(state.failureCode.isEmpty ? "none" : state.failureCode)",
            state.runtime.machineStatusSegment
        ].joined(separator: "; ")

        let primaryStatus: StatusExplanation
        if failureIssue == .pairingRepairRequired {
            let tokenRequired = UITroubleshootKnowledgeBase.isInviteTokenRequiredFailure(state.failureCode)
            let tokenInvalid = UITroubleshootKnowledgeBase.isInviteTokenInvalidFailure(state.failureCode)
            let headline: String
            let whatHappened: String
            let whyItHappened: String
            let userAction: String
            let hardLine: String

            if tokenRequired {
                headline = "当前外网配对缺少邀请令牌"
                whatHappened = "Hub 现在会对外网配对请求强制校验邀请令牌；这次连接没带上有效令牌，所以“连接 Hub”这一步不会进入就绪。"
                whyItHappened = "模型和授权就算显示就绪，也不能绕过这条门禁；继续重试只会重复缺少邀请令牌这一类失败。"
                userAction = "重新打开 Hub 发出的邀请链接，让 XT 自动带入 host / 端口 / token 后再点“一键连接”；不要手填旧 token。"
                hardLine = "external pairing requires valid invite token"
            } else if tokenInvalid {
                headline = "邀请令牌已失效或不匹配"
                whatHappened = "当前阻塞更像是邀请令牌过期、被 Hub 轮换，或 token 与当前这台 Hub 不匹配，而不是单纯的证书或端口问题。"
                whyItHappened = "如果继续用旧邀请做 reconnect，只会反复得到 invite_token_invalid / pairing_token_invalid 这类失败。"
                userAction = "让 Hub 重新复制或轮换邀请令牌，再重新打开邀请链接；必要时先执行“清除配对后重连”，然后重新批准当前设备。"
                hardLine = "stale invite tokens must be rotated before pairing resumes"
            } else {
                headline = "现有配对档案已失效，需要清理并重配"
                whatHappened = "当前阻塞更像是旧 pairing profile、token 或 mTLS client certificate 已经过期或不再匹配，而不是单纯的 Hub 没开。"
                whyItHappened = "如果继续用旧档案做 reconnect，只会反复得到 unauthenticated、certificate_required 或 pairing_health_failed 这类失败。"
                userAction = "先执行“清除配对后重连”，再去 REL Flow Hub → Pairing & Device Trust → 设备列表（允许清单），筛“过期”并删除旧设备条目，然后重新批准。"
                hardLine = "stale pairing must be repaired before smoke resumes"
            }

            primaryStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: headline,
                whatHappened: whatHappened,
                whyItHappened: whyItHappened,
                userAction: userAction,
                machineStatusRef: machineStatusRef,
                hardLine: hardLine,
                highlights: mergedHighlights([
                    "primary_cta=repair_pairing",
                    "diagnostic_entrypoint=pairing_health"
                ], runtime: state.runtime)
            )
        } else if failureIssue == .multipleHubsAmbiguous {
            primaryStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "局域网里发现了多台 Hub，必须先固定目标",
                whatHappened: "当前不是单纯的 Hub 没开，而是 auto-discovery 同时发现了多台候选 Hub；继续 bootstrap / connect 会把首用路径带进歧义状态。",
                whyItHappened: "只要 Internet Host、pairing port 和 gRPC port 还没明确绑定到一台 Hub，后续重连就可能反复打到不同目标。",
                userAction: "先在连接进度里明确选择要连接的那台 Hub，或直接手填 Internet Host / 端口；必要时到目标 Hub 的 LAN (gRPC) 页面关闭另一台 Hub 的广播。",
                machineStatusRef: machineStatusRef,
                hardLine: "ambiguous hub discovery must be resolved before connect",
                highlights: mergedHighlights([
                    "primary_cta=resolve_hub_ambiguity",
                    "diagnostic_entrypoint=pairing_health"
                ], runtime: state.runtime)
            )
        } else if failureIssue == .hubPortConflict {
            primaryStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "Hub 端口冲突，需要先释放占用或切换端口",
                whatHappened: "当前阻塞更像是目标 Hub 的 gRPC / pairing 端口被别的进程占用，而不是 XT 参数完全缺失。",
                whyItHappened: "如果端口仍处于 already in use / eaddrinuse 状态，继续重连只会重复得到同一类失败。",
                userAction: "先到 REL Flow Hub → LAN (gRPC) 或 REL Flow Hub → Diagnostics & Recovery 切到空闲端口，或释放占用进程；再把新端口同步回 XT 并重跑 reconnect smoke。",
                machineStatusRef: machineStatusRef,
                hardLine: "port conflict must be repaired before connect resumes",
                highlights: mergedHighlights([
                    "primary_cta=repair_hub_port_conflict",
                    "diagnostic_entrypoint=lan_grpc"
                ], runtime: state.runtime)
            )
        } else if !connected {
            primaryStatus = StatusExplanation(
                state: failureIssue == .hubUnreachable ? .diagnosticRequired : .blockedWaitingUpstream,
                headline: "先连接 Hub，再继续首用流程",
                whatHappened: "Hub 还没进入可交互状态，所以首用主链仍停在连接这一步。AI 模型和处理授权就算显示就绪，也不代表 Hub 已真正连通。",
                whyItHappened: "向导会把连接 Hub 放在最前面；只要发现、配对和连接还没真正打通，后面的模型、授权和自检都不能代替这一步。",
                userAction: state.runtime.nextRepairAction ?? (
                    failureIssue == .hubUnreachable
                        ? UITroubleshootKnowledgeBase.guide(
                            for: .hubUnreachable,
                            internetHost: state.doctor.currentRoute.internetHost,
                            pairingContext: pairingContext
                        ).steps.first?.instruction ?? unreachableRepairAction(state: state)
                        : unreachableRepairAction(state: state)
                ),
                machineStatusRef: machineStatusRef,
                hardLine: "Hub 连通前，后续步骤不会放行",
                highlights: mergedHighlights([
                    "primary_cta=pair_hub",
                    "diagnostic_entrypoint=pairing_health"
                ], runtime: state.runtime)
            )
        } else if failureIssue == .grantRequired {
            primaryStatus = StatusExplanation(
                state: .grantRequired,
                headline: "模型已可见，但授权还没放行",
                whatHappened: "首用流程已经走到模型和授权这一步，但当前启动检查或回放核对仍在提示这一步还要授权。",
                whyItHappened: "系统会把授权结果、说明和回放结果一起判断，并尽量把修复入口收敛在 3 步内。",
                userAction: state.runtime.nextRepairAction ?? "先去 Hub 授权、能力范围与配额入口修复，再回到 smoke。",
                machineStatusRef: machineStatusRef,
                hardLine: "授权没通过前，不继续放行",
                highlights: mergedHighlights([
                    "repair_entry=REL Flow Hub → Grants & Permissions",
                    "next_step=run_smoke_after_grant"
                ], runtime: state.runtime)
            )
        } else if failureIssue == .permissionDenied {
            primaryStatus = localNetworkPermissionStatus(
                for: state,
                machineStatusRef: machineStatusRef
            ) ?? StatusExplanation(
                state: .permissionDenied,
                headline: "权限或 policy 拒绝，需要先修复入口",
                whatHappened: "当前阻塞来自系统权限、设备能力或 Hub 策略；对应拒绝原因已并入当前 UI 状态。",
                whyItHappened: "权限拒绝会直接显示出来，避免你在系统设置、Hub 和向导之间来回猜。",
                userAction: state.runtime.nextRepairAction ?? "先处理系统权限或设备信任，再回到首用路径继续。",
                machineStatusRef: machineStatusRef,
                hardLine: "permission blockers remain visible until repaired",
                highlights: mergedHighlights([
                    "repair_entry=system_permissions_or_hub_pairing",
                    "three_step_budget=true"
                ], runtime: state.runtime)
            )
        } else if failureIssue == .modelNotReady {
            primaryStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "模型或路由还没就绪，先确认真实可用模型",
                whatHappened: "当前阻塞更像是提供方还没准备好、上游仍在等待，或目标模型根本不在真实可用清单里，而不是授权已经通过。",
                whyItHappened: "如果这里继续显示成已就绪，你会误以为只差授权一步，实际仍会在模型路由上回退到本地或直接失败。",
                userAction: state.runtime.nextRepairAction ?? "先去 Supervisor Control Center · AI 模型和 XT 设置 → 诊断核对真实可执行模型，再回到 smoke。",
                machineStatusRef: machineStatusRef,
                hardLine: "模型没就绪前，会一直明确拦住",
                highlights: mergedHighlights([
                    "repair_entry=Supervisor Control Center · AI 模型",
                    "diagnostic_entrypoint=model_route_readiness"
                ], runtime: state.runtime)
            )
        } else if failureIssue == .connectorScopeBlocked {
            primaryStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "远端付费路由被边界拦住，先看 Hub 排障",
                whatHappened: "当前阻塞更像是远端导出开关、设备远端策略、预算策略或用户远端偏好把付费远端拦住了，而不是模型没加载。",
                whyItHappened: "这类问题如果只看成一般授权或权限问题，会把真正的边界原因藏掉，也很容易先去错入口。",
                userAction: state.runtime.nextRepairAction ?? "先到 XT 设置 → 诊断记录这次拒绝原因和审计编号，再去 REL Flow Hub → 诊断与恢复查看远端导出开关和修复提示。",
                machineStatusRef: machineStatusRef,
                hardLine: "边界没修好前，远端路由不会恢复",
                highlights: mergedHighlights([
                    "repair_entry=REL Flow Hub → Diagnostics & Recovery",
                    "diagnostic_entrypoint=remote_export_gate"
                ], runtime: state.runtime)
            )
        } else if state.runtime.replayBlocked {
            primaryStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "首用自检还没通过，先看回放结果",
                whatHappened: "Hub 已接入，模型也已配置，但回放核对还没通过，所以现在不能把你送入首个任务。",
                whyItHappened: "回放会继续作为首用自检的硬门槛；没通过前，不会把首个任务显示成可开始。",
                userAction: state.runtime.nextRepairAction ?? "先在 Diagnostics 里查看这次拒绝原因和 replay 场景，再重新触发 reconnect smoke。",
                machineStatusRef: machineStatusRef,
                hardLine: "自检没过前，不继续放行首个任务",
                highlights: mergedHighlights([
                    "primary_cta=run_smoke",
                    "diagnostic_entrypoint=audit_logs"
                ], runtime: state.runtime)
            )
        } else if hasModel {
            primaryStatus = StatusExplanation(
                state: .ready,
                headline: connectedRouteSummary ?? "首用流程已接近完成，可以继续开始第一个任务",
                whatHappened: "连接 Hub 和模型配置都已到位；如果回放和冻结检查也都正常，就可以转向重连自检和首个任务入口。",
                whyItHappened: "这里会沿用同一套状态语义和已验证范围判断，让你看到的进度和其他界面保持一致。",
                userAction: state.runtime.nextRepairAction ?? "先跑 Reconnect Smoke；通过后回 Home 查看项目汇总，或进入 Supervisor 窗口发起大任务。",
                machineStatusRef: machineStatusRef,
                hardLine: "当前仍只放行已验证范围",
                highlights: mergedHighlights([
                    "primary_cta=run_smoke",
                    "follow_up=open_supervisor"
                ], runtime: state.runtime)
            )
        } else {
            primaryStatus = StatusExplanation(
                state: .inProgress,
                headline: connectedRouteSummary ?? "连接 Hub 已完成，下一步去 AI 模型设置",
                whatHappened: "Hub 已接入，但当前还没把首个任务需要的模型角色冻结到位。",
                whyItHappened: "首用流程要求先完成连接 Hub，再到 AI 模型页完成角色绑定，避免把模型缺失误判成授权问题。",
                userAction: "先在 Supervisor Control Center · AI 模型里至少给 coder / supervisor 配置一个 Hub 模型，再继续 grant 与 smoke。",
                machineStatusRef: machineStatusRef,
                hardLine: "还没选模型前，不进入自检",
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
            releaseHeadline = "请求超出已验证范围，先回到主链"
        } else if releaseDecision == DeliveryScopeFreezeDecision.hold.rawValue {
            releaseHeadline = "已验证范围仍在等待收口"
        } else {
            releaseHeadline = "当前仅对外展示已验证主链"
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
                id: "connect_hub",
                title: "连接 Hub",
                subtitle: connectHubSubtitle(
                    failureIssue: failureIssue,
                    connected: connected,
                    linking: state.linking,
                    connectedSummary: connectedRouteSummary
                ),
                systemImage: connected ? "link.circle.fill" : "link.badge.plus",
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "run_smoke",
                title: "重连自检",
                subtitle: runSmokeSubtitle(runtime: state.runtime),
                systemImage: "bolt.horizontal.circle",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "open_repair_entry",
                title: "查看授权与排障",
                subtitle: reviewSubtitle(
                    failureIssue: failureIssue,
                    failureCode: state.failureCode,
                    runtime: state.runtime,
                    pairingContext: pairingContext
                ),
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
        } else if failureIssue == .modelNotReady || failureIssue == .connectorScopeBlocked {
            resolveGrantState = .diagnosticRequired
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
        let pairHubState: XTUISurfaceState
        if connected {
            pairHubState = .ready
        } else if failureIssue == .pairingRepairRequired
            || failureIssue == .multipleHubsAmbiguous
            || failureIssue == .hubPortConflict
            || failureIssue == .hubUnreachable {
            pairHubState = .diagnosticRequired
        } else if state.linking {
            pairHubState = .inProgress
        } else {
            pairHubState = .blockedWaitingUpstream
        }
        let steps = [
            UIFirstRunStep(
                kind: .pairHub,
                title: "连接 Hub",
                summary: pairHubSummary(
                    connected: connected,
                    hasModel: hasModel,
                    resolveGrantState: resolveGrantState
                ),
                state: pairHubState,
                repairEntry: .xtPairHub
            ),
            UIFirstRunStep(
                kind: .chooseModel,
                title: "Supervisor Control Center · AI 模型",
                summary: chooseModelSummary(connected: connected, hasModel: hasModel),
                state: hasModel ? .ready : (connected ? .inProgress : .blockedWaitingUpstream),
                repairEntry: .xtChooseModel
            ),
            UIFirstRunStep(
                kind: .resolveGrant,
                title: "处理授权",
                summary: resolveGrantSummary(connected: connected, state: resolveGrantState),
                state: resolveGrantState,
                repairEntry: failureIssue == .permissionDenied
                    ? .systemPermissions
                    : failureIssue == .modelNotReady
                    ? .xtChooseModel
                    : failureIssue == .connectorScopeBlocked
                    ? .hubDiagnostics
                    : .hubGrants
            ),
            UIFirstRunStep(
                kind: .runSmoke,
                title: "运行自检",
                summary: "通过重连自检和回放核对，确认连接 Hub、模型和授权能一起正常工作。",
                state: runSmokeState,
                repairEntry: .hubDiagnostics
            ),
            UIFirstRunStep(
                kind: .verifyReadiness,
                title: "核验就绪",
                summary: "明确检查当前连接方式、模型数量、工具链路和会话运行时是否都已就绪。",
                state: verifyState,
                repairEntry: .xtDiagnostics
            ),
            UIFirstRunStep(
                kind: .startFirstTask,
                title: "开始首个任务",
                summary: "只回到当前已验证主链：Home 看项目汇总，Supervisor 发起首个任务。",
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

    fileprivate static func runSmokeSubtitle(runtime: UIFailClosedRuntimeSnapshot) -> String {
        if runtime.replayPass == true {
            return "自检通过；连接 Hub、模型和授权都已连通"
        }
        if runtime.replayPass == false {
            return "自检没通过；先看回放结果和诊断"
        }
        return "验证连接 Hub、模型和授权是否都已连通"
    }

    fileprivate static func reviewSubtitle(
        failureIssue: UITroubleshootIssue?,
        failureCode: String = "",
        runtime: UIFailClosedRuntimeSnapshot,
        pairingContext: UITroubleshootPairingContext? = nil
    ) -> String {
        if let subtitle = localNetworkRepairSubtitle(failureCode: failureCode) {
            return subtitle
        }
        if failureIssue == .pairingRepairRequired
            || failureIssue == .multipleHubsAmbiguous
            || failureIssue == .hubPortConflict
            || failureIssue == .hubUnreachable
            || failureIssue == .connectorScopeBlocked {
            return UITroubleshootKnowledgeBase.repairEntryDetail(
                for: failureIssue,
                runtime: runtime,
                pairingContext: pairingContext
            )
        }
        if !runtime.nextDirectedAction.isEmpty {
            return "系统建议先做：\(runtime.nextDirectedAction)"
        }
        if let failureIssue {
            return "\(failureIssue.title)；\(runtime.nextRepairAction ?? "先打开排障入口")"
        }
        if let denyCode = runtime.launchDenyCodes.first(where: { !$0.isEmpty }) {
            return "当前拒绝原因：\(denyCode)"
        }
        return "授权、权限、模型未就绪或 Hub 连不上的问题，都从这里进入排查"
    }

    private static func localNetworkPermissionStatus(
        for state: HubSetupWizardState,
        machineStatusRef: String
    ) -> StatusExplanation? {
        guard isLocalNetworkFailureCode(state.failureCode) else { return nil }
        let launchStatus = localHubLaunchStatusIfNeeded(for: state.failureCode)
        let blockedCapabilities = launchStatus?.blockedCapabilitiesSummary ?? "none"
        let localHubBlocked = launchStatus?.blocksPaidOrWebCapabilities == true
        let rootCause = launchStatus?.rootCauseErrorCode ?? ""

        let whyItHappened: String
        let userAction: String
        if localHubBlocked {
            whyItHappened = "XT 当前只看见本机 loopback Hub；与此同时，本机 fallback Hub 也处于 \(rootCause.isEmpty ? "bridge_unavailable" : rootCause) 降级，\(blockedCapabilities) 仍被挡住。继续把首用流程显示成可继续，只会把问题拖到 Supervisor 真正发请求时才暴露。"
            userAction = "先到系统设置 → 隐私与安全性 → 本地网络允许 X-Terminal；如果已经允许，再检查当前 Wi-Fi / AP 是否开启了 client isolation。若暂时只能走本机路径，再到 REL Flow Hub → Diagnostics & Recovery 修复 \(rootCause.isEmpty ? "本机 bridge" : rootCause)。"
        } else {
            whyItHappened = "XT 当前只看见本机 loopback Hub。最常见原因是 macOS 本地网络权限没生效，或当前 Wi-Fi / AP 开了 client isolation，所以同网远端 Hub 没法进入 pairing。"
            userAction = "先到系统设置 → 隐私与安全性 → 本地网络允许 X-Terminal；如果已经允许，再检查当前 Wi-Fi / AP 是否开启了 client isolation。"
        }

        var highlights = [
            "repair_entry=system_permissions_or_hub_pairing",
            "three_step_budget=true",
            "remote_lan_blocked=true"
        ]
        if !rootCause.isEmpty {
            highlights.append("local_hub_root_cause=\(rootCause)")
        }
        if blockedCapabilities != "none" {
            highlights.append("local_hub_blocked_capabilities=\(blockedCapabilities)")
        }

        return StatusExplanation(
            state: .permissionDenied,
            headline: "XT 只能看到本机 loopback Hub，远端同网发现被挡住了",
            whatHappened: "当前发现阶段没有命中远端 Hub，所以 pairing 请求还没真正发到 Hub 端；XT 现在看到的只有自己机器上的 loopback Hub。",
            whyItHappened: whyItHappened,
            userAction: state.runtime.nextRepairAction ?? userAction,
            machineStatusRef: machineStatusRef,
            hardLine: "remote LAN remains blocked until Local Network / Wi-Fi policy is repaired",
            highlights: mergedHighlights(highlights, runtime: state.runtime)
        )
    }

    private static func localNetworkRepairSubtitle(failureCode: String) -> String? {
        guard isLocalNetworkFailureCode(failureCode) else { return nil }
        let launchStatus = localHubLaunchStatusIfNeeded(for: failureCode)
        guard let launchStatus, launchStatus.blocksPaidOrWebCapabilities else {
            return "XT 只看见本机 loopback Hub；先打开本地网络权限，若已允许再检查当前 Wi-Fi / AP 是否开启了 client isolation。"
        }
        let rootCause = launchStatus.rootCauseErrorCode.isEmpty
            ? "本机 bridge"
            : launchStatus.rootCauseErrorCode
        return "XT 只看见本机 loopback Hub；另外本机 fallback Hub 也处于 \(rootCause)，\(launchStatus.blockedCapabilitiesSummary) 仍被阻塞。先修本地网络，再到 REL Flow Hub → Diagnostics & Recovery 修 bridge。"
    }

    private static func localHubLaunchStatusIfNeeded(
        for failureCode: String
    ) -> XTHubLaunchStatusSnapshot? {
        guard isLocalNetworkFailureCode(failureCode) else { return nil }
        return XTHubLaunchStatusStore.load()
    }

    private static func isLocalNetworkFailureCode(_ failureCode: String) -> Bool {
        let normalized = UITroubleshootKnowledgeBase.normalizedFailureCode(failureCode)
        return normalized.contains("local_network_permission_required")
            || normalized.contains("local_network_discovery_blocked")
    }

    fileprivate static func pairingContext(for state: HubSetupWizardState) -> UITroubleshootPairingContext? {
        UITroubleshootPairingContext(
            firstPairCompletionProofSnapshot: state.doctor.firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: state.doctor.pairedRouteSetSnapshot
        )
    }

    fileprivate static func connectedRouteSummary(for state: HubSetupWizardState) -> String? {
        guard state.localConnected || state.remoteConnected else { return nil }
        let summary = state.doctor.pairedRouteSetSnapshot?.summaryLine
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return summary.isEmpty ? nil : summary
    }

    fileprivate static func connectHubSubtitle(
        failureIssue: UITroubleshootIssue?,
        connected: Bool,
        linking: Bool,
        connectedSummary: String? = nil
    ) -> String {
        if linking {
            return "正在发现 Hub、刷新配对并建立连接"
        }
        switch failureIssue {
        case .pairingRepairRequired:
            return "当前需要清理旧配对后重新连接"
        case .multipleHubsAmbiguous:
            return "先固定目标 Hub，再继续连接"
        case .hubPortConflict:
            return "先修复端口冲突，再继续连接"
        case .hubUnreachable:
            return "先核对 Hub 可达性，再继续连接"
        default:
            if connected {
                return connectedSummary ?? "Hub 已连通；需要重试或改参数时看下方连接进度"
            }
            return "先把发现、配对和连接这条主链走通"
        }
    }

    private static func unreachableRepairAction(state: HubSetupWizardState) -> String {
        let route = state.doctor.currentRoute
        let host = route.internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host.isEmpty == false else {
            return "先完成一键配置；如失败，再按主机、端口和 Hub 不可达这 3 步继续排查。"
        }
        return "先核对当前目标 \(host) 的 Pairing Port \(route.pairingPort) 和 gRPC Port \(route.grpcPort)；同局域网优先使用 LAN IP，走公网则先确认防火墙 / NAT 已放行。"
    }

    private static func pairHubSummary(
        connected: Bool,
        hasModel: Bool,
        resolveGrantState: XTUISurfaceState
    ) -> String {
        guard connected == false, hasModel || resolveGrantState == .ready else {
            return "先把发现、配对和连接这条主链打通。"
        }
        return "AI 模型和处理授权就算显示就绪，也只说明那两张卡暂时没阻塞，不代表连接 Hub 已完成；仍要先把发现、配对和连接打通。"
    }

    private static func chooseModelSummary(connected: Bool, hasModel: Bool) -> String {
        if hasModel && !connected {
            return "模型已在统一入口完成绑定；但这只表示角色选择已固定，不代表 Hub 已真正连通。"
        }
        return "先到 AI 模型里把首个任务要用的角色配好，避免把模型问题误判成授权问题。"
    }

    private static func resolveGrantSummary(connected: Bool, state: XTUISurfaceState) -> String {
        if state == .ready && !connected {
            return "授权卡显示就绪，只表示当前没有明确的授权阻塞；连接 Hub 仍然是更上游的前置步骤。"
        }
        return "授权、权限、模型未就绪或 Hub 连不上的问题，都应该在 3 步内定位到修复入口。"
    }
}

struct HubSetupWizardView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var supervisorManager = SupervisorManager.shared
    @StateObject private var modelManager = HubModelManager.shared
    @State private var activeFocusRequest: XTHubSetupFocusRequest?
    @State private var connectionToolsExpanded = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: UIThemeTokens.sectionSpacing) {
                    headerSection
                    PrimaryActionRail(title: "首用动作", actions: journeyPlan.actions, onTap: handleAction)
                    setupProgressSection
                        .id("pair_progress")
                    StatusExplanationCard(explanation: journeyPlan.primaryStatus)
                    modelSelectionSection
                        .id("choose_model")
                    verifyReadinessSection
                        .id("verify_readiness")
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
                modelManager.setAppModel(appModel)
                if appModel.hubInteractive {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
            }
            .onChange(of: appModel.hubInteractive) { connected in
                if connected {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
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
            Text("先把 Hub 连接打通，再继续模型、授权和自检。上面是首用动作，下面直接看发现 / 配对 / 连接的实时进度。")
                .font(UIThemeTokens.bodyFont())
                .foregroundStyle(.secondary)
        }
    }

    private var modelSelectionSection: some View {
        GroupBox("AI 模型主入口") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "choose_model") {
                    XTFocusContextCard(context: context)
                }
                Text("向导这里不再直接改写角色模型；只汇总当前状态，并把你带到 Supervisor Control Center · AI 模型这个唯一稳定入口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已配置模型角色：\(journeyPlan.configuredModelRoles)/\(journeyPlan.totalModelRoles)")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                        Text(journeyPlan.configuredModelRoles > 0 ? "当前向导只保留摘要与修复跳转。" : "当前还没有完成首用角色绑定，建议至少先配置 coder / supervisor。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开 Supervisor Control Center · AI 模型") {
                        openSupervisorModelSettings(
                            title: "完成首用模型配置",
                            detail: "Hub 首次连接向导这里只保留摘要；模型编辑、替换和路由修复统一进入 Supervisor Control Center · AI 模型。"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("角色")
                            .foregroundStyle(.secondary)
                        Text("当前绑定")
                            .foregroundStyle(.secondary)
                        Text("入口")
                            .foregroundStyle(.secondary)
                    }
                    .font(UIThemeTokens.monoFont())

                    ForEach(AXRole.allCases) { role in
                        GridRow {
                            Text(role.displayName)
                                .frame(width: 120, alignment: .leading)
                            Text(configuredGlobalModelID(for: role) ?? "未配置")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(configuredGlobalModelID(for: role) == nil ? UIThemeTokens.color(for: .inProgress) : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("定位") {
                                openSupervisorModelSettings(
                                    role: role,
                                    title: "检查 \(role.displayName) 模型绑定",
                                    detail: configuredGlobalModelID(for: role).map {
                                        "当前记录的模型是 `\($0)`；如需替换、核对 inventory 或修复路由，请直接在统一模型入口处理。"
                                    } ?? "当前角色还没有绑定模型；请在统一模型入口完成首用配置。"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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
                                Button("定位到 \(issue.role.displayName)") {
                                    openSupervisorModelSettings(
                                        role: issue.role,
                                        title: "处理 \(issue.role.displayName) 模型阻塞",
                                        detail: issue.suggestedModelId.map {
                                            "\(issue.message) 建议优先检查 `\($0)` 是否已经进入真实可执行列表。"
                                        } ?? issue.message
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
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

                Text("建议至少先配置 coder / supervisor；如果卡在 Hub 授权、能力范围或配额，就先去 REL Flow Hub → Models & Paid Access / Grants & Permissions，再回统一模型入口确认真实可执行列表。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var setupProgressSection: some View {
        GroupBox("连接进度") {
            VStack(alignment: .leading, spacing: 10) {
                if let context = focusContext(for: "pair_progress") {
                    XTFocusContextCard(context: context)
                }

                if let inviteStatusPresentation {
                    HubInviteStatusCard(presentation: inviteStatusPresentation)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progressValue, total: 3.0)
                    Text(pairProgressHintText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

                DisclosureGroup(isExpanded: $connectionToolsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("自动探测失败、需要固定目标 Hub，或要清掉旧配对时，再展开这里。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
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
                                Text("正式入口")
                                    .frame(width: 130, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("hub.xhubsystem.com", text: internetHostBinding)
                                        .textFieldStyle(.roundedBorder)
                                    Text(formalEntryGuidancePresentation.message)
                                        .font(.caption)
                                        .foregroundStyle(formalEntryGuidancePresentation.state.tint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            GridRow {
                                Text("邀请令牌（首配用）")
                                    .frame(width: 130, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("来自 Hub 邀请链接", text: inviteTokenBinding)
                                        .textFieldStyle(.roundedBorder)
                                    Text(inviteTokenGuidancePresentation.message)
                                        .font(.caption)
                                        .foregroundStyle(inviteTokenGuidancePresentation.state.tint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            GridRow {
                                Text("axhubctl 路径")
                                    .frame(width: 130, alignment: .leading)
                                TextField("自动探测", text: axhubctlPathBinding)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("连接参数与修复工具")
                            .font(.headline)
                        Spacer()
                        Text(connectionToolsExpanded ? "展开中" : "已折叠")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                if !appModel.skillsCompatibilitySnapshot.governanceSurfaceEntries.isEmpty {
                    XTSkillGovernanceSurfaceView(
                        items: appModel.skillsCompatibilitySnapshot.governanceSurfaceEntries,
                        title: "技能治理核对（Governance surface）",
                        maxItems: 4
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
                    if shouldOfferLocalNetworkRepair(for: appModel.hubSetupFailureCode) {
                        HStack(spacing: 8) {
                            Button(XTSystemSettingsLinks.buttonLabel(for: .localNetwork)) {
                                XTSystemSettingsLinks.openPrivacy(.localNetwork)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Text("如果已经允许，再确认当前 Wi-Fi / AP 没开 client isolation，且 XT 能访问 Hub 的 pairing 端口。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                TroubleshootPanel(
                    title: "高频问题 3 步修复",
                    issues: UITroubleshootIssue.highFrequencyIssues,
                    paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
                    internetHost: appModel.hubInternetHost,
                    pairingContext: troubleshootPairingContext
                )
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
        guard let orchestrator = appModel.legacySupervisorRuntimeContextIfLoaded?.orchestrator else {
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
        let snapshot = visibleModelSnapshot
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

    private var visibleModelSnapshot: ModelStateSnapshot {
        modelManager.visibleSnapshot(fallback: appModel.modelsState)
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

    private func configuredGlobalModelID(for role: AXRole) -> String? {
        let modelID = appModel.settingsStore.settings.assignment(for: role).model?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return modelID.isEmpty ? nil : modelID
    }

    private func handleAction(_ action: PrimaryActionRailAction) {
        switch action.id {
        case "connect_hub":
            handleConnectHubAction()
        case "run_smoke":
            appModel.startHubReconnectOnly()
        case "open_repair_entry":
            let issue = journeyPlan.currentFailureIssue
            if issue == .modelNotReady {
                openSupervisorModelSettings(
                    role: .coder,
                    title: UITroubleshootKnowledgeBase.repairEntryTitle(for: issue),
                    detail: UIFirstRunJourneyPlanner.reviewSubtitle(
                        failureIssue: issue,
                        failureCode: appModel.hubSetupFailureCode,
                        runtime: runtimeSnapshot,
                        pairingContext: troubleshootPairingContext
                    )
                )
                return
            }
            let targetSection: String
            switch issue {
            case .pairingRepairRequired, .multipleHubsAmbiguous, .hubPortConflict:
                targetSection = "pair_progress"
            default:
                targetSection = "troubleshoot"
            }
            let title = UITroubleshootKnowledgeBase.repairEntryTitle(for: issue)
            let detail = UIFirstRunJourneyPlanner.reviewSubtitle(
                failureIssue: issue,
                failureCode: appModel.hubSetupFailureCode,
                runtime: runtimeSnapshot,
                pairingContext: troubleshootPairingContext
            )
            appModel.requestHubSetupFocus(
                sectionId: targetSection,
                title: title,
                detail: detail
            )
        default:
            break
        }
    }

    private func handleConnectHubAction() {
        commitPendingHubEndpointEdits()
        let issue = journeyPlan.currentFailureIssue
        switch issue {
        case .pairingRepairRequired:
            connectionToolsExpanded = true
            appModel.resetPairingStateAndOneClickSetup()
        case .multipleHubsAmbiguous:
            connectionToolsExpanded = true
            appModel.requestHubSetupFocus(
                sectionId: "pair_progress",
                title: "固定目标 Hub 后继续连接",
                detail: UITroubleshootKnowledgeBase.repairEntryDetail(
                    for: .multipleHubsAmbiguous,
                    runtime: runtimeSnapshot
                )
            )
        case .hubPortConflict:
            connectionToolsExpanded = true
            appModel.requestHubSetupFocus(
                sectionId: "pair_progress",
                title: "修复 Hub 端口冲突",
                detail: UITroubleshootKnowledgeBase.repairEntryDetail(
                    for: .hubPortConflict,
                    runtime: runtimeSnapshot
                )
            )
        default:
            if appModel.hubRemoteLinking || appModel.hubInteractive {
                appModel.requestHubSetupFocus(
                    sectionId: "pair_progress",
                    title: "查看连接进度",
                    detail: "这里直接看发现 / 配对 / 连接的当前状态；需要手动修复时，再展开连接参数与修复工具。"
                )
            } else {
                appModel.startHubOneClickSetup()
            }
        }
    }

    private func commitPendingHubEndpointEdits() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        if NSApp.mainWindow !== NSApp.keyWindow {
            NSApp.mainWindow?.makeFirstResponder(nil)
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
        case .awaitingApproval:
            return 0.6
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
        case .awaitingApproval:
            return "lock.shield.fill"
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
        case .awaitingApproval:
            return .orange
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
        case .awaitingApproval:
            return "awaiting approval"
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

    private func openSupervisorModelSettings(
        role: AXRole? = nil,
        title: String,
        detail: String
    ) {
        appModel.requestModelSettingsFocus(
            role: role,
            title: title,
            detail: detail
        )
        supervisorManager.requestSupervisorWindow(
            sheet: .modelSettings,
            reason: "hub_setup_model_settings",
            focusConversation: false,
            startConversation: false
        )
    }

    private var inviteStatusPresentation: HubInviteStatusPresentation? {
        HubInviteStatusPlanner.build(
            inviteAlias: appModel.hubInviteAlias,
            internetHost: appModel.hubInternetHost,
            pairingPort: appModel.hubPairingPort,
            grpcPort: appModel.hubGrpcPort,
            inviteToken: appModel.hubInviteToken,
            hubInstanceID: appModel.hubInviteInstanceID,
            connected: appModel.hubInteractive,
            linking: appModel.hubRemoteLinking,
            failureCode: appModel.hubSetupFailureCode
        )
    }

    private var pairProgressHintText: String {
        if UITroubleshootKnowledgeBase.isInviteTokenFailure(appModel.hubSetupFailureCode) {
            return "当前先修复邀请令牌，再继续连接。"
        }
        if !appModel.hubInviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "正式首配参数已载入，通常可直接一键连接。"
        }
        if hasStableFormalEntry {
            return "正式入口已设置；切网后 XT 会优先验证这条路径。"
        }
        return "进入页面会先自动探测一轮；失败后再手填。"
    }

    private var formalEntryGuidancePresentation: HubRemoteAccessGuidancePresentation {
        HubRemoteAccessGuidanceBuilder.formalEntry(
            internetHost: appModel.hubInternetHost
        )
    }

    private var inviteTokenGuidancePresentation: HubRemoteAccessGuidancePresentation {
        HubRemoteAccessGuidanceBuilder.inviteToken(
            internetHost: appModel.hubInternetHost,
            inviteToken: appModel.hubInviteToken
        )
    }

    private var hasStableFormalEntry: Bool {
        if case .stableNamed = XTHubRemoteAccessHostClassification
            .classify(appModel.hubInternetHost).kind {
            return true
        }
        return false
    }

    private var pairingPortBinding: Binding<Int> {
        Binding(
            get: { appModel.hubPairingPort },
            set: { value in
                appModel.setHubPairingPortFromUser(value)
            }
        )
    }

    private var grpcPortBinding: Binding<Int> {
        Binding(
            get: { appModel.hubGrpcPort },
            set: { value in
                appModel.setHubGrpcPortFromUser(value)
            }
        )
    }

    private var internetHostBinding: Binding<String> {
        Binding(
            get: { appModel.hubInternetHost },
            set: { value in
                appModel.setHubInternetHostFromUser(value)
            }
        )
    }

    private var inviteTokenBinding: Binding<String> {
        Binding(
            get: { appModel.hubInviteToken },
            set: { value in
                appModel.hubInviteToken = value
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
        if shouldOfferLocalNetworkRepair(for: rawCode) {
            if let launchStatus = XTHubLaunchStatusStore.load(
                baseDir: appModel.hubBaseDir ?? HubPaths.baseDir()
            ),
               launchStatus.blocksPaidOrWebCapabilities {
                let rootCause = launchStatus.rootCauseErrorCode.isEmpty
                    ? "本机 bridge"
                    : launchStatus.rootCauseErrorCode
                return "XT 当前只能发现本机 loopback Hub，远端同网发现被挡住了。另外，本机 fallback Hub 也处于 \(rootCause)，\(launchStatus.blockedCapabilitiesSummary) 仍被阻塞。先打开“本地网络”权限；如果已经允许，再检查当前 Wi-Fi / AP 是否开启了 client isolation。"
            }
            return "XT 当前只能发现本机 loopback Hub，远端同网发现被挡住了。先打开“本地网络”权限；如果已经允许，再检查当前 Wi-Fi / AP 是否开启了 client isolation。"
        }
        if let issue = UITroubleshootKnowledgeBase.issue(forFailureCode: rawCode) {
            return UITroubleshootKnowledgeBase.guide(
                for: issue,
                internetHost: appModel.hubInternetHost,
                pairingContext: troubleshootPairingContext
            ).steps.first?.instruction
        }
        return nil
    }

    private func shouldOfferLocalNetworkRepair(for rawCode: String) -> Bool {
        let normalized = UITroubleshootKnowledgeBase.normalizedFailureCode(rawCode)
        return normalized.contains("local_network_permission_required")
            || normalized.contains("local_network_discovery_blocked")
    }

    private var troubleshootPairingContext: UITroubleshootPairingContext? {
        UITroubleshootPairingContext(
            firstPairCompletionProofSnapshot: doctorReport.firstPairCompletionProofSnapshot,
            pairedRouteSetSnapshot: doctorReport.pairedRouteSetSnapshot
        )
    }

    private func processHubSetupFocusRequest(_ proxy: ScrollViewProxy) {
        guard let request = appModel.hubSetupFocusRequest else { return }
        activeFocusRequest = request
        if request.sectionId == "pair_progress" {
            connectionToolsExpanded = true
        }
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
