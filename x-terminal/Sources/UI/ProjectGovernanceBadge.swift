import SwiftUI

struct ProjectGovernancePresentation {
    var executionTier: AXProjectExecutionTier
    var effectiveExecutionTier: AXProjectExecutionTier?
    var supervisorInterventionTier: AXProjectSupervisorInterventionTier
    var recommendedSupervisorInterventionTier: AXProjectSupervisorInterventionTier?
    var effectiveSupervisorInterventionTier: AXProjectSupervisorInterventionTier?
    var recommendedWorkOrderDepth: AXProjectSupervisorWorkOrderDepth?
    var effectiveWorkOrderDepth: AXProjectSupervisorWorkOrderDepth?
    var projectAIStrengthBand: AXProjectAIStrengthBand?
    var projectAIStrengthConfidence: Double?
    var projectAIStrengthReasons: [String]
    var supervisorAdaptationMode: AXProjectSupervisorAdaptationMode?
    var adaptationSummaryOverridesWarning: Bool
    var reviewPolicyMode: AXProjectReviewPolicyMode
    var progressHeartbeatSeconds: Int
    var reviewPulseSeconds: Int
    var brainstormReviewSeconds: Int
    var eventDrivenReviewEnabled: Bool
    var eventReviewTriggerLabels: [String]
    var projectMemoryCeiling: XTMemoryServingProfile
    var supervisorReviewMemoryCeiling: XTMemoryServingProfile
    var capabilityLabels: [String]
    var invalidMessages: [String]
    var warningMessages: [String]
    var compatSource: String
    var statusSummary: String
    var clampSummary: String
    var adaptationSummary: String
    var guidanceSummary: String
    var guidanceAckSummary: String
    var followUpRhythmSummary: String?

    init(resolved: AXProjectResolvedGovernanceState) {
        executionTier = resolved.configuredBundle.executionTier
        effectiveExecutionTier = resolved.effectiveBundle.executionTier == resolved.configuredBundle.executionTier
            ? nil
            : resolved.effectiveBundle.executionTier
        supervisorInterventionTier = resolved.configuredBundle.supervisorInterventionTier
        recommendedSupervisorInterventionTier = resolved.supervisorAdaptation.recommendedSupervisorTier == resolved.configuredBundle.supervisorInterventionTier
            ? nil
            : resolved.supervisorAdaptation.recommendedSupervisorTier
        effectiveSupervisorInterventionTier = resolved.effectiveBundle.supervisorInterventionTier == resolved.configuredBundle.supervisorInterventionTier
            ? nil
            : resolved.effectiveBundle.supervisorInterventionTier
        recommendedWorkOrderDepth = resolved.supervisorAdaptation.recommendedWorkOrderDepth
        effectiveWorkOrderDepth = resolved.supervisorAdaptation.effectiveWorkOrderDepth
        projectAIStrengthBand = resolved.supervisorAdaptation.projectAIStrengthProfile?.strengthBand
        projectAIStrengthConfidence = resolved.supervisorAdaptation.projectAIStrengthProfile?.confidence
        projectAIStrengthReasons = resolved.supervisorAdaptation.projectAIStrengthProfile?.reasons ?? []
        supervisorAdaptationMode = resolved.supervisorAdaptation.adaptationPolicy.adaptationMode
        adaptationSummaryOverridesWarning =
            (resolved.supervisorAdaptation.projectAIStrengthProfile?.recommendedSupervisorFloor ?? .s0SilentAudit) >
            resolved.supervisorAdaptation.configuredSupervisorTier
        reviewPolicyMode = resolved.effectiveBundle.reviewPolicyMode
        progressHeartbeatSeconds = resolved.effectiveBundle.schedule.progressHeartbeatSeconds
        reviewPulseSeconds = resolved.effectiveBundle.schedule.reviewPulseSeconds
        brainstormReviewSeconds = resolved.effectiveBundle.schedule.brainstormReviewSeconds
        eventDrivenReviewEnabled = resolved.effectiveBundle.schedule.eventDrivenReviewEnabled
        eventReviewTriggerLabels = resolved.effectiveBundle.schedule.eventReviewTriggers.map(\.displayName)
        projectMemoryCeiling = resolved.projectMemoryCeiling
        supervisorReviewMemoryCeiling = resolved.supervisorReviewMemoryCeiling
        capabilityLabels = resolved.capabilityBundle.allowedCapabilityLabels
        invalidMessages = ProjectGovernancePresentation.messages(
            executionTier: resolved.configuredBundle.executionTier,
            validation: resolved.validation,
            kind: .invalid
        )
        warningMessages = ProjectGovernancePresentation.messages(
            executionTier: resolved.configuredBundle.executionTier,
            validation: resolved.validation,
            kind: .warning
        )
        compatSource = resolved.compatSource.rawValue
        statusSummary = ProjectGovernancePresentation.statusSummary(resolved)
        clampSummary = ProjectGovernancePresentation.clampSummary(resolved)
        adaptationSummary = ProjectGovernancePresentation.adaptationSummary(resolved)
        guidanceSummary = ProjectGovernancePresentation.guidanceSummary(
            resolved.effectiveBundle.supervisorInterventionTier.defaultInterventionMode
        )
        guidanceAckSummary = resolved.effectiveBundle.supervisorInterventionTier.defaultAckRequired
            ? "需要确认"
            : "可选确认"
        followUpRhythmSummary = SupervisorReviewPolicyEngine.eventFollowUpCadenceLabel(governance: resolved)
    }

