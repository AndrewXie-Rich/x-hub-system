import SwiftUI

enum ProjectCoderExecutionStatusTone: String, Equatable {
    case neutral
    case success
    case caution
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .caution:
            return .yellow
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

struct ProjectCoderExecutionStatusBadge: Equatable {
    var text: String
    var tone: ProjectCoderExecutionStatusTone
}

struct ProjectCoderExecutionStatusPresentation: Equatable {
    var titleText: String
    var statusText: String
    var tone: ProjectCoderExecutionStatusTone
    var detailBadge: ProjectCoderExecutionStatusBadge?
    var interpretationBadge: ProjectCoderExecutionStatusBadge?
    var helpText: String
    var summaryText: String? = nil
}

enum ProjectCoderExecutionStatusBarStyle: Equatable {
    case elevated
    case inline

    var showsLeadingIcon: Bool {
        switch self {
        case .elevated:
            return true
        case .inline:
            return false
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .elevated:
            return 10
        case .inline:
            return 0
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .elevated:
            return 8
        case .inline:
            return 0
        }
    }

    var showsContainerBackground: Bool {
        switch self {
        case .elevated:
            return true
        case .inline:
            return false
        }
    }

    var showsSummaryText: Bool {
        switch self {
        case .elevated:
            return true
        case .inline:
            return false
        }
    }
}

enum ProjectCoderExecutionStatusResolver {
    static func map(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        hubConnected: Bool,
        governancePresentation: ProjectGovernancePresentation? = nil,
        governanceInterception: ProjectGovernanceInterceptionPresentation? = nil
    ) -> ProjectCoderExecutionStatusPresentation {
        let configuredLabel = ExecutionRoutePresentation.configuredModelLabel(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
        let titleText = "Coder · \(configuredLabel)"
        let routeHelpText = ExecutionRoutePresentation.tooltip(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
        let helpText = combinedHelpText(
            routeHelpText: routeHelpText,
            governancePresentation: governancePresentation,
            governanceInterception: governanceInterception
        )
        let governanceOverride = governanceStatusOverride(
            governanceInterception: governanceInterception
        )
        let summaryText = combinedSummaryText(
            routeSummaryText: ExecutionRoutePresentation.inlineExplanationText(
                configuredModelId: configuredModelId,
                snapshot: snapshot
            ),
            governanceSummaryText: governanceSummaryText(
                governancePresentation: governancePresentation,
                governanceInterception: governanceInterception
            )
        )

        if snapshot.executionPath == "no_record" && !hubConnected {
            return ProjectCoderExecutionStatusPresentation(
                titleText: titleText,
                statusText: "Hub 离线",
                tone: .danger,
                detailBadge: nil,
                helpText: helpText
            )
        }

        let detailBadge = ExecutionRoutePresentation.detailBadge(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        ).map {
            ProjectCoderExecutionStatusBadge(
                text: $0.text,
                tone: detailTone(snapshot: snapshot)
            )
        }
        let interpretationBadge = ExecutionRoutePresentation.interpretationBadge(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        ).map {
            ProjectCoderExecutionStatusBadge(
                text: $0.text,
                tone: interpretationTone(snapshot: snapshot)
            )
        }

        return ProjectCoderExecutionStatusPresentation(
            titleText: titleText,
            statusText: governanceOverride?.statusText
                ?? ExecutionRoutePresentation.statusText(snapshot: snapshot),
            tone: governanceOverride?.tone
                ?? statusTone(snapshot: snapshot),
            detailBadge: detailBadge,
            interpretationBadge: governanceOverride?.interpretationBadge ?? interpretationBadge,
            helpText: helpText,
            summaryText: summaryText
        )
    }

    private struct GovernanceStatusOverride {
        var statusText: String
        var tone: ProjectCoderExecutionStatusTone
        var interpretationBadge: ProjectCoderExecutionStatusBadge?
    }

    private static func governanceSummaryText(
        governancePresentation: ProjectGovernancePresentation?,
        governanceInterception: ProjectGovernanceInterceptionPresentation?
    ) -> String? {
        guard let governanceInterception else { return nil }

        var lines: [String] = []
        if let blockedSummary = nonEmpty(governanceInterception.blockedSummary)
            ?? nonEmpty(governanceInterception.governanceReason) {
            lines.append("最近治理拦截：\(blockedSummary)")
        }
        if let governanceTruth = governanceTruthLine(
            governancePresentation: governancePresentation,
            governanceInterception: governanceInterception
        ) {
            lines.append(governanceTruth)
        }

        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private static func combinedSummaryText(
        routeSummaryText: String?,
        governanceSummaryText: String?
    ) -> String? {
        let parts = [nonEmpty(governanceSummaryText), nonEmpty(routeSummaryText)]
            .compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    private static func combinedHelpText(
        routeHelpText: String,
        governancePresentation: ProjectGovernancePresentation?,
        governanceInterception: ProjectGovernanceInterceptionPresentation?
    ) -> String {
        var lines = routeHelpText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if let governanceTruth = governanceTruthLine(
            governancePresentation: governancePresentation,
            governanceInterception: governanceInterception
        ) {
            appendUniqueLine(governanceTruth, to: &lines)
        }

        if let governanceInterception {
            if let blockedSummary = nonEmpty(governanceInterception.blockedSummary)
                ?? nonEmpty(governanceInterception.governanceReason) {
                appendUniqueLine("最近治理拦截：\(blockedSummary)", to: &lines)
            }
            if let policyReason = nonEmpty(governanceInterception.policyReason) {
                appendUniqueLine("policy_reason=\(policyReason)", to: &lines)
            }
            if let repairAction = nonEmpty(governanceInterception.repairActionSummary) {
                appendUniqueLine("repair_action=\(repairAction)", to: &lines)
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func governanceTruthLine(
        governancePresentation: ProjectGovernancePresentation?,
        governanceInterception: ProjectGovernanceInterceptionPresentation?
    ) -> String? {
        nonEmpty(governanceInterception?.governanceTruthLine)
            ?? nonEmpty(governancePresentation?.displayEffectiveTruthLine)
    }

    private static func appendUniqueLine(
        _ rawValue: String?,
        to lines: inout [String]
    ) {
        guard let line = nonEmpty(rawValue) else { return }
        guard !lines.contains(line) else { return }
        lines.append(line)
    }

    private static func nonEmpty(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func statusTone(snapshot: AXRoleExecutionSnapshot) -> ProjectCoderExecutionStatusTone {
        switch snapshot.executionPath {
        case "remote_model", "direct_provider":
            return .success
        case "hub_downgraded_to_local", "local_fallback_after_remote_error":
            return .warning
        case "local_runtime", "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            return .caution
        case "remote_error":
            return .danger
        default:
            return .neutral
        }
    }

    private static func governanceStatusOverride(
        governanceInterception: ProjectGovernanceInterceptionPresentation?
    ) -> GovernanceStatusOverride? {
        guard let governanceInterception else { return nil }

        let tone = governanceTone(governanceInterception)
        return GovernanceStatusOverride(
            statusText: governanceStatusText(governanceInterception),
            tone: tone,
            interpretationBadge: governanceInterpretationBadge(
                governanceInterception,
                tone: tone
            )
        )
    }

    private static func governanceStatusText(
        _ governanceInterception: ProjectGovernanceInterceptionPresentation
    ) -> String {
        if governanceClampBadgeText(governanceInterception) != nil {
            return "Clamped"
        }

        switch normalizedGovernanceStatus(governanceInterception.item.status) {
        case "failed":
            return "Failed"
        case "blocked":
            return "Blocked"
        default:
            return "Governed"
        }
    }

    private static func governanceTone(
        _ governanceInterception: ProjectGovernanceInterceptionPresentation
    ) -> ProjectCoderExecutionStatusTone {
        let denyCode = normalizedGovernanceStatus(governanceInterception.item.denyCode)
        let policyReason = normalizedGovernanceStatus(governanceInterception.policyReason)
        let itemStatus = normalizedGovernanceStatus(governanceInterception.item.status)

        if policyReason.contains("kill_switch")
            || policyReason.contains("ttl_expired")
            || denyCode == "autonomy_policy_denied" && governanceClampBadgeText(governanceInterception) != nil
            || itemStatus == "failed" {
            return .danger
        }

        return .warning
    }

    private static func governanceInterpretationBadge(
        _ governanceInterception: ProjectGovernanceInterceptionPresentation,
        tone: ProjectCoderExecutionStatusTone
    ) -> ProjectCoderExecutionStatusBadge? {
        let text = governanceClampBadgeText(governanceInterception)
            ?? governanceGateBadgeText(governanceInterception)
        guard let text else { return nil }
        return ProjectCoderExecutionStatusBadge(text: text, tone: tone)
    }

    private static func governanceClampBadgeText(
        _ governanceInterception: ProjectGovernanceInterceptionPresentation
    ) -> String? {
        let policyReason = normalizedGovernanceStatus(governanceInterception.policyReason)

        if policyReason.contains("kill_switch") {
            return "Kill Switch"
        }
        if policyReason.contains("ttl_expired") {
            return "TTL Expired"
        }
        if policyReason.contains("clamped_manual") {
            return "Manual Clamp"
        }
        if policyReason.contains("clamped_guided") {
            return "Guided Clamp"
        }
        if policyReason.contains("runtime_surface") || policyReason.contains("fail_closed") {
            return "Runtime Clamp"
        }

        return nil
    }

    private static func governanceGateBadgeText(
        _ governanceInterception: ProjectGovernanceInterceptionPresentation
    ) -> String? {
        if normalizedGovernanceStatus(governanceInterception.item.policySource)
            == "trusted_automation_device_gate" {
            return "Trusted Automation"
        }

        switch governanceInterception.repairHint?.destination {
        case .executionTier:
            return "A-Tier Gate"
        case .supervisorTier:
            return "S-Tier Gate"
        case .heartbeatReview:
            return "Review Gate"
        case .overview:
            return "Governance Gate"
        case .uiReview:
            return "UI Review"
        case nil:
            return nil
        }
    }

    private static func normalizedGovernanceStatus(_ rawValue: String?) -> String {
        rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func detailTone(snapshot: AXRoleExecutionSnapshot) -> ProjectCoderExecutionStatusTone {
        switch snapshot.executionPath {
        case "hub_downgraded_to_local", "local_fallback_after_remote_error":
            return .warning
        case "remote_error":
            return .danger
        case "remote_model", "direct_provider":
            return .warning
        default:
            return .neutral
        }
    }

    private static func interpretationTone(snapshot: AXRoleExecutionSnapshot) -> ProjectCoderExecutionStatusTone {
        switch snapshot.executionPath {
        case "remote_error":
            return .danger
        case "hub_downgraded_to_local", "local_fallback_after_remote_error":
            return .warning
        default:
            return .warning
        }
    }
}

struct ProjectCoderExecutionStatusBar: View {
    let presentation: ProjectCoderExecutionStatusPresentation
    var style: ProjectCoderExecutionStatusBarStyle = .elevated
    var actionTitle: String? = nil
    var actionHelpText: String? = nil
    var actionDisabled: Bool = false
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: style.showsSummaryText ? 6 : 0) {
            HStack(spacing: 8) {
                if style.showsLeadingIcon {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, weight: .medium))
                }

                Text(presentation.titleText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .help(presentation.helpText)

                Text(presentation.statusText)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(presentation.tone.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(presentation.tone.color.opacity(0.12))
                    .clipShape(Capsule())
                    .help(presentation.helpText)

                if let detailBadge = presentation.detailBadge {
                    Text(detailBadge.text)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(detailBadge.tone.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(detailBadge.tone.color.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .help(presentation.helpText)
                }

                if let interpretationBadge = presentation.interpretationBadge {
                    Text(interpretationBadge.text)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(interpretationBadge.tone.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(interpretationBadge.tone.color.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .help(presentation.helpText)
                }

                Spacer(minLength: 0)

                if style.showsSummaryText,
                   let actionTitle = actionTitle?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !actionTitle.isEmpty,
                   let onAction {
                    Button(actionTitle, action: onAction)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.caption2.weight(.medium))
                        .disabled(actionDisabled)
                        .help(actionHelpText ?? presentation.helpText)
                }
            }

            if style.showsSummaryText,
               let summaryText = presentation.summaryText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !summaryText.isEmpty {
                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(presentation.helpText)
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background {
            if style.showsContainerBackground {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            }
        }
    }
}
