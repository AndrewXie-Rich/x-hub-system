import Foundation
import Testing
@testable import XTerminal

struct SupervisorPortfolioBoardPresentationTests {

    @Test
    func mapTruncatesRowsAndEventsAndKeepsMatchingDrillDown() {
        let overview = SupervisorPortfolioOverviewPresentation(
            iconName: "square.stack.3d.up.fill",
            iconTone: .accent,
            title: "项目总览",
            statusLine: "portfolio=active",
            countBadges: [],
            metricBadgeRows: [],
            projectNotificationLine: nil,
            infrastructureStatusLine: nil,
            infrastructureTransitionLine: nil,
            emptyStateText: nil,
            todayQueue: nil,
            closeOutQueue: nil,
            criticalQueue: nil
        )
        let rows = (1...8).map { index in
            SupervisorPortfolioProjectRowPresentation(
                id: "project-\(index)",
                displayName: "Project \(index)",
                stateText: "active",
                stateTone: .accent,
                freshnessText: "fresh",
                freshnessTone: .success,
                recentText: "最近 1 条",
                selectionButtonTitle: "查看",
                isSelected: index == 3,
                actionabilityTags: [],
                governanceTags: [],
                uiReviewSummaryLine: index == 1 ? "UI review · 可行动 · 核心检查通过" : nil,
                uiReviewTone: index == 1 ? .success : nil,
                actionLine: "当前动作：continue",
                nextLine: "下一步：next step",
                blockerLine: nil
            )
        }
        let uiReviewRows = (1...6).map { index in
            SupervisorPortfolioUIReviewActivityPresentation(
                id: "ui-review-\(index)",
                projectId: "project-\(index)",
                projectName: "Project \(index)",
                statusLine: "可行动 · 证据充分",
                summaryLine: "summary \(index)",
                detailLine: "detail \(index)",
                updatedText: "\(index)m",
                screenshotFileURL: nil,
                tone: .success
            )
        }
        let events = (1...6).map { index in
            SupervisorPortfolioActionEventPresentation(
                id: "event-\(index)",
                sourceLabel: "项目提醒",
                scopeLine: "Project \(index)",
                title: "Event \(index)",
                summaryLine: "summary \(index)",
                nextLine: "next \(index)",
                whyLine: "why \(index)",
                detailLines: ["detail \(index)"],
                detailActionLabel: "打开项目",
                destination: .projectDetail(projectId: "project-\(index)"),
                defaultUnread: true,
                tone: .warning
            )
        }
        let drillDown = SupervisorProjectDrillDownSnapshot.denied(
            projectId: "project-3",
            projectName: "Project 3",
            status: .deniedScope,
            requestedScope: .capsulePlusRecent,
            denyReason: "scope_denied"
        )

        let presentation = SupervisorPortfolioBoardPresentationMapper.map(
            overview: overview,
            projectRows: rows,
            uiReviewActivityRows: uiReviewRows,
            actionEventRows: events,
            selectedProjectID: "project-3",
            lastDrillDownSnapshot: drillDown
        )

        #expect(presentation.overview.title == "项目总览")
        #expect(presentation.projectRows.count == 6)
        #expect(presentation.projectRows.map { $0.id } == ["project-1", "project-2", "project-3", "project-4", "project-5", "project-6"])
        #expect(presentation.uiReviewActivityRows.count == 4)
        #expect(presentation.uiReviewActivityRows.map { $0.id } == ["ui-review-1", "ui-review-2", "ui-review-3", "ui-review-4"])
        #expect(presentation.actionEventRows.count == 4)
        #expect(presentation.actionEventRows.map { $0.id } == ["event-1", "event-2", "event-3", "event-4"])
        #expect(presentation.activeDrillDown?.projectId == "project-3")
        #expect(presentation.recentUIReviewFeedTitle == "最近 UI 审查")
        #expect(presentation.recentActionFeedTitle == "提醒中心")
    }

    @Test
    func mapDropsDrillDownWhenSelectionDoesNotMatch() {
        let overview = SupervisorPortfolioOverviewPresentation(
            iconName: "square.stack.3d.up",
            iconTone: .neutral,
            title: "项目总览",
            statusLine: "portfolio=idle",
            countBadges: [],
            metricBadgeRows: [],
            projectNotificationLine: nil,
            infrastructureStatusLine: nil,
            infrastructureTransitionLine: nil,
            emptyStateText: "empty",
            todayQueue: nil,
            closeOutQueue: nil,
            criticalQueue: nil
        )
        let drillDown = SupervisorProjectDrillDownSnapshot.denied(
            projectId: "project-1",
            projectName: "Project 1",
            status: .deniedProjectInvisible,
            requestedScope: .capsuleOnly,
            denyReason: "not_visible"
        )

        let presentation = SupervisorPortfolioBoardPresentationMapper.map(
            overview: overview,
            projectRows: [],
            uiReviewActivityRows: [],
            actionEventRows: [],
            selectedProjectID: "project-2",
            lastDrillDownSnapshot: drillDown
        )

        #expect(presentation.projectRows.isEmpty)
        #expect(presentation.uiReviewActivityRows.isEmpty)
        #expect(presentation.actionEventRows.isEmpty)
        #expect(presentation.activeDrillDown == nil)
        #expect(presentation.recentUIReviewFeedTitle == nil)
        #expect(presentation.recentActionFeedTitle == nil)
        #expect(presentation.overview.emptyStateText == "empty")
    }
}