    init(
        executionTier: AXProjectExecutionTier,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier,
        reviewPolicyMode: AXProjectReviewPolicyMode,
        progressHeartbeatSeconds: Int,
        reviewPulseSeconds: Int,
        brainstormReviewSeconds: Int,
        eventDrivenReviewEnabled: Bool,
        compatSource: String = "ui_draft"
    ) {
        let minimumSafe = executionTier.minimumSafeSupervisorTier
        let recommended = executionTier.defaultSupervisorInterventionTier
        self.executionTier = executionTier
        effectiveExecutionTier = nil
        self.supervisorInterventionTier = supervisorInterventionTier
        recommendedSupervisorInterventionTier = nil
        effectiveSupervisorInterventionTier = nil
        recommendedWorkOrderDepth = supervisorInterventionTier.defaultWorkOrderDepth
        effectiveWorkOrderDepth = supervisorInterventionTier.defaultWorkOrderDepth
        projectAIStrengthBand = nil
        projectAIStrengthConfidence = nil
        projectAIStrengthReasons = []
        supervisorAdaptationMode = nil
        adaptationSummaryOverridesWarning = false
        self.reviewPolicyMode = reviewPolicyMode
        self.progressHeartbeatSeconds = max(60, progressHeartbeatSeconds)
        self.reviewPulseSeconds = max(0, reviewPulseSeconds)
        self.brainstormReviewSeconds = max(0, brainstormReviewSeconds)
        self.eventDrivenReviewEnabled = eventDrivenReviewEnabled
        eventReviewTriggerLabels = eventDrivenReviewEnabled
            ? executionTier.defaultEventReviewTriggers.map(\.displayName)
            : []
        projectMemoryCeiling = executionTier.defaultProjectMemoryCeiling
        supervisorReviewMemoryCeiling = supervisorInterventionTier.defaultReviewMemoryCeiling
        capabilityLabels = executionTier.baseCapabilityBundle.allowedCapabilityLabels
        invalidMessages = supervisorInterventionTier < minimumSafe
            ? ["\(executionTier.shortToken) 至少需要 \(minimumSafe.shortToken) 才能安全运行。"]
            : []
        warningMessages = supervisorInterventionTier >= minimumSafe && supervisorInterventionTier < recommended
            ? ["\(executionTier.shortToken) 推荐搭配 \(recommended.shortToken) 及以上，当前配置更容易拉长 drift / rescue 的发现窗口。"]
            : []
        self.compatSource = compatSource
        statusSummary = invalidMessages.isEmpty ? "治理组合已接受，后续仍会受 runtime clamp 和 TTL 影响。" : "当前组合无效，创建后应调整到最低安全监督档。"
        clampSummary = "未连接 runtime clamp；这里只展示配置意图。"
        adaptationSummary = "当前还没有 Project AI 强弱自适应评估。"
        guidanceSummary = ProjectGovernancePresentation.guidanceSummary(
            supervisorInterventionTier.defaultInterventionMode
        )
        guidanceAckSummary = supervisorInterventionTier.defaultAckRequired
            ? "需要确认"
            : "可选确认"
        followUpRhythmSummary = nil
    }

