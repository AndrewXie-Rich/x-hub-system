import Foundation
import Testing
@testable import XTerminal

struct SupervisorCandidateReviewPresentationTests {

    @Test
    func boardBuildsSnapshotSummaryAndEmptyState() {
        let presentation = SupervisorCandidateReviewPresentation.board(
            items: [],
            source: "",
            hasFreshSnapshot: false,
            updatedAt: 0,
            inFlightRequestIDs: [],
            hubInteractive: false,
            projectNamesByID: [:],
            focusedRowAnchor: nil,
            now: 1_000
        )

        #expect(presentation.iconName == "tray")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "Supervisor 候选记忆审查：0")
        #expect(presentation.snapshotText == "来源：Hub · 快照偏旧")
        #expect(presentation.freshnessWarningText?.isEmpty == false)
        #expect(presentation.footerNote == nil)
        #expect(presentation.emptyStateText == "当前没有待转入审查的候选记忆。")
        #expect(presentation.isEmpty)
    }

    @Test
    func rowBuildsProjectScopeStateAndStageAction() {
        let item = HubIPCClient.SupervisorCandidateReviewItem(
            schemaVersion: "v1",
            reviewId: "review-1",
            requestId: "req-1",
            evidenceRef: "audit://evidence/1",
            reviewState: "pending_review",
            durablePromotionState: "candidate_only",
            promotionBoundary: "project",
            deviceId: "device-1",
            userId: "user-1",
            appId: "xt",
            threadId: "thread-1",
            threadKey: "thread-key-1",
            projectId: "project-alpha",
            projectIds: [],
            scopes: ["project_memory", "personal_memory"],
            recordTypes: ["canonical", "working_set"],
            auditRefs: ["audit-1"],
            idempotencyKeys: ["idem-1"],
            candidateCount: 3,
            summaryLine: "归并了 3 条高信号候选记忆",
            mirrorTarget: "xt_local_store",
            localStoreRole: "supervisor_memory_store",
            carrierKind: "review_bundle",
            carrierSchemaVersion: "v1",
            pendingChangeId: "draft-1",
            pendingChangeStatus: "draft_open",
            editSessionId: "session-1",
            docId: "doc-1",
            writebackRef: "writeback-1",
            stageCreatedAtMs: 0,
            stageUpdatedAtMs: 0,
            latestEmittedAtMs: 960_000,
            createdAtMs: 940_000,
            updatedAtMs: 960_000
        )

        let row = SupervisorCandidateReviewPresentation.row(
            item,
            inFlightRequestIDs: ["req-1"],
            hubInteractive: true,
            projectNamesByID: ["project-alpha": "Project Alpha"],
            isFocused: true,
            now: 1_000
        )

        #expect(row.anchorID == SupervisorFocusPresentation.candidateReviewRowAnchor(item))
        #expect(row.title.contains("Project Alpha"))
        #expect(row.title.contains("3 条候选记忆"))
        #expect(row.ageText == "刚刚")
        #expect(row.summary == "归并了 3 条高信号候选记忆")
        #expect(row.reviewStateText == "状态：待转入审查")
        #expect(row.scopeText?.contains("项目：Project Alpha") == true)
        #expect(row.scopeText?.contains("scope：project_memory, personal_memory") == true)
        #expect(row.scopeText?.contains("records：canonical, working_set") == true)
        #expect(row.draftText == "draft：draft-1 · status=draft_open")
        #expect(row.evidenceText == "handoff：req-1 · evidence=audit://evidence/1")
        #expect(row.isFocused)
        #expect(row.isInFlight)
        #expect(row.actionDescriptors.map(\.label) == ["转入审查"])
        #expect(row.actionDescriptors[0].isEnabled == false)
    }
}
