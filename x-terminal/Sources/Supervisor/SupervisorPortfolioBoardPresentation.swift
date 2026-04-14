import Foundation

struct SupervisorPortfolioBoardPresentation: Equatable {
    var overview: SupervisorPortfolioOverviewPresentation
    var projectRows: [SupervisorPortfolioProjectRowPresentation]
    var uiReviewActivityRows: [SupervisorPortfolioUIReviewActivityPresentation]
    var actionEventRows: [SupervisorPortfolioActionEventPresentation]
    var activeDrillDown: SupervisorProjectDrillDownSnapshot?
    var recentUIReviewFeedTitle: String?
    var recentActionFeedTitle: String?
}

enum SupervisorPortfolioBoardPresentationMapper {
    static let defaultMaxProjectRows = 6
    static let defaultMaxUIReviewScanProjects = 12
    static let defaultMaxUIReviewActivityRows = 4
    static let defaultMaxActionEvents = 4

    static func map(
        overview: SupervisorPortfolioOverviewPresentation,
        projectRows: [SupervisorPortfolioProjectRowPresentation],
        uiReviewActivityRows: [SupervisorPortfolioUIReviewActivityPresentation],
        actionEventRows: [SupervisorPortfolioActionEventPresentation],
        selectedProjectID: String?,
        lastDrillDownSnapshot: SupervisorProjectDrillDownSnapshot?,
        maxProjectRows: Int = defaultMaxProjectRows,
        maxUIReviewActivityRows: Int = defaultMaxUIReviewActivityRows,
        maxActionEvents: Int = defaultMaxActionEvents
    ) -> SupervisorPortfolioBoardPresentation {
        let displayedRows = Array(projectRows.prefix(maxProjectRows))
        let displayedUIReviewRows = Array(uiReviewActivityRows.prefix(maxUIReviewActivityRows))
        let displayedEvents = Array(actionEventRows.prefix(maxActionEvents))
        let activeDrillDown: SupervisorProjectDrillDownSnapshot?
        if let snapshot = lastDrillDownSnapshot,
           snapshot.projectId == selectedProjectID {
            activeDrillDown = snapshot
        } else {
            activeDrillDown = nil
        }

        return SupervisorPortfolioBoardPresentation(
            overview: overview,
            projectRows: displayedRows,
            uiReviewActivityRows: displayedUIReviewRows,
            actionEventRows: displayedEvents,
            activeDrillDown: activeDrillDown,
            recentUIReviewFeedTitle: displayedUIReviewRows.isEmpty ? nil : "最近 UI 审查",
            recentActionFeedTitle: displayedEvents.isEmpty ? nil : "提醒中心"
        )
    }
}