    var effectiveExecutionLabel: String {
        effectiveExecutionTier.map { "\($0.shortToken) \($0.shortLabel)" } ?? "\(executionTier.shortToken) \(executionTier.shortLabel)"
    }

    var effectiveSupervisorLabel: String {
        effectiveSupervisorInterventionTier.map { "\($0.shortToken) \($0.shortLabel)" } ?? "\(supervisorInterventionTier.shortToken) \(supervisorInterventionTier.shortLabel)"
    }

    var reviewCadenceText: String {
        "heartbeat \(governanceDurationLabel(progressHeartbeatSeconds)) · pulse \(governanceDurationLabel(reviewPulseSeconds)) · brainstorm \(governanceDurationLabel(brainstormReviewSeconds))"
    }

    var compatSourceLabel: String {
        switch compatSource {
        case AXProjectGovernanceCompatSource.explicitDualDial.rawValue:
            return "A/S 档位显式配置"
        case AXProjectGovernanceCompatSource.legacyAutonomyLevel.rawValue:
            return "兼容旧项目卡片档位"
        case AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue:
            return "兼容旧执行面预设"
        case AXProjectGovernanceCompatSource.defaultConservative.rawValue:
            return "默认保守基线"
        case "ui_draft":
            return "界面草稿预览"
        case "multi_project_detail":
            return "多项目详情卡片"
        default:
            return compatSource
        }
    }

    var compatSourceDetail: String? {
        switch compatSource {
        case AXProjectGovernanceCompatSource.explicitDualDial.rawValue:
            return "当前项目已明确保存 A-tier / S-tier / Review Policy，后续以这组治理拨盘为准。"
        case AXProjectGovernanceCompatSource.legacyAutonomyLevel.rawValue:
            return "当前治理仍在兼容旧 project card 档位影子值。建议在项目设置里保存一次 A-tier / S-tier，让运行时不再依赖旧字段。"
        case AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue:
            return "当前治理仍由旧执行面预设映射而来。建议补一次显式 A-tier / S-tier 配置，避免后续继续走兼容桥。"
        case AXProjectGovernanceCompatSource.defaultConservative.rawValue:
            return "当前项目还没有显式治理配置，系统先按保守基线运行；需要自治时再明确调高 A-tier / S-tier。"
        default:
            return nil
        }
    }

    var governanceSourceHint: String? {
        switch compatSource {
        case AXProjectGovernanceCompatSource.legacyAutonomyLevel.rawValue,
             AXProjectGovernanceCompatSource.legacyAutonomyMode.rawValue,
             AXProjectGovernanceCompatSource.defaultConservative.rawValue:
            return compatSourceDetail
        default:
            return nil
        }
    }

    var homeStatusMessage: String {
        if let invalid = invalidMessages.first {
            return invalid
        }
        let normalizedAdaptation = adaptationSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if adaptationSummaryOverridesWarning && normalizedAdaptation != "当前还没有 Project AI 强弱自适应评估。" {
            return normalizedAdaptation
        }
        if let warning = warningMessages.first {
            return warning
        }
        if normalizedAdaptation != "当前还没有 Project AI 强弱自适应评估。" {
            return normalizedAdaptation
        }
        if let sourceHint = governanceSourceHint {
            return sourceHint
        }
        return statusSummary
    }

