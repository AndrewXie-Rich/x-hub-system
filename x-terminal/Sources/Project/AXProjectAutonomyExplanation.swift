import Foundation

enum AXProjectAutonomyExplanationStyle: Equatable, Sendable {
    case uiChinese
    case guardrailEnglish
}

enum AXProjectAutonomyClampKind: String, Equatable, Sendable {
    case killSwitch = "hub_override=kill_switch"
    case ttlExpired = "autonomy_ttl_expired"
    case clampManual = "hub_override=clamp_manual"
    case clampGuided = "hub_override=clamp_guided"
}

struct AXProjectAutonomyClampExplanation: Equatable, Sendable {
    var kind: AXProjectAutonomyClampKind
    var policyReason: String
    var summary: String
    var nextStep: String
}

func xtRuntimeSurfaceExplanation(
    mode: AXProjectAutonomyMode,
    style: AXProjectAutonomyExplanationStyle
) -> String {
    switch style {
    case .uiChinese:
        switch mode {
        case .manual:
            return "当前生效的是最保守 runtime surface：device tools、browser runtime、connector actions 和 extensions 全部关闭。"
        case .guided:
            return "当前生效的是 Guided runtime surface：只保留 browser runtime；device tools、connector side effect 和 extensions 继续被拦下。"
        case .trustedOpenClawMode:
            return "当前生效的是 Full runtime surface：会按当前 capability、binding 与 grant 条件放行，但仍继续受 trusted automation、tool policy、Hub memory、runtime surface TTL 和 kill-switch 共同约束。"
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

func xtAutonomyClampExplanation(
    policyReason: String,
    style: AXProjectAutonomyExplanationStyle
) -> AXProjectAutonomyClampExplanation? {
    guard let kind = xtAutonomyClampKind(policyReason: policyReason) else {
        return nil
    }
    return xtAutonomyClampExplanation(
        kind: kind,
        style: style,
        sourceLabel: nil
    )
}

func xtAutonomyClampExplanation(
    effective: AXProjectAutonomyEffectivePolicy,
    style: AXProjectAutonomyExplanationStyle
) -> AXProjectAutonomyClampExplanation? {
    let kind: AXProjectAutonomyClampKind
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

    return xtAutonomyClampExplanation(
        kind: kind,
        style: style,
        sourceLabel: xtAutonomyClampSourceLabel(for: kind, effective: effective, style: style)
    )
}

private func xtAutonomyClampKind(policyReason: String) -> AXProjectAutonomyClampKind? {
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

private func xtAutonomyClampSourceLabel(
    for kind: AXProjectAutonomyClampKind,
    effective: AXProjectAutonomyEffectivePolicy,
    style: AXProjectAutonomyExplanationStyle
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

private func xtAutonomyClampExplanation(
    kind: AXProjectAutonomyClampKind,
    style: AXProjectAutonomyExplanationStyle,
    sourceLabel: String?
) -> AXProjectAutonomyClampExplanation {
    switch style {
    case .uiChinese:
        return xtChineseAutonomyClampExplanation(kind: kind, sourceLabel: sourceLabel)
    case .guardrailEnglish:
        return xtEnglishAutonomyClampExplanation(kind: kind)
    }
}

private func xtChineseAutonomyClampExplanation(
    kind: AXProjectAutonomyClampKind,
    sourceLabel: String?
) -> AXProjectAutonomyClampExplanation {
    let sourcePrefix = sourceLabel ?? ""
    switch kind {
    case .killSwitch:
        return AXProjectAutonomyClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "\(sourcePrefix)kill-switch 已生效：当前 runtime surface 已被压到最保守状态，device/browser/connector/extension 四类执行面全部被系统拦下。",
            nextStep: "清除 kill-switch 后再重试高风险动作。"
        )
    case .ttlExpired:
        return AXProjectAutonomyClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "当前 runtime surface TTL 已过期，项目执行面已自动回收到最保守 surface；如需继续放开，需要重新显式授权。",
            nextStep: "重新刷新自治窗口或重新授权后再继续。"
        )
    case .clampManual:
        return AXProjectAutonomyClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "当前 \(sourcePrefix)clamp_manual 已把 runtime surface 压回最保守 surface。项目里的治理档位仍会保留，但实际执行面不会放行。",
            nextStep: "清除 clamp_manual 后再重试相关动作。"
        )
    case .clampGuided:
        return AXProjectAutonomyClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "当前 \(sourcePrefix)clamp_guided 已把 runtime surface 压回 Guided surface，只保留 browser runtime 这条受控执行面。",
            nextStep: "恢复 Full runtime surface 或清除 clamp_guided 后再重试更高风险动作。"
        )
    }
}

private func xtEnglishAutonomyClampExplanation(
    kind: AXProjectAutonomyClampKind
) -> AXProjectAutonomyClampExplanation {
    switch kind {
    case .killSwitch:
        return AXProjectAutonomyClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "Project governance has engaged the kill switch for this runtime surface.",
            nextStep: "Clear the kill switch before retrying this action."
        )
    case .ttlExpired:
        return AXProjectAutonomyClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "The trusted autonomy window expired, so higher-risk actions are paused.",
            nextStep: "Refresh the autonomy window before retrying."
        )
    case .clampManual:
        return AXProjectAutonomyClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "Project governance has clamped this project to the most conservative runtime surface.",
            nextStep: "Clear the clamp before retrying this action."
        )
    case .clampGuided:
        return AXProjectAutonomyClampExplanation(
            kind: kind,
            policyReason: kind.rawValue,
            summary: "Project governance has clamped this project to the guided runtime surface.",
            nextStep: "Restore the full runtime surface before retrying higher-risk actions."
        )
    }
}
