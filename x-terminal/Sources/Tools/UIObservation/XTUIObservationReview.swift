import Foundation

enum XTUIReviewCheckStatus: String, Codable, Equatable, Sendable {
    case pass
    case warning
    case fail
    case notApplicable = "not_applicable"
}

enum XTUIReviewVerdict: String, Codable, Equatable, Sendable {
    case ready
    case attentionNeeded = "attention_needed"
    case insufficientEvidence = "insufficient_evidence"
}

enum XTUIReviewConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

struct XTUIReviewCheck: Codable, Equatable, Sendable {
    var code: String
    var status: XTUIReviewCheckStatus
    var detail: String
}

struct XTUIReviewRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.ui_review.v1"

    var schemaVersion: String
    var reviewID: String
    var projectID: String
    var bundleID: String
    var bundleRef: String
    var surfaceType: XTUIObservationSurfaceType
    var probeDepth: XTUIObservationProbeDepth
    var objective: String
    var verdict: XTUIReviewVerdict
    var confidence: XTUIReviewConfidence
    var sufficientEvidence: Bool
    var objectiveReady: Bool
    var interactiveTargetCount: Int
    var criticalActionExpected: Bool
    var criticalActionVisible: Bool
    var issueCodes: [String]
    var checks: [XTUIReviewCheck]
    var summary: String
    var createdAtMs: Int64
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case reviewID = "review_id"
        case projectID = "project_id"
        case bundleID = "bundle_id"
        case bundleRef = "bundle_ref"
        case surfaceType = "surface_type"
        case probeDepth = "probe_depth"
        case objective
        case verdict
        case confidence
        case sufficientEvidence = "sufficient_evidence"
        case objectiveReady = "objective_ready"
        case interactiveTargetCount = "interactive_target_count"
        case criticalActionExpected = "critical_action_expected"
        case criticalActionVisible = "critical_action_visible"
        case issueCodes = "issue_codes"
        case checks
        case summary
        case createdAtMs = "created_at_ms"
        case auditRef = "audit_ref"
    }
}

struct XTUIReviewLatestReference: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.ui_review_latest_ref.v1"

    var schemaVersion: String
    var surfaceType: XTUIObservationSurfaceType
    var reviewID: String
    var reviewRef: String
    var bundleID: String
    var bundleRef: String
    var verdict: XTUIReviewVerdict
    var confidence: XTUIReviewConfidence
    var sufficientEvidence: Bool
    var objectiveReady: Bool
    var issueCodes: [String]
    var summary: String
    var updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case surfaceType = "surface_type"
        case reviewID = "review_id"
        case reviewRef = "review_ref"
        case bundleID = "bundle_id"
        case bundleRef = "bundle_ref"
        case verdict
        case confidence
        case sufficientEvidence = "sufficient_evidence"
        case objectiveReady = "objective_ready"
        case issueCodes = "issue_codes"
        case summary
        case updatedAtMs = "updated_at_ms"
    }
}

struct XTUIReviewStoredRecord: Equatable, Sendable {
    var review: XTUIReviewRecord
    var reviewRef: String
}

enum XTUIReviewStore {
    static func loadLatestBrowserPageReference(for ctx: AXProjectContext) -> XTUIReviewLatestReference? {
        guard FileManager.default.fileExists(atPath: ctx.uiReviewLatestBrowserPageURL.path),
              let data = try? Data(contentsOf: ctx.uiReviewLatestBrowserPageURL),
              let ref = try? JSONDecoder().decode(XTUIReviewLatestReference.self, from: data) else {
            return nil
        }
        return ref
    }

    static func loadLatestBrowserPageReview(for ctx: AXProjectContext) -> XTUIReviewRecord? {
        guard let latest = loadLatestBrowserPageReference(for: ctx) else {
            return nil
        }
        return loadReview(ref: latest.reviewRef, for: ctx)
    }

    static func loadReview(ref: String, for ctx: AXProjectContext) -> XTUIReviewRecord? {
        guard let url = XTUIObservationStore.resolveLocalRef(ref, for: ctx),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let review = try? JSONDecoder().decode(XTUIReviewRecord.self, from: data) else {
            return nil
        }
        return review
    }