    var homeClampMessage: String? {
        let normalized = clampSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "当前没有额外 clamp；但仍继续受 Hub 授权、runtime surface TTL、readiness 与 kill-switch 约束。":
            return nil
        case "未连接 runtime clamp；这里只展示配置意图。":
            return nil
        default:
            return normalized
        }
    }

    var compactCalloutMessage: String? {
        if let invalid = invalidMessages.first {
            return invalid
        }
        if let warning = warningMessages.first {
            return warning
        }
        if let sourceHint = governanceSourceHint {
            return sourceHint
        }
        return homeClampMessage
    }

    var compactCalloutTone: ProjectGovernanceCalloutTone {
        if !invalidMessages.isEmpty {
            return .invalid
        }
        if !warningMessages.isEmpty {
            return .warning
        }
        if governanceSourceHint != nil {
            return .info
        }
        return homeClampMessage == nil ? .neutral : .info
    }

    private enum MessageKind {
        case invalid
        case warning
    }

    private static func messages(
        executionTier: AXProjectExecutionTier,
        validation: AXProjectGovernanceValidation,
        kind: MessageKind
    ) -> [String] {
        switch kind {
        case .invalid:
            guard !validation.invalidReasons.isEmpty else { return [] }
            return ["\(executionTier.shortToken) 至少需要 \(validation.minimumSafeSupervisorTier.shortToken) 才能安全运行；当前组合已进入 fail-closed 风险区。"]
        case .warning:
            guard !validation.warningReasons.isEmpty else { return [] }
            return ["\(executionTier.shortToken) 推荐搭配 \(validation.recommendedSupervisorTier.shortToken) 及以上，当前组合允许但偏保守。"]
        }
    }

    private static func statusSummary(_ resolved: AXProjectResolvedGovernanceState) -> String {
        if resolved.validation.shouldFailClosed {
            return "当前治理组合无效，生效档位已收束到 \(resolved.effectiveBundle.executionTier.shortToken) / \(resolved.effectiveBundle.supervisorInterventionTier.shortToken)。"
        }
        if resolved.effectiveBundle.executionTier != resolved.configuredBundle.executionTier
            || resolved.effectiveBundle.supervisorInterventionTier != resolved.configuredBundle.supervisorInterventionTier {
            return "当前生效治理已被运行时收束；请同时看预设值和生效值。"
        }
        return "当前预设值和生效值一致。"
    }

    private static func adaptationSummary(_ resolved: AXProjectResolvedGovernanceState) -> String {
        let adaptation = resolved.supervisorAdaptation
        guard let strength = adaptation.projectAIStrengthProfile else {
            return "当前还没有 Project AI 强弱自适应评估。"
        }

        let confidence = Int((strength.confidence * 100).rounded())
        let base = "Project AI 评估=\(strength.strengthBand.rawValue)（置信度 \(confidence)%）"
        if strength.strengthBand == .unknown {
            if adaptation.recommendedSupervisorTier > adaptation.configuredSupervisorTier {
                return "\(base)；当前证据仍不足，建议至少提升到 \(adaptation.recommendedSupervisorTier.shortToken)。"
            }
            return "\(base)；当前证据仍不足，系统先沿现有治理运行并继续观察。"
        }
        if adaptation.effectiveSupervisorTier > adaptation.configuredSupervisorTier {
            return "\(base)；Supervisor 已从 \(adaptation.configuredSupervisorTier.shortToken) 抬到 \(adaptation.effectiveSupervisorTier.shortToken)。"
        }
        if adaptation.recommendedSupervisorTier > adaptation.configuredSupervisorTier {
            return "\(base)；当前建议至少提升到 \(adaptation.recommendedSupervisorTier.shortToken)，但尚未自动生效。"
        }
        return "\(base)；当前监督档位无需额外抬高。"
    }

    private static func clampSummary(_ resolved: AXProjectResolvedGovernanceState) -> String {
        let autonomy = resolved.effectiveAutonomy
        if let clamp = xtAutonomyClampExplanation(
            effective: autonomy,
            style: .uiChinese
        ) {
            return clamp.summary
        }
        if resolved.configuredBundle.executionTier == .a4OpenClaw
            && (!resolved.trustedAutomationStatus.trustedAutomationReady || !resolved.trustedAutomationStatus.permissionOwnerReady) {
            return "A4 Full Surface 已配置，但 device/browser 仍受 trusted automation readiness 和 permission owner gate 约束。"
        }
        return "当前没有额外 clamp；但仍继续受 Hub 授权、runtime surface TTL、readiness 与 kill-switch 约束。"
    }

    private static func guidanceSummary(_ mode: SupervisorGuidanceInterventionMode) -> String {
        switch mode {
        case .observeOnly:
            return "仅观察，默认不注入 guidance"
        case .suggestNextSafePoint:
            return "下一个 safe point 给建议"
        case .replanNextSafePoint:
            return "下一个 safe point 要求重排"
        case .stopImmediately:
            return "触发介入后立即停止"
        }
    }
}

