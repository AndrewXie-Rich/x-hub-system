import Darwin
import Foundation
import Testing
@testable import XTerminal

@MainActor
struct ProjectMemoryUIReviewPromptTests {
    @Test
    func projectMemoryBlockIncludesLatestUIReviewInObservationsWorkingSetAndEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_project_memory_ui_review_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let registryBase = root.appendingPathComponent("registry", isDirectory: true)
        try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)
        setenv("XTERMINAL_PROJECT_REGISTRY_BASE_DIR", registryBase.path, 1)
        defer { unsetenv("XTERMINAL_PROJECT_REGISTRY_BASE_DIR") }

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 500,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [
                AXProjectEntry(
                    projectId: projectId,
                    rootPath: root.path,
                    displayName: "UI Review Prompt",
                    lastOpenedAt: 500,
                    manualOrderIndex: 0,
                    pinned: false,
                    statusDigest: "runtime=browser_ready",
                    currentStateSummary: "Browser observation pipeline is active",
                    nextStepSummary: "Use the latest review in memory",
                    blockerSummary: "CTA visibility still needs checking",
                    lastSummaryAt: 500,
                    lastEventAt: 500
                )
            ]
        )
        AXProjectRegistryStore.save(registry)

        let review = XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: "uir-project-prompt",
            projectID: projectId,
            bundleID: "bundle-project-prompt",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-project-prompt.json",
            surfaceType: .browserPage,
            probeDepth: .deep,
            objective: "browser_page_actionability",
            verdict: .attentionNeeded,
            confidence: .medium,
            sufficientEvidence: true,
            objectiveReady: false,
            interactiveTargetCount: 0,
            criticalActionExpected: true,
            criticalActionVisible: false,
            issueCodes: ["interactive_target_missing", "critical_action_not_visible"],
            checks: [
                XTUIReviewCheck(
                    code: "interactive_target_present",
                    status: .warning,
                    detail: "No interactive targets were detected in the captured structure."
                ),
                XTUIReviewCheck(
                    code: "critical_action_not_visible",
                    status: .warning,
                    detail: "The page looks like a login or gated flow, but no likely primary action was detected."
                )
            ],
            summary: "attention needed; confidence=medium; issues=interactive_target_missing,critical_action_not_visible",
            createdAtMs: 500_000,
            auditRef: "audit-project-prompt"
        )
        _ = try XTUIReviewStore.writeReview(review, for: ctx)

        let session = ChatSessionModel()
        let memory = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "# X-Terminal Memory\n\n## Goal\nShip reliable UI automation.",
            recentText: "user: continue from the last browser review",
            userText: "继续推进当前页面的自动化"
        )

        #expect(memory.contains("[latest_ui_review]"))
        #expect(memory.contains("verdict: attention_needed"))
        #expect(memory.contains("ui_review: ref=local://.xterminal/ui_review/reviews/uir-project-prompt.json"))
        #expect(memory.contains("latest_ui_review:"))
        #expect(memory.contains("critical_action_not_visible"))
        #expect(memory.contains("checks:"))
    }
}
