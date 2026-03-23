import Foundation

enum AXProjectGovernanceExplanationStyle: Equatable, Sendable {
    case uiChinese
    case guardrailEnglish
}

typealias AXProjectAutonomyExplanationStyle = AXProjectGovernanceExplanationStyle

enum AXProjectGovernanceClampKind: String, Equatable, Sendable {
    case killSwitch = "hub_override=kill_switch"
    case ttlExpired = "autonomy_ttl_expired"
    case clampManual = "hub_override=clamp_manual"
    case clampGuided = "hub_override=clamp_guided"
}

typealias AXProjectAutonomyClampKind = AXProjectGovernanceClampKind

struct AXProjectGovernanceClampExplanation: Equatable, Sendable {
    var kind: AXProjectGovernanceClampKind
    var policyReason: String
    var summary: String
    var nextStep: String
}

typealias AXProjectAutonomyClampExplanation = AXProjectGovernanceClampExplanation

func xtProjectRuntimeSurfaceExplanation(
    mode: AXProjectRuntimeSurfaceMode,
    style: AXProjectGovernanceExplanationStyle
) -> String {
    switch style {
    case .uiChinese:
        switch mode {
        case .manual:
            return "当前生效的是最保守执行面：设备工具、浏览器运行时、连接器动作和扩展全部关闭。"
        case .guided:
            return "当前生效的是浏览器受控执行面：只保留浏览器运行时；设备工具、连接器副作用和扩展继续被拦下。"
        case .trustedOpenClawMode:
            return "当前生效的是完整执行面：会按当前能力包、绑定和授权条件放行，但仍继续受受治理自动化、工具策略、Hub 记忆、执行面 TTL 和紧急回收共同约束。"
        }
    case .guardrailEnglish:
        switch mode {
        case .manual:
            return "The project is on the most conservative runtime surface, so browser, device, connector, and extension actions stay blocked."
        case .guided:
            return "The project is on the guided runtime surface, so only browser runtime remains available while device-level actions stay blocked."
        case .trustedOpenClawMode:
            return "The project is on the full runtime surface, but higher-risk actions still remain subject to grants, bindings, TTL, and kill-switch controls."
        }
    }
}

@available(*, deprecated, message: "Use xtProjectRuntimeSurfaceExplanation(mode:style:)")
func xtRuntimeSurfaceExplanation(
    mode: AXProjectAutonomyMode,
    style: AXProjectAutonomyExplanationStyle
) -> String {
    xtProjectRuntimeSurfaceExplanation(mode: mode, style: style)
}

func xtProjectGovernanceClampExplanation(
    policyReason: String,
    style: AXProjectGovernanceExplanationStyle
) -> AXProjectGovernanceClampExplanation? {
    guard let kind = xtProjectGovernanceClampKind(policyReason: policyReason) else {
        return nil
    }
    return xtProjectGovernanceClampExplanation(
        kind: kind,
        style: style,
        sourceLabel: nil
    )
}

func xtProjectGovernanceClampExplanation(
    effective: AXProjectRuntimeSurfaceEffectivePolicy,
    style: AXProjectGovernanceExplanationStyle
) -> AXProjectGovernanceClampExplanation? {
    let kind: AXProjectGovernanceClampKind
    if effective.killSwitchEngaged {
        kind = .killSwitch
    } else if effective.expired {
        kind = .ttlExpired
    } else if effective.hubOverrideMode == .clampManual {
        kind = .clampManual
    } else if effective.hubOverrideMode == .clampGuided,
              effective.configuredMode == .trustedOpenClawMode,
              effective.effectiveMode == .guided {
        kind = .clampGuided
    } else {
        return nil
    }

    return xtProjectGovernanceClampExplanation(
        kind: kind,
        style: style,
        sourceLabel: xtProjectGovernanceClampSourceLabel(for: kind, effective: effective, style: style)
    )
}

@available(*, deprecated, message: "Use xtProjectGovernanceClampExplanation(policyReason:style:)")
func xtAutonomyClampExplanation(
    policyReason: String,
    style: AXProjectAutonomyExplanationStyle
) -> AXProjectAutonomyClampExplanation? {
    xtProjectGovernanceClampExplanation(
        policyReason: policyReason,
        style: style
    )
}

