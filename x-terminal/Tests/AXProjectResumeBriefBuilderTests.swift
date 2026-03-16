import Foundation
import Testing
@testable import XTerminal

struct AXProjectResumeBriefBuilderTests {
    @Test
    func returnsFallbackWhenProjectHasNoDurableArtifacts() throws {
        let root = try makeProjectRoot(named: "resume-empty")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("当前项目还没有足够的持久记忆"))
    }

    @Test
    func prefersSessionSummaryStateButKeepsCanonicalGoalAndDecisions() throws {
        let root = try makeProjectRoot(named: "resume-summary-preferred")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)

        var memory = AXMemory.new(projectName: "resume-summary-preferred", projectRoot: root.path)
        memory.goal = "Preserve precise project handoff quality across AI switches."
        memory.currentState = ["Canonical memory exists"]
        memory.decisions = ["Keep resume summary local-only even when tokens are cheap."]
        memory.nextSteps = ["Old next step from canonical memory"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        let summary = AXSessionSummaryCapsule(
            schemaVersion: AXSessionSummaryCapsule.schemaVersion,
            phase: .sessionResetOrSwitch,
            projectId: projectId,
            projectRoot: root.path,
            reason: "project_switch",
            createdAtMs: 300_000,
            memorySummary: AXMemoryLifecycleMemorySummary(
                goal: "",
                currentState: "Blocked on validating the resume entry route.",
                blocker: "Need to verify the summary stays out of the main prompt.",
                nextStep: "Land /resume and natural-language resume trigger."
            ),
            workingSetSummary: AXMemoryLifecycleWorkingSetSummary(
                recentMessageCount: 2,
                recentUserTurnCount: 1,
                latestUserMessage: "Please give me a clean handoff summary next time.",
                latestAssistantMessage: "I will build a dedicated local-only resume entry.",
                resumeSummary: "latest_user=Please give me a clean handoff summary next time.",
                refs: []
            ),
            refs: [ctx.memoryJSONURL.path]
        )

        try FileManager.default.createDirectory(
            at: ctx.sessionSummariesDir,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: ctx.latestSessionSummaryURL, options: .atomic)

        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("当前目标：Preserve precise project handoff quality across AI switches."))
        #expect(rendered.contains("当前状态：Blocked on validating the resume entry route."))
        #expect(rendered.contains("当前阻塞：Need to verify the summary stays out of the main prompt."))
        #expect(rendered.contains("建议下一步：Land /resume and natural-language resume trigger."))
        #expect(rendered.contains("Keep resume summary local-only even when tokens are cheap."))
        #expect(rendered.contains("最后一条用户信息"))
        #expect(rendered.contains("来源：canonical memory / latest session summary"))
    }

    @Test
    func includesLatestUIReviewWhenPresent() throws {
        let root = try makeProjectRoot(named: "resume-ui-review")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "resume-ui-review", projectRoot: root.path)
        memory.goal = "Keep local handoff quality high after browser observations."
        memory.currentState = ["Browser observation pipeline is active"]
        memory.nextSteps = ["Use latest UI review in the resume brief"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        try writeSampleUIReview(
            ctx: ctx,
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            reviewID: "uir-resume-test",
            verdict: .attentionNeeded,
            confidence: .medium,
            sufficientEvidence: true,
            objectiveReady: false,
            issueCodes: ["critical_action_not_visible"],
            summary: "attention needed; confidence=medium; issues=critical_action_not_visible"
        )

        let rendered = AXProjectResumeBriefBuilder.render(ctx: ctx)

        #expect(rendered.contains("最近一次 UI review："))
        #expect(rendered.contains("verdict=attention_needed"))
        #expect(rendered.contains("issues=critical_action_not_visible"))
        #expect(rendered.contains("来源：canonical memory"))
        #expect(rendered.contains("latest ui review"))
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_resume_brief_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeSampleUIReview(
        ctx: AXProjectContext,
        projectId: String,
        reviewID: String,
        verdict: XTUIReviewVerdict,
        confidence: XTUIReviewConfidence,
        sufficientEvidence: Bool,
        objectiveReady: Bool,
        issueCodes: [String],
        summary: String
    ) throws {
        let review = XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: reviewID,
            projectID: projectId,
            bundleID: "bundle-\(reviewID)",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-\(reviewID).json",
            surfaceType: .browserPage,
            probeDepth: .standard,
            objective: "browser_page_actionability",
            verdict: verdict,
            confidence: confidence,
            sufficientEvidence: sufficientEvidence,
            objectiveReady: objectiveReady,
            interactiveTargetCount: 0,
            criticalActionExpected: true,
            criticalActionVisible: false,
            issueCodes: issueCodes,
            checks: [
                XTUIReviewCheck(
                    code: "critical_action_not_visible",
                    status: .warning,
                    detail: "A likely primary action was not visible in the current browser page."
                )
            ],
            summary: summary,
            createdAtMs: 400_000,
            auditRef: "audit-\(reviewID)"
        )
        _ = try XTUIReviewStore.writeReview(review, for: ctx)
    }
}
