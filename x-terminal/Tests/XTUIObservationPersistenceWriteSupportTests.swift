import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTUIObservationPersistenceWriteSupportTests {
    @Test
    func observationLatestReferenceFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeTempDirectory("ui_observation")
        defer {
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        let initial = try XTUIObservationStore.writeBundle(
            makeBundle(bundleID: "bundle-old", completedAtMs: 1_773_400_000_000),
            artifacts: [:],
            for: ctx
        )
        #expect(initial.bundle.bundleID == "bundle-old")

        let capture = XTUIObservationWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: root, capture: capture)

        let stored = try XTUIObservationStore.writeBundle(
            makeBundle(bundleID: "bundle-new", completedAtMs: 1_773_400_001_000),
            artifacts: [:],
            for: ctx
        )

        let latest = try #require(XTUIObservationStore.loadLatestBrowserPageReference(for: ctx))
        #expect(stored.bundle.bundleID == "bundle-new")
        #expect(latest.bundleID == "bundle-new")
        #expect(XTUIObservationStore.loadLatestBrowserPageBundle(for: ctx)?.bundleID == "bundle-new")

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 3)
        #expect(options.filter { $0.contains(.atomic) }.count == 2)
        #expect(options.filter(\.isEmpty).count == 1)
    }

    @Test
    func reviewLatestReferenceFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeTempDirectory("ui_review")
        defer {
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        let initial = try XTUIReviewStore.writeReview(
            makeReview(reviewID: "review-old", bundleID: "bundle-old", createdAtMs: 1_773_400_010_000),
            for: ctx
        )
        #expect(initial.review.reviewID == "review-old")

        let capture = XTUIObservationWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: root, capture: capture)

        let stored = try XTUIReviewStore.writeReview(
            makeReview(reviewID: "review-new", bundleID: "bundle-new", createdAtMs: 1_773_400_011_000),
            for: ctx
        )

        let latest = try #require(XTUIReviewStore.loadLatestBrowserPageReference(for: ctx))
        let latestEvidence = try #require(XTUIReviewAgentEvidenceStore.loadLatestBrowserPage(for: ctx))
        #expect(stored.review.reviewID == "review-new")
        #expect(latest.reviewID == "review-new")
        #expect(XTUIReviewStore.loadLatestBrowserPageReview(for: ctx)?.reviewID == "review-new")
        #expect(latestEvidence.reviewID == "review-new")
        #expect(latestEvidence.reviewRef == XTUIReviewStore.reviewRef(reviewID: "review-new"))
        #expect(latestEvidence.renderedText().contains("checks:"))

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 6)
        #expect(options.filter { $0.contains(.atomic) }.count == 4)
        #expect(options.filter(\.isEmpty).count == 2)
    }

    private func makeTempDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_ui_observation_write_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func installScopedExistingFileOutOfSpaceOverride(root: URL, capture: XTUIObservationWriteCapture) {
        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            if !Self.normalizedPath(url).hasPrefix(Self.normalizedPath(root)) {
                try data.write(to: url, options: options)
                return
            }
            capture.appendWriteOption(options)
            if options.contains(.atomic),
               let existingTarget = Self.existingTargetForAtomicTemp(url),
               FileManager.default.fileExists(atPath: existingTarget.path) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: url, options: options)
        }
    }

    private func makeBundle(bundleID: String, completedAtMs: Int64) -> XTUIObservationBundle {
        XTUIObservationBundle(
            schemaVersion: XTUIObservationBundle.currentSchemaVersion,
            bundleID: bundleID,
            projectID: "project-alpha",
            runID: "run-1",
            stepID: "step-1",
            sessionID: "session-1",
            surfaceType: .browserPage,
            surfaceID: "surface-main",
            probeDepth: .standard,
            triggerSource: "test",
            captureStatus: .captured,
            captureStartedAtMs: completedAtMs - 100,
            captureCompletedAtMs: completedAtMs,
            viewport: XTUIObservationViewport(width: 1440, height: 900, scale: 2.0),
            environment: XTUIObservationEnvironment(platform: "macOS", theme: "light", locale: "en_US"),
            pixelLayer: XTUIObservationPixelLayer(
                status: .captured,
                fullRef: "local://.xterminal/ui_observation/artifacts/\(bundleID)/pixel/full.png",
                thumbnailRef: "local://.xterminal/ui_observation/artifacts/\(bundleID)/pixel/thumb.png",
                cropRefs: [],
                width: 1440,
                height: 900
            ),
            structureLayer: XTUIObservationStructureLayer(
                status: .captured,
                roleSnapshotRef: "local://.xterminal/ui_observation/artifacts/\(bundleID)/structure/roles.json",
                axTreeRef: "local://.xterminal/ui_observation/artifacts/\(bundleID)/structure/axtree.json"
            ),
            textLayer: XTUIObservationTextLayer(
                status: .captured,
                visibleTextRef: "local://.xterminal/ui_observation/artifacts/\(bundleID)/text/visible.txt",
                ocrRef: "local://.xterminal/ui_observation/artifacts/\(bundleID)/text/ocr.txt"
            ),
            runtimeLayer: XTUIObservationRuntimeLayer(
                status: .captured,
                consoleErrorCount: 0,
                networkErrorCount: 0,
                runtimeLogRef: "local://.xterminal/ui_observation/artifacts/\(bundleID)/runtime/log.json"
            ),
            layoutLayer: XTUIObservationLayoutLayer(
                status: .captured,
                layoutMetricsRef: "local://.xterminal/ui_observation/artifacts/\(bundleID)/layout/metrics.json",
                interactiveTargets: 3,
                visiblePrimaryCTA: true
            ),
            privacy: XTUIObservationPrivacy(
                classification: "internal",
                redacted: false,
                redactionRef: ""
            ),
            acceptancePackRef: "local://.xterminal/ui_observation/artifacts/\(bundleID)/acceptance/pack.json",
            auditRef: "audit-\(bundleID)"
        )
    }

    private func makeReview(reviewID: String, bundleID: String, createdAtMs: Int64) -> XTUIReviewRecord {
        XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: reviewID,
            projectID: "project-alpha",
            bundleID: bundleID,
            bundleRef: XTUIObservationStore.bundleRef(bundleID: bundleID),
            surfaceType: .browserPage,
            probeDepth: .standard,
            objective: "Confirm page is ready for the next action.",
            verdict: .ready,
            confidence: .high,
            sufficientEvidence: true,
            objectiveReady: true,
            interactiveTargetCount: 3,
            criticalActionExpected: true,
            criticalActionVisible: true,
            issueCodes: [],
            checks: [
                XTUIReviewCheck(code: "cta_visible", status: .pass, detail: "Primary action is visible.")
            ],
            summary: "UI is ready.",
            createdAtMs: createdAtMs,
            auditRef: "audit-\(reviewID)"
        )
    }

    private static func existingTargetForAtomicTemp(_ url: URL) -> URL? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."),
              let tempRange = name.range(of: ".tmp-") else {
            return nil
        }
        let targetName = String(name[name.index(after: name.startIndex)..<tempRange.lowerBound])
        guard !targetName.isEmpty else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(targetName)
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path.replacingOccurrences(
            of: "/private",
            with: "",
            options: [.anchored]
        )
    }
}

private final class XTUIObservationWriteCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var writeOptions: [Data.WritingOptions] = []

    func appendWriteOption(_ option: Data.WritingOptions) {
        lock.lock()
        defer { lock.unlock() }
        writeOptions.append(option)
    }

    func writeOptionsSnapshot() -> [Data.WritingOptions] {
        lock.lock()
        defer { lock.unlock() }
        return writeOptions
    }
}
