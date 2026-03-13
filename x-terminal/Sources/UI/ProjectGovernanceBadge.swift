import SwiftUI

struct ProjectGovernancePresentation {
    var executionTier: AXProjectExecutionTier
    var effectiveExecutionTier: AXProjectExecutionTier?
    var supervisorInterventionTier: AXProjectSupervisorInterventionTier
    var effectiveSupervisorInterventionTier: AXProjectSupervisorInterventionTier?
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
    var guidanceSummary: String
    var guidanceAckSummary: String

    init(resolved: AXProjectResolvedGovernanceState) {
        executionTier = resolved.configuredBundle.executionTier
        effectiveExecutionTier = resolved.effectiveBundle.executionTier == resolved.configuredBundle.executionTier
            ? nil
            : resolved.effectiveBundle.executionTier
        supervisorInterventionTier = resolved.configuredBundle.supervisorInterventionTier
        effectiveSupervisorInterventionTier = resolved.effectiveBundle.supervisorInterventionTier == resolved.configuredBundle.supervisorInterventionTier
            ? nil
            : resolved.effectiveBundle.supervisorInterventionTier
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
        guidanceSummary = ProjectGovernancePresentation.guidanceSummary(
            resolved.effectiveBundle.supervisorInterventionTier.defaultInterventionMode
        )
        guidanceAckSummary = resolved.effectiveBundle.supervisorInterventionTier.defaultAckRequired
            ? "guidance ack required"
            : "guidance ack optional"
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
        effectiveSupervisorInterventionTier = nil
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
        guidanceSummary = ProjectGovernancePresentation.guidanceSummary(
            supervisorInterventionTier.defaultInterventionMode
        )
        guidanceAckSummary = supervisorInterventionTier.defaultAckRequired
            ? "guidance ack required"
            : "guidance ack optional"
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
            return "当前 configured combo 无效，effective 已收束到 \(resolved.effectiveBundle.executionTier.shortToken) / \(resolved.effectiveBundle.supervisorInterventionTier.shortToken)。"
        }
        if resolved.effectiveBundle.executionTier != resolved.configuredBundle.executionTier
            || resolved.effectiveBundle.supervisorInterventionTier != resolved.configuredBundle.supervisorInterventionTier {
            return "effective governance 已被 runtime 收束；请同时看 configured 与 effective。"
        }
        return "configured 与 effective 当前一致。"
    }

    private static func clampSummary(_ resolved: AXProjectResolvedGovernanceState) -> String {
        let autonomy = resolved.effectiveAutonomy
        if autonomy.killSwitchEngaged {
            return "kill-switch 生效：所有高风险自治面 fail-closed。"
        }
        if autonomy.expired {
            return "autonomy TTL 已过期：surface preset 已被回收到 manual。"
        }
        if autonomy.hubOverrideMode != .none {
            return "当前存在 clamp：\(autonomy.hubOverrideMode.rawValue) -> effective surface \(autonomy.effectiveMode.rawValue)。"
        }
        if resolved.configuredBundle.executionTier == .a4OpenClaw
            && (!resolved.trustedAutomationStatus.trustedAutomationReady || !resolved.trustedAutomationStatus.permissionOwnerReady) {
            return "A4 已配置，但 device/browser 仍受 trusted automation readiness 和 permission owner gate 约束。"
        }
        return "当前没有额外 clamp；仍继续受 Hub grant / TTL / readiness / kill-switch 约束。"
    }

    private static func guidanceSummary(_ mode: SupervisorGuidanceInterventionMode) -> String {
        switch mode {
        case .observeOnly:
            return "observe only; no guidance injection by default"
        case .suggestNextSafePoint:
            return "suggest at next safe point"
        case .replanNextSafePoint:
            return "replan at next safe point"
        case .stopImmediately:
            return "stop immediately on intervention"
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
                governanceChip("Invalid", label: "fail-closed", color: .red)
            } else if !presentation.warningMessages.isEmpty {
                governanceChip("Watch", label: "below recommended", color: .yellow)
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

            governanceRow("Execution") {
                Text("\(presentation.executionTier.shortToken) \(presentation.executionTier.shortLabel)")
                if let effectiveExecutionTier = presentation.effectiveExecutionTier {
                    Text("effective \(effectiveExecutionTier.shortToken) \(effectiveExecutionTier.shortLabel)")
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("Supervisor") {
                Text("\(presentation.supervisorInterventionTier.shortToken) \(presentation.supervisorInterventionTier.shortLabel)")
                if let effectiveSupervisorTier = presentation.effectiveSupervisorInterventionTier {
                    Text("effective \(effectiveSupervisorTier.shortToken) \(effectiveSupervisorTier.shortLabel)")
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("Review Policy") {
                Text(presentation.reviewPolicyMode.displayName)
                Text(presentation.reviewCadenceText)
                    .foregroundStyle(.secondary)
            }

            governanceRow("Guidance") {
                Text(presentation.guidanceSummary)
                Text(presentation.guidanceAckSummary)
                    .foregroundStyle(.secondary)
            }

            governanceRow("Event Review") {
                Text(presentation.eventDrivenReviewEnabled ? "enabled" : "disabled")
                if !presentation.eventReviewTriggerLabels.isEmpty {
                    Text(presentation.eventReviewTriggerLabels.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }

            governanceRow("Memory") {
                Text("coder \(presentation.projectMemoryCeiling.rawValue)")
                Text("supervisor \(presentation.supervisorReviewMemoryCeiling.rawValue)")
                    .foregroundStyle(.secondary)
            }

            governanceRow("Capabilities") {
                Text(presentation.capabilityLabels.isEmpty ? "(none)" : presentation.capabilityLabels.joined(separator: ", "))
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            governanceRow("Status") {
                Text(presentation.statusSummary)
                    .foregroundStyle(.secondary)
            }

            governanceRow("Clamp") {
                Text(presentation.clampSummary)
                    .foregroundStyle(.secondary)
            }

            governanceRow("Compat") {
                Text(presentation.compatSource)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
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
            return "OpenClaw"
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
