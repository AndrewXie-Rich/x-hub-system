import Foundation
import Testing
@testable import XTerminal

struct SupervisorPrimarySignalPresentationTests {

    @Test
    func mapperReturnsNilForStableOverview() {
        let presentation = SupervisorPrimarySignalPresentationMapper.map(
            overview: SupervisorSignalCenterOverviewPresentation(
                priority: .stable,
                priorityText: SupervisorHeartbeatPriority.stable.label,
                priorityTone: .neutral,
                headlineText: "信号中心空闲",
                detailText: "当前无待处理事项。",
                metadataText: "idle",
                focusAction: nil
            )
        )

        #expect(presentation == nil)
    }

    @Test
    func mapperPreservesOverviewFieldsForActionableSignal() {
        let overview = SupervisorSignalCenterOverviewPresentation(
            priority: .immediate,
            priorityText: SupervisorHeartbeatPriority.immediate.label,
            priorityTone: .warning,
            headlineText: "Hub 待处理授权",
            detailText: "先完成 grant 审批，再继续自动化。",
            metadataText: "2 项待处理 · 最新 2m",
            focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.pendingHubGrantBoardAnchorID),
                label: "查看授权板",
                tone: .warning
            )
        )

        let presentation = SupervisorPrimarySignalPresentationMapper.map(
            overview: overview
        )

        #expect(
            presentation == SupervisorPrimarySignalPresentation(
                badgeText: SupervisorHeartbeatPriority.immediate.label,
                badgeTone: .warning,
                eyebrowText: "当前主信号",
                headlineText: "Hub 待处理授权",
                detailText: "先完成 grant 审批，再继续自动化。",
                metadataText: "2 项待处理 · 最新 2m",
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.pendingHubGrantBoardAnchorID),
                    label: "查看授权板",
                    tone: .warning
                )
            )
        )

        #expect(
            presentation?.cockpitAction == PrimaryActionRailAction(
                id: SupervisorPrimarySignalPresentation.cockpitActionID,
                title: "查看授权板",
                subtitle: "先完成 grant 审批，再继续自动化。",
                systemImage: "shield.lefthalf.filled",
                style: .secondary
            )
        )
    }
}