    static func loadRecentBrowserPageReviews(
        for ctx: AXProjectContext,
        limit: Int = 5
    ) -> [XTUIReviewStoredRecord] {
        guard FileManager.default.fileExists(atPath: ctx.uiReviewRecordsDir.path),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: ctx.uiReviewRecordsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> XTUIReviewStoredRecord? in
                guard let data = try? Data(contentsOf: url),
                      let review = try? JSONDecoder().decode(XTUIReviewRecord.self, from: data) else {
                    return nil
                }
                return XTUIReviewStoredRecord(
                    review: review,
                    reviewRef: reviewRef(reviewID: review.reviewID)
                )
            }
            .sorted { lhs, rhs in
                if lhs.review.createdAtMs == rhs.review.createdAtMs {
                    return lhs.review.reviewID > rhs.review.reviewID
                }
                return lhs.review.createdAtMs > rhs.review.createdAtMs
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    static func reviewRef(reviewID: String) -> String {
        "local://.xterminal/ui_review/reviews/\(reviewID).json"
    }

    static func writeReview(
        _ review: XTUIReviewRecord,
        for ctx: AXProjectContext
    ) throws -> XTUIReviewStoredRecord {
        try ensureDirs(for: ctx)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reviewData = try encoder.encode(review)
        try writeAtomic(data: reviewData, to: ctx.uiReviewRecordURL(reviewID: review.reviewID))

        let latest = XTUIReviewLatestReference(
            schemaVersion: XTUIReviewLatestReference.currentSchemaVersion,
            surfaceType: review.surfaceType,
            reviewID: review.reviewID,
            reviewRef: reviewRef(reviewID: review.reviewID),
            bundleID: review.bundleID,
            bundleRef: review.bundleRef,
            verdict: review.verdict,
            confidence: review.confidence,
            sufficientEvidence: review.sufficientEvidence,
            objectiveReady: review.objectiveReady,
            issueCodes: review.issueCodes,
            summary: review.summary,
            updatedAtMs: review.createdAtMs
        )
        let latestData = try encoder.encode(latest)
        try writeAtomic(data: latestData, to: ctx.uiReviewLatestBrowserPageURL)

        if let evidence = XTUIReviewPromptDigest.agentEvidenceSnapshot(
            for: ctx,
            maxChecks: 8,
            maxHistoryItems: 5
        ) {
            try? XTUIReviewAgentEvidenceStore.write(evidence, for: ctx)
        }

        return XTUIReviewStoredRecord(review: review, reviewRef: latest.reviewRef)
    }

    private static func ensureDirs(for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        try FileManager.default.createDirectory(at: ctx.uiReviewDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ctx.uiReviewRecordsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ctx.uiReviewAgentEvidenceDir, withIntermediateDirectories: true)
    }

    private static func writeAtomic(data: Data, to url: URL) throws {
        try XTStoreWriteSupport.writeSnapshotData(data, to: url)
    }
}

enum XTBrowserUIReviewEngine {
    static func review(
        storedBundle: XTUIObservationStoredBundle,
        ctx: AXProjectContext
    ) throws -> XTUIReviewStoredRecord {
        let bundle = storedBundle.bundle
        let visibleText = loadTextArtifact(ref: bundle.textLayer.visibleTextRef, ctx: ctx)
        let runtimeArtifact = loadRuntimeArtifact(ref: bundle.runtimeLayer.runtimeLogRef, ctx: ctx)

        let pixelAvailable = bundle.pixelLayer.status == .captured
        let structureAvailable = bundle.structureLayer.status == .captured
        let runtimeAvailable = bundle.runtimeLayer.status == .captured
        let interactiveTargets = structureAvailable ? max(0, bundle.layoutLayer.interactiveTargets) : 0
        let hasVisibleText = usefulVisibleTextPresent(visibleText)
        let criticalActionExpected = shouldExpectCriticalAction(
            currentURL: runtimeArtifact?.currentURL ?? "",
            visibleText: visibleText
        )
        let criticalActionVisible = structureAvailable && bundle.layoutLayer.visiblePrimaryCTA

        var checks: [XTUIReviewCheck] = []
        var issueCodes: [String] = []

        func addCheck(
            _ code: String,
            status: XTUIReviewCheckStatus,
            detail: String,
            issueCode: String? = nil
        ) {
            checks.append(XTUIReviewCheck(code: code, status: status, detail: detail))
            guard let issueCode, status == .warning || status == .fail else {
                return
            }
            if !issueCodes.contains(issueCode) {
                issueCodes.append(issueCode)
            }
        }

        if pixelAvailable {
            addCheck(
                "pixel_capture_available",
                status: .pass,
                detail: "Screen capture evidence is available for this browser page."
            )
        } else {
            addCheck(
                "pixel_capture_available",
                status: .warning,
                detail: "Screen capture evidence is unavailable, so pixel-level review is missing.",
                issueCode: "pixel_capture_missing"
            )
        }

        if structureAvailable {
            addCheck(
                "structure_capture_available",
                status: .pass,
                detail: "Accessibility structure evidence is available for this browser page."
            )
        } else {
            addCheck(
                "structure_capture_available",
                status: .warning,
                detail: "Accessibility structure evidence is unavailable, so layout semantics are incomplete.",
                issueCode: "structure_capture_missing"
            )
        }

        if hasVisibleText {
            addCheck(
                "visible_text_available",
                status: .pass,
                detail: "Visible UI text is available for local reasoning."
            )
        } else {
            addCheck(
                "visible_text_available",
                status: .warning,
                detail: "Visible UI text is missing or too weak to support reliable local reasoning.",
                issueCode: "visible_text_missing"
            )
        }

        if runtimeAvailable {
            addCheck(
                "runtime_capture_available",
                status: .pass,
                detail: "Browser runtime evidence is available."
            )
        } else {
            addCheck(
                "runtime_capture_available",
                status: .fail,
                detail: "Browser runtime evidence is missing, so the page cannot be trusted for automation review.",
                issueCode: "runtime_capture_missing"
            )
        }

        if structureAvailable {
            if interactiveTargets > 0 {
                addCheck(
                    "interactive_target_present",
                    status: .pass,
                    detail: "The captured structure exposes \(interactiveTargets) interactive target(s)."
                )
            } else {
                addCheck(
                    "interactive_target_present",
                    status: .warning,
                    detail: "No interactive targets were detected in the captured structure.",
                    issueCode: "interactive_target_missing"
                )
            }
        } else {
            addCheck(
                "interactive_target_present",
                status: .notApplicable,
                detail: "Interactive target detection is unavailable without structure capture."
            )
        }

        if criticalActionExpected {
            if structureAvailable, criticalActionVisible {
                addCheck(
                    "critical_action_not_visible",
                    status: .pass,
                    detail: "A likely primary action is visible in the current browser page."
                )
            } else if structureAvailable {
                addCheck(
                    "critical_action_not_visible",
                    status: .warning,
                    detail: "The page looks like a login or gated flow, but no likely primary action was detected.",
                    issueCode: "critical_action_not_visible"
                )
            } else {
                addCheck(
                    "critical_action_not_visible",
                    status: .notApplicable,
                    detail: "Primary action visibility could not be evaluated without structure capture."
                )
            }
        } else {
            addCheck(
                "critical_action_not_visible",
                status: .notApplicable,
                detail: "No critical action expectation was inferred from the current page context."
            )
        }

        let confidence = reviewConfidence(
            pixelAvailable: pixelAvailable,
            structureAvailable: structureAvailable,
            hasVisibleText: hasVisibleText,
            runtimeAvailable: runtimeAvailable
        )
        let sufficientEvidence = runtimeAvailable && (pixelAvailable || structureAvailable || hasVisibleText)
        let verdict: XTUIReviewVerdict
        if !sufficientEvidence || checks.contains(where: { $0.status == .fail }) {
            verdict = .insufficientEvidence
        } else if checks.contains(where: { $0.status == .warning }) {
            verdict = .attentionNeeded
        } else {
            verdict = .ready
        }

        let review = XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: "uir-\(Int(Date().timeIntervalSince1970))-\(shortID())",
            projectID: bundle.projectID,
            bundleID: bundle.bundleID,
            bundleRef: XTUIObservationStore.bundleRef(bundleID: bundle.bundleID),
            surfaceType: bundle.surfaceType,
            probeDepth: bundle.probeDepth,
            objective: "browser_page_actionability",
            verdict: verdict,
            confidence: confidence,
            sufficientEvidence: sufficientEvidence,
            objectiveReady: verdict == .ready,
            interactiveTargetCount: interactiveTargets,
            criticalActionExpected: criticalActionExpected,
            criticalActionVisible: criticalActionVisible,
            issueCodes: issueCodes,
            checks: checks,
            summary: buildSummary(
                verdict: verdict,
                confidence: confidence,
                issueCodes: issueCodes,
                interactiveTargets: interactiveTargets,
                criticalActionExpected: criticalActionExpected,
                criticalActionVisible: criticalActionVisible
            ),
            createdAtMs: bundle.captureCompletedAtMs,
            auditRef: bundle.auditRef
        )
        return try XTUIReviewStore.writeReview(review, for: ctx)
    }

