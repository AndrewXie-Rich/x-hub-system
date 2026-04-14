import SwiftUI

private func uiTroubleshootTrimmedNonEmpty(_ raw: String?) -> String? {
    let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

enum UITroubleshootIssue: String, CaseIterable, Codable, Sendable {
    case grantRequired = "grant_required"
    case permissionDenied = "permission_denied"
    case modelNotReady = "model_not_ready"
    case connectorScopeBlocked = "connector_scope_blocked"
    case paidModelAccessBlocked = "paid_model_access_blocked"
    case pairingRepairRequired = "pairing_repair_required"
    case multipleHubsAmbiguous = "multiple_hubs_ambiguous"
    case hubPortConflict = "hub_port_conflict"
    case hubUnreachable = "hub_unreachable"

    static let highFrequencyIssues: [UITroubleshootIssue] = [
        .multipleHubsAmbiguous,
        .hubPortConflict,
        .pairingRepairRequired,
        .hubUnreachable,
        .modelNotReady,
        .connectorScopeBlocked,
        .paidModelAccessBlocked,
        .grantRequired,
        .permissionDenied
    ]

    var title: String {
        switch self {
        case .grantRequired:
            return "需要授权"
        case .permissionDenied:
            return "权限被拒绝"
        case .modelNotReady:
            return "模型未就绪"
        case .connectorScopeBlocked:
            return "远端导出受阻"
        case .paidModelAccessBlocked:
            return "付费模型访问受阻"
        case .pairingRepairRequired:
            return "配对需要修复"
        case .multipleHubsAmbiguous:
            return "发现多台 Hub"
        case .hubPortConflict:
            return "Hub 端口冲突"
        case .hubUnreachable:
            return "Hub 不可达"
        }
    }

    var summary: String {
        switch self {
        case .grantRequired:
            return "需要付费模型、联网或设备级高风险能力时，先确认当前模型入口，再到 Hub 授权、能力范围与配额入口修复。"
        case .permissionDenied:
            return "设备能力、系统权限或 Hub 安全边界拒绝时，不再只显示原始报错，而是直接指到对应修复面。"
        case .modelNotReady:
            return "当上游仍在等待、提供方尚未就绪，或目标模型根本不在真实可用清单里时，应该直接带你去检查模型和路由，而不是只给一个模糊阻塞。"
        case .connectorScopeBlocked:
            return "当 Hub 的远端导出开关、设备远端策略、预算策略或用户远端偏好把付费远端挡住时，应该直接带你去 Hub 排障和边界修复入口。"
        case .paidModelAccessBlocked:
            return "当设备级付费模型策略、白名单或预算把请求挡住时，诊断入口应该直接指向设备信任、模型和预算，而不是只告诉你权限被拒。"
        case .pairingRepairRequired:
            return "当本地配对档案过期、令牌失效或证书不再匹配时，系统应该明确要求你清理失效配对并重配，而不是继续拿旧档案反复重连。"
        case .multipleHubsAmbiguous:
            return "当局域网里同时发现多台 Hub 时，必须先固定目标 Hub，再继续连接；不能继续靠自动发现猜。"
        case .hubPortConflict:
            return "当 Hub 的 gRPC 或配对端口被占用时，应该直接带你去改端口或释放占用，而不是只显示笼统的连接失败。"
        case .hubUnreachable:
            return "Hub 不可达时，模型和授权就算显示就绪，也只说明那两张卡暂时没阻塞，不代表连接 Hub 已完成；优先检查目标主机、端口和对外可达性。"
        }
    }
}

enum UITroubleshootDestination: String, Codable, Sendable {
    case xtPairHub = "xt_pair_hub"
    case xtChooseModel = "xt_choose_model"
    case xtDiagnostics = "xt_diagnostics"
    case hubLAN = "hub_lan_grpc"
    case hubPairing = "hub_pairing_device_trust"
    case hubModels = "hub_models_paid_access"
    case hubGrants = "hub_grants_permissions"
    case hubSecurity = "hub_security_boundary"
    case hubDiagnostics = "hub_diagnostics_recovery"
    case systemPermissions = "system_permissions"
    case homeSupervisor = "home_supervisor_first_task"

    var label: String {
        switch self {
        case .xtPairHub:
            return "XT 设置 → 连接 Hub"
        case .xtChooseModel:
            return "Supervisor 控制中心 → AI 模型"
        case .xtDiagnostics:
            return "XT 设置 → 诊断与核对"
        case .hubLAN:
            return "REL Flow Hub → 网络连接"
        case .hubPairing:
            return "REL Flow Hub → 配对与设备信任"
        case .hubModels:
            return "REL Flow Hub → 模型与付费访问"
        case .hubGrants:
            return "REL Flow Hub → 授权与权限"
        case .hubSecurity:
            return "REL Flow Hub → 安全边界"
        case .hubDiagnostics:
            return "REL Flow Hub → 诊断与恢复"
        case .systemPermissions:
            return "系统设置 → 权限"
        case .homeSupervisor:
            return "首页 / Supervisor → 开始第一个任务"
        }
    }
}

struct UITroubleshootStep: Identifiable, Codable, Equatable, Sendable {
    let index: Int
    let instruction: String
    let destination: UITroubleshootDestination

    var id: String { "\(destination.rawValue)-\(index)" }
}

struct UITroubleshootGuide: Identifiable, Codable, Equatable, Sendable {
    let issue: UITroubleshootIssue
    let summary: String
    let steps: [UITroubleshootStep]

    var id: String { issue.rawValue }
    var title: String { issue.title }
    var maxFixSteps: Int { steps.count }
}

struct UITroubleshootActionDescriptor: Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
}

