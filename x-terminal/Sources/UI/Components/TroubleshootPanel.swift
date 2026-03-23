import SwiftUI

enum UITroubleshootIssue: String, CaseIterable, Codable, Sendable {
    case grantRequired = "grant_required"
    case permissionDenied = "permission_denied"
    case paidModelAccessBlocked = "paid_model_access_blocked"
    case pairingRepairRequired = "pairing_repair_required"
    case hubUnreachable = "hub_unreachable"

    var title: String {
        switch self {
        case .grantRequired:
            return "Grant required"
        case .permissionDenied:
            return "Permission denied"
        case .paidModelAccessBlocked:
            return "Paid model access blocked"
        case .pairingRepairRequired:
            return "Pairing repair required"
        case .hubUnreachable:
            return "Hub unreachable"
        }
    }

    var summary: String {
        switch self {
        case .grantRequired:
            return "需要付费模型、联网或设备级高风险能力时，先确认当前模型入口，再到 Hub 授权、能力范围与配额入口修复。"
        case .permissionDenied:
            return "设备能力、系统权限或 Hub 安全边界拒绝时，不再只显示原始报错，而是直接指到对应修复面。"
        case .paidModelAccessBlocked:
            return "当设备级付费模型策略、白名单或预算把请求挡住时，诊断入口必须直接指向设备信任、模型与预算，而不是退回无上下文 permission denied。"
        case .pairingRepairRequired:
            return "当本地配对档案过期、token 失效或 mTLS 证书不再匹配时，系统必须明确要求清理失效配对并重配，而不是继续用旧档案反复 reconnect。"
        case .hubUnreachable:
            return "Hub 不可达时，优先检查配对参数、Hub 诊断状态，再回到首用向导重试。"
        }
    }
}

enum UITroubleshootDestination: String, Codable, Sendable {
    case xtPairHub = "xt_pair_hub"
    case xtChooseModel = "xt_choose_model"
    case xtDiagnostics = "xt_diagnostics"
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
            return "XT Settings → Pair Hub"
        case .xtChooseModel:
            return "XT Settings → AI 模型"
        case .xtDiagnostics:
            return "XT Settings → Diagnostics"
        case .hubPairing:
            return "Hub Settings → Pairing & Device Trust"
        case .hubModels:
            return "Hub Settings → Models & Paid Access"
        case .hubGrants:
            return "Hub Settings → Grants & Permissions"
        case .hubSecurity:
            return "Hub Settings → Security Boundary"
        case .hubDiagnostics:
            return "Hub Settings → Diagnostics & Recovery"
        case .systemPermissions:
            return "System Settings → Permissions"
        case .homeSupervisor:
            return "Home / Supervisor → Start First Task"
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

enum UITroubleshootKnowledgeBase {
    static func guides(for issues: [UITroubleshootIssue]) -> [UITroubleshootGuide] {
        issues.map(guide(for:))
    }

    static func guide(for issue: UITroubleshootIssue) -> UITroubleshootGuide {
        switch issue {
        case .grantRequired:
            return UITroubleshootGuide(
                issue: issue,
                summary: issue.summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "确认 XT 当前任务用的模型已经在首用路径里选定，避免把 grant 问题误判成模型缺失。", destination: .xtChooseModel),
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
                    UITroubleshootStep(index: 2, instruction: "若是系统权限问题，直接打开系统权限；若是 Hub 能力范围或安全边界问题，去 Hub 的 Grants & Permissions 或 Security Boundary 修复。", destination: .systemPermissions),
                    UITroubleshootStep(index: 3, instruction: "完成修复后到 XT Diagnostics 查看最新结果并重新触发一次请求。", destination: .xtDiagnostics)
                ]
            )
        case .paidModelAccessBlocked:
            return UITroubleshootGuide(
                issue: issue,
                summary: issue.summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先确认 XT 当前选中的 model_id 是否就是被拦截的 paid model，并记录 device_name / model_id / policy_mode。", destination: .xtChooseModel),
                    UITroubleshootStep(index: 2, instruction: "到 Hub 配对与设备信任页检查该设备是 new_profile 还是 legacy_grant，以及付费模型模式 / allowlist 是否允许当前请求。", destination: .hubPairing),
                    UITroubleshootStep(index: 3, instruction: "再到 Hub Models & Paid Access 查看 daily / single-request budget；修复后回 XT Diagnostics 重试。", destination: .hubModels)
                ]
            )
        case .pairingRepairRequired:
            return UITroubleshootGuide(
                issue: issue,
                summary: issue.summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "先回 XT Pair Hub 执行“清除配对后重连”，把本地失效 token / client cert / cached profile 一次清干净。", destination: .xtPairHub),
                    UITroubleshootStep(index: 2, instruction: "再到 Hub Settings -> Pairing & Device Trust -> 设备列表（允许清单），优先筛“过期”并删除旧设备条目，然后重新批准当前设备。", destination: .hubPairing),
                    UITroubleshootStep(index: 3, instruction: "重配完成后重新执行 one-click setup / reconnect smoke，确认 unauthenticated / certificate_required 不再出现。", destination: .hubDiagnostics)
                ]
            )
        case .hubUnreachable:
            return UITroubleshootGuide(
                issue: issue,
                summary: issue.summary,
                steps: [
                    UITroubleshootStep(index: 1, instruction: "回到 XT Pair Hub 确认 pairing port、gRPC port、internet host 与 axhubctl 路径。", destination: .xtPairHub),
                    UITroubleshootStep(index: 2, instruction: "在 Hub Diagnostics & Recovery 查看 launch status、日志与一键修复动作。", destination: .hubDiagnostics),
                    UITroubleshootStep(index: 3, instruction: "完成修复后重新执行 one-click setup / reconnect smoke。", destination: .hubPairing)
                ]
            )
        }
    }

    static func issue(forFailureCode rawCode: String) -> UITroubleshootIssue? {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !code.isEmpty else { return nil }
        if code.contains("device_paid_model_disabled") || code.contains("device_paid_model_not_allowed") || code.contains("device_daily_token_budget_exceeded") || code.contains("device_single_request_token_exceeded") || code.contains("legacy_grant_flow_required") {
            return .paidModelAccessBlocked
        }
        if code.contains("unauthenticated")
            || code.contains("mtls_client_certificate_required")
            || code.contains("pairing_health_failed")
            || code.contains("bootstrap_refresh_failed")
            || code.contains("discover_failed_using_cached_profile")
            || code.contains("missing_pairing_secret") {
            return .pairingRepairRequired
        }
        if code.contains("grant_required") || code.contains("grant_pending") {
            return .grantRequired
        }
        if code.contains("permission_denied") || code.contains("forbidden") || code.contains("denied_by_policy") {
            return .permissionDenied
        }
        if code.contains("hub_unreachable") || code.contains("connection_refused") || code.contains("discovery_failed") {
            return .hubUnreachable
        }
        return nil
    }
}

struct TroubleshootPanel: View {
    let title: String
    let issues: [UITroubleshootIssue]

    init(title: String = "Troubleshoot", issues: [UITroubleshootIssue] = UITroubleshootIssue.allCases) {
        self.title = title
        self.issues = issues
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ForEach(UITroubleshootKnowledgeBase.guides(for: issues)) { guide in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(guide.title, systemImage: iconName(for: guide.issue))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(guide.maxFixSteps) steps")
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
        case .paidModelAccessBlocked:
            return "lock.desktopcomputer"
        case .pairingRepairRequired:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .hubUnreachable:
            return "bolt.horizontal.circle"
        }
    }
}