    private static func loadTextArtifact(ref: String, ctx: AXProjectContext) -> String {
        guard let url = XTUIObservationStore.resolveLocalRef(ref, for: ctx),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadRuntimeArtifact(
        ref: String,
        ctx: AXProjectContext
    ) -> XTUIReviewRuntimeArtifact? {
        guard let url = XTUIObservationStore.resolveLocalRef(ref, for: ctx),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let artifact = try? JSONDecoder().decode(XTUIReviewRuntimeArtifact.self, from: data) else {
            return nil
        }
        return artifact
    }

    private static func usefulVisibleTextPresent(_ raw: String) -> Bool {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { $0 != "(no visible text available)" }
            .filter { !$0.hasPrefix("current_url=") }
        return !lines.isEmpty
    }

    private static func shouldExpectCriticalAction(
        currentURL: String,
        visibleText: String
    ) -> Bool {
        let haystack = [currentURL, visibleText]
            .joined(separator: " ")
            .lowercased()
        guard !haystack.isEmpty else { return false }
        let tokens = [
            "login",
            "sign in",
            "signin",
            "log in",
            "checkout",
            "payment",
            "verify",
            "password",
            "continue",
            "create account",
            "register"
        ]
        return tokens.contains(where: { haystack.contains($0) })
    }

    private static func reviewConfidence(
        pixelAvailable: Bool,
        structureAvailable: Bool,
        hasVisibleText: Bool,
        runtimeAvailable: Bool
    ) -> XTUIReviewConfidence {
        if runtimeAvailable && pixelAvailable && structureAvailable && hasVisibleText {
            return .high
        }
        if runtimeAvailable && ((structureAvailable && hasVisibleText) || (pixelAvailable && hasVisibleText) || (pixelAvailable && structureAvailable)) {
            return .medium
        }
        return .low
    }

    private static func buildSummary(
        verdict: XTUIReviewVerdict,
        confidence: XTUIReviewConfidence,
        issueCodes: [String],
        interactiveTargets: Int,
        criticalActionExpected: Bool,
        criticalActionVisible: Bool
    ) -> String {
        var fragments: [String] = []
        switch verdict {
        case .ready:
            fragments.append("ready")
        case .attentionNeeded:
            fragments.append("attention needed")
        case .insufficientEvidence:
            fragments.append("insufficient evidence")
        }
        fragments.append("confidence=\(confidence.rawValue)")

        if issueCodes.isEmpty {
            fragments.append("all core review checks passed")
        } else {
            fragments.append("issues=\(issueCodes.joined(separator: ","))")
        }

        if interactiveTargets > 0 {
            fragments.append("interactive_targets=\(interactiveTargets)")
        }
        if criticalActionExpected {
            fragments.append(criticalActionVisible ? "critical_action=visible" : "critical_action=not_visible")
        }
        return fragments.joined(separator: "; ")
    }

    private static func shortID() -> String {
        String(UUID().uuidString.lowercased().prefix(8))
    }
}

enum XTUIReviewPromptDigest {
    static func inlineSummary(_ latest: XTUIReviewLatestReference?) -> String {
        guard let latest else { return "" }
        return [
            "ref=\(normalizedReviewValue(latest.reviewRef, fallback: "(none)"))",
            "verdict=\(latest.verdict.rawValue)",
            "confidence=\(latest.confidence.rawValue)",
            "sufficient_evidence=\(latest.sufficientEvidence)",
            "objective_ready=\(latest.objectiveReady)",
            "issues=\(issueCodesText(latest.issueCodes))",
            "summary=\(cappedReviewText(latest.summary, maxChars: 180))"
        ].joined(separator: " ")
    }