struct UITroubleshootPairingContext: Equatable, Sendable {
    let firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot?
    let pairedRouteSetSnapshot: XTPairedRouteSetSnapshot?

    init?(
        firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot?,
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot?
    ) {
        guard firstPairCompletionProofSnapshot != nil || pairedRouteSetSnapshot != nil else {
            return nil
        }
        self.firstPairCompletionProofSnapshot = firstPairCompletionProofSnapshot
        self.pairedRouteSetSnapshot = pairedRouteSetSnapshot
    }

    var readiness: XTPairedRouteReadiness {
        pairedRouteSetSnapshot?.readiness ?? firstPairCompletionProofSnapshot?.readiness ?? .unknown
    }

    var stableRemoteRoutePresent: Bool {
        pairedRouteSetSnapshot?.stableRemoteRoute != nil
            || firstPairCompletionProofSnapshot?.stableRemoteRoutePresent == true
    }

    var stableRemoteHost: String? {
        uiTroubleshootTrimmedNonEmpty(pairedRouteSetSnapshot?.stableRemoteRoute?.host)
    }

    var remoteShadowSmokeStatus: XTFirstPairRemoteShadowSmokeStatus {
        firstPairCompletionProofSnapshot?.remoteShadowSmokeStatus ?? .notRun
    }

    var remoteShadowReasonCode: String? {
        uiTroubleshootTrimmedNonEmpty(firstPairCompletionProofSnapshot?.remoteShadowReasonCode)
    }

    var remoteShadowSummary: String? {
        uiTroubleshootTrimmedNonEmpty(firstPairCompletionProofSnapshot?.remoteShadowSummary)
    }

    var sameLanVerified: Bool {
        firstPairCompletionProofSnapshot?.sameLanVerified == true
            || pairedRouteSetSnapshot?.lanRoute != nil
    }

    var formalRemoteVerificationPending: Bool {
        readiness == .localReady
            && stableRemoteRoutePresent
            && (remoteShadowSmokeStatus == .notRun || remoteShadowSmokeStatus == .running)
    }

    var remoteShadowFailed: Bool {
        remoteShadowSmokeStatus == .failed || readiness == .remoteDegraded
    }

    var proofShowsRemoteReady: Bool {
        readiness == .remoteReady
    }
}

enum UITroubleshootKnowledgeBase {
    static func guides(
        for issues: [UITroubleshootIssue],
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        internetHost: String? = nil,
        pairingContext: UITroubleshootPairingContext? = nil
    ) -> [UITroubleshootGuide] {
        issues.map {
            guide(
                for: $0,
                paidAccessSnapshot: paidAccessSnapshot,
                internetHost: internetHost,
                pairingContext: pairingContext
            )
        }
    }

