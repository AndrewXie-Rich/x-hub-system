import Foundation
import Testing
@testable import XTerminal

struct SupervisorPortfolioActionFeedPresentationTests {

    @Test
    func mapBuildsAuthorizationEventPresentation() {
        let event = SupervisorProjectActionEvent(
            eventId: "evt-auth",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            eventType: .awaitingAuthorization,
            severity: .authorizationRequired,
            actionTitle: "项目待授权：Project Alpha",
            actionSummary: "Waiting for pending approval",
            whyItMatters: "The project cannot continue until the grant is approved.",
            nextAction: "Approve the grant",
            occurredAt: 1
        )

        let presentation = SupervisorPortfolioActionEventPresentationMapper.map(event)

        #expect(presentation.id == "evt-auth")
        #expect(presentation.sourceLabel == "待授权提醒")
        #expect(presentation.scopeLine == "Project Alpha")
        #expect(presentation.title == "项目待授权：Project Alpha")
        #expect(presentation.summaryLine == "Waiting for pending approval")
        #expect(presentation.nextLine == "下一步：Approve the grant")
        #expect(presentation.whyLine == "为什么重要：The project cannot continue until the grant is approved.")
        #expect(presentation.detailLines.contains("项目：Project Alpha"))
        #expect(presentation.detailActionLabel == "打开项目")
        #expect(presentation.destination == .projectDetail(projectId: "project-alpha"))
        #expect(presentation.defaultUnread == true)
        #expect(presentation.tone == .danger)
    }

    @Test
    func mapBuildsPairingNotificationPresentation() {
        let signal = SupervisorPortfolioSystemNotificationSignal(
            id: "pairing:repair",
            sourceLabel: "配对信息",
            scopeLine: "Hub 配对 / 连接",
            title: "配对续连待修复",
            summaryLine: "正式异网入口还没恢复。",
            whyLine: "切网后可能直接断开。",
            nextStepLine: "打开 Hub 配对并核对正式异网入口。",
            detailLines: [
                "当前状态：配对续连待修复",
                "建议动作：打开 Hub 配对并核对正式异网入口。"
            ],
            detailActionLabel: "打开处理",
            destination: .openURL("xterminal://hub-setup"),
            tone: .danger,
            defaultUnread: true
        )

        let presentation = SupervisorPortfolioActionEventPresentationMapper.map(signal)

        #expect(presentation.id == "pairing:repair")
        #expect(presentation.sourceLabel == "配对信息")
        #expect(presentation.scopeLine == "Hub 配对 / 连接")
        #expect(presentation.title == "配对续连待修复")
        #expect(presentation.nextLine == "下一步：打开 Hub 配对并核对正式异网入口。")
        #expect(presentation.whyLine == "为什么重要：切网后可能直接断开。")
        #expect(presentation.detailActionLabel == "打开处理")
        #expect(presentation.destination == .openURL("xterminal://hub-setup"))
        #expect(presentation.defaultUnread == true)
        #expect(presentation.tone == .danger)
    }

    @Test
    func toneMappingMatchesSeverity() {
        #expect(SupervisorPortfolioActionEventPresentationMapper.tone(.silentLog) == .neutral)
        #expect(SupervisorPortfolioActionEventPresentationMapper.tone(.badgeOnly) == .accent)
        #expect(SupervisorPortfolioActionEventPresentationMapper.tone(.briefCard) == .warning)
        #expect(SupervisorPortfolioActionEventPresentationMapper.tone(.interruptNow) == .danger)
        #expect(SupervisorPortfolioActionEventPresentationMapper.tone(.authorizationRequired) == .danger)
    }
}