    static func promptBlock(for ctx: AXProjectContext) -> String {
        guard let latest = XTUIReviewStore.loadLatestBrowserPageReference(for: ctx) else {
            return ""
        }
        let review = XTUIReviewStore.loadLatestBrowserPageReview(for: ctx)
        let presentation = XTUIReviewPresentation.loadLatestBrowserPage(for: ctx)
        let checksText = formatEvidenceList(
            review?.checks.prefix(3).map { check in
                evidenceEntry(
                    check.code,
                    "\(check.status.rawValue) :: \(cappedReviewText(check.detail, maxChars: 120))"
                )
            } ?? []
        )
        let trendText = formatEvidenceList(
            presentation.map {
                [
                    evidenceEntry("status", trendStatusText($0.trend?.status)),
                    evidenceEntry("headline", $0.trend?.headline),
                    evidenceEntry("detail", $0.trend?.detail)
                ]
            } ?? []
        )
        let recentHistoryText = formatEvidenceList(
            recentHistoryEntries(for: presentation, maxItems: 3)
        )
        var lines = [
            """
[latest_ui_review]
review_ref: \(normalizedReviewValue(latest.reviewRef, fallback: "(none)"))
bundle_ref: \(normalizedReviewValue(latest.bundleRef, fallback: "(none)"))
verdict: \(latest.verdict.rawValue)
confidence: \(latest.confidence.rawValue)
sufficient_evidence: \(latest.sufficientEvidence)
objective_ready: \(latest.objectiveReady)
issue_codes: \(issueCodesText(latest.issueCodes))
summary: \(cappedReviewText(latest.summary, maxChars: 220))
"""
        ]
        if review?.checks.isEmpty == false {
            lines.append("checks:\n\(checksText)")
        }
        if presentation?.trend != nil {
            lines.append("trend:\n\(trendText)")
        }
        if !(presentation?.recentHistory.isEmpty ?? true) {
            lines.append("recent_history:\n\(recentHistoryText)")
        }
        lines.append("[/latest_ui_review]")
        return lines.joined(separator: "\n")
    }