    static func guide(
        for issue: UITroubleshootIssue,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        internetHost: String? = nil,
        pairingContext: UITroubleshootPairingContext? = nil
    ) -> UITroubleshootGuide {
        switch issue {
        case .grantRequired:
            return UITroubleshootGuide(
                issue: issue,
                summary: issue.summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "确认当前任务用的模型已经在 Supervisor 控制中心 → AI 模型里选定，避免把授权问题误判成模型缺失。", destination: .xtChooseModel),
                    UITroubleshootStep(index: 2, instruction: "到 Hub 授权面核对这次请求需要的能力范围与配额，例如付费模型、联网访问或设备能力。", destination: .hubGrants),
                    UITroubleshootStep(index: 3, instruction: "授权修复后回到配对 / smoke 路径重试，再进入首个任务。", destination: .xtPairHub)
                ]
            )
        case .permissionDenied:
            return UITroubleshootGuide(
                issue: issue,
                summary: issue.summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先看是 XT 侧权限还是 Hub policy 拒绝；首选入口是 Hub 配对与设备信任页。", destination: .hubPairing),
                    UITroubleshootStep(index: 2, instruction: "若日志出现 `local_network_permission_required` 或 `local_network_discovery_blocked`，先到系统设置 → 隐私与安全性 → 本地网络允许 X-Terminal；若已经允许，再确认当前 Wi-Fi / AP 没开 client isolation。若是其它系统权限或 Hub 安全边界问题，也从这里继续修。", destination: .systemPermissions),
                    UITroubleshootStep(index: 3, instruction: "完成修复后到 XT 设置 → 诊断 查看最新结果并重新触发一次请求。", destination: .xtDiagnostics)
                ]
            )
        case .modelNotReady:
            return UITroubleshootGuide(
                issue: issue,
                summary: issue.summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先在 Supervisor 控制中心 → AI 模型核对当前模型 ID、配置链路和最近一次实际命中的链路，避免把路由阻塞误判成授权问题。", destination: .xtChooseModel),
                    UITroubleshootStep(index: 2, instruction: "到 REL Flow Hub → 模型与付费访问 查看真实可用模型清单、提供方就绪状态，以及当前绑定是否还存在。", destination: .hubModels),
                    UITroubleshootStep(index: 3, instruction: "修复后回 XT 设置 → 诊断与核对，重跑一次路由诊断，确认原始拒绝原因不再出现。", destination: .xtDiagnostics)
                ]
            )
        case .connectorScopeBlocked:
            return UITroubleshootGuide(
                issue: issue,
                summary: issue.summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先到 XT 设置 → 诊断与核对 或路由诊断里记下这次拒绝原因、审计编号和实际回退路径，确认当前不是模型缺失或 Hub 不可达。", destination: .xtDiagnostics),
                    UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 诊断与恢复 查看远端导出开关、恢复建议和对应审计；如果看到远端导出被拦，优先从这里定位。", destination: .hubDiagnostics),
                    UITroubleshootStep(index: 3, instruction: "再按这次拒绝原因修边界：设备或策略拦截优先看 REL Flow Hub → 安全边界；预算拦截看模型与付费访问；如果只是用户自己关掉了远端偏好，就回 XT 调整后再重试。", destination: .hubSecurity)
                ]
            )
        case .paidModelAccessBlocked:
            let pairedDeviceTruth = paidAccessSnapshot.map {
                XTRouteTruthPresentation.paidModelRuntimeTruthText($0)
            }
            let summary: String = {
                guard let pairedDeviceTruth,
                      !pairedDeviceTruth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return issue.summary
                }
                return "\(issue.summary) 当前设备真值：\(pairedDeviceTruth)。"
            }()
            let budgetHintSuffix: String = {
                guard let pairedDeviceTruth,
                      !pairedDeviceTruth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return ""
                }
                return " 当前设备真值：\(pairedDeviceTruth)。"
            }()
            return UITroubleshootGuide(
                issue: issue,
                summary: summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先确认当前选中的 model_id 是否就是被拦截的付费模型，并在 Supervisor 控制中心 → AI 模型记录 device_name / model_id / policy_mode。", destination: .xtChooseModel),
                    UITroubleshootStep(index: 2, instruction: "到 Hub 配对与设备信任页检查该设备是 new_profile 还是 legacy_grant，以及付费模型模式 / allowlist 是否允许当前请求。", destination: .hubPairing),
                    UITroubleshootStep(index: 3, instruction: "再到 REL Flow Hub → 模型与付费访问 查看 daily / single-request budget；修复后回 XT 设置 → 诊断 重试。\(budgetHintSuffix)", destination: .hubModels)
                ]
            )
        case .pairingRepairRequired:
            return pairingRepairGuide(issue: issue, pairingContext: pairingContext)
        case .multipleHubsAmbiguous:
            return UITroubleshootGuide(
                issue: issue,
                summary: issue.summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先到 XT 设置 → 连接 Hub 明确选择要连接的那台 Hub；如果目标 Hub 已知，也可以直接手填 Internet Host、配对端口和 gRPC 端口，停止让自动发现继续猜。", destination: .xtPairHub),
                    UITroubleshootStep(index: 2, instruction: "再到目标 Hub 的网络连接页面核对它实际广播的 Internet Host 与端口；若同网段还有另一台 Hub，先停掉它的局域网广播或改成手动指定。", destination: .hubLAN),
                    UITroubleshootStep(index: 3, instruction: "固定目标 Hub 后重新执行重连自检，确认多 Hub 歧义这类原始错误不再出现。", destination: .xtDiagnostics)
                ]
            )
        case .hubPortConflict:
            return UITroubleshootGuide(
                issue: issue,
                summary: issue.summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 记下当前配对端口和 gRPC 端口，避免继续拿旧端口反复重连。", destination: .xtPairHub),
                    UITroubleshootStep(index: 2, instruction: "到 REL Flow Hub → 网络连接 或 REL Flow Hub → 诊断与恢复 把 Hub 切到空闲端口，或释放已经占用该端口的进程，直到端口占用提示消失。", destination: .hubLAN),
                    UITroubleshootStep(index: 3, instruction: "把新端口同步回 XT 后重新执行重连自检，确认配对和 gRPC 都恢复。", destination: .xtDiagnostics)
                ]
            )
        case .hubUnreachable:
            return hubUnreachableGuide(
                issue: issue,
                internetHost: internetHost,
                pairingContext: pairingContext
            )
        }
    }

    private static func pairingRepairGuide(
        issue: UITroubleshootIssue,
        pairingContext: UITroubleshootPairingContext?
    ) -> UITroubleshootGuide {
        if pairingContext?.readiness == .remoteBlocked {
            return UITroubleshootGuide(
                issue: issue,
                summary: "当前更像是正式异网路径被 pairing / identity 边界拦住，而不是普通网络波动。XT 侧同网首配已经到位，但旧令牌、证书或设备信任和 Hub 上的当前记录不再匹配；不要继续拿旧入口反复重试。",
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 执行“清除配对后重连”，重新载入当前 Hub 的邀请、主机和端口；不要继续保留旧 token 或旧证书。", destination: .xtPairHub),
                    UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 配对与设备信任 → 设备列表（允许清单）删除旧设备条目，并重新复制或轮换邀请令牌；重新批准当前设备后再导出接入包。", destination: .hubPairing),
                    UITroubleshootStep(index: 3, instruction: "修复后回 XT 重跑重连自检；只有 invite / unauthenticated / certificate 这类身份错误消失后，才算这次配对修复完成。", destination: .hubDiagnostics)
                ]
            )
        }

        if pairingContext?.formalRemoteVerificationPending == true {
            return UITroubleshootGuide(
                issue: issue,
                summary: "同网首配已经完成，XT 也已经拿到稳定异网入口；当前正式异网路径还在验证中。除非你现在明确看到 invite_token / unauthenticated / certificate 这类身份错误，否则不要先清空现有配对。",
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 核对当前 Internet Host、配对端口和 gRPC 端口与 Hub 最新导出一致；如果这次只是离网后的首次异网验证，先保留现有配对。", destination: .xtPairHub),
                    UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 配对与设备信任 确认当前设备条目、邀请状态和设备信任仍有效；不要继续拿旧邀请链接覆盖新配置。", destination: .hubPairing),
                    UITroubleshootStep(index: 3, instruction: "如果随后仍出现明确的 invite / certificate / unauthenticated 失败，再执行“清除配对后重连”；否则优先回 XT / Hub 诊断补跑正式异网验证。", destination: .hubDiagnostics)
                ]
            )
        }

        return UITroubleshootGuide(
            issue: issue,
            summary: issue.summary,
            steps: [
                UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 执行“清除配对后重连”；如果刚看到 `first_pair_requires_same_lan`，先把 XT 和 Hub 放回同一 Wi‑Fi / 同一局域网，再继续。注意同一个 SSID 不一定等于同一 LAN：若仍失败，优先检查 AP 是否开启了 client isolation 或把设备分到不同 VLAN。若你是通过邀请接入，优先重新打开 Hub 邀请链接，让主机、端口和令牌自动填入，不要手填旧令牌。", destination: .xtPairHub),
                UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 配对与设备信任 → 设备列表（允许清单）；若刚看到 invite_token_required / invite_token_invalid，让 Hub 重新复制或轮换邀请令牌，再删除旧设备条目并重新批准当前设备。", destination: .hubPairing),
                UITroubleshootStep(index: 3, instruction: "重配完成后重新执行一键配置或重连自检，确认原始认证失败不再出现。", destination: .hubDiagnostics)
            ]
        )
    }

    private static func hubUnreachableGuide(
        issue: UITroubleshootIssue,
        internetHost: String?,
        pairingContext: UITroubleshootPairingContext?
    ) -> UITroubleshootGuide {
        let classification = XTHubRemoteAccessHostClassification.classify(
            pairingContext?.stableRemoteHost ?? internetHost
        )
        let host = classification.displayHost ?? "未设置"
        let hostInstructionTarget = classification.displayHost ?? "当前导出的正式异网入口"

        if let pairingContext {
            let remoteShadowReasonSuffix = pairingContext.remoteShadowReasonCode.map {
                " 最近一次正式异网验证返回 \($0)。"
            } ?? ""

            if pairingContext.readiness == .remoteBlocked {
                return UITroubleshootGuide(
                    issue: issue,
                    summary: "Hub 当前不可达，但首配完成证明显示同网首配已经通过，正式异网路径现在是被 pairing / identity 边界挡住，而不是普通网络抖动。继续切网重试旧入口没有意义。",
                    steps: [
                        UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 核对 Internet Host \(hostInstructionTarget) 和端口是否来自最新邀请；如果不是，重新打开 Hub 邀请链接，不要继续用旧入口。", destination: .xtPairHub),
                        UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 配对与设备信任 删除旧设备、轮换邀请令牌或刷新设备信任；确认当前设备重新批准后再导出接入包。", destination: .hubPairing),
                        UITroubleshootStep(index: 3, instruction: "修复 pairing / identity 后到 REL Flow Hub → 诊断与恢复 重新跑异网诊断，再回 XT 重连自检。", destination: .hubDiagnostics)
                    ]
                )
            }

            if pairingContext.remoteShadowFailed {
                let hostPhrase = classification.displayHost.map { " \($0)" } ?? ""
                let degradedSummary = "Hub 当前不可达，但 XT 已有稳定异网入口\(hostPhrase)，而且同网首配已经完成。最近一次正式异网验证失败，这更像是 Hub 服务、监听端口、防火墙、NAT 或 relay / forwarding 出问题，而不是要重做首配。" + remoteShadowReasonSuffix
                return UITroubleshootGuide(
                    issue: issue,
                    summary: degradedSummary,
                    steps: [
                        UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 核对 Internet Host \(hostInstructionTarget)、配对端口和 gRPC 端口与当前 Hub 导出一致；先保留现有配对资料。", destination: .xtPairHub),
                        UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 网络连接 检查 app 没休眠、pairing / gRPC 端口正在监听，并确认防火墙、NAT 或 relay 转发仍指向当前 Hub。", destination: .hubLAN),
                        UITroubleshootStep(index: 3, instruction: "然后到 REL Flow Hub → 诊断与恢复 重跑正式异网验证；如果仍失败，再按最新 reason code 继续修。", destination: .hubDiagnostics)
                    ]
                )
            }

            if pairingContext.proofShowsRemoteReady {
                let hostPhrase = classification.displayHost.map { " \($0)" } ?? ""
                return UITroubleshootGuide(
                    issue: issue,
                    summary: "Hub 当前不可达，但 XT 之前已经验证过正式异网入口\(hostPhrase)。这次更像是当前 Hub 服务、监听或转发临时回退，不是缺少首配或邀请。",
                    steps: [
                        UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 核对 Internet Host \(hostInstructionTarget)、配对端口和 gRPC 端口与当前 Hub 导出一致；不要先清除已验证过的配对。", destination: .xtPairHub),
                        UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 网络连接 检查 app 没休眠、pairing / gRPC 端口正在监听，并确认防火墙、NAT 或 relay 转发没有临时回退。", destination: .hubLAN),
                        UITroubleshootStep(index: 3, instruction: "如果命名入口和端口都正确，继续到 REL Flow Hub → 诊断与恢复 重跑远端诊断；修好后回 XT 重新执行重连自检。", destination: .hubDiagnostics)
                    ]
                )
            }

            if pairingContext.formalRemoteVerificationPending {
                let hostPhrase = classification.displayHost.map { " \($0)" } ?? ""
                let verificationPhrase = pairingContext.remoteShadowSmokeStatus == .running
                    ? "正在补跑正式异网验证"
                    : "还没拿到正式异网成功证据"
                return UITroubleshootGuide(
                    issue: issue,
                    summary: "Hub 当前不可达，但同网首配已经完成，XT 也拿到了稳定异网入口\(hostPhrase)。当前更像是正式异网路径\(verificationPhrase)，不要先把这当成要重新配对。",
                    steps: [
                        UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 核对 Internet Host \(hostInstructionTarget) 和端口与当前 Hub 导出一致；不要先清空当前配对。", destination: .xtPairHub),
                        UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 网络连接 确认稳定入口、relay / tailnet / DNS、监听端口和保活状态都正常；Hub 需要保持在线。", destination: .hubLAN),
                        UITroubleshootStep(index: 3, instruction: "到 REL Flow Hub → 诊断与恢复 等待当前正式异网验证完成，或手动重跑远端诊断；通过后再离网重试。", destination: .hubDiagnostics)
                    ]
                )
            }
        }

        switch classification.kind {
        case .missing:
            return UITroubleshootGuide(
                issue: issue,
                summary: "Hub 当前不可达，而且 XT 还没有正式远端入口。只要 Internet Host 为空，离开同一 Wi‑Fi / 同一局域网后就没有可复用的命名入口，这不是普通的短时网络波动。",
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 确认 Internet Host 仍为空；如果这是第一次配对，请先把 XT 和 Hub 放回同一 Wi‑Fi / 同一局域网完成首配。", destination: .xtPairHub),
                    UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 网络连接 配置稳定主机名，例如 tailnet、relay 或 DNS 主机名；不要继续只依赖局域网发现。", destination: .hubLAN),
                    UITroubleshootStep(index: 3, instruction: "导出新的正式接入包后回 XT 重试；必要时再到 REL Flow Hub → 诊断与恢复 确认远端入口已经在线。", destination: .hubDiagnostics)
                ]
            )
        case .lanOnly:
            return UITroubleshootGuide(
                issue: issue,
                summary: "Hub 当前不可达，而且 XT 记录的 Internet Host 还是 \(host)，当前只有同网入口。这类入口只适合同一 Wi‑Fi、同一局域网或同一 VPN；一旦换到别的互联网，它就不是稳定远端入口。",
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 确认 Internet Host 仍是 \(host)；如果你现在就在同一局域网，优先回同网完成首次配对或重连。", destination: .xtPairHub),
                    UITroubleshootStep(index: 2, instruction: "如果要长期异网接入，到 REL Flow Hub → 网络连接 配置稳定主机名或 relay，不要继续把 .local / localhost 当正式外网入口。", destination: .hubLAN),
                    UITroubleshootStep(index: 3, instruction: "更新 XT 的接入包后重新执行重连自检，再到 REL Flow Hub → 诊断与恢复 确认新的远端入口可用。", destination: .hubDiagnostics)
                ]
            )
        case .rawIP(let scope):
            return UITroubleshootGuide(
                issue: issue,
                summary: "Hub 当前不可达，而且 XT 记录的是\(scope.doctorLabel) \(host) 这类临时 raw IP。它在换网、休眠、NAT 或公网 IP 变化后很容易失效，不适合作为长期稳定入口。",
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 确认 raw IP \(host) 仍指向当前目标 Hub，且配对端口和 gRPC 端口没有抄错。", destination: .xtPairHub),
                    UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 网络连接 把入口改成稳定命名入口，例如 tailnet、relay 或 DNS 主机名；不要继续依赖\(scope.doctorLabel) raw IP。", destination: .hubLAN),
                    UITroubleshootStep(index: 3, instruction: "更新 XT 的正式接入包后重跑重连自检；必要时到 REL Flow Hub → 诊断与恢复 核对新的命名入口和转发状态。", destination: .hubDiagnostics)
                ]
            )
        case .stableNamed:
            return UITroubleshootGuide(
                issue: issue,
                summary: "Hub 当前不可达，但 XT 已经有正式异网入口 \(host)。这更像是 Hub 服务休眠、pairing / gRPC 端口没监听、防火墙拦截，或 relay / NAT 没把流量转到当前这台 Hub。",
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先回 XT 设置 → 连接 Hub 核对 Internet Host \(host)、配对端口和 gRPC 端口与当前 Hub 导出的值完全一致。", destination: .xtPairHub),
                    UITroubleshootStep(index: 2, instruction: "再到 REL Flow Hub → 网络连接 检查 app 没休眠、pairing / gRPC 端口正在监听，并确认防火墙、NAT 或 relay 转发没有断开。", destination: .hubLAN),
                    UITroubleshootStep(index: 3, instruction: "如果命名入口和端口都正确，继续到 REL Flow Hub → 诊断与恢复 重跑远端诊断；修好后回 XT 重新执行重连自检。", destination: .hubDiagnostics)
                ]
            )
        }
    }

    static func issue(forFailureCode rawCode: String) -> UITroubleshootIssue? {
        let normalized = normalizedFailureCode(rawCode)
        guard !normalized.isEmpty else { return nil }
        if normalized.contains("bonjour_multiple_hubs_ambiguous")
            || normalized.contains("lan_multiple_hubs_ambiguous")
            || normalized.contains("multiple_hubs_ambiguous") {
            return .multipleHubsAmbiguous
        }
        if normalized.contains("hub_port_conflict")
            || normalized.contains("grpc_port_in_use")
            || normalized.contains("pairing_port_in_use")
            || normalized.contains("port_in_use")
            || normalized.contains("eaddrinuse")
            || normalized.contains("address_already_in_use") {
            return .hubPortConflict
        }
        if normalized.contains("device_paid_model_disabled") || normalized.contains("device_paid_model_not_allowed") || normalized.contains("device_daily_token_budget_exceeded") || normalized.contains("device_single_request_token_exceeded") || normalized.contains("legacy_grant_flow_required") {
            return .paidModelAccessBlocked
        }
        if normalized.contains("connector_scope_blocked")
            || normalized.contains("remote_export_blocked")
            || normalized.contains("device_remote_export_denied")
            || normalized.contains("policy_remote_denied")
            || normalized.contains("budget_remote_denied")
            || normalized.contains("remote_disabled_by_user_pref") {
            return .connectorScopeBlocked
        }
        if normalized.contains("blocked_waiting_upstream")
            || normalized.contains("provider_not_ready")
            || normalized.contains("model_not_found")
            || normalized.contains("remote_model_not_found") {
            return .modelNotReady
        }
        if normalized.contains("unauthenticated")
            || normalized.contains("first_pair_requires_same_lan")
            || normalized.contains("pairing_approval_timeout")
            || normalized.contains("pairing_owner_auth_cancelled")
            || normalized.contains("pairing_owner_auth_failed")
            || normalized.contains("hub_instance_mismatch")
            || normalized.contains("pairing_profile_epoch_stale")
            || normalized.contains("route_pack_outdated")
            || normalized.contains("mtls_client_certificate_required")
            || normalized.contains("pairing_health_failed")
            || normalized.contains("bootstrap_refresh_failed")
            || normalized.contains("discover_failed_using_cached_profile")
            || normalized.contains("missing_pairing_secret")
            || normalized.contains("missing_tls_csr")
            || normalized.contains("invite_token_required")
            || normalized.contains("invite_token_invalid")
            || normalized.contains("pairing_token_expired")
            || normalized.contains("pairing_token_invalid")
            || normalized.contains("pairing_secret_expired")
            || normalized.contains("bootstrap_token_expired")
            || normalized.contains("bootstrap_token_invalid")
            || normalized.contains("client_certificate_expired") {
            return .pairingRepairRequired
        }
        if normalized.contains("grant_required") || normalized.contains("grant_pending") {
            return .grantRequired
        }
        if normalized.contains("local_network_permission_required")
            || normalized.contains("local_network_discovery_blocked")
            || normalized.contains("permission_denied")
            || normalized.contains("forbidden")
            || normalized.contains("denied_by_policy") {
            return .permissionDenied
        }
        if normalized.contains("hub_unreachable")
            || normalized.contains("connection_refused")
            || normalized.contains("tcp_timeout")
            || normalized.contains("grpc_unavailable")
            || normalized.contains("grpc_probe_failed")
            || normalized.contains("network_unreachable")
            || normalized.contains("source_ip_not_allowed")
            || normalized.contains("discovery_failed")
            || normalized.contains("bootstrap_failed")
            || normalized.contains("bootstrap_refresh_failed") {
            return .hubUnreachable
        }
        return nil
    }

    static func primaryAction(for issue: UITroubleshootIssue?, defaultPairSubtitle: String) -> UITroubleshootActionDescriptor {
        switch issue {
        case .pairingRepairRequired:
            return UITroubleshootActionDescriptor(
                id: "repair_pairing",
                title: "清理失效配对并重连",
                subtitle: "删除本地失效令牌、证书和旧配对档案后重新连接",
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
        case .multipleHubsAmbiguous:
            return UITroubleshootActionDescriptor(
                id: "resolve_hub_ambiguity",
                title: "固定目标 Hub 后继续连接",
                subtitle: "在连接 Hub 里明确选择一台 Hub，或手填 Internet Host / 端口后重连",
                systemImage: "pin.circle"
            )
        case .hubPortConflict:
            return UITroubleshootActionDescriptor(
                id: "repair_hub_port_conflict",
                title: "修复 Hub 端口冲突",
                subtitle: "先切换到空闲 gRPC / pairing 端口，或释放占用后再重连",
                systemImage: "exclamationmark.triangle"
            )
        case .modelNotReady:
            return UITroubleshootActionDescriptor(
                id: "open_model_route_readiness",
                title: "检查模型与路由就绪",
                subtitle: "先核对当前模型 ID、Hub 实际可用清单和提供方状态",
                systemImage: "cpu"
            )
        case .connectorScopeBlocked:
            return UITroubleshootActionDescriptor(
                id: "open_hub_recovery",
                title: "检查 Hub 排障",
                subtitle: "先看远端导出开关、拒绝原因和修复提示",
                systemImage: "lock.shield"
            )
        default:
            return UITroubleshootActionDescriptor(
                id: "pair_hub",
                title: "连接 Hub",
                subtitle: defaultPairSubtitle,
                systemImage: "link.badge.plus"
            )
        }
    }

    static func repairEntryTitle(for issue: UITroubleshootIssue?) -> String {
        switch issue {
        case .pairingRepairRequired:
            return "打开配对修复入口"
        case .multipleHubsAmbiguous:
            return "打开 Hub 选择入口"
        case .hubPortConflict:
            return "打开端口冲突修复入口"
        case .modelNotReady:
            return "打开模型就绪排障入口"
        case .connectorScopeBlocked:
            return "打开 Hub Recovery"
        default:
            return "查看授权与排障"
        }
    }

    static func normalizedFailureCode(_ rawCode: String) -> String {
        rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    static func isInviteTokenRequiredFailure(_ rawCode: String) -> Bool {
        normalizedFailureCode(rawCode).contains("invite_token_required")
    }

    static func isInviteTokenInvalidFailure(_ rawCode: String) -> Bool {
        let normalized = normalizedFailureCode(rawCode)
        return normalized.contains("invite_token_invalid")
            || normalized.contains("pairing_token_invalid")
            || normalized.contains("bootstrap_token_invalid")
            || normalized.contains("pairing_token_expired")
            || normalized.contains("bootstrap_token_expired")
    }

    static func isInviteTokenFailure(_ rawCode: String) -> Bool {
        isInviteTokenRequiredFailure(rawCode) || isInviteTokenInvalidFailure(rawCode)
    }

    static func repairEntryDetail(
        for issue: UITroubleshootIssue?,
        runtime: UIFailClosedRuntimeSnapshot,
        pairingContext: UITroubleshootPairingContext? = nil
    ) -> String {
        switch issue {
        case .pairingRepairRequired:
            if pairingContext?.readiness == .remoteBlocked {
                return "XT 清除失效配对并重新载入当前邀请 -> Hub 删除旧设备并轮换令牌 / 证书 -> 重新批准 -> 异网重连自检"
            }
            if pairingContext?.formalRemoteVerificationPending == true {
                return "XT 保留当前同网配对 -> Hub 核对稳定异网入口与设备条目 -> 仅在明确身份错误时再清配对 -> 补跑正式异网验证"
            }
            return "XT 重新载入 Hub 邀请 / 清本地配对 -> Hub 轮换邀请令牌并删旧设备 -> 重新批准 -> 重连自检"
        case .multipleHubsAmbiguous:
            return "XT 固定目标 Hub / 手填 Internet Host -> Hub 核对局域网广播与端口 -> 重连自检"
        case .hubPortConflict:
            return "Hub 换到空闲端口或释放占用 -> XT 同步新的配对 / gRPC 端口 -> 重连自检"
        case .modelNotReady:
            return "XT 核对当前模型和实际路由记录 -> REL Flow Hub 检查模型清单和提供方状态 -> XT 诊断与核对重跑"
        case .connectorScopeBlocked:
            return "XT 诊断与核对记下实际路由记录 / 审计编号 / 拒绝原因 -> Hub 排障查看远端导出开关 -> 按安全边界或预算入口修复"
        case .hubUnreachable:
            if pairingContext?.readiness == .remoteBlocked {
                return "不要反复重试旧入口 -> XT 刷新邀请 / 证书 -> Hub 修 pairing/device trust -> 再做异网重连自检"
            }
            if pairingContext?.remoteShadowFailed == true {
                return "XT 保留现有配对 -> Hub 检查服务监听 / 防火墙 / NAT / relay -> 重跑正式异网验证"
            }
            if pairingContext?.proofShowsRemoteReady == true {
                return "XT 保留已验证配对 -> Hub 检查当前服务 / 转发回退 -> 重跑异网自检"
            }
            if pairingContext?.formalRemoteVerificationPending == true {
                return "XT 核对 stable host / 端口并保留当前配对 -> Hub 保持在线并检查 relay / forwarding -> 补跑正式异网验证"
            }
            return "XT 核对主机和端口 -> Hub 核对对外监听与局域网/公网可达性 -> 重连自检"
        default:
            if !runtime.nextDirectedAction.isEmpty {
                return "系统建议先做：\(runtime.nextDirectedAction)"
            }
            if let issue {
                return "\(issue.title)；\(runtime.nextRepairAction ?? "先打开排障入口")"
            }
            if let denyCode = runtime.launchDenyCodes.first(where: { !$0.isEmpty }) {
                return "当前拒绝原因：\(denyCode)"
            }
            return "授权、权限、模型未就绪或 Hub 连不上，都从这里进入排查"
        }
    }
}

struct TroubleshootPanel: View {
    let title: String
    let issues: [UITroubleshootIssue]
    let paidAccessSnapshot: HubRemotePaidAccessSnapshot?
    let internetHost: String?
    let pairingContext: UITroubleshootPairingContext?

    init(
        title: String = "三步排障",
        issues: [UITroubleshootIssue] = UITroubleshootIssue.allCases,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        internetHost: String? = nil,
        pairingContext: UITroubleshootPairingContext? = nil
    ) {
        self.title = title
        self.issues = issues
        self.paidAccessSnapshot = paidAccessSnapshot
        self.internetHost = internetHost
        self.pairingContext = pairingContext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ForEach(
                UITroubleshootKnowledgeBase.guides(
                    for: issues,
                    paidAccessSnapshot: paidAccessSnapshot,
                    internetHost: internetHost,
                    pairingContext: pairingContext
                )
            ) { guide in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(guide.title, systemImage: iconName(for: guide.issue))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(guide.maxFixSteps) 步")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Text(guide.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(guide.steps) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(step.index).")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.instruction)
                                    .font(.caption)
                                Text(step.destination.label)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func iconName(for issue: UITroubleshootIssue) -> String {
        switch issue {
        case .grantRequired:
            return "checkmark.shield"
        case .permissionDenied:
            return "hand.raised"
        case .modelNotReady:
            return "cpu"
        case .connectorScopeBlocked:
            return "lock.shield"
        case .paidModelAccessBlocked:
            return "lock.desktopcomputer"
        case .pairingRepairRequired:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .multipleHubsAmbiguous:
            return "pin.circle"
        case .hubPortConflict:
            return "exclamationmark.triangle"
        case .hubUnreachable:
            return "bolt.horizontal.circle"
        }
    }
}
