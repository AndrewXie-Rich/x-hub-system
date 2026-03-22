import Foundation
import Testing
@testable import XTerminal

struct SupervisorPendingHubGrantPresentationTests {

    @Test
    func boardBuildsSnapshotSummaryAndEmptyState() {
        let presentation = SupervisorPendingHubGrantPresentation.board(
            grants: [],
            source: "",
            hasFreshSnapshot: false,
            updatedAt: 0,
            inFlightGrantIDs: [],
            hubInteractive: false,
            focusedRowAnchor: nil,
            now: 1_000
        )

        #expect(presentation.iconName == "checkmark.shield")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "Hub 待处理授权：0")
        #expect(presentation.snapshotText == "来源：Hub · 快照偏旧")
        #expect(presentation.freshnessWarningText?.isEmpty == false)
        #expect(presentation.footerNote == nil)
        #expect(presentation.emptyStateText == "当前没有待审批的 Hub 授权。")
        #expect(presentation.isEmpty)
    }

    @Test
    func rowBuildsFocusInflightAndActions() {
        let grant = SupervisorManager.SupervisorPendingGrant(
            id: "grant-1",
            dedupeKey: "grant:key",
            grantRequestId: "req-1",
            requestId: "skill-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            capability: "browser.control",
            modelId: "gpt-5.4",
            reason: "browser automation requested",
            requestedTtlSec: 600,
            requestedTokenCap: 4000,
            createdAt: 940,
            actionURL: "x-terminal://supervisor?grant=req-1",
            priorityRank: 1,
            priorityReason: "critical path",
            nextAction: "approve now"
        )

        let row = SupervisorPendingHubGrantPresentation.row(
            grant,
            inFlightGrantIDs: ["req-1"],
            hubInteractive: true,
            isFocused: true,
            now: 1_000
        )

        #expect(row.anchorID == SupervisorFocusPresentation.pendingHubGrantRowAnchor(grant))
        #expect(row.title.contains("P1"))
        #expect(row.title.contains("Project Alpha"))
        #expect(row.ageText == "刚刚")
        #expect(row.summary.isEmpty == false)
        #expect(row.supplementaryReasonText?.contains("原因：") == true)
        #expect(row.priorityReasonText == "优先级解释：critical path")
        #expect(row.nextActionText == "建议动作：approve now")
        #expect(row.scopeSummaryText?.isEmpty == false)
        #expect(row.grantIdentifierText == "授权单号：req-1")
        #expect(row.isFocused)
        #expect(row.isInFlight)
        #expect(row.actionDescriptors.map(\.label) == ["详情", "打开", "批准", "拒绝"])
        #expect(row.actionDescriptors[2].isEnabled == false)
    }

    @Test
    func snapshotTextIncludesUpdatedAgeWhenPresent() {
        let text = SupervisorPendingHubGrantPresentation.snapshotText(
            source: "hub-live",
            hasFreshSnapshot: true,
            updatedAt: 940,
            now: 1_000
        )

        #expect(text == "来源：hub-live · 更新 刚刚 · 快照新鲜")
    }
}