    static func agentEvidenceSnapshot(
        for ctx: AXProjectContext,
        maxChecks: Int = 4,
        maxHistoryItems: Int = 3
    ) -> XTUIReviewAgentEvidenceSnapshot? {
        guard let latest = XTUIReviewStore.loadLatestBrowserPageReference(for: ctx),
              let review = XTUIReviewStore.loadLatestBrowserPageReview(for: ctx) else {
            return nil
        }
        let presentation = XTUIReviewPresentation.loadLatestBrowserPage(for: ctx)
        let bundle = XTUIObservationStore.loadBundle(ref: latest.bundleRef, for: ctx)
        let checks = review.checks
            .prefix(max(1, maxChecks))
            .map { check in
                "\(check.code)=\(check.status.rawValue) :: \(cappedReviewText(check.detail, maxChars: 140))"
            }

        return XTUIReviewAgentEvidenceSnapshot(
            schemaVersion: XTUIReviewAgentEvidenceSnapshot.currentSchemaVersion,
            reviewID: review.reviewID,
            projectID: review.projectID,
            bundleID: review.bundleID,
            auditRef: review.auditRef,
            reviewRef: normalizedReviewValue(latest.reviewRef, fallback: "(none)"),
            bundleRef: normalizedReviewValue(latest.bundleRef, fallback: "(none)"),
            updatedAtMs: latest.updatedAtMs,
            verdict: latest.verdict,
            confidence: latest.confidence,
            sufficientEvidence: latest.sufficientEvidence,
            objectiveReady: latest.objectiveReady,
            issueCodes: review.issueCodes,
            summary: cappedReviewText(latest.summary, maxChars: 220),
            artifactRefs: [
                evidenceEntry("screenshot_ref", bundle?.pixelLayer.fullRef),
                evidenceEntry("thumbnail_ref", bundle?.pixelLayer.thumbnailRef),
                evidenceEntry("visible_text_ref", bundle?.textLayer.visibleTextRef),
                evidenceEntry("ocr_ref", bundle?.textLayer.ocrRef),
                evidenceEntry("runtime_log_ref", bundle?.runtimeLayer.runtimeLogRef),
                evidenceEntry("layout_metrics_ref", bundle?.layoutLayer.layoutMetricsRef),
                evidenceEntry("role_snapshot_ref", bundle?.structureLayer.roleSnapshotRef),
                evidenceEntry("ax_tree_ref", bundle?.structureLayer.axTreeRef)
            ].compactMap { $0 },
            artifactPaths: [
                evidenceEntry("review_path", presentation?.reviewFileURL?.path),
                evidenceEntry("bundle_path", presentation?.bundleFileURL?.path),
                evidenceEntry("screenshot_path", presentation?.screenshotFileURL?.path),
                evidenceEntry("visible_text_path", presentation?.visibleTextFileURL?.path)
            ].compactMap { $0 },
            checks: checks,
            trend: (presentation.map {
                [
                    evidenceEntry("status", trendStatusText($0.trend?.status)),
                    evidenceEntry("headline", $0.trend?.headline),
                    evidenceEntry("detail", $0.trend?.detail)
                ]
            } ?? []).compactMap { $0 },
            comparison: comparisonEntries(for: presentation).compactMap { $0 },
            recentHistory: recentHistoryEntries(for: presentation, maxItems: maxHistoryItems).compactMap { $0 }
        )
    }