@available(*, deprecated, message: "Use xtProjectGovernanceClampExplanation(effective:style:)")
func xtAutonomyClampExplanation(
    effective: AXProjectAutonomyEffectivePolicy,
    style: AXProjectAutonomyExplanationStyle
) -> AXProjectAutonomyClampExplanation? {
    xtProjectGovernanceClampExplanation(
        effective: effective,
        style: style
    )
}

private func xtProjectGovernanceClampKind(policyReason: String) -> AXProjectGovernanceClampKind? {
    let normalized = policyReason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch true {
    case normalized.contains("kill_switch"):
        return .killSwitch
    case normalized.contains("ttl_expired"):
        return .ttlExpired
    case normalized.contains("clamp_manual"):
        return .clampManual
    case normalized.contains("clamp_guided"):
        return .clampGuided
    default:
        return nil
    }
}

private func xtProjectGovernanceClampSourceLabel(
    for kind: AXProjectGovernanceClampKind,
    effective: AXProjectRuntimeSurfaceEffectivePolicy,
    style: AXProjectGovernanceExplanationStyle
) -> String? {
    switch kind {
    case .killSwitch:
        if effective.remoteOverrideMode == .killSwitch {
            return style == .uiChinese ? "Hub " : "Hub "
        }
    case .clampManual:
        if effective.remoteOverrideMode == .clampManual {
            return style == .uiChinese ? "Hub " : "Hub "
        }
    case .clampGuided:
        if effective.remoteOverrideMode == .clampGuided {
            return style == .uiChinese ? "Hub " : "Hub "
        }
    case .ttlExpired:
        break
    }
    return nil
}

private func xtProjectGovernanceClampExplanation(
    kind: AXProjectGovernanceClampKind,
    style: AXProjectGovernanceExplanationStyle,
    sourceLabel: String?
) -> AXProjectGovernanceClampExplanation {
    switch style {
    case .uiChinese:
        return xtChineseProjectGovernanceClampExplanation(kind: kind, sourceLabel: sourceLabel)
    case .guardrailEnglish:
        return xtEnglishProjectGovernanceClampExplanation(kind: kind)
    }
}

private func xtChineseProjectGovernanceClampExplanation(
    kind: AXProjectGovernanceClampKind,
    sourceLabel: String?
) -> AXProjectGovernanceClampExplanation {
    let trimmedSourceLabel = sourceLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let sourcePrefix = trimmedSourceLabel.isEmpty ? "" : "\(trimmedSourceLabel) "
    switch kind {
    case .killSwitch:
        return AXProjectGovernanceClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "\(sourcePrefix)kill-switch 紧急回收已生效：当前执行面已被压到最保守状态，设备、浏览器、连接器和扩展四类执行面全部被系统拦下。",
            nextStep: "清除 kill-switch 后再重试高风险动作。"
        )
    case .ttlExpired:
        return AXProjectGovernanceClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "当前执行面 TTL 已过期，项目执行面已自动回收到最保守状态；如需继续放开，需要重新显式授权。",
            nextStep: "刷新执行窗口或重新授权后再继续。"
        )
    case .clampManual:
        return AXProjectGovernanceClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "\(sourcePrefix)已把执行面压回最保守状态。项目里的治理档位仍会保留，但实际动作不会放行。",
            nextStep: "解除这条收束后再重试相关动作。"
        )
    case .clampGuided:
        return AXProjectGovernanceClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "\(sourcePrefix)已把执行面收回到浏览器受控状态，只保留浏览器这条受控执行面。",
            nextStep: "恢复完整执行面或解除这条收束后，再重试更高风险动作。"
        )
    }
}

private func xtEnglishProjectGovernanceClampExplanation(
    kind: AXProjectGovernanceClampKind
) -> AXProjectGovernanceClampExplanation {
    switch kind {
    case .killSwitch:
        return AXProjectGovernanceClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "Project governance has engaged the kill switch for this runtime surface.",
            nextStep: "Clear the kill switch before retrying this action."
        )
    case .ttlExpired:
        return AXProjectGovernanceClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "The trusted runtime-surface window expired, so higher-risk actions are paused.",
            nextStep: "Refresh the runtime-surface window before retrying."
        )
    case .clampManual:
        return AXProjectGovernanceClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "Project governance has clamped this project to the most conservative runtime surface.",
            nextStep: "Clear the clamp before retrying this action."
        )
    case .clampGuided:
        return AXProjectGovernanceClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "Project governance has clamped this project to the guided runtime surface.",
            nextStep: "Restore the full runtime surface before retrying higher-risk actions."
        )
    }
}
