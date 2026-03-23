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

        let bundle = XTUIObservationBundle(
            schemaVersion: XTUIObservationBundle.currentSchemaVersion,
            bundleID: "bundle-project-prompt",
            projectID: projectId,
            runID: "run-project-prompt",
            stepID: "step-project-prompt",
            sessionID: "session-project-prompt",
            surfaceType: .browserPage,
            surfaceID: "surface-project-prompt",
            probeDepth: .deep,
            triggerSource: "test",
            captureStatus: .captured,
            captureStartedAtMs: 499_000,
            captureCompletedAtMs: 500_000,
            viewport: XTUIObservationViewport(width: 1280, height: 720, scale: 2),
            environment: XTUIObservationEnvironment(platform: "macos", theme: "light", locale: "en-US"),
            pixelLayer: XTUIObservationPixelLayer(
                status: .captured,
                fullRef: XTUIObservationStore.artifactRef(bundleID: "bundle-project-prompt", relativePath: "full.png"),
                thumbnailRef: XTUIObservationStore.artifactRef(bundleID: "bundle-project-prompt", relativePath: "thumb.png"),
                cropRefs: [],
                width: 1280,
                height: 720
            ),
            structureLayer: XTUIObservationStructureLayer(
                status: .captured,
                roleSnapshotRef: XTUIObservationStore.artifactRef(bundleID: "bundle-project-prompt", relativePath: "role_snapshot.txt"),
                axTreeRef: XTUIObservationStore.artifactRef(bundleID: "bundle-project-prompt", relativePath: "structure.json")
            ),
            textLayer: XTUIObservationTextLayer(
                status: .captured,
                visibleTextRef: XTUIObservationStore.artifactRef(bundleID: "bundle-project-prompt", relativePath: "visible_text.txt"),
                ocrRef: XTUIObservationStore.artifactRef(bundleID: "bundle-project-prompt", relativePath: "ocr.txt")
            ),
            runtimeLayer: XTUIObservationRuntimeLayer(
                status: .captured,
                consoleErrorCount: 1,
                networkErrorCount: 0,
                runtimeLogRef: XTUIObservationStore.artifactRef(bundleID: "bundle-project-prompt", relativePath: "runtime.json")
            ),
            layoutLayer: XTUIObservationLayoutLayer(
                status: .captured,
                layoutMetricsRef: XTUIObservationStore.artifactRef(bundleID: "bundle-project-prompt", relativePath: "layout.json"),
                interactiveTargets: 0,
                visiblePrimaryCTA: false
            ),
            privacy: XTUIObservationPrivacy(classification: "internal", redacted: false, redactionRef: ""),
            acceptancePackRef: "",
            auditRef: "audit-bundle-project-prompt"
        )
        _ = try XTUIObservationStore.writeBundle(
            bundle,
            artifacts: [
                "full.png": Data([0x89, 0x50, 0x4E, 0x47]),
                "thumb.png": Data([0x89, 0x50, 0x4E, 0x47]),
                "visible_text.txt": Data("Login page".utf8),
                "ocr.txt": Data("Login".utf8),
                "role_snapshot.txt": Data("AXButton Sign In".utf8),
                "structure.json": Data("{}".utf8),
                "runtime.json": Data("{}".utf8),
                "layout.json": Data("{}".utf8)
            ],
            for: ctx
        )

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

        let previousReview = XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: "uir-project-prompt-previous",
            projectID: projectId,
            bundleID: "bundle-project-prompt",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-project-prompt.json",
            surfaceType: .browserPage,
            probeDepth: .standard,
            objective: "browser_page_actionability",
            verdict: .ready,
            confidence: .high,
            sufficientEvidence: true,
            objectiveReady: true,
            interactiveTargetCount: 2,
            criticalActionExpected: false,
            criticalActionVisible: false,
            issueCodes: [],
            checks: [
                XTUIReviewCheck(
                    code: "pixel_capture_available",
                    status: .pass,
                    detail: "Screen capture evidence is available for this browser page."
                )
            ],
            summary: "ready; confidence=high; all core review checks passed",
            createdAtMs: 420_000,
            auditRef: "audit-project-prompt-previous"
        )
        _ = try XTUIReviewStore.writeReview(previousReview, for: ctx)
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
        #expect(memory.contains("source_scope=ui_review_agent_evidence"))
        #expect(memory.contains("local://.xterminal/ui_review/agent_evidence/uir-project-prompt.json"))
        #expect(memory.contains("checks:"))
        #expect(memory.contains("artifact_refs:"))
        #expect(memory.contains("screenshot_ref=local://.xterminal/ui_observation/artifacts/bundle-project-prompt/full.png"))
        #expect(memory.contains("visible_text_ref=local://.xterminal/ui_observation/artifacts/bundle-project-prompt/visible_text.txt"))
        #expect(memory.contains("trend:"))
        #expect(memory.contains("status=regressed"))
        #expect(memory.contains("recent_history:"))
        #expect(memory.contains("review_id=uir-project-prompt-previous"))
    }

    @Test
    func projectMemoryBlockDoesNotIncludeSupervisorPersonalMemorySections() {
        let session = ChatSessionModel()

        let memory = session.projectMemoryBlockForTesting(
            canonicalMemory: "# X-Terminal Memory\n\n## Goal\nShip project-scoped delivery only.",
            recentText: "user: continue current project execution",
            userText: "继续推进当前项目"
        )

        #expect(memory.contains("[MEMORY_V1]"))
        #expect(memory.contains("[L0_CONSTITUTION]"))
        #expect(memory.contains("[L1_CANONICAL]"))
        #expect(memory.contains("[L3_WORKING_SET]"))
        #expect(!memory.contains("## Personal Memory Context"))
        #expect(!memory.contains("## Follow-Up Queue Context"))
        #expect(!memory.contains("## Personal Review Context"))
        #expect(!memory.contains("Preferred user name:"))
        #expect(!memory.contains("[CROSS_LINK_REFS]"))
    }

    @Test
    func projectMemoryBlockIncludesStructuredUIReviewRepairContractWhenPendingGuidanceExists() throws {
        let session = ChatSessionModel()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_project_memory_ui_review_repair_contract_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-ui-repair-contract-1",
                reviewId: "review-ui-repair-contract-1",
                projectId: "proj-ui-repair-contract-1",
                targetRole: .projectChat,
                deliveryMode: .stopSignal,
                interventionMode: .stopImmediately,
                safePointPolicy: .immediate,
                guidanceText: """
Repair primary CTA visibility before continuing browser automation.
instruction=Restore a visible primary CTA for the current objective, rerun UI review, then resume automation.
source=ui_review_repair
request_id=req-ui-repair-contract-1
skill_id=browser.runtime.inspect
status=completed
ui_review_ref=local://.xterminal/ui_review/agent_evidence/review-ui-repair-contract-1.json
ui_review_review_id=review-ui-repair-contract-1
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
                auditRef: "audit-guidance-ui-repair-contract-1"
            ),
            for: ctx
        )

        let memory = session.projectMemoryBlockForTesting(
            ctx: ctx,
            canonicalMemory: "# X-Terminal Memory\n\n## Goal\nRecover browser automation safely.",
            recentText: "user: continue from the last browser repair checkpoint",
            userText: "继续推进当前页面的自动化",
            safePointState: SupervisorSafePointExecutionState(
                runStartedAtMs: 1_773_382_100_000,
                flowStep: 1,
                toolResultsCount: 0,
                verifyRunIndex: 0,
                finalizeOnly: false
            )
        )

        #expect(memory.contains("[pending_supervisor_guidance]"))
        #expect(memory.contains("execution_gate: final_only_until_ack"))
        #expect(memory.contains("[ui_review_repair_contract]"))
        #expect(memory.contains("repair_action: repair_primary_cta_visibility"))
        #expect(memory.contains("repair_focus: critical_action"))
        #expect(memory.contains("next_safe_action: open_ui_review"))
        #expect(memory.contains("ui_review_ref: local://.xterminal/ui_review/agent_evidence/review-ui-repair-contract-1.json"))
        #expect(memory.contains("ui_review_issue_codes: critical_action_not_visible,interactive_target_missing"))
        #expect(memory.contains("instruction: Restore a visible primary CTA for the current objective, rerun UI review, then resume automation."))
        #expect(memory.contains("skill_result_summary: deviceBrowserControl completed: Critical CTA missing"))
    }
}