    static func evidenceBlock(for ctx: AXProjectContext, maxChecks: Int = 4) -> String {
        agentEvidenceSnapshot(for: ctx, maxChecks: maxChecks)?.renderedText() ?? ""
    }
}

struct XTUIReviewAgentEvidenceSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.ui_review_agent_evidence.v1"

    var schemaVersion: String
    var reviewID: String
    var projectID: String
    var bundleID: String
    var auditRef: String
    var reviewRef: String
    var bundleRef: String
    var updatedAtMs: Int64
    var verdict: XTUIReviewVerdict
    var confidence: XTUIReviewConfidence
    var sufficientEvidence: Bool
    var objectiveReady: Bool
    var issueCodes: [String]
    var summary: String
    var artifactRefs: [String]
    var artifactPaths: [String]
    var checks: [String]
    var trend: [String]
    var comparison: [String]
    var recentHistory: [String]

    func renderedText() -> String {
        let checksText = checks.isEmpty ? "- (none)" : checks.map { "- \($0)" }.joined(separator: "\n")
        return """
ref=\(reviewRef)
bundle_ref=\(bundleRef)
updated_at_ms=\(updatedAtMs)
verdict=\(verdict.rawValue)
confidence=\(confidence.rawValue)
sufficient_evidence=\(sufficientEvidence)
objective_ready=\(objectiveReady)
issue_codes=\(issueCodesText(issueCodes))
summary=\(summary)
artifact_refs:
\(formatEvidenceList(artifactRefs))
artifact_paths:
\(formatEvidenceList(artifactPaths))
checks:
\(checksText)
trend:
\(formatEvidenceList(trend))
comparison:
\(formatEvidenceList(comparison))
recent_history:
\(formatEvidenceList(recentHistory))
"""
    }
}

enum XTUIReviewAgentEvidenceStore {
    static let latestBrowserPageRef = "local://.xterminal/ui_review/agent_evidence/latest_browser_page.json"

    static func reviewRef(reviewID: String) -> String {
        let safe = sanitizedReviewAgentEvidenceToken(reviewID)
        return "local://.xterminal/ui_review/agent_evidence/\(safe).json"
    }

