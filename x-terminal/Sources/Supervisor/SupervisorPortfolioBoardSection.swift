import SwiftUI

struct SupervisorPortfolioBoardSection: View {
    let presentation: SupervisorPortfolioBoardPresentation
    let activeDrillDownPresentation: SupervisorProjectDrillDownPresentation?
    @Binding var selectedDrillDownScope: SupervisorProjectDrillDownScope
    let onSelectProject: (String) -> Void
    let onOpenProjectDetail: (String) -> Void
    let onOpenProjectGovernance: (String, XTProjectGovernanceDestination) -> Void
    let onOpenProjectUIReview: (String) -> Void
    let onRefreshProjectUIReview: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.overview.iconName)
                    .foregroundColor(toneColor(presentation.overview.iconTone))
                Text(presentation.overview.title)
                    .font(.headline)

                Spacer()

                Text(presentation.overview.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                ForEach(presentation.overview.countBadges) { badge in
                    PortfolioCountBadge(badge: badge)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(presentation.overview.metricBadgeRows.enumerated()), id: \.offset) { entry in
                    HStack(spacing: 8) {
                        ForEach(entry.element) { badge in
                            PortfolioMetricBadge(badge: badge)
                        }
                    }
                }
            }

            if let projectNotificationLine = presentation.overview.projectNotificationLine {
                Text(projectNotificationLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let infrastructureStatusLine = presentation.overview.infrastructureStatusLine {
                VStack(alignment: .leading, spacing: 2) {
                    Text(infrastructureStatusLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let infrastructureTransitionLine = presentation.overview.infrastructureTransitionLine {
                        Text(infrastructureTransitionLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if let emptyStateText = presentation.overview.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let todayQueue = presentation.overview.todayQueue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(todayQueue.title)
                            .font(.caption.weight(.semibold))
                        if let priorityHint = todayQueue.priorityHint {
                            Text(priorityHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(todayQueue.statusLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ForEach(todayQueue.rows) { item in
                            PortfolioActionabilityRow(item: item)
                        }
                    }
                }

                if let closeOutQueue = presentation.overview.closeOutQueue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(closeOutQueue.title)
                            .font(.caption.weight(.semibold))
                        if let priorityHint = closeOutQueue.priorityHint {
                            Text(priorityHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(closeOutQueue.statusLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ForEach(closeOutQueue.rows) { item in
                            PortfolioActionabilityRow(item: item)
                        }
                    }
                }

                if let criticalQueue = presentation.overview.criticalQueue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(criticalQueue.title)
                            .font(.caption.weight(.semibold))
                        ForEach(criticalQueue.rows) { item in
                            Text(item.text)
                                .font(.caption2)
                                .foregroundStyle(toneColor(item.tone))
                                .lineLimit(2)
                        }
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(presentation.projectRows) { row in
                            PortfolioProjectRow(
                                row: row,
                                onSelect: {
                                    onSelectProject(row.id)
                                },
                                onOpenGovernance: { destination in
                                    onOpenProjectGovernance(row.id, destination)
                                },
                                onOpenUIReview: {
                                    onOpenProjectUIReview(row.id)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 170)

                if let activeDrillDownPresentation {
                    SupervisorProjectDrillDownPanel(
                        presentation: activeDrillDownPresentation,
                        selectedDrillDownScope: $selectedDrillDownScope,
                        onOpenProjectDetail: onOpenProjectDetail,
                        onOpenGovernance: { destination in
                            onOpenProjectGovernance(activeDrillDownPresentation.projectId, destination)
                        },
                        onOpenProjectUIReview: onOpenProjectUIReview,
                        onRefreshProjectUIReview: onRefreshProjectUIReview
                    )
                }

                if let recentUIReviewFeedTitle = presentation.recentUIReviewFeedTitle {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recentUIReviewFeedTitle)
                            .font(.caption.weight(.semibold))
                        ForEach(presentation.uiReviewActivityRows) { row in
                            PortfolioUIReviewActivityRow(
                                row: row,
                                onOpenProjectDetail: {
                                    onOpenProjectDetail(row.projectId)
                                },
                                onOpenProjectUIReview: {
                                    onOpenProjectUIReview(row.projectId)
                                },
                                onRefreshProjectUIReview: {
                                    onRefreshProjectUIReview(row.projectId)
                                }
                            )
                        }
                    }
                }

                if let recentActionFeedTitle = presentation.recentActionFeedTitle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recentActionFeedTitle)
                            .font(.caption.weight(.semibold))
                        ForEach(presentation.actionEventRows) { event in
                            PortfolioActionEventRow(event: event)
                        }
                    }
                }
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

private struct PortfolioCountBadge: View {
    let badge: SupervisorPortfolioBadgePresentation

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(toneColor(badge.tone))
                .frame(width: 7, height: 7)
            Text("\(badge.title) \(badge.count)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(Capsule())
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

private struct PortfolioMetricBadge: View {
    let badge: SupervisorPortfolioBadgePresentation

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(toneColor(badge.tone))
                .frame(width: 8, height: 8)
            Text("\(badge.title) \(badge.count)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .clipShape(Capsule())
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

private struct PortfolioProjectRow: View {
    @EnvironmentObject private var appModel: AppModel

    let row: SupervisorPortfolioProjectRowPresentation
    let onSelect: () -> Void
    let onOpenGovernance: (XTProjectGovernanceDestination) -> Void
    let onOpenUIReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.displayName)
                    .font(.caption.weight(.semibold))
                Text(row.stateText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(toneColor(row.stateTone))
                Spacer()
                Text(row.freshnessText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(toneColor(row.freshnessTone))
                Text(row.recentText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Button(row.selectionButtonTitle) {
                    onSelect()
                }
                .buttonStyle(.borderless)
                .font(.caption2)
            }

            if !row.actionabilityTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(row.actionabilityTags) { tag in
                        PortfolioToneTag(tag: tag)
                    }
                }
            }

            if !row.governanceTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(row.governanceTags) { tag in
                        PortfolioToneTag(tag: tag)
                    }
                }
            }

            if let governancePresentation {
                ProjectGovernanceCompactSummaryView(
                    presentation: governancePresentation,
                    showCallout: true,
                    onExecutionTierTap: { onOpenGovernance(.executionTier) },
                    onSupervisorTierTap: { onOpenGovernance(.supervisorTier) },
                    onReviewCadenceTap: { onOpenGovernance(.heartbeatReview) },
                    onStatusTap: { onOpenGovernance(.overview) },
                    onCalloutTap: { onOpenGovernance(.overview) }
                )
            }

            if let uiReviewSummaryLine = row.uiReviewSummaryLine {
                Button(action: onOpenUIReview) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.caption2)
                        Text(uiReviewSummaryLine)
                            .font(.caption2)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(toneColor(row.uiReviewTone ?? .neutral))
                }
                .buttonStyle(.plain)
            }

            Text(row.actionLine)
                .font(.caption2)
                .lineLimit(2)

            Text(row.nextLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let blockerLine = row.blockerLine {
                Text(blockerLine)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(row.isSelected ? Color.accentColor : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var governancePresentation: ProjectGovernancePresentation? {
        SupervisorPortfolioGovernanceSurfaceSupport.presentation(
            projectId: row.id,
            appModel: appModel
        )
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

private struct PortfolioActionabilityRow: View {
    let item: SupervisorPortfolioActionabilityRowPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(toneColor(item.tone))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.projectName) · \(item.kindLabel)")
                    .font(.caption2.weight(.semibold))
                Text(item.recommendedNextAction)
                    .font(.caption2)
                    .lineLimit(2)
                Text(item.whyText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
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

private struct PortfolioToneTag: View {
    let tag: SupervisorPortfolioTagPresentation

    var body: some View {
        let resolvedToneColor = toneColor(tag.tone)
        Text(tag.title)
            .font(.caption2.monospaced())
            .foregroundStyle(resolvedToneColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(resolvedToneColor.opacity(0.12))
            .clipShape(Capsule())
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

private struct SupervisorProjectDrillDownPanel: View {
    @EnvironmentObject private var appModel: AppModel

    let presentation: SupervisorProjectDrillDownPresentation
    @Binding var selectedDrillDownScope: SupervisorProjectDrillDownScope
    let onOpenProjectDetail: (String) -> Void
    let onOpenGovernance: (XTProjectGovernanceDestination) -> Void
    let onOpenProjectUIReview: (String) -> Void
    let onRefreshProjectUIReview: (String) -> Void

    @StateObject private var uiReviewActionState = XTUIReviewActionState()
    @StateObject private var uiReviewUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var lastObservedUIReviewSignature: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(presentation.projectName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Picker("查看范围", selection: $selectedDrillDownScope) {
                ForEach(presentation.scopeOptions) { option in
                    Text(option.title).tag(option.scope)
                }
            }
            .pickerStyle(.segmented)

            Text(presentation.statusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let governancePresentation {
                ProjectGovernanceCompactSummaryView(
                    presentation: governancePresentation,
                    showCallout: true,
                    onExecutionTierTap: { onOpenGovernance(.executionTier) },
                    onSupervisorTierTap: { onOpenGovernance(.supervisorTier) },
                    onReviewCadenceTap: { onOpenGovernance(.heartbeatReview) },
                    onStatusTap: { onOpenGovernance(.overview) },
                    onCalloutTap: { onOpenGovernance(.overview) }
                )
            }

            if !presentation.governanceTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(presentation.governanceTags) { tag in
                        PortfolioToneTag(tag: tag)
                    }
                }
            }

            if let runtimeSummary = presentation.runtimeSummary {
                Text(runtimeSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let scopeRestrictionText = presentation.scopeRestrictionText {
                Text(scopeRestrictionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let latestUIReview = presentation.latestUIReview {
                VStack(alignment: .leading, spacing: 6) {
                    latestUIReviewHeader
                    ProjectUIReviewCard(
                        review: latestUIReview,
                        onShowHistory: projectContext == nil ? nil : { uiReviewActionState.presentHistory() },
                        onResampleSnapshot: projectContext == nil ? nil : {
                            guard let projectContext else { return }
                            Task {
                                await uiReviewActionState.runSnapshot(in: projectContext) { _ in
                                    onRefreshProjectUIReview(presentation.projectId)
                                }
                            }
                        },
                        isResampling: uiReviewActionState.isResampling,
                        showsScreenshotPreview: true
                    )
                    .xtTransientUpdateCardChrome(
                        cornerRadius: 12,
                        isUpdated: uiReviewUpdateFeedback.isHighlighted,
                        focusTint: latestUIReviewTintColor,
                        updateTint: latestUIReviewTintColor,
                        baseBackground: .clear,
                        baseBorder: latestUIReviewTintColor.opacity(0.14),
                        updateBackgroundOpacity: 0.08,
                        updateBorderOpacity: 0.26,
                        updateShadowOpacity: 0.12
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    latestUIReviewHeader
                    Text("当前项目还没有浏览器 UI review。运行一次页面 snapshot 后，Supervisor 才能直接看到页面证据和执行判断。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    if projectContext != nil {
                        XTUIReviewActionStrip(
                            items: [drillDownSnapshotAction].compactMap { $0 },
                            controlSize: .small,
                            font: .caption2
                        )
                    }
                }
            }

            XTUIReviewStatusMessageView(
                message: uiReviewActionState.statusMessage,
                isError: uiReviewActionState.statusIsError,
                font: .caption2
            )

            ForEach(presentation.sections) { section in
                SupervisorProjectDrillDownSectionView(section: section)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            lastObservedUIReviewSignature = observedUIReviewSignature
        }
        .onChange(of: observedUIReviewSignature) { newValue in
            defer { lastObservedUIReviewSignature = newValue }
            guard let lastObservedUIReviewSignature, lastObservedUIReviewSignature != newValue else {
                return
            }
            uiReviewUpdateFeedback.trigger()
        }
        .onChange(of: uiReviewActionState.refreshNonce) { refreshNonce in
            guard refreshNonce > 0 else { return }
            uiReviewUpdateFeedback.trigger()
        }
        .onDisappear {
            uiReviewUpdateFeedback.cancel(resetState: true)
        }
        .sheet(isPresented: $uiReviewActionState.showHistorySheet) {
            if let projectContext {
                ProjectUIReviewHistorySheet(ctx: projectContext)
            }
        }
    }

    private var projectContext: AXProjectContext? {
        appModel.projectContext(for: presentation.projectId)
    }

    private var governancePresentation: ProjectGovernancePresentation? {
        SupervisorPortfolioGovernanceSurfaceSupport.presentation(
            projectId: presentation.projectId,
            appModel: appModel
        )
    }

    private var latestUIReviewHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("最近 UI 审查")
                .font(.caption2.weight(.semibold))
            Spacer()
            if uiReviewUpdateFeedback.showsBadge {
                XTTransientUpdateBadge(tint: latestUIReviewTintColor)
            }
            XTUIReviewActionStrip(
                items: drillDownNavigationActions,
                controlSize: .small,
                font: .caption2
            )
        }
    }

    private var observedUIReviewSignature: String {
        presentation.latestUIReview?.transientUpdateSignature ?? "none"
    }

    private var latestUIReviewTintColor: Color {
        guard let latestUIReview = presentation.latestUIReview else {
            return .accentColor
        }
        return uiReviewToneColor(latestUIReview.verdict)
    }

    private func uiReviewToneColor(_ verdict: XTUIReviewVerdict) -> Color {
        switch verdict {
        case .ready:
            return .green
        case .attentionNeeded:
            return .orange
        case .insufficientEvidence:
            return .red
        }
    }

    private var drillDownNavigationActions: [XTUIReviewActionStripItem] {
        [
            XTUIReviewActionStripItem(
                id: "view-project",
                title: "查看项目",
                style: .borderless
            ) {
                onOpenProjectDetail(presentation.projectId)
            },
            XTUIReviewActionStripItem(
                id: "open-ui-review",
                title: "打开 UI 审查",
                style: .borderless
            ) {
                onOpenProjectUIReview(presentation.projectId)
            }
        ]
    }

    private var drillDownSnapshotAction: XTUIReviewActionStripItem? {
        guard projectContext != nil else { return nil }
        return XTUIReviewActionStripItem(
            id: "run-snapshot",
            title: uiReviewActionState.isResampling ? "采集中…" : "运行快照",
            systemImage: uiReviewActionState.isResampling ? "arrow.triangle.2.circlepath" : "camera.viewfinder",
            style: .borderedProminent,
            isDisabled: uiReviewActionState.isResampling
        ) {
            guard let projectContext else { return }
            Task {
                await uiReviewActionState.runSnapshot(in: projectContext) { _ in
                    onRefreshProjectUIReview(presentation.projectId)
                }
            }
        }
    }
}

private struct SupervisorProjectDrillDownSectionView: View {
    let section: SupervisorProjectDrillDownSectionPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = section.title {
                Text(title)
                    .font(.caption2.weight(.semibold))
            }

            ForEach(section.lines) { line in
                Text(line.text)
                    .font(line.monospaced ? .caption2.monospaced() : .caption2)
                    .foregroundStyle(lineColor(line.tone))
                    .lineLimit(line.lineLimit)
            }
        }
    }

    private func lineColor(_ tone: SupervisorProjectDrillDownLineTone) -> Color {
        switch tone {
        case .primary:
            return .primary
        case .secondary:
            return .secondary
        case .warning:
            return .orange
        }
    }
}

@MainActor
private enum SupervisorPortfolioGovernanceSurfaceSupport {
    static func presentation(
        projectId: String,
        appModel: AppModel
    ) -> ProjectGovernancePresentation? {
        guard let project = appModel.registry.project(for: projectId) else { return nil }
        return ProjectGovernancePresentation(
            resolved: appModel.resolvedProjectGovernance(for: project)
        )
    }
}

private struct PortfolioActionEventRow: View {
    let event: SupervisorPortfolioActionEventPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(toneColor(event.tone))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.caption2.weight(.semibold))
                Text(event.summaryLine)
                    .font(.caption2)
                    .lineLimit(2)
                Text(event.nextLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(event.whyLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
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

private struct PortfolioUIReviewActivityRow: View {
    @EnvironmentObject private var appModel: AppModel

    let row: SupervisorPortfolioUIReviewActivityPresentation
    let onOpenProjectDetail: () -> Void
    let onOpenProjectUIReview: () -> Void
    let onRefreshProjectUIReview: () -> Void

    @StateObject private var uiReviewActionState = XTUIReviewActionState()
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.caption2)
                            .foregroundStyle(toneColor(row.tone))
                        Text(row.projectName)
                            .font(.caption2.weight(.semibold))
                        Text(row.statusLine)
                            .font(.caption2)
                            .foregroundStyle(toneColor(row.tone))
                            .lineLimit(1)
                    }

                    Spacer()

                    if updateFeedback.showsBadge {
                        XTTransientUpdateBadge(
                            tint: toneColor(row.tone)
                        )
                    }

                    Text(row.updatedText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text(row.summaryLine)
                    .font(.caption2)
                    .lineLimit(2)

                if let detailLine = row.detailLine {
                    Text(detailLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                XTUIReviewActionStrip(
                    items: activityActions,
                    controlSize: .small,
                    font: .caption2
                )

                XTUIReviewStatusMessageView(
                    message: uiReviewActionState.statusMessage,
                    isError: uiReviewActionState.statusIsError,
                    font: .caption2
                )
            }

            if let screenshotFileURL = row.screenshotFileURL {
                ProjectUIReviewScreenshotPreview(
                    url: screenshotFileURL,
                    title: nil,
                    height: 82,
                    maxHeight: 90,
                    cornerRadius: 8
                )
                .frame(width: 132)
            }
        }
        .padding(8)
        .xtTransientUpdateCardChrome(
            cornerRadius: 8,
            isUpdated: updateFeedback.isHighlighted,
            focusTint: toneColor(row.tone),
            updateTint: toneColor(row.tone),
            baseBackground: Color(NSColor.controlBackgroundColor).opacity(0.55)
        )
        .onChange(of: uiReviewActionState.refreshNonce) { refreshNonce in
            guard refreshNonce > 0 else { return }
            updateFeedback.trigger()
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
        }
        .sheet(isPresented: $uiReviewActionState.showHistorySheet) {
            if let projectContext {
                ProjectUIReviewHistorySheet(ctx: projectContext)
            }
        }
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

    private var projectContext: AXProjectContext? {
        appModel.projectContext(for: row.projectId)
    }

    private var activityActions: [XTUIReviewActionStripItem] {
        var items: [XTUIReviewActionStripItem] = [
            XTUIReviewActionStripItem(
                id: "view-project",
                title: "查看项目",
                style: .borderless
            ) {
                onOpenProjectDetail()
            },
            XTUIReviewActionStripItem(
                id: "open-ui-review",
                title: "打开 UI 审查",
                style: .borderless
            ) {
                onOpenProjectUIReview()
            }
        ]

        if projectContext != nil {
            items.append(
                XTUIReviewActionStripItem(
                    id: "history",
                    title: "历史记录",
                    style: .borderless
                ) {
                    uiReviewActionState.presentHistory()
                }
            )
            items.append(
                XTUIReviewActionStripItem(
                    id: "resample",
                    title: uiReviewActionState.isResampling ? "采集中…" : "重新运行快照",
                    style: .borderless,
                    isDisabled: uiReviewActionState.isResampling
                ) {
                    guard let projectContext else { return }
                    Task {
                        await uiReviewActionState.runSnapshot(in: projectContext) { _ in
                            onRefreshProjectUIReview()
                        }
                    }
                }
            )
        }

        return items
    }
}
