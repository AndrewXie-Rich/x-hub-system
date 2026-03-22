import Foundation
import SwiftUI

struct SupervisorHeartbeatFeedView: View {
    let entries: [SupervisorManager.HeartbeatFeedEntry]
    let primarySignalPresentation: SupervisorPrimarySignalPresentation?
    let onOpenFocus: (String) -> Void
    let onPrimarySignalAction: (SupervisorSignalCenterOverviewAction) -> Void
    let listMaxHeight: CGFloat

    init(
        entries: [SupervisorManager.HeartbeatFeedEntry],
        primarySignalPresentation: SupervisorPrimarySignalPresentation? = nil,
        onOpenFocus: @escaping (String) -> Void,
        onPrimarySignalAction: @escaping (SupervisorSignalCenterOverviewAction) -> Void = { _ in },
        listMaxHeight: CGFloat = 360
    ) {
        self.entries = entries
        self.primarySignalPresentation = primarySignalPresentation
        self.onOpenFocus = onOpenFocus
        self.onPrimarySignalAction = onPrimarySignalAction
        self.listMaxHeight = listMaxHeight
    }

    var body: some View {
        let presentation = SupervisorHeartbeatPresentation.map(entries: entries)
        let attentionEntries = presentation.entries.filter(\.priority.belongsToAttentionSection)
        let recentEntries = presentation.entries.filter { !$0.priority.belongsToAttentionSection }

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: presentation.iconName)
                    .foregroundStyle(presentation.iconTone.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.headline)
                    if let primarySignalPresentation {
                        Text("当前：\(primarySignalPresentation.badgeText)")
                            .font(.caption)
                            .foregroundStyle(primarySignalPresentation.badgeTone.color)
                    } else if let overview = presentation.overview {
                        Text("当前：\(overview.priorityText)")
                            .font(.caption)
                            .foregroundStyle(overview.priorityTone.color)
                    }
                }
                Spacer()
            }

            if presentation.isEmpty {
                Text(presentation.emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let primarySignalPresentation {
                    primarySignalCard(primarySignalPresentation)
                } else if let overview = presentation.overview {
                    overviewCard(overview)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !attentionEntries.isEmpty {
                            sectionHeader(
                                title: "优先处理",
                                subtitle: "这些 heartbeat 直接对应治理修复、授权或诊断动作。"
                            )
                            ForEach(attentionEntries) { entry in
                                entryCard(entry)
                            }
                        }

                        if !recentEntries.isEmpty {
                            sectionHeader(
                                title: attentionEntries.isEmpty ? "最近汇报" : "其他更新",
                                subtitle: attentionEntries.isEmpty
                                    ? "这里保留最近几条 heartbeat 汇报。"
                                    : "这些 heartbeat 主要用于持续观察，不一定需要立刻处理。"
                            )
                            ForEach(recentEntries) { entry in
                                entryCard(entry)
                            }
                        }
                    }
                }
                .frame(maxHeight: listMaxHeight)
            }
        }
    }

    @ViewBuilder
    private func overviewCard(_ overview: SupervisorHeartbeatOverviewPresentation) -> some View {
        SupervisorSignalSummaryCard(
            badgeText: overview.priorityText,
            badgeTone: overview.priorityTone,
            eyebrowText: "当前主信号",
            headlineText: overview.headlineText,
            headlineTone: overview.priorityTone,
            headlineFont: .subheadline.weight(.semibold),
            detailText: overview.detailText,
            metadataText: overview.metadataText,
            backgroundColor: overviewBackgroundColor(for: overview),
            borderColor: overview.priorityTone.color.opacity(0.22),
            actionDescriptor: overview.focusAction.map { focusAction in
                SupervisorSignalSummaryActionDescriptor(
                    label: focusAction.label,
                    tone: focusAction.tone,
                    style: signalActionStyle(for: focusAction.style),
                    isEnabled: focusAction.isEnabled
                ) {
                    if case .openFocus(let rawURL) = focusAction.action {
                        onOpenFocus(rawURL)
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func primarySignalCard(
        _ overview: SupervisorPrimarySignalPresentation
    ) -> some View {
        SupervisorSignalSummaryCard(
            badgeText: overview.badgeText,
            badgeTone: overview.badgeTone,
            eyebrowText: overview.eyebrowText,
            headlineText: overview.headlineText,
            headlineTone: overview.badgeTone,
            headlineFont: .subheadline.weight(.semibold),
            detailText: overview.detailText,
            metadataText: overview.metadataText,
            backgroundColor: primarySignalBackgroundColor(for: overview),
            borderColor: overview.badgeTone.color.opacity(0.22),
            actionDescriptor: overview.focusAction.map { focusAction in
                SupervisorSignalSummaryActionDescriptor(
                    label: focusAction.label,
                    tone: focusAction.tone,
                    style: primarySignalActionStyle(for: focusAction.tone),
                    isEnabled: true
                ) {
                    onPrimarySignalAction(focusAction.action)
                }
            }
        )
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func entryCard(_ entry: SupervisorHeartbeatEntryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                chip(
                    text: entry.priorityText,
                    tone: entry.priorityTone,
                    emphasized: entry.priority != .stable
                )
                chip(
                    text: entry.reasonText,
                    tone: .neutral,
                    emphasized: false
                )
                Spacer()
                Text(entry.timeText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.headlineText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.headlineTone.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(entry.changeText)
                    .font(.caption2)
                    .foregroundStyle(entry.changeTone.color)
            }

            if entry.detailLines.isEmpty {
                Text(entry.contentText)
                    .font(.caption)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entry.detailLines.enumerated()), id: \.offset) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(entry.headlineTone.color.opacity(0.7))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            Text(item.element)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let focusAction = entry.focusAction {
                focusActionButton(focusAction)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor(for: entry))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(entry.priorityTone.color.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func chip(
        text: String,
        tone: SupervisorHeaderControlTone,
        emphasized: Bool
    ) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(emphasized ? tone.color : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        emphasized
                            ? tone.color.opacity(0.14)
                            : Color.secondary.opacity(0.08)
                    )
            )
    }

    @ViewBuilder
    private func focusActionButton(_ focusAction: SupervisorHeartbeatActionDescriptor) -> some View {
        if focusAction.style == .prominent {
            Button(focusAction.label) {
                if case .openFocus(let rawURL) = focusAction.action {
                    onOpenFocus(rawURL)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(focusAction.tone.color)
            .controlSize(.small)
            .disabled(!focusAction.isEnabled)
        } else {
            Button(focusAction.label) {
                if case .openFocus(let rawURL) = focusAction.action {
                    onOpenFocus(rawURL)
                }
            }
            .buttonStyle(.bordered)
            .tint(focusAction.tone.color)
            .controlSize(.small)
            .disabled(!focusAction.isEnabled)
        }
    }

    private func signalActionStyle(
        for style: SupervisorHeartbeatActionStyle
    ) -> SupervisorSignalSummaryActionStyle {
        switch style {
        case .standard:
            return .standard
        case .prominent:
            return .prominent
        }
    }

    private func primarySignalActionStyle(
        for tone: SupervisorHeaderControlTone
    ) -> SupervisorSignalSummaryActionStyle {
        switch tone {
        case .warning, .danger:
            return .prominent
        case .neutral, .accent, .success:
            return .standard
        }
    }

    private func backgroundColor(for entry: SupervisorHeartbeatEntryPresentation) -> Color {
        switch entry.priority {
        case .immediate:
            return SupervisorHeaderControlTone.warning.color.opacity(0.08)
        case .attention:
            return SupervisorHeaderControlTone.accent.color.opacity(0.07)
        case .watch:
            return SupervisorHeaderControlTone.success.color.opacity(0.06)
        case .stable:
            return Color.secondary.opacity(0.08)
        }
    }

    private func overviewBackgroundColor(for overview: SupervisorHeartbeatOverviewPresentation) -> Color {
        switch overview.priority {
        case .immediate:
            return SupervisorHeaderControlTone.warning.color.opacity(0.12)
        case .attention:
            return SupervisorHeaderControlTone.accent.color.opacity(0.11)
        case .watch:
            return SupervisorHeaderControlTone.success.color.opacity(0.10)
        case .stable:
            return Color.secondary.opacity(0.10)
        }
    }

    private func primarySignalBackgroundColor(
        for overview: SupervisorPrimarySignalPresentation
    ) -> Color {
        switch overview.badgeTone {
        case .danger:
            return SupervisorHeaderControlTone.danger.color.opacity(0.12)
        case .warning:
            return SupervisorHeaderControlTone.warning.color.opacity(0.12)
        case .accent:
            return SupervisorHeaderControlTone.accent.color.opacity(0.11)
        case .success:
            return SupervisorHeaderControlTone.success.color.opacity(0.10)
        case .neutral:
            return Color.secondary.opacity(0.10)
        }
    }
}

struct SupervisorHeartbeatBoardSection: View {
    let entries: [SupervisorManager.HeartbeatFeedEntry]
    let primarySignalPresentation: SupervisorPrimarySignalPresentation?
    let onOpenFocus: (String) -> Void
    let onPrimarySignalAction: (SupervisorSignalCenterOverviewAction) -> Void

    var body: some View {
        SupervisorHeartbeatFeedView(
            entries: entries,
            primarySignalPresentation: primarySignalPresentation,
            onOpenFocus: onOpenFocus,
            onPrimarySignalAction: onPrimarySignalAction,
            listMaxHeight: 248
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
