import Foundation
import Testing
@testable import XTerminal

@MainActor
struct ChatSessionModelRecentContextTests {

    @Test
    func defaultRecentPromptWindowUsesEightTurns() {
        let session = ChatSessionModel()

        #expect(session.recentPromptTurnLimitForTesting(userText: "继续写这个功能") == 16)
        #expect(session.recentPromptTurnLimitForTesting(userText: "请分析当前实现") == 8)
        #expect(
            session.recentPromptTurnLimitForTesting(
                userText: "普通新请求",
                expandRecentOnceAfterLoad: true
            ) == 16
        )
    }

    @Test
    func recentConversationPreviewKeepsEightTurnsByDefault() {
        let session = ChatSessionModel()
        session.messages = makeTurns(count: 10)

        let preview = session.recentConversationForTesting(userText: "新的问题", maxTurns: 8)

        let lines = Set(preview.split(separator: "\n").map(String.init))
        #expect(!lines.contains("user: user-1"))
        #expect(!lines.contains("assistant: assistant-2"))
        #expect(lines.contains("user: user-3"))
        #expect(lines.contains("assistant: assistant-10"))
    }

    @Test
    func projectMemoryRetrievalTriggersOnlyForHistoryOrSpecQueries() {
        let session = ChatSessionModel()

        #expect(session.shouldRequestProjectMemoryRetrievalForTesting(userText: "你能把我之前说过的话再总结一下吗"))
        #expect(session.shouldRequestProjectMemoryRetrievalForTesting(userText: "这个项目的 tech stack 决策是什么"))
        #expect(session.shouldRequestProjectMemoryRetrievalForTesting(userText: "展开 memory://decision/proj-1/approved-stack"))
        #expect(!session.shouldRequestProjectMemoryRetrievalForTesting(userText: "继续修当前编译错误"))
    }

    @Test
    func projectMemoryRetrievalFormattingSurfacesDenyAndTruncationMetadata() {
        let session = ChatSessionModel()

        let denied = session.formattedProjectMemoryRetrievalBlockForTesting(
            response: HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_retrieval",
                scope: "current_project",
                auditRef: "audit-denied-1",
                reasonCode: "scope_gate",
                denyCode: "cross_scope_memory_denied",
                snippets: [],
                truncatedItems: 0,
                redactedItems: 0
            )
        )
        let truncated = session.formattedProjectMemoryRetrievalBlockForTesting(
            response: HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_retrieval",
                scope: "current_project",
                auditRef: "audit-truncated-1",
                reasonCode: nil,
                denyCode: nil,
                snippets: [
                    HubIPCClient.MemoryRetrievalSnippet(
                        snippetId: "snippet-1",
                        sourceKind: "decision_track",
                        title: "approved stack",
                        ref: "memory://decision/proj/1",
                        text: "Use Swift + governed Hub memory.",
                        score: 96,
                        truncated: false
                    )
                ],
                truncatedItems: 2,
                redactedItems: 1
            )
        )

        #expect(denied?.contains("status=denied") == true)
        #expect(denied?.contains("audit_ref=audit-denied-1") == true)
        #expect(denied?.contains("reason_code=scope_gate") == true)
        #expect(denied?.contains("deny_code=cross_scope_memory_denied") == true)
        #expect(truncated?.contains("status=truncated") == true)
        #expect(truncated?.contains("audit_ref=audit-truncated-1") == true)
        #expect(truncated?.contains("truncated_items=2") == true)
        #expect(truncated?.contains("redacted_items=1") == true)
        #expect(truncated?.contains("[decision_track] approved stack") == true)
    }

    @Test
    func projectMemoryRetrievalPromotesExplicitRefQueriesToStageTwo() {
        let session = ChatSessionModel()
        let ref = "memory://decision/proj-1/approved-stack"

        #expect(session.projectMemoryRetrievalStageForTesting(userText: "展开 \(ref) 的详情") == "stage2_explicit_ref_read")
        #expect(session.projectMemoryExplicitRefsForTesting(userText: "展开 \(ref) 的详情") == [ref])

        let block = session.formattedProjectMemoryRetrievalBlockForTesting(
            response: HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_retrieval",
                scope: "current_project",
                auditRef: "audit-ref-1",
                snippets: [
                    HubIPCClient.MemoryRetrievalSnippet(
                        snippetId: "snippet-explicit-1",
                        sourceKind: "decision_track",
                        title: "approved stack ref",
                        ref: ref,
                        text: "Formal decision text for the approved stack.",
                        score: 97,
                        truncated: false
                    )
                ],
                truncatedItems: 0,
                redactedItems: 0
            ),
            retrievalStage: "stage2_explicit_ref_read",
            explicitRefs: [ref]
        )

        #expect(block?.contains("retrieval_stage=stage2_explicit_ref_read") == true)
        #expect(block?.contains("explicit_refs=\(ref)") == true)
        #expect(block?.contains("summary_insufficient=true") == false)
    }

    @Test
    func projectMemoryServingProfileEscalatesForStructureReviewAndRefactorPlanning() {
        let session = ChatSessionModel()

        #expect(
            session.preferredProjectMemoryServingProfileForTesting(
                userText: "梳理项目结构并给出重构建议"
            ) == .m2PlanReview
        )
        #expect(
            session.preferredProjectMemoryServingProfileForTesting(
                userText: "先完整通读整个仓库，再给我架构重构路径"
            ) == .m3DeepDive
        )
        #expect(
            session.preferredProjectMemoryServingProfileForTesting(
                userText: "继续修当前编译错误"
            ) == nil
        )
    }

    @Test
    func localProjectMemoryFallbackIncludesServingProfileAndExpandedCanonicalForReview() {
        let session = ChatSessionModel()
        let longCanonical = String(repeating: "c", count: 3_500)

        let reviewBlock = session.projectMemoryBlockForTesting(
            canonicalMemory: longCanonical,
            recentText: "recent",
            userText: "梳理项目结构并给出重构建议"
        )
        let executeBlock = session.projectMemoryBlockForTesting(
            canonicalMemory: longCanonical,
            recentText: "recent",
            userText: "继续修当前编译错误"
        )

        #expect(reviewBlock.contains("[SERVING_PROFILE]"))
        #expect(reviewBlock.contains("[LONGTERM_MEMORY]"))
        #expect(reviewBlock.contains("longterm_mode=summary_only"))
        #expect(reviewBlock.contains("retrieval_available=false"))
        #expect(reviewBlock.contains("fulltext_not_loaded=true"))
        #expect(reviewBlock.contains("profile_id: m2_plan_review"))
        #expect(reviewBlock.contains(longCanonical))
        #expect(!executeBlock.contains(longCanonical))
    }

    @Test
    func projectMemoryBlockIncludesPendingSupervisorGuidance() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-memory-guidance")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-project-memory-1",
                reviewId: "review-project-memory-1",
                projectId: "proj-project-memory-1",
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "先重新对齐 done definition，再开始重构。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_380_000_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-project-memory-1"
            ),
            for: ctx
        )

        let block = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "goal: improve review loop",
            recentText: "recent",
            userText: "继续推进当前实现"
        )

        #expect(block.contains("[pending_supervisor_guidance]"))
        #expect(block.contains("injection_id: guidance-project-memory-1"))
        #expect(block.contains("ack_status: pending"))
        #expect(block.contains("lifecycle: active"))
        #expect(block.contains("guidance_text:"))
        #expect(block.contains("先重新对齐 done definition，再开始重构。"))
    }

    @Test
    func explicitSupervisorGuidanceAckPersistsRejectedStatus() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-ack-rejected")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-ack-rejected-1",
                reviewId: "review-ack-rejected-1",
                projectId: "proj-ack-rejected-1",
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "改成更稳的 replan 路线。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_381_000_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-ack-rejected-1"
            ),
            for: ctx
        )

        session.applySupervisorGuidanceAckForTesting(
            ctx: ctx,
            envelope: ToolActionEnvelope(
                tool_calls: nil,
                final: "当前先不采纳这条 guidance。",
                guidance_ack: ToolGuidanceAckPayload(
                    injection_id: "guidance-ack-rejected-1",
                    status: .rejected,
                    note: "Conflicts with the approved migration boundary."
                )
            )
        )

        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.ackStatus == .rejected)
        #expect(updated.ackNote == "Conflicts with the approved migration boundary.")
    }

    @Test
    func executableEnvelopeAutoAcceptsPendingSupervisorGuidance() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-ack-auto")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-ack-auto-1",
                reviewId: "review-ack-auto-1",
                projectId: "proj-ack-auto-1",
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .nextToolBoundary,
                guidanceText: "先读取当前 diff，再决定是否重构。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_382_000_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-ack-auto-1"
            ),
            for: ctx
        )

        session.applySupervisorGuidanceAckForTesting(
            ctx: ctx,
            envelope: ToolActionEnvelope(
                tool_calls: [
                    ToolCall(
                        id: "read-diff",
                        tool: .git_diff,
                        args: [:]
                    )
                ],
                final: nil,
                guidance_ack: nil
            ),
            visiblePendingGuidanceInjectionId: "guidance-ack-auto-1"
        )

        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.ackStatus == .accepted)
        #expect(updated.ackNote == "auto_accepted_from_executable_result")
    }

    @Test
    func executableEnvelopeDoesNotAutoAcceptGuidanceBeforeSafePointVisibility() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-ack-not-visible")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-ack-not-visible-1",
                reviewId: "review-ack-not-visible-1",
                projectId: "proj-ack-not-visible-1",
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "下一 planning step 再切到 replan。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_382_100_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-ack-not-visible-1"
            ),
            for: ctx
        )

        session.applySupervisorGuidanceAckForTesting(
            ctx: ctx,
            envelope: ToolActionEnvelope(
                tool_calls: [
                    ToolCall(
                        id: "read-current-state",
                        tool: .read_file,
                        args: ["path": .string("README.md")]
                    )
                ],
                final: nil,
                guidance_ack: nil
            ),
            visiblePendingGuidanceInjectionId: nil
        )

        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.ackStatus == .pending)
        #expect(updated.ackNote.isEmpty)
    }

    @Test
    func immediateGuidancePausesToolExecutionUntilPromptHasSeenIt() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-immediate-pause")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-immediate-pause-1",
                reviewId: "review-immediate-pause-1",
                projectId: "proj-immediate-pause-1",
                targetRole: .coder,
                deliveryMode: .stopSignal,
                interventionMode: .stopImmediately,
                safePointPolicy: .immediate,
                guidanceText: "立刻停下，先重看方案。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_382_200_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-immediate-pause-1"
            ),
            for: ctx
        )

        let unseenPause = session.pendingSupervisorGuidancePauseBeforeToolExecutionForTesting(
            ctx: ctx,
            runStartedAtMs: 1_773_382_100_000,
            step: 1,
            toolResultsCount: 0
        )
        let seenPause = session.pendingSupervisorGuidancePauseBeforeToolExecutionForTesting(
            ctx: ctx,
            runStartedAtMs: 1_773_382_100_000,
            step: 1,
            toolResultsCount: 0,
            lastPromptVisibleGuidanceInjectionId: "guidance-immediate-pause-1"
        )

        #expect(unseenPause == "guidance-immediate-pause-1")
        #expect(seenPause == nil)
    }

    @Test
    func slashGuidanceShowsAndManuallyAcceptsPendingGuidance() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-slash")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-slash-1",
                reviewId: "review-slash-1",
                projectId: "proj-slash-1",
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .nextToolBoundary,
                guidanceText: "先看当前 blocker，再决定是否继续 patch。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_383_000_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-slash-1"
            ),
            for: ctx
        )

        let status = session.handleSlashGuidanceForTesting(args: [], ctx: ctx)
        #expect(status.contains("pending guidance:"))
        #expect(status.contains("guidance-slash-1"))
        #expect(status.contains("lifecycle: active"))

        let accept = session.handleSlashGuidanceForTesting(
            args: ["accept", "manual", "operator", "ok"],
            ctx: ctx
        )
        #expect(accept.contains("已更新 guidance ack"))

        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.ackStatus == .accepted)
        #expect(updated.ackNote == "manual operator ok")
    }

    @Test
    func guidanceAckLatestBlockIncludesAckNote() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-ack-note")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-ack-note-1",
                reviewId: "review-ack-note-1",
                projectId: "proj-ack-note-1",
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "改成更稳的 replan 路线。",
                ackStatus: .rejected,
                ackRequired: true,
                ackNote: "Need extra evidence before moving the migration boundary.",
                injectedAtMs: 1_773_384_000_000,
                ackUpdatedAtMs: 1_773_384_000_100,
                auditRef: "audit-guidance-ack-note-1"
            ),
            for: ctx
        )

        let block = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "goal: improve review loop",
            recentText: "recent",
            userText: "继续推进当前实现"
        )

        #expect(block.contains("[latest_supervisor_guidance]"))
        #expect(block.contains("ack_status: rejected"))
        #expect(block.contains("ack_note: Need extra evidence before moving the migration boundary."))
        #expect(block.contains("lifecycle: settled"))
    }

    @Test
    func projectMemoryBlockRespectsSafePointDeliveryWindow() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-safe-point-window")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-safe-point-window-1",
                reviewId: "review-safe-point-window-1",
                projectId: "proj-safe-point-window-1",
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "下一 planning step 再插入。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 200,
                ackUpdatedAtMs: 0,
                auditRef: "audit-safe-point-window-1"
            ),
            for: ctx
        )

        let firstStep = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "goal: improve review loop",
            recentText: "recent",
            userText: "继续推进当前实现",
            safePointState: SupervisorSafePointExecutionState(
                runStartedAtMs: 100,
                flowStep: 1,
                toolResultsCount: 0,
                verifyRunIndex: 0,
                finalizeOnly: false
            )
        )
        let secondStep = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "goal: improve review loop",
            recentText: "recent",
            userText: "继续推进当前实现",
            safePointState: SupervisorSafePointExecutionState(
                runStartedAtMs: 100,
                flowStep: 2,
                toolResultsCount: 0,
                verifyRunIndex: 0,
                finalizeOnly: false
            )
        )

        #expect(!firstStep.contains("[pending_supervisor_guidance]"))
        #expect(secondStep.contains("[pending_supervisor_guidance]"))
        #expect(secondStep.contains("guidance-safe-point-window-1"))
    }

    private func makeTurns(count: Int) -> [AXChatMessage] {
        var out: [AXChatMessage] = []
        for index in 1...count {
            let base = Double(index * 10)
            out.append(AXChatMessage(role: .user, content: "user-\(index)", createdAt: base))
            out.append(AXChatMessage(role: .assistant, content: "assistant-\(index)", createdAt: base + 1))
        }
        return out
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