    static func write(
        _ snapshot: XTUIReviewAgentEvidenceSnapshot,
        for ctx: AXProjectContext
    ) throws {
        try ctx.ensureDirs()
        try FileManager.default.createDirectory(at: ctx.uiReviewDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ctx.uiReviewAgentEvidenceDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try XTStoreWriteSupport.writeSnapshotData(data, to: ctx.uiReviewAgentEvidenceURL(reviewID: snapshot.reviewID))
        try XTStoreWriteSupport.writeSnapshotData(data, to: ctx.uiReviewLatestBrowserPageAgentEvidenceURL)
    }

    static func loadLatestBrowserPage(for ctx: AXProjectContext) -> XTUIReviewAgentEvidenceSnapshot? {
        guard let data = try? Data(contentsOf: ctx.uiReviewLatestBrowserPageAgentEvidenceURL) else {
            return nil
        }
        return try? JSONDecoder().decode(XTUIReviewAgentEvidenceSnapshot.self, from: data)
    }

    static func load(reviewID: String, for ctx: AXProjectContext) -> XTUIReviewAgentEvidenceSnapshot? {
        guard let data = try? Data(contentsOf: ctx.uiReviewAgentEvidenceURL(reviewID: reviewID)) else {
            return nil
        }
        return try? JSONDecoder().decode(XTUIReviewAgentEvidenceSnapshot.self, from: data)
    }

    static func load(ref: String, for ctx: AXProjectContext) -> XTUIReviewAgentEvidenceSnapshot? {
        let normalized = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if normalized == latestBrowserPageRef {
            return loadLatestBrowserPage(for: ctx)
        }

        let prefix = "local://.xterminal/ui_review/agent_evidence/"
        guard normalized.hasPrefix(prefix) else { return nil }
        let token = String(normalized.dropFirst(prefix.count))
        guard token.hasSuffix(".json") else { return nil }
        let reviewID = String(token.dropLast(".json".count))
        guard !reviewID.isEmpty else { return nil }
        return load(reviewID: reviewID, for: ctx)
    }
}

private func evidenceEntry(_ label: String, _ value: String?) -> String? {
    let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return "\(label)=\(trimmed)"
}

private func formatEvidenceList(_ items: [String?]) -> String {
    let lines = items.compactMap { $0 }
    guard !lines.isEmpty else { return "- (none)" }
    return lines.map { "- \($0)" }.joined(separator: "\n")
}

private func trendStatusText(_ status: XTUIReviewTrendStatus?) -> String? {
    switch status {
    case .improved:
        return "improved"
    case .stable:
        return "stable"
    case .regressed:
        return "regressed"
    case nil:
        return nil
    }
}

private func comparisonEntries(
    for presentation: XTUIReviewPresentation?
) -> [String?] {
    guard let comparison = presentation?.comparison else {
        return []
    }

    var entries: [String?] = [
        evidenceEntry(
            "added_issues",
            comparison.addedIssueLabels.isEmpty ? "(none)" : comparison.addedIssueLabels.joined(separator: ", ")
        ),
        evidenceEntry(
            "resolved_issues",
            comparison.resolvedIssueLabels.isEmpty ? "(none)" : comparison.resolvedIssueLabels.joined(separator: ", ")
        )
    ]

    entries.append(
        contentsOf: comparison.metrics.prefix(4).map { metric in
            Optional("metric=\(metric.label) | \(comparisonToneText(metric.tone)) | \(metric.detail)")
        }
    )
    return entries
}

private func recentHistoryEntries(
    for presentation: XTUIReviewPresentation?,
    maxItems: Int
) -> [String?] {
    guard let presentation else { return [] }
    return presentation.recentHistory.prefix(max(1, maxItems)).map { item in
        let issues = item.issueCodes.isEmpty ? "(none)" : item.issueCodes.joined(separator: ",")
        return "review_id=\(item.reviewID) verdict=\(item.verdict.rawValue) confidence=\(item.confidence.rawValue) objective_ready=\(item.objectiveReady) issues=\(issues) updated_at_ms=\(item.updatedAtMs) review_ref=\(item.reviewRef)"
    }
}

private func comparisonToneText(_ tone: XTUIReviewDiffTone) -> String {
    switch tone {
    case .improved:
        return "improved"
    case .stable:
        return "stable"
    case .regressed:
        return "regressed"
    }
}

private func normalizedReviewValue(_ raw: String, fallback: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func sanitizedReviewAgentEvidenceToken(_ raw: String) -> String {
    let base = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: ":", with: "_")
    return base.isEmpty ? UUID().uuidString.lowercased() : base
}

private func issueCodesText(_ issueCodes: [String]) -> String {
    let cleaned = issueCodes
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return cleaned.isEmpty ? "(none)" : cleaned.joined(separator: ",")
}

private func cappedReviewText(_ raw: String, maxChars: Int) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "(none)" }
    guard trimmed.count > max(1, maxChars) else { return trimmed }
    let end = trimmed.index(trimmed.startIndex, offsetBy: max(1, maxChars))
    return String(trimmed[..<end]) + "..."
}

private struct XTUIReviewRuntimeArtifact: Codable, Equatable, Sendable {
    var sessionID: String
    var currentURL: String
    var browserEngine: String
    var transport: String
    var browserRuntimeSnapshotRef: String
    var actionMode: String
    var projectID: String
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case currentURL = "current_url"
        case browserEngine = "browser_engine"
        case transport
        case browserRuntimeSnapshotRef = "browser_runtime_snapshot_ref"
        case actionMode = "action_mode"
        case projectID = "project_id"
        case auditRef = "audit_ref"
    }
}