enum ProjectGovernanceCalloutTone {
    case neutral
    case info
    case warning
    case invalid
}

struct ProjectGovernanceCompactSummaryView: View {
    let presentation: ProjectGovernancePresentation
    var showCallout: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProjectGovernanceBadge(presentation: presentation, compact: true)

            if showCallout, let callout = presentation.compactCalloutMessage {
                Text(callout)
                    .font(.caption2)
                    .foregroundStyle(calloutColor(presentation.compactCalloutTone))
                    .lineLimit(2)
            }

            if let followUpRhythmSummary = presentation.followUpRhythmSummary,
               !followUpRhythmSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("自动跟进：\(followUpRhythmSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func calloutColor(_ tone: ProjectGovernanceCalloutTone) -> Color {
        switch tone {
        case .invalid:
            return .red
        case .warning:
            return .orange
        case .info:
            return .secondary
        case .neutral:
            return .secondary
        }
    }
}

struct ProjectGovernanceBadge: View {
    let presentation: ProjectGovernancePresentation
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            governanceChip(
                presentation.executionTier.shortToken,
                label: presentation.executionTier.shortLabel,
                color: .blue
            )
            governanceChip(
                presentation.supervisorInterventionTier.shortToken,
                label: presentation.supervisorInterventionTier.shortLabel,
                color: .orange
            )
            governanceChip(
                presentation.reviewPolicyMode.shortLabel,
                label: presentation.reviewCadenceText,
                color: .green
            )
            if !presentation.invalidMessages.isEmpty {
                governanceChip("无效", label: "fail-closed", color: .red)
            } else if !presentation.warningMessages.isEmpty {
                governanceChip("注意", label: "低于推荐", color: .yellow)
            }
        }
    }

    private func governanceChip(_ title: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            Text(title)
                .font(.system(compact ? .caption : .caption, design: .monospaced).weight(.semibold))
            Text(label)
                .font(.system(compact ? .caption2 : .caption2, design: .rounded))
                .lineLimit(compact ? 1 : 2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 7)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 10)
                .fill(color.opacity(0.10))
        )
    }
}

struct ProjectGovernanceInspector: View {
    let presentation: ProjectGovernancePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !presentation.invalidMessages.isEmpty {
                governanceMessageBlock(
                    title: "无效组合",
                    messages: presentation.invalidMessages,
                    color: .red
                )
            } else if !presentation.warningMessages.isEmpty {
                governanceMessageBlock(
                    title: "风险提示",
                    messages: presentation.warningMessages,
                    color: .orange
                )
            }

