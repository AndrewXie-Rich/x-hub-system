import SwiftUI

struct SupervisorPendingSkillApprovalBoardSection: View {
    let presentation: SupervisorPendingSkillApprovalBoardPresentation
    let onRefresh: () -> Void
    let onAction: (SupervisorCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .foregroundColor(toneColor(presentation.iconTone))
                Text(presentation.title)
                    .font(.headline)

                Spacer()

                Text(presentation.modeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新 Supervisor 本地待批技能")
            }

            if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(presentation.rows) { approval in
                            SupervisorPendingSkillApprovalRowView(
                                approval: approval,
                                onAction: onAction
                            )
                            .id(approval.anchorID)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 178)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toneColor(_ tone: SupervisorHeaderControlTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

struct SupervisorRecentSkillActivityBoardSection: View {
    let presentation: SupervisorRecentSkillActivityBoardPresentation
    let highlightedRequestID: String?
    let onRefresh: () -> Void
    let onAction: (SupervisorCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .foregroundColor(toneColor(presentation.iconTone))
                Text(presentation.title)
                    .font(.headline)

                Spacer()

                Text(presentation.summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新 Supervisor 最近技能活动")
            }

            if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(presentation.items) { item in
                            SupervisorRecentSkillActivityCardView(
                                item: item,
                                isFocused: highlightedRequestID == item.requestId,
                                actions: SupervisorCardActionResolver.recentSkillActivityActions(item),
                                onAction: onAction
                            )
                            .id(SupervisorFocusPresentation.recentSkillActivityRowAnchor(item))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toneColor(_ tone: SupervisorHeaderControlTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

struct SupervisorEventLoopBoardSection: View {
    let presentation: SupervisorEventLoopBoardPresentation
    let onAction: (SupervisorCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .foregroundColor(toneColor(presentation.iconTone))
                Text(presentation.title)
                    .font(.headline)

                Spacer()

                Text(presentation.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(presentation.rows) { item in
                            SupervisorEventLoopActivityRowView(
                                item: item,
                                onAction: onAction
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 176)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toneColor(_ tone: SupervisorHeaderControlTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

struct SupervisorPendingHubGrantBoardSection: View {
    let presentation: SupervisorPendingHubGrantBoardPresentation
    let onRefresh: () -> Void
    let onAction: (SupervisorCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .foregroundColor(toneColor(presentation.iconTone))
                Text(presentation.title)
                    .font(.headline)

                Spacer()

                Text(presentation.snapshotText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新 Hub 授权快照")
            }

            if let freshnessWarningText = presentation.freshnessWarningText {
                Text(freshnessWarningText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let footerNote = presentation.footerNote {
                Text(footerNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(presentation.rows) { grant in
                            SupervisorPendingHubGrantRowView(
                                grant: grant,
                                onAction: onAction
                            )
                            .id(grant.anchorID)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 178)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toneColor(_ tone: SupervisorHeaderControlTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

struct SupervisorCandidateReviewBoardSection: View {
    let presentation: SupervisorCandidateReviewBoardPresentation
    let onRefresh: () -> Void
    let onAction: (SupervisorCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .foregroundColor(toneColor(presentation.iconTone))
                Text(presentation.title)
                    .font(.headline)

                Spacer()

                Text(presentation.snapshotText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新 candidate review 快照")
            }

            if let freshnessWarningText = presentation.freshnessWarningText {
                Text(freshnessWarningText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let footerNote = presentation.footerNote {
                Text(footerNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(presentation.rows) { item in
                            SupervisorCandidateReviewRowView(
                                item: item,
                                onAction: onAction
                            )
                            .id(item.anchorID)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 178)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toneColor(_ tone: SupervisorHeaderControlTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

private struct SupervisorPendingSkillApprovalRowView: View {
    let approval: SupervisorPendingSkillApprovalRowPresentation
    let onAction: (SupervisorCardAction) -> Void
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var lastObservedSignature: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    approval.title,
                    systemImage: approval.iconName
                )
                .font(.subheadline)
                .fontWeight(.medium)

                Spacer(minLength: 8)

                Text(approval.ageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if updateFeedback.showsBadge {
                    XTTransientUpdateBadge(
                        tint: .orange,
                        font: .system(.caption2, design: .monospaced),
                        fontWeight: .semibold,
                        horizontalPadding: 8,
                        verticalPadding: 4
                    )
                }
            }

            Text(approval.summary)
                .font(.caption)
                .lineLimit(2)

            if let nextStepText = approval.nextStepText {
                Text(nextStepText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let routingText = approval.routingText {
                Text(routingText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let routingExplanationText = approval.routingExplanationText {
                Text(routingExplanationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let noteText = approval.noteText {
                Text(noteText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(alignment: .center, spacing: 8) {
                Text(approval.requestIdentifierText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                SupervisorInlineActionStrip(
                    actions: approval.actionDescriptors,
                    style: .regular,
                    onAction: onAction
                )
            }
        }
        .padding(10)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isFocused: approval.isFocused,
            isUpdated: updateFeedback.isHighlighted,
            focusTint: .orange,
            updateTint: .orange,
            baseBackground: approval.isFocused ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.08),
            baseBorder: approval.isFocused ? Color.orange.opacity(0.65) : Color.clear,
            baseLineWidth: approval.isFocused ? 1.5 : 1,
            emphasizedLineWidth: 1.5,
            updateBackgroundOpacity: 0.12,
            updateBorderOpacity: 0.32,
            updateShadowOpacity: 0.12
        )
        .onAppear {
            lastObservedSignature = observedSignature
        }
        .onChange(of: observedSignature) { newValue in
            defer { lastObservedSignature = newValue }
            guard let lastObservedSignature, lastObservedSignature != newValue else { return }
            updateFeedback.trigger()
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
        }
    }

    private var observedSignature: String {
        [
            approval.title,
            approval.ageText,
            approval.summary,
            approval.nextStepText ?? "",
            approval.noteText ?? "",
            approval.requestIdentifierText,
            approval.actionDescriptors.map { "\($0.label):\($0.isEnabled)" }.joined(separator: ",")
        ].joined(separator: "|")
    }
}

private struct SupervisorRecentSkillActivityCardView: View {
    let item: SupervisorManager.SupervisorRecentSkillActivity
    let isFocused: Bool
    let actions: [SupervisorCardActionDescriptor]
    let onAction: (SupervisorCardAction) -> Void
    @State private var showDiagnostics = false
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var lastObservedSignature: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: SupervisorSkillActivityPresentation.iconName(for: item))
                    .foregroundStyle(iconColor)
                    .font(.system(size: 14))

                Text(SupervisorSkillActivityPresentation.title(for: item))
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)

                Spacer()

                Text(SupervisorSkillActivityPresentation.statusLabel(for: item))
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(iconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(iconColor.opacity(0.12))
                    .clipShape(Capsule())

                if updateFeedback.showsBadge {
                    XTTransientUpdateBadge(
                        tint: iconColor,
                        font: .system(.caption2, design: .monospaced),
                        fontWeight: .semibold,
                        horizontalPadding: 8,
                        verticalPadding: 4
                    )
                }
            }

            HStack(spacing: 8) {
                let summaryText = SupervisorSkillActivityPresentation.preferredCardSummary(for: item)

                Text(item.projectName)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)

                if !summaryText.isEmpty {
                    Text(summaryText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(SupervisorSkillActivityPresentation.toolBadge(for: item))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(SupervisorSkillActivityPresentation.body(for: item))
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            let governedCardLines = SupervisorSkillActivityPresentation.cardGovernedDetailLines(for: item)
            if !governedCardLines.isEmpty {
                ForEach(governedCardLines, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if !item.toolSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("目标：\(item.toolSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let blockedSummaryLine = SupervisorSkillActivityPresentation.blockedSummaryLine(for: item) {
                Text(blockedSummaryLine)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if let governanceTruthLine = SupervisorSkillActivityPresentation.displayGovernanceTruthLine(for: item) {
                Text(governanceTruthLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let governanceLine = SupervisorSkillActivityPresentation.governanceLine(for: item) {
                Text(governanceLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let followUpRhythmLine = SupervisorSkillActivityPresentation.followUpRhythmLine(for: item) {
                Text(followUpRhythmLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let guidanceLine = SupervisorSkillActivityPresentation.pendingGuidanceLine(for: item) {
                Text(guidanceLine)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if let contractLine = SupervisorSkillActivityPresentation.guidanceContractLine(for: item) {
                Text(contractLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let nextSafeActionLine = SupervisorSkillActivityPresentation.guidanceNextSafeActionLine(for: item) {
                Text(nextSafeActionLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                ForEach(actions) { action in
                    actionButton(action)
                }

                Spacer()
            }

            DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                ScrollView {
                    Text(SupervisorSkillActivityPresentation.diagnostics(for: item))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(.top, 6)
            }
            .font(.caption)
            .tint(.secondary)
        }
        .padding(12)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isFocused: isFocused,
            isUpdated: updateFeedback.isHighlighted,
            focusTint: .orange,
            updateTint: iconColor,
            baseBackground: iconColor.opacity(0.06),
            baseBorder: iconColor.opacity(0.18),
            updateShadowOpacity: 0.14
        )
        .onAppear {
            lastObservedSignature = observedSignature
        }
        .onChange(of: observedSignature) { newValue in
            defer { lastObservedSignature = newValue }
            guard let lastObservedSignature, lastObservedSignature != newValue else { return }
            updateFeedback.trigger()
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
        }
    }

    private var iconColor: Color {
        switch item.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "queued":
            return .blue
        case "running":
            return .mint
        case "awaiting_authorization":
            return SupervisorSkillActivityPresentation.isAwaitingLocalApproval(item) ? .yellow : .orange
        case "completed":
            return .green
        case "failed":
            return .red
        case "blocked":
            return .orange
        case "canceled":
            return .secondary
        default:
            return .secondary
        }
    }

    private var timeLabel: String {
        let timestamp = item.updatedAt ?? item.createdAt ?? 0
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private var observedSignature: String {
        [
            item.status,
            item.resultSummary,
            item.denyCode,
            item.policySource,
            item.policyReason,
            SupervisorSkillActivityPresentation.preferredCardSummary(for: item),
            SupervisorSkillActivityPresentation.cardGovernedDetailLines(for: item).joined(separator: "||"),
            SupervisorSkillActivityPresentation.blockedSummaryLine(for: item) ?? "",
            SupervisorSkillActivityPresentation.governanceTruthLine(for: item) ?? "",
            item.grantRequestId,
            item.grantId,
            item.resultEvidenceRef,
            String(item.record.updatedAtMs)
        ].joined(separator: "|")
    }

    @ViewBuilder
    private func actionButton(_ action: SupervisorCardActionDescriptor) -> some View {
        switch action.style {
        case .prominent:
            Button(action.label) {
                onAction(action.action)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!action.isEnabled)
        case .standard:
            Button(action.label) {
                onAction(action.action)
            }
            .buttonStyle(.bordered)
            .disabled(!action.isEnabled)
        }
    }
}

private struct SupervisorEventLoopActivityRowView: View {
    let item: SupervisorEventLoopRowPresentation
    let onAction: (SupervisorCardAction) -> Void
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var lastObservedSignature: String?

    var body: some View {
        let statusColor = toneColor(item.statusTone)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.triggerLabel)
                    .font(.caption.weight(.semibold))
                Text(item.projectLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(item.statusLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())

                if updateFeedback.showsBadge {
                    XTTransientUpdateBadge(
                        tint: statusColor,
                        font: .system(.caption2, design: .monospaced),
                        fontWeight: .semibold,
                        horizontalPadding: 8,
                        verticalPadding: 4
                    )
                }
            }

            if let triggerText = item.triggerText {
                Text(triggerText)
                    .font(.caption)
                    .lineLimit(2)
            }

            if let resultText = item.resultText {
                Text(resultText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let blockedSummaryText = item.blockedSummaryText {
                Text(blockedSummaryText)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if let governanceTruthText = item.governanceTruthText {
                Text(governanceTruthText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let governanceReasonText = item.governanceReasonText {
                Text(governanceReasonText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let policyReasonText = item.policyReasonText {
                Text(policyReasonText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let policyText = item.policyText {
                Text(policyText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let contractText = item.contractText {
                Text(contractText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let nextSafeActionText = item.nextSafeActionText {
                Text(nextSafeActionText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(item.reasonText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(item.dedupeKeyText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                SupervisorInlineActionStrip(
                    actions: item.actionDescriptors,
                    style: .borderlessCaption,
                    onAction: onAction
                )
                Text(item.ageText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isUpdated: updateFeedback.isHighlighted,
            focusTint: statusColor,
            updateTint: statusColor,
            baseBackground: statusColor.opacity(0.06),
            baseBorder: statusColor.opacity(0.18),
            updateBackgroundOpacity: 0.1,
            updateBorderOpacity: 0.3,
            updateShadowOpacity: 0.12
        )
        .onAppear {
            lastObservedSignature = observedSignature
        }
        .onChange(of: observedSignature) { newValue in
            defer { lastObservedSignature = newValue }
            guard let lastObservedSignature, lastObservedSignature != newValue else { return }
            updateFeedback.trigger()
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
        }
    }

    private func toneColor(_ tone: SupervisorEventLoopTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .info:
            return .blue
        case .running:
            return .mint
        case .success:
            return .green
        case .warning:
            return .orange
        }
    }

    private var observedSignature: String {
        var parts: [String] = []
        parts.append(item.triggerLabel)
        parts.append(item.projectLabel)
        parts.append(item.statusLabel)
        parts.append(item.triggerText ?? "")
        parts.append(item.resultText ?? "")
        parts.append(item.policyText ?? "")
        parts.append(item.contractText ?? "")
        parts.append(item.nextSafeActionText ?? "")
        parts.append(item.reasonText)
        parts.append(item.dedupeKeyText)
        parts.append(item.ageText)
        parts.append(item.actionDescriptors.map { "\($0.label):\($0.isEnabled)" }.joined(separator: ","))
        parts.append(item.blockedSummaryText ?? "")
        parts.append(item.governanceTruthText ?? "")
        parts.append(item.governanceReasonText ?? "")
        parts.append(item.policyReasonText ?? "")
        return parts.joined(separator: "|")
    }
}

private struct SupervisorPendingHubGrantRowView: View {
    let grant: SupervisorPendingHubGrantRowPresentation
    let onAction: (SupervisorCardAction) -> Void
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var lastObservedSignature: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(grant.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer(minLength: 8)

                Text(grant.ageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if updateFeedback.showsBadge {
                    XTTransientUpdateBadge(
                        tint: .orange,
                        font: .system(.caption2, design: .monospaced),
                        fontWeight: .semibold,
                        horizontalPadding: 8,
                        verticalPadding: 4
                    )
                }
            }

            Text(grant.summary)
                .font(.caption)
                .lineLimit(2)

            ForEach(Array(grant.governedContextLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let supplementaryReasonText = grant.supplementaryReasonText {
                Text(supplementaryReasonText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let priorityReasonText = grant.priorityReasonText {
                Text(priorityReasonText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let nextActionText = grant.nextActionText {
                Text(nextActionText)
                    .font(.caption)
                    .lineLimit(2)
            }

            if let scopeSummaryText = grant.scopeSummaryText {
                Text(scopeSummaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 8) {
                Text(grant.grantIdentifierText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                if grant.isInFlight {
                    ProgressView()
                        .controlSize(.small)
                }

                SupervisorInlineActionStrip(
                    actions: grant.actionDescriptors,
                    style: .regular,
                    onAction: onAction
                )
            }
        }
        .padding(10)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isFocused: grant.isFocused,
            isUpdated: updateFeedback.isHighlighted,
            focusTint: .orange,
            updateTint: .orange,
            baseBackground: grant.isFocused ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.08),
            baseBorder: grant.isFocused ? Color.orange.opacity(0.65) : Color.clear,
            baseLineWidth: grant.isFocused ? 1.5 : 1,
            emphasizedLineWidth: 1.5,
            updateBackgroundOpacity: 0.12,
            updateBorderOpacity: 0.32,
            updateShadowOpacity: 0.12
        )
        .onAppear {
            lastObservedSignature = observedSignature
        }
        .onChange(of: observedSignature) { newValue in
            defer { lastObservedSignature = newValue }
            guard let lastObservedSignature, lastObservedSignature != newValue else { return }
            updateFeedback.trigger()
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
        }
    }

    private var observedSignature: String {
        [
            grant.title,
            grant.ageText,
            grant.summary,
            grant.governedContextLines.joined(separator: "\n"),
            grant.supplementaryReasonText ?? "",
            grant.priorityReasonText ?? "",
            grant.nextActionText ?? "",
            grant.scopeSummaryText ?? "",
            grant.grantIdentifierText,
            String(grant.isInFlight),
            grant.actionDescriptors.map { "\($0.label):\($0.isEnabled)" }.joined(separator: ",")
        ].joined(separator: "|")
    }
}

private struct SupervisorCandidateReviewRowView: View {
    let item: SupervisorCandidateReviewRowPresentation
    let onAction: (SupervisorCardAction) -> Void
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var lastObservedSignature: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer(minLength: 8)

                Text(item.ageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if updateFeedback.showsBadge {
                    XTTransientUpdateBadge(
                        tint: .accentColor,
                        font: .system(.caption2, design: .monospaced),
                        fontWeight: .semibold,
                        horizontalPadding: 8,
                        verticalPadding: 4
                    )
                }
            }

            Text(item.summary)
                .font(.caption)
                .lineLimit(2)

            Text(item.reviewStateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let scopeText = item.scopeText {
                Text(scopeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let draftText = item.draftText {
                Text(draftText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 8) {
                Text(item.evidenceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                if item.isInFlight {
                    ProgressView()
                        .controlSize(.small)
                }

                SupervisorInlineActionStrip(
                    actions: item.actionDescriptors,
                    style: .regular,
                    onAction: onAction
                )
            }
        }
        .padding(10)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isFocused: item.isFocused,
            isUpdated: updateFeedback.isHighlighted,
            focusTint: .accentColor,
            updateTint: .accentColor,
            baseBackground: item.isFocused ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
            baseBorder: item.isFocused ? Color.accentColor.opacity(0.65) : Color.clear,
            baseLineWidth: item.isFocused ? 1.5 : 1,
            emphasizedLineWidth: 1.5,
            updateBackgroundOpacity: 0.12,
            updateBorderOpacity: 0.32,
            updateShadowOpacity: 0.12
        )
        .onAppear {
            lastObservedSignature = observedSignature
        }
        .onChange(of: observedSignature) { newValue in
            defer { lastObservedSignature = newValue }
            guard let lastObservedSignature, lastObservedSignature != newValue else { return }
            updateFeedback.trigger()
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
        }
    }

    private var observedSignature: String {
        [
            item.title,
            item.ageText,
            item.summary,
            item.reviewStateText,
            item.scopeText ?? "",
            item.draftText ?? "",
            item.evidenceText,
            String(item.isInFlight),
            item.actionDescriptors.map { "\($0.label):\($0.isEnabled)" }.joined(separator: ",")
        ].joined(separator: "|")
    }
}
