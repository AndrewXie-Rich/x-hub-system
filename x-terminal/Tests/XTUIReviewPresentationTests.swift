import Foundation
import Testing
@testable import XTerminal

struct XTUIReviewPresentationTests {
    @Test
    func loadLatestBrowserPageBuildsFriendlyReadableFields() throws {
        let root = try makeProjectRoot(named: "ui-review-presentation")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let bundle = XTUIObservationBundle(
            schemaVersion: XTUIObservationBundle.currentSchemaVersion,
            bundleID: "bundle-presentation-test",
            projectID: AXProjectRegistryStore.projectId(forRoot: root),
            runID: "run-presentation",
            stepID: "step-presentation",
            sessionID: "session-presentation",
            surfaceType: .browserPage,
            surfaceID: "surface-presentation",
            probeDepth: .deep,
            triggerSource: "test",
            captureStatus: .captured,
            captureStartedAtMs: 590_000,
            captureCompletedAtMs: 600_000,
            viewport: XTUIObservationViewport(width: 1280, height: 720, scale: 2),
            environment: XTUIObservationEnvironment(platform: "macos", theme: "light", locale: "en-US"),
            pixelLayer: XTUIObservationPixelLayer(
                status: .captured,
                fullRef: XTUIObservationStore.artifactRef(bundleID: "bundle-presentation-test", relativePath: "full.png"),
                thumbnailRef: XTUIObservationStore.artifactRef(bundleID: "bundle-presentation-test", relativePath: "full.png"),
                cropRefs: [],
                width: 1280,
                height: 720
            ),
            structureLayer: XTUIObservationStructureLayer(
                status: .captured,
                roleSnapshotRef: XTUIObservationStore.artifactRef(bundleID: "bundle-presentation-test", relativePath: "role_snapshot.txt"),
                axTreeRef: XTUIObservationStore.artifactRef(bundleID: "bundle-presentation-test", relativePath: "structure.json")
            ),
            textLayer: XTUIObservationTextLayer(
                status: .captured,
                visibleTextRef: XTUIObservationStore.artifactRef(bundleID: "bundle-presentation-test", relativePath: "visible_text.txt"),
                ocrRef: ""
            ),
            runtimeLayer: XTUIObservationRuntimeLayer(
                status: .captured,
                consoleErrorCount: 0,
                networkErrorCount: 0,
                runtimeLogRef: XTUIObservationStore.artifactRef(bundleID: "bundle-presentation-test", relativePath: "runtime.json")
            ),
            layoutLayer: XTUIObservationLayoutLayer(
                status: .captured,
                layoutMetricsRef: XTUIObservationStore.artifactRef(bundleID: "bundle-presentation-test", relativePath: "layout.json"),
                interactiveTargets: 0,
                visiblePrimaryCTA: false
            ),
            privacy: XTUIObservationPrivacy(classification: "internal", redacted: false, redactionRef: ""),
            acceptancePackRef: "",
            auditRef: "audit-bundle-presentation"
        )
        _ = try XTUIObservationStore.writeBundle(
            bundle,
            artifacts: [
                "full.png": Data([0x89, 0x50, 0x4E, 0x47]),
                "visible_text.txt": Data("Login page".utf8),
                "role_snapshot.txt": Data("AXButton Sign In".utf8),
                "structure.json": Data("{}".utf8),
                "runtime.json": Data("{}".utf8),
                "layout.json": Data("{}".utf8)
            ],
            for: ctx
        )

        let review = XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: "uir-presentation-test",
            projectID: AXProjectRegistryStore.projectId(forRoot: root),
            bundleID: "bundle-presentation-test",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-presentation-test.json",
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
                )
            ],
            summary: "attention needed; confidence=medium; issues=interactive_target_missing,critical_action_not_visible",
            createdAtMs: 600_000,
            auditRef: "audit-ui-review-presentation"
        )
        _ = try XTUIReviewStore.writeReview(review, for: ctx)

        let olderReview = XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: "uir-presentation-older",
            projectID: AXProjectRegistryStore.projectId(forRoot: root),
            bundleID: "bundle-presentation-test",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-presentation-test.json",
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
            createdAtMs: 500_000,
            auditRef: "audit-ui-review-presentation-older"
        )
        _ = try XTUIReviewStore.writeReview(olderReview, for: ctx)

        _ = try XTUIReviewStore.writeReview(review, for: ctx)

        let presentation = try #require(XTUIReviewPresentation.loadLatestBrowserPage(for: ctx))
        let agentEvidence = try #require(
            XTUIReviewPromptDigest.agentEvidenceSnapshot(for: ctx, maxChecks: 2, maxHistoryItems: 2)
        )
        #expect(presentation.verdictLabel == "需关注")
        #expect(presentation.confidenceLabel == "中")
        #expect(presentation.evidenceLabel == "证据充分")
        #expect(presentation.objectiveLabel == "暂不建议直接执行")
        #expect(presentation.issueLabels == ["未识别可交互目标", "未看到关键操作"])
        #expect(presentation.issueSummary == "未识别可交互目标 · 未看到关键操作")
        #expect(presentation.compactStatusText == "UI review · 需关注 · 未识别可交互目标 · 未看到关键操作")
        #expect(presentation.interactiveTargetSummary == "未识别可交互目标")
        #expect(presentation.criticalActionSummary == "关键动作缺失")
        #expect(presentation.checks.count == 1)
        #expect(presentation.checks.first?.codeLabel == "可交互目标")
        #expect(presentation.relativeUpdatedText(now: Date(timeIntervalSince1970: 960)) == "6分钟前")
        #expect(presentation.reviewRef == "local://.xterminal/ui_review/reviews/uir-presentation-test.json")
        #expect(presentation.reviewFileURL?.lastPathComponent == "uir-presentation-test.json")
        #expect(presentation.bundleFileURL?.lastPathComponent == "bundle-presentation-test.json")
        #expect(presentation.screenshotFileURL?.lastPathComponent == "full.png")
        #expect(presentation.visibleTextFileURL?.lastPathComponent == "visible_text.txt")
        #expect(presentation.recentHistory.count == 1)
        #expect(presentation.recentHistory.first?.reviewID == "uir-presentation-older")
        #expect(presentation.recentHistory.first?.verdictLabel == "可行动")
        #expect(presentation.trend?.status == .regressed)
        #expect(presentation.trend?.headline == "较上次退化")
        #expect(presentation.trend?.detail.contains("问题数 0 -> 2") == true)
        #expect(presentation.comparison?.addedIssueLabels == ["未看到关键操作", "未识别可交互目标"])
        #expect(presentation.comparison?.resolvedIssueLabels == [])
        #expect(presentation.comparison?.metrics.contains(where: {
            $0.label == "结论" && $0.detail == "可行动 -> 需关注" && $0.tone == .regressed
        }) == true)
        #expect(presentation.comparison?.metrics.contains(where: {
            $0.label == "交互目标" && $0.detail == "2 -> 0 (-2)" && $0.tone == .regressed
        }) == true)
        #expect(presentation.comparison?.metrics.contains(where: {
            $0.label == "关键动作" && $0.detail == "不适用 -> 缺失" && $0.tone == .regressed
        }) == true)
        #expect(presentation.comparison?.metrics.contains(where: {
            $0.label == "可执行性" && $0.detail == "由可直接执行变为暂不建议直接执行" && $0.tone == .regressed
        }) == true)
        #expect(agentEvidence.reviewRef == "local://.xterminal/ui_review/reviews/uir-presentation-test.json")
        #expect(agentEvidence.reviewID == "uir-presentation-test")
        #expect(agentEvidence.projectID == AXProjectRegistryStore.projectId(forRoot: root))
        #expect(agentEvidence.auditRef == "audit-ui-review-presentation")
        #expect(agentEvidence.checks.count == 1)
        #expect(agentEvidence.artifactRefs.contains("screenshot_ref=local://.xterminal/ui_observation/artifacts/bundle-presentation-test/full.png"))
        #expect(agentEvidence.artifactRefs.contains("visible_text_ref=local://.xterminal/ui_observation/artifacts/bundle-presentation-test/visible_text.txt"))
        #expect(agentEvidence.trend.contains("status=regressed"))
        #expect(agentEvidence.recentHistory.contains(where: { $0.contains("review_id=uir-presentation-older") }))
        #expect(agentEvidence.renderedText().contains("recent_history:"))
        #expect(agentEvidence.renderedText().contains("comparison:"))

        let history = XTUIReviewPresentation.loadHistory(for: ctx, limit: 5)
        #expect(history.count == 2)
        #expect(history.first?.reviewID == "uir-presentation-test")
        #expect(history.last?.reviewID == "uir-presentation-older")
        #expect(history.first?.bundleFileURL?.lastPathComponent == "bundle-presentation-test.json")
        #expect(history.first?.screenshotFileURL?.lastPathComponent == "full.png")
        #expect(history.first?.visibleTextFileURL?.lastPathComponent == "visible_text.txt")
        #expect(history.last?.issueSummary == "核心检查通过")

        let comparison = XTUIReviewDiffPresentation.compare(latest: history[0], previous: history[1])
        #expect(comparison.addedIssueLabels == ["未看到关键操作", "未识别可交互目标"])
        #expect(comparison.resolvedIssueLabels.isEmpty)
    }

    @Test
    func loadLatestBrowserPageReturnsNilWhenReviewDoesNotExist() throws {
        let root = try makeProjectRoot(named: "ui-review-presentation-empty")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        #expect(XTUIReviewPresentation.loadLatestBrowserPage(for: ctx) == nil)
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_ui_review_presentation_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
