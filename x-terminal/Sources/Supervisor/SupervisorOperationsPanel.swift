import SwiftUI

struct SupervisorSignalCenterPanel<Content: View>: View {
    let maxHeight: CGFloat
    let focusRequestNonce: Int?
    let pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
    let pendingSkillApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
    let recentSkillActivities: [SupervisorManager.SupervisorRecentSkillActivity]
    let overviewPresentation: SupervisorSignalCenterOverviewPresentation
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
}