            governanceRow("执行档位") {
                Text("预设：\(presentation.executionTier.shortToken) \(presentation.executionTier.shortLabel)")
                if let effectiveExecutionTier = presentation.effectiveExecutionTier {
                    Text("生效：\(effectiveExecutionTier.shortToken) \(effectiveExecutionTier.shortLabel)")
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("Supervisor 档位") {
                Text("预设：\(presentation.supervisorInterventionTier.shortToken) \(presentation.supervisorInterventionTier.shortLabel)")
                if let recommendedSupervisorTier = presentation.recommendedSupervisorInterventionTier {
                    Text("建议：\(recommendedSupervisorTier.shortToken) \(recommendedSupervisorTier.shortLabel)")
                        .foregroundStyle(.secondary)
                }
                if let effectiveSupervisorTier = presentation.effectiveSupervisorInterventionTier {
                    Text("生效：\(effectiveSupervisorTier.shortToken) \(effectiveSupervisorTier.shortLabel)")
                        .foregroundStyle(.secondary)
                }
            }

            if let strengthBand = presentation.projectAIStrengthBand {
                governanceRow("Project AI 强弱") {
                    Text(
                        "\(strengthBand.displayName)\(presentation.projectAIStrengthConfidence.map { " · 置信度 \(Int(($0 * 100).rounded()))%" } ?? "")"
                    )
                    if let mode = presentation.supervisorAdaptationMode {
                        Text("适配模式：\(mode.displayName)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !presentation.projectAIStrengthReasons.isEmpty {
                governanceRow("评估依据") {
                    Text(presentation.projectAIStrengthReasons.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let recommendedWorkOrderDepth = presentation.recommendedWorkOrderDepth,
               let effectiveWorkOrderDepth = presentation.effectiveWorkOrderDepth {
                governanceRow("派工深度") {
                    Text("建议：\(recommendedWorkOrderDepth.displayName)")
                    Text("生效：\(effectiveWorkOrderDepth.displayName)")
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("Review 策略") {
                Text(presentation.reviewPolicyMode.displayName)
                Text(presentation.reviewCadenceText)
                    .foregroundStyle(.secondary)
            }

            if let followUpRhythmSummary = presentation.followUpRhythmSummary,
               !followUpRhythmSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                governanceRow("自动跟进节奏") {
                    Text(followUpRhythmSummary)
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("Guidance 注入") {
                Text(presentation.guidanceSummary)
                Text(presentation.guidanceAckSummary)
                    .foregroundStyle(.secondary)
            }

            governanceRow("事件驱动 Review") {
                Text(presentation.eventDrivenReviewEnabled ? "已开启" : "已关闭")
                if !presentation.eventReviewTriggerLabels.isEmpty {
                    Text(presentation.eventReviewTriggerLabels.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("上下文供给") {
                Text("coder：\(presentation.projectMemoryCeiling.rawValue)")
                Text("supervisor：\(presentation.supervisorReviewMemoryCeiling.rawValue)")
                    .foregroundStyle(.secondary)
            }

            governanceRow("能力包") {
                Text(presentation.capabilityLabels.isEmpty ? "(none)" : presentation.capabilityLabels.joined(separator: ", "))
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            governanceRow("当前状态") {
                Text(presentation.statusSummary)
                    .foregroundStyle(.secondary)
            }

            if !presentation.adaptationSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                governanceRow("自适应监督") {
                    Text(presentation.adaptationSummary)
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("Clamp / 收束") {
                Text(presentation.clampSummary)
                    .foregroundStyle(.secondary)
            }

            governanceRow("治理来源") {
                Text(presentation.compatSourceLabel)
                    .foregroundStyle(.secondary)
                if let detail = presentation.compatSourceDetail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func governanceRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .font(.subheadline)
        }
    }

    private func governanceMessageBlock(title: String, messages: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            ForEach(messages, id: \.self) { message in
                Text(message)
                    .font(.caption)
            }
        }
        .foregroundStyle(color)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.10))
        )
    }
}

func governanceDurationLabel(_ seconds: Int) -> String {
    guard seconds > 0 else { return "off" }
    if seconds % 3600 == 0 {
        return "\(seconds / 3600)h"
    }
    return "\(max(1, seconds / 60))m"
}

extension AXProjectExecutionTier {
    var shortToken: String {
        switch self {
        case .a0Observe:
            return "A0"
        case .a1Plan:
            return "A1"
        case .a2RepoAuto:
            return "A2"
        case .a3DeliverAuto:
            return "A3"
        case .a4OpenClaw:
            return "A4"
        }
    }

    var shortLabel: String {
        switch self {
        case .a0Observe:
            return "Observe"
        case .a1Plan:
            return "Plan"
        case .a2RepoAuto:
            return "Repo Auto"
        case .a3DeliverAuto:
            return "Deliver Auto"
        case .a4OpenClaw:
            return "Full Surface"
        }
    }
}

extension AXProjectSupervisorInterventionTier {
    var shortToken: String {
        switch self {
        case .s0SilentAudit:
            return "S0"
        case .s1MilestoneReview:
            return "S1"
        case .s2PeriodicReview:
            return "S2"
        case .s3StrategicCoach:
            return "S3"
        case .s4TightSupervision:
            return "S4"
        }
    }

    var shortLabel: String {
        switch self {
        case .s0SilentAudit:
            return "Silent Audit"
        case .s1MilestoneReview:
            return "Milestone Review"
        case .s2PeriodicReview:
            return "Periodic Review"
        case .s3StrategicCoach:
            return "Strategic Coach"
        case .s4TightSupervision:
            return "Tight Supervision"
        }
    }
}

extension AXProjectReviewPolicyMode {
    var shortLabel: String {
        switch self {
        case .off:
            return "Off"
        case .milestoneOnly:
            return "Milestone"
        case .periodic:
            return "Periodic"
        case .hybrid:
            return "Hybrid"
        case .aggressive:
            return "Aggressive"
        }
    }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .milestoneOnly:
            return "Milestone Only"
        case .periodic:
            return "Periodic"
        case .hybrid:
            return "Hybrid"
        case .aggressive:
            return "Aggressive"
        }
    }
}

extension AXProjectReviewTrigger {
    var displayName: String {
        switch self {
        case .periodicHeartbeat:
            return "periodic heartbeat"
        case .periodicPulse:
            return "periodic pulse"
        case .failureStreak:
            return "failure streak"
        case .noProgressWindow:
            return "no progress window"
        case .blockerDetected:
            return "blocker detected"
        case .planDrift:
            return "plan drift"
        case .preHighRiskAction:
            return "pre-high-risk"
        case .preDoneSummary:
            return "pre-done"
        case .manualRequest:
            return "manual request"
        case .userOverride:
            return "user override"
        }
    }
}

extension AXProjectAIStrengthBand {
    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .weak:
            return "Weak"
        case .developing:
            return "Developing"
        case .capable:
            return "Capable"
        case .strong:
            return "Strong"
        }
    }
}

extension AXProjectSupervisorAdaptationMode {
    var displayName: String {
        switch self {
        case .manualOnly:
            return "Manual Only"
        case .raiseOnly:
            return "Raise Only"
        case .bidirectional:
            return "Bidirectional"
        }
    }
}

extension AXProjectSupervisorWorkOrderDepth {
    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .brief:
            return "Brief"
        case .milestoneContract:
            return "Milestone Contract"
        case .executionReady:
            return "Execution Ready"
        case .stepLockedRescue:
            return "Step-Locked Rescue"
        }
    }
}

extension SupervisorGuidanceInterventionMode {
    var displayName: String {
        switch self {
        case .observeOnly:
            return "Observe Only"
        case .suggestNextSafePoint:
            return "Suggest At Safe Point"
        case .replanNextSafePoint:
            return "Replan At Safe Point"
        case .stopImmediately:
            return "Stop Immediately"
        }
    }
}
