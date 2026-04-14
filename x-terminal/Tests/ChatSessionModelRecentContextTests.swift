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
    func projectMemoryBlockIncludesEligibleHeartbeatDigestWorkingSet() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-memory-heartbeat-working-set")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-memory-heartbeat",
            updatedAtMs: 1_778_840_120_000,
            lastHeartbeatAtMs: 1_778_840_120_000,
            lastObservedProgressAtMs: 1_778_840_000_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 1_778_840_420_000,
            nextPulseReviewDueAtMs: 1_778_840_900_000,
            nextBrainstormReviewDueAtMs: 1_778_841_800_000,
            latestQualitySnapshot: nil,
            openAnomalies: [],
            lastHeartbeatFingerprint: "hb-project-memory-working-set",
            lastHeartbeatRepeatCount: 1,
            latestProjectPhase: .build,
            latestExecutionStatus: .active,
            latestRiskTier: .low
        )
        let readiness = XTProjectMemoryAssemblyReadiness(
            ready: false,
            statusLine: "attention:project_memory_usage_missing",
            issues: [
                XTProjectMemoryAssemblyIssue(
                    code: "project_memory_usage_missing",
                    severity: .warning,
                    summary: "尚未捕获 Project AI 的最近一次 memory 装配真相",
                    detail: "Doctor 当前只有配置基线，还没有 recent coder usage 来证明本轮 Project AI 实际拿到了哪些 memory objects / planes。"
                )
            ]
        )
        let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-memory-heartbeat",
            projectName: "Memory Heartbeat",
            statusDigest: "runtime stable but coder memory truth is still sparse",
            currentStateSummary: "Build is active",
            nextStepSummary: "Wait for the next coder usage sync",
            blockerSummary: "",
            lastHeartbeatAtMs: schedule.lastHeartbeatAtMs,
            latestQualityBand: .strong,
            latestQualityScore: 89,
            weakReasons: ["project_memory_attention"],
            openAnomalyTypes: [],
            projectPhase: .build,
            executionStatus: .active,
            riskTier: .low,
            cadence: makeHeartbeatCadence(),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .shown,
                reasonCodes: ["project_memory_attention"],
                whatChangedText: "Project AI memory truth still needs attention.",
                whyImportantText: "Doctor 还不能确认最近一轮 coder 真正吃到了哪些 project memory。",
                systemNextStepText: "系统会继续等待下一轮 recent coder usage 补齐 machine-readable truth。"
            ),
            recoveryDecision: nil,
            projectMemoryReadiness: readiness
        )
        let canonical = SupervisorProjectHeartbeatCanonicalSync.record(
            snapshot: snapshot,
            generatedAtMs: schedule.updatedAtMs
        )
        let artifact = try #require(
            XTHeartbeatMemoryProjectionStore.record(
                ctx: ctx,
                snapshot: snapshot,
                schedule: schedule,
                canonicalRecord: canonical,
                generatedAtMs: schedule.updatedAtMs
            )
        )

        #expect(artifact.workingSetProjection.eligible)

        let block = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "goal: tighten project memory continuity",
            recentText: "retrieved decision: keep Hub-first durable truth",
            userText: "继续推进当前实现"
        )

        #expect(block.contains("[heartbeat_digest]"))
        #expect(block.contains("reason_codes: project_memory_attention"))
        #expect(block.contains("what_changed: Project AI memory truth still needs attention."))
        #expect(block.contains("system_next_step: 系统会继续等待下一轮 recent coder usage 补齐 machine-readable truth。"))
        #expect(block.contains("retrieved decision: keep Hub-first durable truth"))
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
    func stopSignalGuidancePromptIncludesExecutionGateAndRouteMetadata() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-stop-signal-prompt")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-stop-signal-prompt-1",
                reviewId: "review-stop-signal-prompt-1",
                projectId: "proj-stop-signal-prompt-1",
                targetRole: .projectChat,
                deliveryMode: .stopSignal,
                interventionMode: .stopImmediately,
                safePointPolicy: .immediate,
                guidanceText: """
source=ui_review_repair
repair_action=repair_primary_cta_visibility
next_safe_action=open_ui_review
""",
                ackStatus: .pending,
                ackRequired: true,
                effectiveSupervisorTier: .s4TightSupervision,
                effectiveWorkOrderDepth: .stepLockedRescue,
                workOrderRef: "plan:plan-ui-review-safe-next-action-v1",
                ackNote: "",
                injectedAtMs: 1_773_382_210_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-stop-signal-prompt-1"
            ),
            for: ctx
        )

        let block = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "goal: recover browser flow safely",
            recentText: "recent",
            userText: "继续推进当前实现",
            safePointState: SupervisorSafePointExecutionState(
                runStartedAtMs: 1_773_382_100_000,
                flowStep: 1,
                toolResultsCount: 0,
                verifyRunIndex: 0,
                finalizeOnly: false
            )
        )

        #expect(block.contains("[pending_supervisor_guidance]"))
        #expect(block.contains("target_role: project_chat"))
        #expect(block.contains("effective_supervisor_tier: s4_tight_supervision"))
        #expect(block.contains("effective_work_order_depth: step_locked_rescue"))
        #expect(block.contains("work_order_ref: plan:plan-ui-review-safe-next-action-v1"))
        #expect(block.contains("execution_gate: final_only_until_ack"))
        #expect(block.contains("repair_action=repair_primary_cta_visibility"))
        #expect(block.contains("next_safe_action=open_ui_review"))
    }

    @Test
    func visibleStopSignalGuidanceGateStripsExecutableCallsWhenFinalIsPresent() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-stop-signal-final-only")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-stop-signal-final-only-1",
                reviewId: "review-stop-signal-final-only-1",
                projectId: "proj-stop-signal-final-only-1",
                targetRole: .projectChat,
                deliveryMode: .stopSignal,
                interventionMode: .stopImmediately,
                safePointPolicy: .immediate,
                guidanceText: "立刻停下，先返回 UI review 并重规划。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_382_220_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-stop-signal-final-only-1"
            ),
            for: ctx
        )

        let gated = session.applyProjectSupervisorGuidanceEnvelopeGateForTesting(
            ctx: ctx,
            envelope: ToolActionEnvelope(
                tool_calls: [
                    ToolCall(
                        id: "read-state",
                        tool: .read_file,
                        args: ["path": .string("README.md")]
                    )
                ],
                skill_calls: [
                    GovernedSkillCall(
                        id: "skill-1",
                        skill_id: "agent-browser",
                        payload: ["action": .string("continue")]
                    )
                ],
                final: "先停下当前自动化，回到 UI Review 检查缺失的 CTA。",
                guidance_ack: ToolGuidanceAckPayload(
                    injection_id: "guidance-stop-signal-final-only-1",
                    status: .accepted,
                    note: "Stopping now and switching to UI review."
                )
            ),
            visiblePendingGuidanceInjectionId: "guidance-stop-signal-final-only-1"
        )

        #expect(!gated.requiresFinalOnly)
        #expect(gated.toolCallCount == 0)
        #expect(gated.skillCallCount == 0)
        #expect(gated.final == "先停下当前自动化，回到 UI Review 检查缺失的 CTA。")
    }

    @Test
    func visibleStopSignalGuidanceGateRequiresFinalOnlyWhenEnvelopeStillRequestsTools() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-stop-signal-tool-only")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-stop-signal-tool-only-1",
                reviewId: "review-stop-signal-tool-only-1",
                projectId: "proj-stop-signal-tool-only-1",
                targetRole: .projectChat,
                deliveryMode: .stopSignal,
                interventionMode: .stopImmediately,
                safePointPolicy: .immediate,
                guidanceText: "先暂停新的工具执行，只输出停机和重规划说明。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_382_230_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-stop-signal-tool-only-1"
            ),
            for: ctx
        )

        let gated = session.applyProjectSupervisorGuidanceEnvelopeGateForTesting(
            ctx: ctx,
            envelope: ToolActionEnvelope(
                tool_calls: [
                    ToolCall(
                        id: "continue-read",
                        tool: .read_file,
                        args: ["path": .string("README.md")]
                    )
                ],
                final: nil,
                guidance_ack: ToolGuidanceAckPayload(
                    injection_id: "guidance-stop-signal-tool-only-1",
                    status: .accepted,
                    note: "Will keep going."
                )
            ),
            visiblePendingGuidanceInjectionId: "guidance-stop-signal-tool-only-1"
        )

        #expect(gated.requiresFinalOnly)
        #expect(gated.guidanceInjectionId == "guidance-stop-signal-tool-only-1")
        #expect(gated.toolCallCount == 0)
        #expect(gated.skillCallCount == 0)
        #expect(gated.final == nil)
    }

    @Test
    func uiReviewRepairFinalizeOnlyInstructionsExposeStructuredRepairTemplate() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-ui-repair-template")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try insertPendingUIReviewRepairGuidance(
            ctx: ctx,
            injectionId: "guidance-ui-repair-template-1",
            reviewId: "review-ui-repair-template-1",
            projectId: "proj-ui-repair-template-1"
        )

        let instructions = session.projectSupervisorFinalizeOnlyResponseContractInstructionsForTesting(
            ctx: ctx,
            visiblePendingGuidanceInjectionId: "guidance-ui-repair-template-1"
        )

        #expect(instructions.contains("Active UI repair contract detected"))
        #expect(instructions.contains("repair_action=repair_primary_cta_visibility"))
        #expect(instructions.contains("repair_focus=critical_action"))
        #expect(instructions.contains("next_safe_action=open_ui_review"))
        #expect(instructions.contains("ui_review_ref=local://.xterminal/ui_review/agent_evidence/review-ui-repair-template-1.json"))
        #expect(instructions.contains("instruction=Restore a visible primary CTA before rerunning UI review."))
    }

    @Test
    func uiReviewRepairFinalNormalizationAddsStructuredRepairHandoffWhenModelOmitsAnchors() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-ui-repair-final")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try insertPendingUIReviewRepairGuidance(
            ctx: ctx,
            injectionId: "guidance-ui-repair-final-1",
            reviewId: "review-ui-repair-final-1",
            projectId: "proj-ui-repair-final-1"
        )

        let normalized = try #require(
            session.normalizedProjectSupervisorFinalForTesting(
                final: "先停下当前自动化，先回到页面检查后再继续。",
                ctx: ctx,
                visiblePendingGuidanceInjectionId: "guidance-ui-repair-final-1"
            )
        )

        #expect(normalized.contains("这次先别继续自动化，先把当前 UI 问题处理掉。"))
        #expect(normalized.contains("先处理的重点："))
        #expect(normalized.contains("- 修复动作：修复主操作按钮可见性（repair_primary_cta_visibility）"))
        #expect(normalized.contains("- 修复焦点：关键操作入口（critical_action）"))
        #expect(normalized.contains("- 安全下一步：打开 UI 审查（open_ui_review）"))
        #expect(normalized.contains("- UI 审查引用：local://.xterminal/ui_review/agent_evidence/review-ui-repair-final-1.json"))
        #expect(normalized.contains("- 处理说明：Restore a visible primary CTA before rerunning UI review."))
        #expect(normalized.contains("接下来先这样处理："))
        #expect(normalized.contains("先停下当前自动化，先回到页面检查后再继续。"))
        #expect(!normalized.contains("当前重规划："))
    }

    @Test
    func visibleStopSignalGuidanceGateWritesAuditRowWhenExecutableCallsAreStripped() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-stop-signal-audit")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try insertPendingUIReviewRepairGuidance(
            ctx: ctx,
            injectionId: "guidance-ui-repair-audit-1",
            reviewId: "review-ui-repair-audit-1",
            projectId: "proj-ui-repair-audit-1"
        )

        let gated = session.applyProjectSupervisorGuidanceEnvelopeGateForTesting(
            ctx: ctx,
            envelope: ToolActionEnvelope(
                tool_calls: [
                    ToolCall(
                        id: "continue-read",
                        tool: .read_file,
                        args: ["path": .string("README.md")]
                    )
                ],
                skill_calls: [
                    GovernedSkillCall(
                        id: "skill-continue",
                        skill_id: "agent-browser",
                        payload: ["action": .string("continue")]
                    )
                ],
                final: "先停下，回到 UI review。",
                guidance_ack: ToolGuidanceAckPayload(
                    injection_id: "guidance-ui-repair-audit-1",
                    status: .accepted,
                    note: "Stop now."
                )
            ),
            visiblePendingGuidanceInjectionId: "guidance-ui-repair-audit-1"
        )

        #expect(!gated.requiresFinalOnly)
        #expect(gated.toolCallCount == 0)
        #expect(gated.skillCallCount == 0)

        let rawEntries = try rawLogEntries(for: ctx)
        let gateEntry = try #require(rawEntries.last(where: { ($0["type"] as? String) == "supervisor_guidance_gate" }))
        #expect(gateEntry["action"] as? String == "strip_executable_calls_for_final_only")
        #expect(gateEntry["injection_id"] as? String == "guidance-ui-repair-audit-1")
        #expect(gateEntry["original_tool_call_count"] as? Int == 1)
        #expect(gateEntry["original_skill_call_count"] as? Int == 1)
        #expect(gateEntry["gated_tool_call_count"] as? Int == 0)
        #expect(gateEntry["gated_skill_call_count"] as? Int == 0)
    }

    @Test
    func grantResolutionContractAppearsInProjectMemoryForPendingGuidance() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-grant-contract")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try insertPendingGrantResolutionGuidance(
            ctx: ctx,
            reviewId: "review-grant-contract-1",
            injectionId: "guidance-grant-contract-1",
            projectId: "proj-grant-contract-1"
        )

        let block = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "goal: continue the governed workflow safely",
            recentText: "recent",
            userText: "继续推进当前实现",
            safePointState: SupervisorSafePointExecutionState(
                runStartedAtMs: 1_773_382_260_000,
                flowStep: 1,
                toolResultsCount: 0,
                verifyRunIndex: 0,
                finalizeOnly: false
            )
        )

        #expect(block.contains("[supervisor_replan_contract]"))
        #expect(block.contains("contract_kind: grant_resolution"))
        #expect(block.contains("primary_blocker: grant_required"))
        #expect(block.contains("next_safe_action: open_hub_grants"))
        #expect(block.contains("recommended_actions: Open Hub grant approval for this project | Retry the governed step after grant approval"))
        #expect(block.contains("work_order_ref: plan:plan-grant-contract-1"))
    }

    @Test
    func grantResolutionFinalizeOnlyInstructionsExposeStructuredReplanTemplate() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-grant-template")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try insertPendingGrantResolutionGuidance(
            ctx: ctx,
            reviewId: "review-grant-template-1",
            injectionId: "guidance-grant-template-1",
            projectId: "proj-grant-template-1"
        )

        let instructions = session.projectSupervisorFinalizeOnlyResponseContractInstructionsForTesting(
            ctx: ctx,
            visiblePendingGuidanceInjectionId: "guidance-grant-template-1"
        )

        #expect(instructions.contains("Active supervisor replan contract detected"))
        #expect(instructions.contains("contract_kind=grant_resolution"))
        #expect(instructions.contains("primary_blocker=grant_required"))
        #expect(instructions.contains("next_safe_action=open_hub_grants"))
        #expect(instructions.contains("work_order_ref=plan:plan-grant-template-1"))
    }

    @Test
    func grantResolutionFinalNormalizationAddsStructuredReplanHandoff() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-grant-final")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try insertPendingGrantResolutionGuidance(
            ctx: ctx,
            reviewId: "review-grant-final-1",
            injectionId: "guidance-grant-final-1",
            projectId: "proj-grant-final-1"
        )

        let normalized = try #require(
            session.normalizedProjectSupervisorFinalForTesting(
                final: "先暂停当前步骤，等待授权完成后再继续。",
                ctx: ctx,
                visiblePendingGuidanceInjectionId: "guidance-grant-final-1"
            )
        )

        #expect(normalized.contains("这次先别继续执行，先按当前重规划处理。"))
        #expect(normalized.contains("先处理的重点："))
        #expect(normalized.contains("- 指导类型：授权处理（grant_resolution）"))
        #expect(normalized.contains("- 当前阻塞：Hub 授权未完成（grant_required）"))
        #expect(normalized.contains("- 安全下一步：打开 Hub 授权面板（open_hub_grants）"))
        #expect(normalized.contains("- 工单引用：plan:plan-grant-final-1"))
        #expect(normalized.contains("- 建议动作：Open Hub grant approval for this project | Retry the governed step after grant approval"))
        #expect(normalized.contains("接下来先这样处理："))
        #expect(normalized.contains("先暂停当前步骤，等待授权完成后再继续。"))
        #expect(!normalized.contains("supervisor replan 合同"))
    }

    @Test
    func incidentRecoveryContractAppearsInProjectMemoryForPendingGuidance() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-incident-contract")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try insertPendingIncidentRecoveryGuidance(
            ctx: ctx,
            reviewId: "review-incident-contract-1",
            injectionId: "guidance-incident-contract-1",
            projectId: "proj-incident-contract-1"
        )

        let block = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "goal: recover the runtime safely",
            recentText: "recent",
            userText: "继续推进当前实现",
            safePointState: SupervisorSafePointExecutionState(
                runStartedAtMs: 1_773_382_280_000,
                flowStep: 1,
                toolResultsCount: 0,
                verifyRunIndex: 0,
                finalizeOnly: false
            )
        )

        #expect(block.contains("[supervisor_replan_contract]"))
        #expect(block.contains("contract_kind: incident_recovery"))
        #expect(block.contains("primary_blocker: runtime_error"))
        #expect(block.contains("next_safe_action: inspect_incident_and_replan"))
        #expect(block.contains("recommended_actions: Inspect the runtime failure evidence | Replan the blocked step before retry"))
    }

    @Test
    func incidentRecoveryFinalNormalizationAddsStructuredReplanHandoff() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-incident-final")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try insertPendingIncidentRecoveryGuidance(
            ctx: ctx,
            reviewId: "review-incident-final-1",
            injectionId: "guidance-incident-final-1",
            projectId: "proj-incident-final-1"
        )

        let normalized = try #require(
            session.normalizedProjectSupervisorFinalForTesting(
                final: "先停下当前执行，检查失败原因后再决定是否重试。",
                ctx: ctx,
                visiblePendingGuidanceInjectionId: "guidance-incident-final-1"
            )
        )

        #expect(normalized.contains("这次先别继续执行，先按当前重规划处理。"))
        #expect(normalized.contains("先处理的重点："))
        #expect(normalized.contains("- 指导类型：故障恢复（incident_recovery）"))
        #expect(normalized.contains("- 当前阻塞：运行时错误（runtime_error）"))
        #expect(normalized.contains("- 安全下一步：先检查当前异常，再决定是否重规划（inspect_incident_and_replan）"))
        #expect(normalized.contains("- 建议动作：Inspect the runtime failure evidence | Replan the blocked step before retry"))
        #expect(normalized.contains("先停下当前执行，检查失败原因后再决定是否重试。"))
        #expect(!normalized.contains("supervisor replan 合同"))
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
        #expect(status.contains("待确认指导："))
        #expect(status.contains("guidance-slash-1"))
        #expect(status.contains("生命周期：生效中"))
        #expect(status.contains("确认状态：待确认 · 需要确认"))

        let accept = session.handleSlashGuidanceForTesting(
            args: ["accept", "manual", "operator", "ok"],
            ctx: ctx
        )
        #expect(accept.contains("已更新指导确认"))

        let latestStatus = session.handleSlashGuidanceForTesting(args: [], ctx: ctx)
        #expect(latestStatus.contains("最新指导："))
        #expect(latestStatus.contains("确认状态：已接受 · 需要确认"))
        #expect(latestStatus.contains("生命周期：已结束"))

        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.ackStatus == .accepted)
        #expect(updated.ackNote == "manual operator ok")
    }

    @Test
    func slashGuidanceHumanizesStructuredGuidanceSummary() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-slash-structured")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-slash-structured-1",
                reviewId: "review-slash-structured-1",
                projectId: "proj-slash-structured-1",
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: """
收到，我会按《Release Runtime》这条指导继续推进：summary=先冻结 release runtime 范围，再补 source gate 证据。
verdict=watch
work_order_ref=plan:release-runtime-1
""",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_383_100_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-slash-structured-1"
            ),
            for: ctx
        )

        let status = session.handleSlashGuidanceForTesting(args: [], ctx: ctx)
        #expect(status.contains("先冻结 release runtime 范围，再补 source gate 证据。"))
        #expect(!status.contains("summary="))
        #expect(!status.contains("收到，我会按《Release Runtime》这条指导继续推进"))
    }

    @Test
    func finalOnlyFailureMessageHumanizesWrappedGuidanceSummary() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-guidance-final-wrapped-summary")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-final-wrapped-summary-1",
                reviewId: "review-final-wrapped-summary-1",
                projectId: "proj-final-wrapped-summary-1",
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .stopImmediately,
                safePointPolicy: .immediate,
                guidanceText: """
收到，我会按《Release Runtime》这条指导继续推进：summary=先冻结 release runtime 范围，再补 source gate 证据。
verdict=watch
""",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_383_110_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-final-wrapped-summary-1"
            ),
            for: ctx
        )

        let message = try #require(
            session.projectSupervisorFinalOnlyFailureMessageForTesting(
                ctx: ctx,
                injectionId: "guidance-final-wrapped-summary-1"
            )
        )

        #expect(message.contains("先冻结 release runtime 范围，再补 source gate 证据。"))
        #expect(message.contains("当前有一条需要先确认的 Supervisor 指导（guidance-final-wrapped-summary-1），所以我先不继续发起新的工具或技能。"))
        #expect(!message.contains("summary="))
        #expect(!message.contains("收到，我会按《Release Runtime》这条指导继续推进"))
        #expect(!message.contains("只输出停机或重规划说明"))
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

    @Test
    func projectRecentDialogueSelectionHonorsProfileFloorAndDropsPureAckNoise() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-recent-dialogue-selection")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        for index in 1...9 {
            let base = Double(index * 10)
            AXRecentContextStore.appendUserMessage(
                ctx: ctx,
                text: "task-\(index): keep the snake game continuity intact",
                createdAt: base
            )
            AXRecentContextStore.appendAssistantMessage(
                ctx: ctx,
                text: "assistant-step-\(index): continue from the current implementation",
                createdAt: base + 1
            )
        }
        AXRecentContextStore.appendUserMessage(ctx: ctx, text: "好", createdAt: 500)
        AXRecentContextStore.appendAssistantMessage(ctx: ctx, text: "收到", createdAt: 501)

        let selection = session.projectRecentDialogueSelectionForTesting(
            ctx: ctx,
            userText: "继续",
            profile: .floor8Pairs
        )

        #expect(selection.profile == .floor8Pairs)
        #expect(selection.source == "recent_context")
        #expect(selection.selectedPairs == 8)
        #expect(selection.text.contains("task-2: keep the snake game continuity intact"))
        #expect(selection.text.contains("assistant-step-9: continue from the current implementation"))
        #expect(!selection.text.contains("user: 好"))
        #expect(!selection.text.contains("assistant: 收到"))
        #expect(selection.dropped == 2)
    }

    @Test
    func resolvedProjectMemoryServingProfileUsesDepthBaselineAndAllowsExplicitEscalation() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-context-depth-profile")
        defer { try? FileManager.default.removeItem(at: root) }

        let lean = AXProjectConfig.default(forProjectRoot: root).settingProjectContextAssembly(
            projectContextDepthProfile: .lean
        )
        let full = AXProjectConfig.default(forProjectRoot: root).settingProjectContextAssembly(
            projectContextDepthProfile: .full
        ).settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach
        )

        #expect(
            session.resolvedProjectMemoryServingProfileForTesting(
                userText: "继续修当前编译错误",
                config: lean
            ) == .m1Execute
        )
        #expect(
            session.resolvedProjectMemoryServingProfileForTesting(
                userText: "梳理项目结构并给出重构建议",
                config: lean
            ) == .m2PlanReview
        )
        #expect(
            session.resolvedProjectMemoryServingProfileForTesting(
                userText: "继续修当前编译错误",
                config: full
            ) == .m4FullScan
        )
    }

    @Test
    func projectMemoryBlockIncludesDialogueWindowAndContextDepthSectionsForFullProfile() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-context-depth-full")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)

        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Keep the current snake game objective and continue the browser MVP.",
            createdAt: 100
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "I will continue from the active browser implementation path.",
            createdAt: 101
        )

        try SupervisorProjectJobStore.upsert(
            SupervisorJobRecord(
                schemaVersion: SupervisorJobRecord.currentSchemaVersion,
                jobId: "job-context-depth-full",
                projectId: projectId,
                goal: "Ship the browser snake MVP",
                priority: .high,
                status: .running,
                source: .supervisor,
                currentOwner: "coder",
                activePlanId: "plan-context-depth-full",
                createdAtMs: 100,
                updatedAtMs: 200,
                auditRef: "audit-job-context-depth-full"
            ),
            for: ctx
        )
        try SupervisorProjectPlanStore.upsert(
            SupervisorPlanRecord(
                schemaVersion: SupervisorPlanRecord.currentSchemaVersion,
                planId: "plan-context-depth-full",
                jobId: "job-context-depth-full",
                projectId: projectId,
                status: .active,
                currentOwner: "coder",
                steps: [
                    SupervisorPlanStepRecord(
                        schemaVersion: SupervisorPlanStepRecord.currentSchemaVersion,
                        stepId: "step-001",
                        title: "Scaffold the browser runtime shell",
                        kind: .launchRun,
                        status: .running,
                        skillId: "",
                        currentOwner: "coder",
                        detail: "Create the minimal runtime shell and confirm page boot.",
                        orderIndex: 0,
                        updatedAtMs: 200
                    )
                ],
                createdAtMs: 100,
                updatedAtMs: 200,
                auditRef: "audit-plan-context-depth-full"
            ),
            for: ctx
        )
        try SupervisorReviewNoteStore.upsert(
            SupervisorReviewNoteBuilder.build(
                reviewId: "review-context-depth-full",
                projectId: projectId,
                trigger: .manualRequest,
                reviewLevel: .r2Strategic,
                verdict: .betterPathFound,
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                ackRequired: true,
                summary: "Prefer the browser MVP shell before adding polish.",
                recommendedActions: ["Create the runtime shell first", "Verify page boot before tuning UX"],
                anchorGoal: "Ship a browser snake MVP",
                anchorDoneDefinition: "The game runs in-browser with movement, food, and game over.",
                anchorConstraints: ["Keep it minimal", "Prefer a shippable first cut"],
                currentState: "Planning the browser shell",
                nextStep: "Build the first page shell",
                blocker: "",
                createdAtMs: 220,
                auditRef: "audit-review-context-depth-full"
            ),
            for: ctx
        )

        let config = AXProjectConfig.default(forProjectRoot: root).settingProjectContextAssembly(
            projectRecentDialogueProfile: .extended40Pairs,
            projectContextDepthProfile: .full
        ).settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach
        )
        let block = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nShip the browser snake MVP.",
            recentText: "[retrieved_memory]\nstatus=ok\n[/retrieved_memory]",
            userText: "继续推进当前实现",
            config: config,
            toolResults: [
                ToolResult(
                    id: "diff-full-1",
                    tool: .git_diff,
                    ok: true,
                    output: "diff --git a/main.js b/main.js"
                )
            ]
        )

        #expect(block.contains("[DIALOGUE_WINDOW]"))
        #expect(block.contains("recent_project_dialogue_profile: extended_40_pairs"))
        #expect(block.contains("[FOCUSED_PROJECT_ANCHOR_PACK]"))
        #expect(block.contains("project_context_depth: full"))
        #expect(block.contains("workflow_present: true"))
        #expect(block.contains("personal_memory_excluded_reason: project_ai_default_scopes_to_project_memory_only"))
        #expect(block.contains("[LONGTERM_OUTLINE]"))
        #expect(block.contains("[CONTEXT_REFS]"))
        #expect(block.contains("[EVIDENCE_PACK]"))
        #expect(block.contains("latest_review"))
        #expect(block.contains("recent_tool_results"))
    }

    @Test
    func projectMemoryInjectsHeartbeatFactsIntoAnchorAndRefsWithoutPromotingSuppressedDigest() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-heartbeat-memory-injection")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let artifact = try #require(
            writeHeartbeatProjection(
                ctx: ctx,
                projectId: projectId,
                projectName: "Heartbeat Project",
                visibility: .suppressed,
                reasonCodes: ["stable_runtime_update_suppressed"],
                whatChangedText: "系统继续按当前节奏推进。",
                whyImportantText: "",
                systemNextStepText: ""
            )
        )

        let config = AXProjectConfig.default(forProjectRoot: root).settingProjectContextAssembly(
            projectRecentDialogueProfile: .floor8Pairs,
            projectContextDepthProfile: .full
        ).settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )
        let block = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nKeep the governed project moving.",
            recentText: "recent",
            userText: "继续推进当前实现",
            config: config
        )

        #expect(artifact.workingSetProjection.eligible == false)
        #expect(block.contains("heartbeat_status_digest: build continues with fresh evidence"))
        #expect(block.contains("heartbeat_current_state: Build is active"))
        #expect(block.contains("heartbeat_next_step: Continue current implementation slice"))
        #expect(block.contains("source_scope=heartbeat_projection"))
        #expect(block.contains(ctx.heartbeatMemoryProjectionURL.path))
        #expect(block.contains("hub://project/\(projectId)/canonical/xterminal.project.heartbeat.summary_json"))
        #expect(!block.contains("[heartbeat_digest]"))
    }

    @Test
    func leanProjectContextDepthOmitsDeepContextSections() throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-context-depth-lean")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Continue the current implementation.",
            createdAt: 100
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "I will continue from the latest project state.",
            createdAt: 101
        )

        let config = AXProjectConfig.default(forProjectRoot: root).settingProjectContextAssembly(
            projectRecentDialogueProfile: .floor8Pairs,
            projectContextDepthProfile: .lean
        )
        let block = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nKeep the project moving.",
            recentText: "recent",
            userText: "继续推进当前实现",
            config: config
        )

        #expect(block.contains("[DIALOGUE_WINDOW]"))
        #expect(block.contains("[FOCUSED_PROJECT_ANCHOR_PACK]"))
        #expect(!block.contains("[LONGTERM_OUTLINE]"))
        #expect(!block.contains("[CONTEXT_REFS]"))
        #expect(!block.contains("[EVIDENCE_PACK]"))
    }

    @Test
    func projectMemoryUsageFieldsCarryStructuredExplainabilityAndActualServingObjects() async throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-memory-usage-fields")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingHubMemoryPreference(enabled: false)
        session.messages = [
            AXChatMessage(role: .user, content: "先看当前编译错误。", createdAt: 10),
            AXChatMessage(role: .assistant, content: "我先检查最近状态。", createdAt: 11),
        ]

        let fields = await session.projectMemoryUsageFieldsForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nKeep the build green.",
            userText: "继续修当前编译错误",
            config: config
        )

        let policy = try #require(fields["project_memory_policy"] as? [String: Any])
        let policyResolution = try #require(fields["project_memory_policy_resolution"] as? [String: Any])
        let resolution = try #require(fields["memory_assembly_resolution"] as? [String: Any])
        let issueCodes = try #require(fields["project_memory_issue_codes"] as? [String])
        let driftDetail = try #require(
            fields["project_memory_issue_memory_resolution_projection_drift"] as? String
        )
        let selectedPlanes = try #require(resolution["selected_planes"] as? [String])
        let selected = try #require(resolution["selected_serving_objects"] as? [String])
        let excluded = try #require(resolution["excluded_blocks"] as? [String])

        #expect(policy["schema_version"] as? String == XTProjectMemoryPolicySnapshot.currentSchemaVersion)
        #expect(policyResolution["schema_version"] as? String == XTMemoryAssemblyResolution.currentSchemaVersion)
        #expect(fields["memory_v1_source"] as? String == XTProjectMemoryGovernance.localProjectMemorySource)
        #expect(fields["role_aware_memory_mode"] as? String == "project_ai")
        #expect(fields["project_memory_resolution_trigger"] as? String == "normal_reply")
        #expect(fields["workflow_present"] as? Bool == false)
        #expect(fields["execution_evidence_present"] as? Bool == false)
        #expect(fields["review_guidance_present"] as? Bool == false)
        #expect(fields["cross_link_hints_selected"] as? Int == 0)
        #expect(fields["project_memory_heartbeat_digest_present"] as? Bool == false)
        #expect(issueCodes.contains("memory_resolution_projection_drift"))
        #expect(driftDetail.contains("policy_selected_planes=project_dialogue_plane,project_anchor_plane,workflow_plane,cross_link_plane"))
        #expect(driftDetail.contains("actual_selected_planes=project_dialogue_plane,project_anchor_plane"))
        #expect(driftDetail.contains("policy_selected_serving_objects=recent_project_dialogue_window,focused_project_anchor_pack,active_workflow,selected_cross_link_hints"))
        #expect(driftDetail.contains("actual_selected_serving_objects=recent_project_dialogue_window,focused_project_anchor_pack"))
        #expect(selectedPlanes.contains("project_dialogue_plane"))
        #expect(selectedPlanes.contains("project_anchor_plane"))
        #expect(!selectedPlanes.contains("workflow_plane"))
        #expect(!selectedPlanes.contains("cross_link_plane"))
        #expect(!selectedPlanes.contains("evidence_plane"))
        #expect(!selectedPlanes.contains("guidance_plane"))
        #expect(selected.contains("recent_project_dialogue_window"))
        #expect(selected.contains("focused_project_anchor_pack"))
        #expect(!selected.contains("active_workflow"))
        #expect(!selected.contains("selected_cross_link_hints"))
        #expect(!selected.contains("execution_evidence"))
        #expect(!selected.contains("guidance"))
        #expect(excluded.contains("active_workflow"))
        #expect(excluded.contains("selected_cross_link_hints"))
        #expect(excluded.contains("execution_evidence"))
        #expect(excluded.contains("guidance"))
    }

    @Test
    func projectMemoryUsageFieldsExposeAutomationContinuityExecutionState() async throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-memory-usage-automation")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingHubMemoryPreference(enabled: false)
        let reportsDir = root.appendingPathComponent("build/reports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: reportsDir,
            withIntermediateDirectories: true
        )
        let handoffPath = "build/reports/xt_automation_handoff_run_step_memory_1.v1.json"
        let retryPackagePath = "build/reports/xt_automation_retry_package_run_step_memory_2.v1.json"
        let verificationContract = XTAutomationVerificationContract(
            expectedState: "post_change_verification_passes",
            verifyMethod: "project_verify_commands",
            retryPolicy: "retry_failed_verify_commands_within_budget",
            holdPolicy: "hold_for_retry_or_replan",
            evidenceRequired: true,
            triggerActionIDs: ["action-verify"],
            verifyCommands: ["swift test --filter SmokeTests"]
        )
        let retryVerificationContract = XTAutomationVerificationContract(
            expectedState: "post_change_verification_passes",
            verifyMethod: "project_verify_commands_override",
            retryPolicy: "manual_retry_or_replan",
            holdPolicy: "hold_for_retry_or_replan",
            evidenceRequired: false,
            triggerActionIDs: ["retry-action-verify"],
            verifyCommands: ["swift test --filter RetrySmokeTests"]
        )
        let verificationReport = XTAutomationVerificationReport(
            required: true,
            executed: true,
            commandCount: 3,
            passedCommandCount: 1,
            holdReason: "automation_verify_failed",
            detail: "Smoke tests are still red.",
            commandResults: [],
            contract: verificationContract
        )
        let blockerDescriptor = XTAutomationBlockerDescriptor(
            code: "automation_verify_failed",
            summary: "Smoke tests are still red.",
            stage: .verification,
            detail: "Focused smoke tests failed during retry.",
            nextSafeAction: "shrink verify scope and retry",
            retryEligible: true,
            currentStepID: "step-verify",
            currentStepTitle: "Verify focused smoke tests",
            currentStepState: .retryWait,
            currentStepSummary: "Waiting before retrying the reduced verify set."
        )
        let retryReasonDescriptor = XTAutomationRetryReasonDescriptor(
            code: "retry_verify_scope",
            category: .verification,
            summary: "Retry with a reduced verify set",
            strategy: "shrink_verify_scope",
            blockerCode: "automation_verify_failed",
            planningMode: nil,
            currentStepID: "step-verify",
            currentStepTitle: "Verify focused smoke tests",
            currentStepState: .retryWait,
            currentStepSummary: "Waiting before retrying the reduced verify set."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let handoffArtifact = XTAutomationRunHandoffArtifact(
            schemaVersion: XTAutomationRunHandoffArtifact.currentSchemaVersion,
            generatedAt: 500_001,
            runID: "run-step-memory-1",
            lineage: nil,
            recipeRef: "recipe-step-memory",
            deliveryRef: nil,
            finalState: .blocked,
            holdReason: "automation_verify_failed",
            detail: "Smoke tests are still red.",
            actionResults: [],
            verificationReport: verificationReport,
            workspaceDiffReport: nil,
            suggestedNextActions: ["shrink verify scope and retry"],
            structuredBlocker: blockerDescriptor,
            currentStepID: "step-verify",
            currentStepTitle: "Verify focused smoke tests",
            currentStepState: .retryWait,
            currentStepSummary: "Waiting before retrying the reduced verify set."
        )
        try encoder.encode(handoffArtifact).write(
            to: root.appendingPathComponent(handoffPath),
            options: .atomic
        )
        let retryPackage = XTAutomationRetryPackage(
            schemaVersion: XTAutomationRetryPackage.currentSchemaVersion,
            generatedAt: 500_002,
            projectID: AXProjectRegistryStore.projectId(forRoot: root),
            lineage: nil,
            sourceRunID: "run-step-memory-1",
            sourceFinalState: .blocked,
            sourceHoldReason: "automation_verify_failed",
            sourceHandoffArtifactPath: handoffPath,
            sourceBlocker: blockerDescriptor,
            retryStrategy: "shrink_verify_scope",
            retryReason: "retry_verify_scope",
            retryReasonDescriptor: retryReasonDescriptor,
            suggestedNextActions: ["shrink verify scope and retry"],
            additionalEvidenceRefs: [],
            planningMode: nil,
            planningSummary: nil,
            runtimePatchOverlay: nil,
            revisedActionGraph: nil,
            revisedVerifyCommands: nil,
            revisedVerificationContract: retryVerificationContract,
            planningArtifactPath: nil,
            recipeProposalArtifactPath: nil,
            retryRunID: "run-step-memory-2",
            retryArtifactPath: retryPackagePath
        )
        try encoder.encode(retryPackage).write(
            to: root.appendingPathComponent(retryPackagePath),
            options: .atomic
        )
        session.messages = [
            AXChatMessage(role: .user, content: "继续修当前编译错误。", createdAt: 10),
            AXChatMessage(role: .assistant, content: "我先接上当前 step 和记忆状态。", createdAt: 11),
        ]

        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 500_000,
                "run_id": "run-step-memory-1",
                "recipe_id": "recipe-step-memory",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 45,
                "resume_token": "resume-step-memory",
                "checkpoint_ref": "checkpoint-step-memory",
                "stable_identity": true,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                "current_step_summary": "Waiting before retrying the reduced verify set.",
                "audit_ref": "audit-step-memory-checkpoint"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 500_001,
                "run_id": "run-step-memory-1",
                "recipe_ref": "recipe-step-memory",
                "final_state": XTAutomationRunState.blocked.rawValue,
                "hold_reason": "automation_verify_failed",
                "detail": "Smoke tests are still red.",
                "executed_action_count": 2,
                "succeeded_action_count": 1,
                "total_action_count": 2,
                "handoff_artifact_path": handoffPath,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                "current_step_summary": "Waiting before retrying the reduced verify set.",
                "verification": [
                    "required": true,
                    "executed": true,
                    "command_count": 3,
                    "passed_command_count": 1,
                    "hold_reason": "automation_verify_failed",
                    "detail": "Smoke tests are still red."
                ],
                "blocker": [
                    "code": "automation_verify_failed",
                    "summary": "Smoke tests are still red.",
                    "stage": XTAutomationBlockerStage.verification.rawValue,
                    "detail": "Focused smoke tests failed during retry.",
                    "next_safe_action": "shrink verify scope and retry",
                    "retry_eligible": true,
                    "current_step_id": "step-verify",
                    "current_step_title": "Verify focused smoke tests",
                    "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                    "current_step_summary": "Waiting before retrying the reduced verify set."
                ],
                "audit_ref": "audit-step-memory-execution"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 500_002,
                "source_run_id": "run-step-memory-1",
                "retry_run_id": "run-step-memory-2",
                "retry_artifact_path": retryPackagePath,
                "retry_strategy": "shrink_verify_scope",
                "retry_reason": "retry_verify_scope",
                "retry_reason_descriptor": [
                    "code": "retry_verify_scope",
                    "category": XTAutomationRetryReasonCategory.verification.rawValue,
                    "summary": "Retry with a reduced verify set",
                    "strategy": "shrink_verify_scope",
                    "blocker_code": "automation_verify_failed",
                    "current_step_id": "step-verify",
                    "current_step_title": "Verify focused smoke tests",
                    "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                    "current_step_summary": "Waiting before retrying the reduced verify set."
                ]
            ],
            for: ctx
        )

        let fields = await session.projectMemoryUsageFieldsForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nKeep Project AI continuity explainable.",
            userText: "继续修当前编译错误",
            config: config
        )
        let block = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nKeep Project AI continuity explainable.",
            recentText: "",
            userText: "继续修当前编译错误",
            config: config
        )

        let resolution = try #require(fields["memory_assembly_resolution"] as? [String: Any])
        let selectedPlanes = try #require(resolution["selected_planes"] as? [String])
        let selected = try #require(resolution["selected_serving_objects"] as? [String])

        #expect(block.contains("automation_context_source: checkpoint+execution_report+retry_package"))
        #expect(block.contains("automation_effective_run_id: run-step-memory-2"))
        #expect(block.contains("automation_delivery_closure_source: retry_package"))
        #expect(block.contains("automation_current_step_title: Verify focused smoke tests"))
        #expect(block.contains("automation_verification_required: true"))
        #expect(block.contains("automation_blocker_stage: verification"))
        #expect(block.contains("automation_retry_reason_strategy: shrink_verify_scope"))

        #expect(fields["project_memory_automation_context_source"] as? String == "checkpoint+execution_report+retry_package")
        #expect(fields["project_memory_automation_run_id"] as? String == "run-step-memory-1")
        #expect(fields["project_memory_automation_effective_run_id"] as? String == "run-step-memory-2")
        #expect(fields["project_memory_automation_delivery_closure_source"] as? String == "retry_package")
        #expect(fields["project_memory_automation_run_state"] as? String == XTAutomationRunState.blocked.rawValue)
        #expect(fields["project_memory_resolution_trigger"] as? String == "retry_execution")
        #expect(fields["project_memory_automation_attempt"] as? Int == 2)
        #expect(fields["project_memory_automation_retry_after_seconds"] as? Int == 45)
        #expect(fields["project_memory_automation_current_step_present"] as? Bool == true)
        #expect(fields["project_memory_automation_current_step_title"] as? String == "Verify focused smoke tests")
        #expect(fields["project_memory_automation_current_step_state"] as? String == XTAutomationRunStepState.retryWait.rawValue)
        #expect(fields["project_memory_automation_verification_present"] as? Bool == true)
        #expect(fields["project_memory_automation_verification_required"] as? Bool == true)
        #expect(fields["project_memory_automation_verification_executed"] as? Bool == true)
        #expect(fields["project_memory_automation_verification_command_count"] as? Int == 3)
        #expect(fields["project_memory_automation_verification_passed_command_count"] as? Int == 1)
        #expect(fields["project_memory_automation_verification_hold_reason"] as? String == "automation_verify_failed")
        let verificationContractObject = try #require(
            fields["project_memory_automation_verification_contract"] as? [String: Any]
        )
        #expect(verificationContractObject["verify_method"] as? String == "project_verify_commands")
        #expect(fields["project_memory_automation_blocker_present"] as? Bool == true)
        #expect(fields["project_memory_automation_blocker_stage"] as? String == XTAutomationBlockerStage.verification.rawValue)
        #expect(fields["project_memory_automation_retry_reason_present"] as? Bool == true)
        #expect(fields["project_memory_automation_retry_reason_summary"] as? String == "Retry with a reduced verify set")
        #expect(fields["project_memory_automation_retry_reason_strategy"] as? String == "shrink_verify_scope")
        let retryVerificationContractObject = try #require(
            fields["project_memory_automation_retry_verification_contract"] as? [String: Any]
        )
        #expect(retryVerificationContractObject["verify_method"] as? String == "project_verify_commands_override")
        #expect(selectedPlanes.contains("execution_state_plane"))
        #expect(selected.contains("current_step"))
        #expect(selected.contains("verification_state"))
        #expect(selected.contains("blocker_state"))
        #expect(selected.contains("retry_reason"))
    }

    @Test
    func projectMemoryUsageFieldsCarryRemoteSnapshotCacheProvenanceFromHubResponse() async throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-memory-usage-cache-provenance")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingHubMemoryPreference(enabled: true)
        session.messages = [
            AXChatMessage(role: .user, content: "继续整理当前项目上下文。", createdAt: 30),
            AXChatMessage(role: .assistant, content: "我会优先看最近项目状态。", createdAt: 31),
        ]

        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            let response = HubIPCClient.MemoryContextResponsePayload(
                text: """
[MEMORY_V1]
[DIALOGUE_WINDOW]
messages:
user: keep continuity
[/DIALOGUE_WINDOW]
[FOCUSED_PROJECT_ANCHOR_PACK]
goal: keep governed memory continuity
[/FOCUSED_PROJECT_ANCHOR_PACK]
[/MEMORY_V1]
""",
                source: "hub_memory_v1_grpc",
                resolvedMode: mode.rawValue,
                requestedProfile: route.servingProfile.rawValue,
                resolvedProfile: route.servingProfile.rawValue,
                freshness: "ttl_cache",
                cacheHit: true,
                remoteSnapshotCacheScope: "mode=project_chat project_id=proj-cache",
                remoteSnapshotCachedAtMs: 1_774_000_000_000,
                remoteSnapshotAgeMs: 6_000,
                remoteSnapshotTTLRemainingMs: 9_000,
                budgetTotalTokens: 512,
                usedTotalTokens: 128,
                layerUsage: [],
                truncatedLayers: [],
                redactedItems: 0,
                privateDrops: 0
            )
            return HubIPCClient.MemoryContextResolutionResult(
                response: response,
                source: response.source,
                resolvedMode: mode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "ttl_cache",
                cacheHit: true,
                remoteSnapshotCacheScope: "mode=project_chat project_id=proj-cache",
                remoteSnapshotCachedAtMs: 1_774_000_000_000,
                remoteSnapshotAgeMs: 6_000,
                remoteSnapshotTTLRemainingMs: 9_000,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let fields = await session.projectMemoryUsageFieldsForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nKeep the Hub continuity observable.",
            userText: "继续整理当前项目上下文",
            config: config
        )

        #expect(fields["memory_v1_source"] as? String == "hub_snapshot_plus_local_overlay")
        #expect(fields["memory_v1_freshness"] as? String == "ttl_cache")
        #expect(fields["memory_v1_cache_hit"] as? Bool == true)
        #expect(fields["memory_v1_remote_snapshot_cache_scope"] as? String == "mode=project_chat project_id=proj-cache")
        #expect(fields["memory_v1_remote_snapshot_cached_at_ms"] as? Int64 == 1_774_000_000_000)
        #expect(fields["memory_v1_remote_snapshot_age_ms"] as? Int == 6_000)
        #expect(fields["memory_v1_remote_snapshot_ttl_remaining_ms"] as? Int == 9_000)
    }

    @Test
    func projectMemoryUsageFieldsExposeHeartbeatDigestInjectionTruth() async throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-memory-usage-heartbeat-digest")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingHubMemoryPreference(enabled: false)
        session.messages = [
            AXChatMessage(role: .user, content: "继续推进当前实现。", createdAt: 40),
            AXChatMessage(role: .assistant, content: "我会结合 heartbeat 和记忆状态继续推进。", createdAt: 41),
        ]
        _ = try #require(
            writeHeartbeatProjection(
                ctx: ctx,
                projectId: AXProjectRegistryStore.projectId(forRoot: root),
                projectName: "Heartbeat Usage",
                visibility: .shown,
                reasonCodes: ["project_memory_attention", "open_anomalies_present"],
                whatChangedText: "Project AI memory truth still needs attention.",
                whyImportantText: "Doctor 还不能确认最近一轮 coder 真正吃到了哪些 project memory。",
                systemNextStepText: "系统会继续等待下一轮 recent coder usage 补齐 machine-readable truth。",
                weakReasons: ["project_memory_attention"],
                projectMemoryReadiness: XTProjectMemoryAssemblyReadiness(
                    ready: false,
                    statusLine: "attention:project_memory_usage_missing",
                    issues: [
                        XTProjectMemoryAssemblyIssue(
                            code: "project_memory_usage_missing",
                            severity: .warning,
                            summary: "尚未捕获 Project AI 的最近一次 memory 装配真相",
                            detail: "Doctor 当前只有配置基线，还没有 recent coder usage 来证明本轮 Project AI 实际拿到了哪些 memory objects / planes。"
                        )
                    ]
                )
            )
        )

        let fields = await session.projectMemoryUsageFieldsForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nKeep the project moving with explainable memory.",
            userText: "继续推进当前实现",
            config: config
        )

        #expect(fields["project_memory_heartbeat_digest_present"] as? Bool == true)
        #expect(fields["project_memory_heartbeat_digest_visibility"] as? String == "shown")
        #expect(fields["project_memory_heartbeat_digest_reason_codes"] as? [String] == [
            "project_memory_attention",
            "open_anomalies_present",
        ])
    }

    @Test
    func projectMemoryUsageFieldsRecognizeGuidanceAndExecutionEvidenceWhenActuallyRendered() async throws {
        let session = ChatSessionModel()
        let root = try makeProjectRoot(named: "project-memory-usage-guidance")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingHubMemoryPreference(enabled: false)
        session.messages = [
            AXChatMessage(role: .user, content: "继续推进。", createdAt: 20),
            AXChatMessage(role: .assistant, content: "我会先收集证据。", createdAt: 21),
        ]
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-project-memory-usage-1",
                reviewId: "review-project-memory-usage-1",
                projectId: "proj-project-memory-usage-1",
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "先对齐证据，再继续自动推进。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_380_000_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-project-memory-usage-1"
            ),
            for: ctx
        )

        let fields = await session.projectMemoryUsageFieldsForTesting(
            ctx: ctx,
            canonicalMemory: "# Goal\nKeep the build green.",
            userText: "继续推进并核对证据",
            config: config,
            toolResults: [
                ToolResult(
                    id: "tool-1",
                    tool: .read_file,
                    ok: true,
                    output: "Read Sources/App.swift"
                )
            ]
        )

        let resolution = try #require(fields["memory_assembly_resolution"] as? [String: Any])
        let selectedPlanes = try #require(resolution["selected_planes"] as? [String])
        let selected = try #require(resolution["selected_serving_objects"] as? [String])

        #expect(fields["execution_evidence_present"] as? Bool == true)
        #expect(fields["review_guidance_present"] as? Bool == true)
        #expect(fields["project_memory_resolution_trigger"] as? String == "review_guidance_follow_up")
        #expect(selectedPlanes.contains("project_dialogue_plane"))
        #expect(selectedPlanes.contains("project_anchor_plane"))
        #expect(selectedPlanes.contains("evidence_plane"))
        #expect(selectedPlanes.contains("guidance_plane"))
        #expect(selected.contains("execution_evidence"))
        #expect(selected.contains("guidance"))
    }

    private func writeHeartbeatProjection(
        ctx: AXProjectContext,
        projectId: String,
        projectName: String,
        visibility: XTHeartbeatDigestVisibilityDecision,
        reasonCodes: [String],
        whatChangedText: String,
        whyImportantText: String,
        systemNextStepText: String,
        statusDigest: String = "build continues with fresh evidence",
        currentStateSummary: String = "Build is active",
        nextStepSummary: String = "Continue current implementation slice",
        blockerSummary: String = "",
        qualityBand: HeartbeatQualityBand = .strong,
        qualityScore: Int = 88,
        weakReasons: [String] = [],
        openAnomalyTypes: [HeartbeatAnomalyType] = [],
        projectPhase: HeartbeatProjectPhase? = .build,
        executionStatus: HeartbeatExecutionStatus? = .active,
        riskTier: HeartbeatRiskTier? = .low,
        recoveryDecision: HeartbeatRecoveryDecision? = nil,
        repeatCount: Int = 0,
        projectMemoryReadiness: XTProjectMemoryAssemblyReadiness? = nil
    ) -> XTHeartbeatMemoryProjectionArtifact? {
        let updatedAtMs: Int64 = 1_778_900_120_000
        let openAnomalies = openAnomalyTypes.enumerated().map { index, anomalyType in
            HeartbeatAnomalyNote(
                anomalyId: "anomaly-\(projectId)-\(index)-\(anomalyType.rawValue)",
                projectId: projectId,
                anomalyType: anomalyType,
                severity: .concern,
                confidence: 0.9,
                reason: anomalyType.displayName,
                evidenceRefs: [],
                detectedAtMs: updatedAtMs,
                recommendedEscalation: .pulseReview
            )
        }
        let schedule = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: projectId,
            updatedAtMs: updatedAtMs,
            lastHeartbeatAtMs: updatedAtMs,
            lastObservedProgressAtMs: updatedAtMs - 20_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: updatedAtMs + 300_000,
            nextPulseReviewDueAtMs: updatedAtMs + 900_000,
            nextBrainstormReviewDueAtMs: updatedAtMs + 1_800_000,
            latestQualitySnapshot: nil,
            openAnomalies: openAnomalies,
            lastHeartbeatFingerprint: "hb-\(projectId)",
            lastHeartbeatRepeatCount: repeatCount,
            latestProjectPhase: projectPhase,
            latestExecutionStatus: executionStatus,
            latestRiskTier: riskTier
        )
        let snapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: projectId,
            projectName: projectName,
            statusDigest: statusDigest,
            currentStateSummary: currentStateSummary,
            nextStepSummary: nextStepSummary,
            blockerSummary: blockerSummary,
            lastHeartbeatAtMs: updatedAtMs,
            latestQualityBand: qualityBand,
            latestQualityScore: qualityScore,
            weakReasons: weakReasons,
            openAnomalyTypes: openAnomalyTypes,
            projectPhase: projectPhase,
            executionStatus: executionStatus,
            riskTier: riskTier,
            cadence: makeHeartbeatCadence(updatedAtMs: updatedAtMs),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: visibility,
                reasonCodes: reasonCodes,
                whatChangedText: whatChangedText,
                whyImportantText: whyImportantText,
                systemNextStepText: systemNextStepText
            ),
            recoveryDecision: recoveryDecision,
            projectMemoryReadiness: projectMemoryReadiness
        )
        let canonical = SupervisorProjectHeartbeatCanonicalSync.record(
            snapshot: snapshot,
            generatedAtMs: updatedAtMs
        )
        return XTHeartbeatMemoryProjectionStore.record(
            ctx: ctx,
            snapshot: snapshot,
            schedule: schedule,
            canonicalRecord: canonical,
            generatedAtMs: updatedAtMs
        )
    }

    private func makeHeartbeatCadence(
        updatedAtMs: Int64
    ) -> SupervisorCadenceExplainability {
        SupervisorCadenceExplainability(
            progressHeartbeat: SupervisorCadenceDimensionExplainability(
                dimension: .progressHeartbeat,
                configuredSeconds: 300,
                recommendedSeconds: 300,
                effectiveSeconds: 300,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: updatedAtMs + 300_000,
                nextDueReasonCodes: ["heartbeat_active"],
                isDue: false
            ),
            reviewPulse: SupervisorCadenceDimensionExplainability(
                dimension: .reviewPulse,
                configuredSeconds: 900,
                recommendedSeconds: 900,
                effectiveSeconds: 900,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: updatedAtMs + 900_000,
                nextDueReasonCodes: ["pulse_pending"],
                isDue: false
            ),
            brainstormReview: SupervisorCadenceDimensionExplainability(
                dimension: .brainstormReview,
                configuredSeconds: 1800,
                recommendedSeconds: 1800,
                effectiveSeconds: 1800,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: updatedAtMs + 1_800_000,
                nextDueReasonCodes: ["brainstorm_pending"],
                isDue: false
            ),
            eventFollowUpCooldownSeconds: 120
        )
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

    private func insertPendingUIReviewRepairGuidance(
        ctx: AXProjectContext,
        injectionId: String,
        reviewId: String,
        projectId: String
    ) throws {
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: injectionId,
                reviewId: reviewId,
                projectId: projectId,
                targetRole: .projectChat,
                deliveryMode: .stopSignal,
                interventionMode: .stopImmediately,
                safePointPolicy: .immediate,
                guidanceText: """
Repair primary CTA visibility before continuing browser automation.
instruction=Restore a visible primary CTA before rerunning UI review.
source=ui_review_repair
request_id=req-\(injectionId)
skill_id=browser.runtime.inspect
status=completed
ui_review_ref=local://.xterminal/ui_review/agent_evidence/\(reviewId).json
ui_review_review_id=\(reviewId)
ui_review_verdict=attention_needed
repair_action=repair_primary_cta_visibility
repair_focus=critical_action
next_safe_action=open_ui_review
ui_review_issue_codes=critical_action_not_visible,interactive_target_missing
ui_review_summary=Primary CTA is missing from the current browser page.
skill_result_summary=deviceBrowserControl completed: Critical CTA missing
""",
                ackStatus: .pending,
                ackRequired: true,
                effectiveSupervisorTier: .s4TightSupervision,
                effectiveWorkOrderDepth: .stepLockedRescue,
                workOrderRef: "plan:plan-ui-review-safe-next-action-v1",
                ackNote: "",
                injectedAtMs: 1_773_382_240_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-\(injectionId)"
            ),
            for: ctx
        )
    }

    private func insertPendingGrantResolutionGuidance(
        ctx: AXProjectContext,
        reviewId: String,
        injectionId: String,
        projectId: String
    ) throws {
        try SupervisorReviewNoteStore.upsert(
            SupervisorReviewNoteBuilder.build(
                reviewId: reviewId,
                projectId: projectId,
                trigger: .blockerDetected,
                reviewLevel: .r3Rescue,
                verdict: .highRisk,
                targetRole: .projectChat,
                deliveryMode: .stopSignal,
                ackRequired: true,
                effectiveSupervisorTier: .s4TightSupervision,
                effectiveWorkOrderDepth: .stepLockedRescue,
                workOrderRef: "plan:plan-\(reviewId.replacingOccurrences(of: "review-", with: ""))",
                summary: "Project is blocked on a pending Hub grant and cannot safely continue side effects.",
                recommendedActions: [
                    "Open Hub grant approval for this project",
                    "Retry the governed step after grant approval"
                ],
                anchorGoal: "Resume the governed workflow once authorization is in place.",
                anchorDoneDefinition: "Grant is approved and the blocked step can resume safely.",
                anchorConstraints: ["Do not bypass fail-closed grant policy."],
                currentState: "The project is paused behind a grant gate.",
                nextStep: "Wait for Hub grant approval, then resume the blocked task.",
                blocker: "grant_required",
                createdAtMs: 1_773_382_270_000,
                auditRef: "audit-\(reviewId)"
            ),
            for: ctx
        )
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: injectionId,
                reviewId: reviewId,
                projectId: projectId,
                targetRole: .projectChat,
                deliveryMode: .stopSignal,
                interventionMode: .stopImmediately,
                safePointPolicy: .immediate,
                guidanceText: """
verdict=high_risk
summary=Project is blocked on a pending Hub grant and cannot safely continue side effects.
effective_supervisor_tier=s4_tight_supervision
effective_work_order_depth=step_locked_rescue
work_order_ref=plan:plan-\(reviewId.replacingOccurrences(of: "review-", with: ""))
actions=Open Hub grant approval for this project | Retry the governed step after grant approval
""",
                ackStatus: .pending,
                ackRequired: true,
                effectiveSupervisorTier: .s4TightSupervision,
                effectiveWorkOrderDepth: .stepLockedRescue,
                workOrderRef: "plan:plan-\(reviewId.replacingOccurrences(of: "review-", with: ""))",
                ackNote: "",
                injectedAtMs: 1_773_382_271_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-\(injectionId)"
            ),
            for: ctx
        )
    }

    private func insertPendingIncidentRecoveryGuidance(
        ctx: AXProjectContext,
        reviewId: String,
        injectionId: String,
        projectId: String
    ) throws {
        try SupervisorReviewNoteStore.upsert(
            SupervisorReviewNoteBuilder.build(
                reviewId: reviewId,
                projectId: projectId,
                trigger: .failureStreak,
                reviewLevel: .r3Rescue,
                verdict: .highRisk,
                targetRole: .projectChat,
                deliveryMode: .stopSignal,
                ackRequired: true,
                effectiveSupervisorTier: .s4TightSupervision,
                effectiveWorkOrderDepth: .stepLockedRescue,
                workOrderRef: "plan:plan-\(reviewId.replacingOccurrences(of: "review-", with: ""))",
                summary: "Project hit a runtime failure and needs a governed incident recovery pass before retrying.",
                recommendedActions: [
                    "Inspect the runtime failure evidence",
                    "Replan the blocked step before retry"
                ],
                anchorGoal: "Resume the workflow without repeating the same runtime failure.",
                anchorDoneDefinition: "Failure cause is understood and the next retry path is safe.",
                anchorConstraints: ["Do not auto-retry blindly after a runtime error."],
                currentState: "The project is paused after a runtime failure.",
                nextStep: "Inspect the failure evidence and update the plan before retrying.",
                blocker: "runtime_error",
                createdAtMs: 1_773_382_290_000,
                auditRef: "audit-\(reviewId)"
            ),
            for: ctx
        )
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: injectionId,
                reviewId: reviewId,
                projectId: projectId,
                targetRole: .projectChat,
                deliveryMode: .stopSignal,
                interventionMode: .stopImmediately,
                safePointPolicy: .immediate,
                guidanceText: """
verdict=high_risk
summary=Project hit a runtime failure and needs a governed incident recovery pass before retrying.
effective_supervisor_tier=s4_tight_supervision
effective_work_order_depth=step_locked_rescue
work_order_ref=plan:plan-\(reviewId.replacingOccurrences(of: "review-", with: ""))
actions=Inspect the runtime failure evidence | Replan the blocked step before retry
""",
                ackStatus: .pending,
                ackRequired: true,
                effectiveSupervisorTier: .s4TightSupervision,
                effectiveWorkOrderDepth: .stepLockedRescue,
                workOrderRef: "plan:plan-\(reviewId.replacingOccurrences(of: "review-", with: ""))",
                ackNote: "",
                injectedAtMs: 1_773_382_291_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-\(injectionId)"
            ),
            for: ctx
        )
    }

    private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return [] }
        let data = try Data(contentsOf: ctx.rawLogURL)
        guard let text = String(data: data, encoding: .utf8) else {
            struct RawLogDecodeError: Error {}
            throw RawLogDecodeError()
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    private func makeHeartbeatCadence() -> SupervisorCadenceExplainability {
        SupervisorCadenceExplainability(
            progressHeartbeat: SupervisorCadenceDimensionExplainability(
                dimension: .progressHeartbeat,
                configuredSeconds: 300,
                recommendedSeconds: 300,
                effectiveSeconds: 300,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: 1_778_840_420_000,
                nextDueReasonCodes: ["heartbeat_active"],
                isDue: false
            ),
            reviewPulse: SupervisorCadenceDimensionExplainability(
                dimension: .reviewPulse,
                configuredSeconds: 900,
                recommendedSeconds: 900,
                effectiveSeconds: 900,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: 1_778_840_900_000,
                nextDueReasonCodes: ["pulse_pending"],
                isDue: false
            ),
            brainstormReview: SupervisorCadenceDimensionExplainability(
                dimension: .brainstormReview,
                configuredSeconds: 1800,
                recommendedSeconds: 1800,
                effectiveSeconds: 1800,
                effectiveReasonCodes: ["configured"],
                nextDueAtMs: 1_778_841_800_000,
                nextDueReasonCodes: ["brainstorm_pending"],
                isDue: false
            ),
            eventFollowUpCooldownSeconds: 120
        )
    }
}
