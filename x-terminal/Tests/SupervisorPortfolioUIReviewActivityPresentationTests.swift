import Foundation
import Testing
@testable import XTerminal

struct SupervisorPortfolioUIReviewActivityPresentationTests {

    @Test
    func mapBuildsRecentUIReviewActivityWithTrendSummary() {
        let review = XTUIReviewPresentation(
            reviewRef: "local://.xterminal/ui_review/reviews/project-alpha.json",
            bundleRef: "local://.xterminal/ui_observation/bundles/project-alpha.json",
            verdict: .attentionNeeded,
            confidence: .medium,
            sufficientEvidence: true,
            objectiveReady: false,
            issueCodes: ["critical_action_not_visible", "interactive_target_missing"],
            summary: "attention needed",
            updatedAtMs: 120_000,
            interactiveTargetCount: 0,
            criticalActionExpected: true,
            criticalActionVisible: false,
            checks: [],
            reviewFileURL: nil,
            bundleFileURL: nil,
            screenshotFileURL: nil,
            visibleTextFileURL: nil,
            recentHistory: [],
            trend: XTUIReviewTrendPresentation(
                status: .regressed,
                headline: "较上次退化",
                detail: "问题数 0 -> 2"
            ),
            comparison: XTUIReviewDiffPresentation(
                addedIssueLabels: ["未看到关键操作", "未识别可交互目标"],
                resolvedIssueLabels: ["核心检查通过"],
                metrics: []
            )
        )

        let presentation = SupervisorPortfolioUIReviewActivityPresentationMapper.map(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            review: review,
            now: Date(timeIntervalSince1970: 180)
        )

        #expect(presentation.id == "ui-review:project-alpha")
        #expect(presentation.projectId == "project-alpha")
        #expect(presentation.projectName == "Project Alpha")
        #expect(presentation.statusLine == "需关注 · 证据充分")
        #expect(presentation.summaryLine == "未看到关键操作 · 未识别可交互目标")
        #expect(presentation.detailLine == "较上次退化 · 新增 2 项 · 解决 1 项")
        #expect(presentation.updatedText == "1分钟前")
        #expect(presentation.screenshotFileURL == nil)
        #expect(presentation.tone == .warning)
    }

    @Test
    func mapKeepsStableRowIdentityAcrossNewReviewArtifacts() {
        let first = XTUIReviewPresentation(
            reviewRef: "local://reviews/project-alpha-v1.json",
            bundleRef: "local://bundles/project-alpha-v1.json",
            verdict: .ready,
            confidence: .high,
            sufficientEvidence: true,
            objectiveReady: true,
            issueCodes: [],
            summary: "ready",
            updatedAtMs: 60_000,
            interactiveTargetCount: 3,
            criticalActionExpected: true,
            criticalActionVisible: true,
            checks: [],
            reviewFileURL: nil,
            bundleFileURL: nil,
            screenshotFileURL: nil,
            visibleTextFileURL: nil,
            recentHistory: [],
            trend: nil,
            comparison: nil
        )
        let second = XTUIReviewPresentation(
            reviewRef: "local://reviews/project-alpha-v2.json",
            bundleRef: "local://bundles/project-alpha-v2.json",
            verdict: .attentionNeeded,
            confidence: .medium,
            sufficientEvidence: true,
            objectiveReady: false,
            issueCodes: ["critical_action_not_visible"],
            summary: "attention needed",
            updatedAtMs: 120_000,
            interactiveTargetCount: 1,
            criticalActionExpected: true,
            criticalActionVisible: false,
            checks: [],
            reviewFileURL: nil,
            bundleFileURL: nil,
            screenshotFileURL: nil,
            visibleTextFileURL: nil,
            recentHistory: [],
            trend: nil,
            comparison: nil
        )

        let firstPresentation = SupervisorPortfolioUIReviewActivityPresentationMapper.map(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            review: first,
            now: Date(timeIntervalSince1970: 180)
        )
        let secondPresentation = SupervisorPortfolioUIReviewActivityPresentationMapper.map(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            review: second,
            now: Date(timeIntervalSince1970: 180)
        )

        #expect(firstPresentation.id == "ui-review:project-alpha")
        #expect(secondPresentation.id == "ui-review:project-alpha")
        #expect(firstPresentation.id == secondPresentation.id)
        #expect(firstPresentation.summaryLine == "核心检查通过")
        #expect(secondPresentation.summaryLine == "未看到关键操作")
    }
}
