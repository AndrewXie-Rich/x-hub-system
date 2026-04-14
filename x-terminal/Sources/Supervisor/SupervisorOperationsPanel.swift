import SwiftUI

struct SupervisorSignalCenterPanel<Content: View>: View {
    let maxHeight: CGFloat
    let focusRequestNonce: Int?
    let pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
    let pendingSkillApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
    let recentSkillActivities: [SupervisorManager.SupervisorRecentSkillActivity]
    let overviewPresentation: SupervisorSignalCenterOverviewPresentation
    let reviewMemorySummary: SupervisorMemoryAssemblyCompactSummary?
    let onProcessFocusRequest: (ScrollViewProxy) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { dashboardScrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    overviewCard(
                        overviewPresentation,
                        dashboardScrollProxy: dashboardScrollProxy
                    )
                    if let reviewMemorySummary {
                        reviewMemorySummaryCard(
                            reviewMemorySummary,
                            dashboardScrollProxy: dashboardScrollProxy
                        )
                    }
                    Divider()
                    content()
                }
            }
            .frame(maxHeight: maxHeight)
            .onAppear {
                onProcessFocusRequest(dashboardScrollProxy)
            }
            .onChange(of: focusRequestNonce) { _ in
                onProcessFocusRequest(dashboardScrollProxy)
            }
            .onChange(of: pendingHubGrants) { _ in
                onProcessFocusRequest(dashboardScrollProxy)
            }
            .onChange(of: pendingSkillApprovals) { _ in
                onProcessFocusRequest(dashboardScrollProxy)
            }
            .onChange(of: recentSkillActivities) { _ in
                onProcessFocusRequest(dashboardScrollProxy)
            }
        }
    }

    @ViewBuilder
    private func overviewCard(
        _ presentation: SupervisorSignalCenterOverviewPresentation,
        dashboardScrollProxy: ScrollViewProxy
    ) -> some View {
        SupervisorSignalSummaryCard(
            badgeText: presentation.priorityText,
            badgeTone: presentation.priorityTone,
            eyebrowText: "当前主信号",
            headlineText: presentation.headlineText,
            headlineTone: presentation.priorityTone,
            detailText: presentation.detailText,
            metadataText: presentation.metadataText,
            backgroundColor: presentation.priorityTone.color.opacity(0.10),
            borderColor: presentation.priorityTone.color.opacity(0.20),
            actionDescriptor: presentation.focusAction.map { focusAction in
                SupervisorSignalSummaryActionDescriptor(
                    label: focusAction.label,
                    tone: focusAction.tone,
                    style: .prominent,
                    isEnabled: true
                ) {
                    if case .scrollToBoard(let anchorID) = focusAction.action {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            dashboardScrollProxy.scrollTo(anchorID, anchor: .top)
                        }
                    }
                }
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func reviewMemorySummaryCard(
        _ summary: SupervisorMemoryAssemblyCompactSummary,
        dashboardScrollProxy: ScrollViewProxy
    ) -> some View {
        SignalCenterReviewMemorySummaryCard(
            summary: summary,
            onOpenMemoryBoard: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    dashboardScrollProxy.scrollTo(
                        SupervisorFocusPresentation.memoryBoardAnchorID,
                        anchor: .top
                    )
                }
            }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct SignalCenterReviewMemorySummaryCard: View {
    let summary: SupervisorMemoryAssemblyCompactSummary
    let onOpenMemoryBoard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.secondary)
                Text("Supervisor Review Memory")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button("查看装配") {
                    onOpenMemoryBoard()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(summary.headlineText)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let detailText = summary.detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("这张卡只说明 Supervisor 这次实际装配了多深的 review-memory，不等于当前主信号，也不等于 S-Tier 本身。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .help(summary.helpText)
    }
}
