import Foundation
import Testing
@testable import XTerminal

@MainActor
struct AXMemoryLifecycleTests {
    @Test
    func afterTurnArtifactWritesMachineReadableDeltaAndCompactionHint() throws {
        let fixture = ToolExecutorProjectFixture(name: "memory-lifecycle-after-turn")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: fixture.root)

        var before = AXMemory.new(projectName: "memory-lifecycle-after-turn", projectRoot: fixture.root.path)
        before.goal = "Improve project memory continuity."
        before.currentState = ["Investigating recent context gaps"]
        before.nextSteps = ["Review the old prompt window"]
        before.openQuestions = ["Need a stable lifecycle artifact format"]
        try AXProjectStore.saveMemory(before, for: ctx)

        let oldBase = Date(timeIntervalSince1970: 1_778_900_000).timeIntervalSince1970
        for index in 0..<10 {
            let ts = oldBase + Double(index * 5)
            AXRecentContextStore.appendUserMessage(ctx: ctx, text: "old-user-\(index)", createdAt: ts)
            AXRecentContextStore.appendAssistantMessage(ctx: ctx, text: "old-assistant-\(index)", createdAt: ts + 1)
        }

        try SupervisorDecisionTrackStore.upsert(
            SupervisorDecisionTrackBuilder.build(
                decisionId: "dec-existing",
                projectId: projectId,
                category: .scopeFreeze,
                status: .approved,
                statement: "Keep lifecycle work scoped to machine-readable artifacts.",
                source: "owner",
                reversible: true,
                approvalRequired: false,
                auditRef: "audit-existing",
                evidenceRefs: ["build/reports/xt_w3_35_scope.json"],
                createdAtMs: Int64((oldBase * 1_000.0).rounded())
            ),
            for: ctx
        )

        let turnCreatedAt = Date(timeIntervalSince1970: 1_779_800_100).timeIntervalSince1970
        let userText = "技术栈决定采用 SwiftUI，同时我更喜欢更自然、action-first 的界面风格。"
        let assistantText = "我会把生命周期 artifact、working set summary 和 compaction hint 一起落盘。"
        AXRecentContextStore.appendUserMessage(ctx: ctx, text: userText, createdAt: turnCreatedAt)
        AXRecentContextStore.appendAssistantMessage(ctx: ctx, text: assistantText, createdAt: turnCreatedAt + 1)

        var after = before
        after.currentState = ["Lifecycle artifact writer is implemented"]
        after.nextSteps = ["Add focused lifecycle tests"]
        after.openQuestions = []
        after.risks = []
        after.updatedAt = turnCreatedAt

        var delta = AXMemoryDelta.empty()
        delta.currentStateAdd = ["Lifecycle artifact writer is implemented"]
        delta.currentStateRemove = ["Investigating recent context gaps"]
        delta.nextStepsAdd = ["Add focused lifecycle tests"]
        delta.nextStepsRemove = ["Review the old prompt window"]
        delta.openQuestionsRemove = ["Need a stable lifecycle artifact format"]

