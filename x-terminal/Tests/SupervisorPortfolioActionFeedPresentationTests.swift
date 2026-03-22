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
        #expect(presentation.title == "项目待授权：Project Alpha")
        #expect(presentation.summaryLine == "Waiting for pending approval")
        #expect(presentation.nextLine == "下一步：Approve the grant")
        #expect(presentation.whyLine == "为什么重要：The project cannot continue until the grant is approved.")
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