        let artifact = try #require(
            AXMemoryLifecycleStore.recordAfterTurn(
                ctx: ctx,
                turn: AXConversationTurn(createdAt: turnCreatedAt, user: userText, assistant: assistantText),
                beforeMemory: before,
                observationDelta: delta,
                afterMemory: after,
                pipelineSource: "runtime_fallback"
            )
        )

        #expect(FileManager.default.fileExists(atPath: ctx.latestMemoryLifecycleURL.path))
        #expect(artifact.phase == .afterTurn)
        #expect(artifact.pipelineSource == "runtime_fallback")
        #expect(artifact.nextStepDelta.change == .updated)
        #expect(artifact.blockerDelta.change == .cleared)
        #expect(artifact.workingSetSummary.resumeSummary.contains("carry_next=Add focused lifecycle tests"))
        #expect(artifact.decisionCandidates.count == 1)
        #expect(artifact.decisionCandidates.first?.category == .techStack)
        #expect(artifact.decisionCandidates.first?.status == .proposed)
        #expect(artifact.backgroundPreferenceCandidates.count == 1)
        #expect(artifact.backgroundPreferenceCandidates.first?.domain == .uxStyle)
        #expect(!artifact.compactionHint.rollupNodeIds.isEmpty)
        #expect(artifact.compactionHint.protectedNodeIds.contains("decision-dec-existing"))
        #expect(artifact.refs.contains(ctx.supervisorDecisionTrackURL.path))

        let latestData = try Data(contentsOf: ctx.latestMemoryLifecycleURL)
        let decoded = try JSONDecoder().decode(AXAfterTurnMemoryLifecycleArtifact.self, from: latestData)
        #expect(decoded.turnId == artifact.turnId)
        #expect(decoded.compactionHint.rollupNodeIds == artifact.compactionHint.rollupNodeIds)
    }

    @Test
    func afterTurnArtifactDoesNotPromoteAssistantOnlySpeculation() throws {
        let fixture = ToolExecutorProjectFixture(name: "memory-lifecycle-no-assistant-promotion")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        try ctx.ensureDirs()

        let turnCreatedAt = Date(timeIntervalSince1970: 1_779_800_500).timeIntervalSince1970
        let userText = "继续排查现在的上下文问题。"
        let assistantText = "那我们就定 React 并直接扩大 release scope。"
        AXRecentContextStore.appendUserMessage(ctx: ctx, text: userText, createdAt: turnCreatedAt)
        AXRecentContextStore.appendAssistantMessage(ctx: ctx, text: assistantText, createdAt: turnCreatedAt + 1)

        let before = AXMemory.new(projectName: "memory-lifecycle-no-assistant-promotion", projectRoot: fixture.root.path)
        var after = before
        after.currentState = ["Still investigating context issues"]
        var delta = AXMemoryDelta.empty()
        delta.currentStateAdd = after.currentState
        delta.decisionsAdd = ["Use React and expand release scope"]

        let artifact = try #require(
            AXMemoryLifecycleStore.recordAfterTurn(
                ctx: ctx,
                turn: AXConversationTurn(createdAt: turnCreatedAt, user: userText, assistant: assistantText),
                beforeMemory: before,
                observationDelta: delta,
                afterMemory: after,
                pipelineSource: "runtime_fallback"
            )
        )

        #expect(artifact.decisionCandidates.isEmpty)
        #expect(artifact.backgroundPreferenceCandidates.isEmpty)
    }

    @Test
    func switchingProjectsWritesSessionSummaryCapsuleForPreviousProject() throws {
        let oldFixture = ToolExecutorProjectFixture(name: "memory-lifecycle-session-old")
        let newFixture = ToolExecutorProjectFixture(name: "memory-lifecycle-session-new")
        defer {
            oldFixture.cleanup()
            newFixture.cleanup()
        }

        let oldCtx = AXProjectContext(root: oldFixture.root)
        let newCtx = AXProjectContext(root: newFixture.root)
        try oldCtx.ensureDirs()
        try newCtx.ensureDirs()

        var memory = AXMemory.new(projectName: "memory-lifecycle-session-old", projectRoot: oldFixture.root.path)
        memory.goal = "Keep session summaries available across project switches."
        memory.currentState = ["Blocked on final review"]
        memory.nextSteps = ["Continue with structured rollout"]
        memory.openQuestions = ["Need a concise switch summary"]
        try AXProjectStore.saveMemory(memory, for: oldCtx)

        let now = Date(timeIntervalSince1970: 1_779_900_000).timeIntervalSince1970
        AXRecentContextStore.appendUserMessage(
            ctx: oldCtx,
            text: "Need to remember why this project is blocked",
            createdAt: now - 10
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: oldCtx,
            text: "Because the final review still needs a concise lifecycle summary",
            createdAt: now - 9
        )

        let session = ChatSessionModel()
        session.ensureLoaded(ctx: oldCtx, limit: 20)
        session.ensureLoaded(ctx: newCtx, limit: 20)

        #expect(FileManager.default.fileExists(atPath: oldCtx.latestSessionSummaryURL.path))
        let summaryData = try Data(contentsOf: oldCtx.latestSessionSummaryURL)
        let summary = try JSONDecoder().decode(AXSessionSummaryCapsule.self, from: summaryData)
        #expect(summary.phase == .sessionResetOrSwitch)
        #expect(summary.reason == "project_switch")
        #expect(summary.memorySummary.nextStep == "Continue with structured rollout")
        #expect(summary.workingSetSummary.latestUserMessage == "Need to remember why this project is blocked")
        #expect(summary.refs.contains(oldCtx.memoryJSONURL.path))
        #expect(summary.refs.contains(AXRecentContextStore.jsonURL(for: oldCtx).path))
    }

    @Test
    func clearSlashWritesSessionSummaryCapsuleForCurrentProject() throws {
        let fixture = ToolExecutorProjectFixture(name: "memory-lifecycle-clear-current")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "memory-lifecycle-clear-current", projectRoot: fixture.root.path)
        memory.goal = "Persist an explicit summary before clearing the current conversation."
        memory.currentState = ["Chat window contains active troubleshooting context"]
        memory.nextSteps = ["Resume from the saved summary after clear"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        let now = Date(timeIntervalSince1970: 1_779_900_500).timeIntervalSince1970
        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Summarize this before I clear the chat",
            createdAt: now - 4
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "I will persist a short current-project session summary first.",
            createdAt: now - 3
        )

        let session = ChatSessionModel()
        session.ensureLoaded(ctx: ctx, limit: 20)
        session.draft = "/clear"
        session.send(
            ctx: ctx,
            memory: memory,
            config: nil,
            router: LLMRouter(settingsStore: SettingsStore())
        )

        #expect(session.messages.isEmpty)
        #expect(FileManager.default.fileExists(atPath: ctx.latestSessionSummaryURL.path))

        let summaryData = try Data(contentsOf: ctx.latestSessionSummaryURL)
        let summary = try JSONDecoder().decode(AXSessionSummaryCapsule.self, from: summaryData)
        #expect(summary.phase == .sessionResetOrSwitch)
        #expect(summary.reason == "session_reset")
        #expect(summary.memorySummary.goal == "Persist an explicit summary before clearing the current conversation.")
        #expect(summary.workingSetSummary.latestAssistantMessage == "I will persist a short current-project session summary first.")
    }
}
