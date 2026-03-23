import AppKit
import Testing
@testable import XTerminal

private actor XTW337TestGate {
    func run(_ operation: @MainActor () async throws -> Void) async rethrows {
        try await TrustedAutomationPermissionTestGate.shared.run(operation)
    }
}

@MainActor
struct XTW337BrowserUIObservationTests {
    private static let gate = XTW337TestGate()
    private static func activeRuntimeSurfaceDate() -> Date {
        Date()
    }

    @Test
    func browserSnapshotProducesCapturedUIObservationBundleWhenScreenRecordingIsReady() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "xt-w3-37-browser-ui-observation")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makeXTW337PermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .granted,
                    auditRef: "audit-xt-w3-37-ready"
                )
            }
            DeviceAutomationTools.installBrowserOpenProviderForTesting { _ in true }
            DeviceAutomationTools.installUIObservationProviderForTesting { _ in
                XTDeviceUIObservationResult(
                    snapshot: XTW337BrowserUIObservationTests.makeUISnapshot(),
                    matchedElements: []
                )
            }
            DeviceAutomationTools.installScreenCaptureProviderForTesting {
                makeXTW337TestCGImage(width: 8, height: 6)
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetBrowserOpenProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
                DeviceAutomationTools.resetScreenCaptureProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            config = config.settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Self.activeRuntimeSurfaceDate()
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            let open = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string("https://example.com/login")
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(open.ok)

            let snapshot = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("snapshot"),
                        "probe_depth": .string("standard")
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(snapshot.ok)
            let summary = try #require(toolSummaryObject(snapshot.output))
            let bundleRef = try #require(jsonString(summary["ui_observation_bundle_ref"]))
            let reviewRef = try #require(jsonString(summary["ui_review_ref"]))
            #expect(jsonString(summary["ui_observation_status"]) == XTUIObservationBundleStatus.captured.rawValue)
            #expect(jsonString(summary["ui_observation_probe_depth"]) == XTUIObservationProbeDepth.standard.rawValue)
            #expect(jsonNumber(summary["ui_observation_captured_layers"]) == 5)
            #expect(jsonString(summary["browser_runtime_ui_observation_ref"]) == bundleRef)
            #expect(jsonString(summary["ui_review_verdict"]) == XTUIReviewVerdict.ready.rawValue)
            #expect(jsonString(summary["ui_review_confidence"]) == XTUIReviewConfidence.high.rawValue)
            #expect(jsonBool(summary["ui_review_sufficient_evidence"]) == true)
            #expect(jsonBool(summary["ui_review_objective_ready"]) == true)
            #expect(jsonArray(summary["ui_review_issue_codes"])?.isEmpty == true)
            #expect(jsonString(summary["browser_runtime_ui_review_ref"]) == reviewRef)
            #expect(jsonString(summary["browser_runtime_ui_review_verdict"]) == XTUIReviewVerdict.ready.rawValue)
            #expect(toolBody(snapshot.output).contains("local://.xterminal/browser_runtime/snapshots/"))

            let bundleURL = try #require(XTUIObservationStore.resolveLocalRef(bundleRef, for: ctx))
            #expect(FileManager.default.fileExists(atPath: bundleURL.path))
            let bundleData = try Data(contentsOf: bundleURL)
            let bundle = try JSONDecoder().decode(XTUIObservationBundle.self, from: bundleData)
            #expect(bundle.surfaceType == .browserPage)
            #expect(bundle.captureStatus == .captured)
            #expect(bundle.probeDepth == .standard)
            #expect(bundle.pixelLayer.status == .captured)
            #expect(bundle.structureLayer.status == .captured)
            #expect(bundle.textLayer.status == .captured)
            #expect(bundle.runtimeLayer.status == .captured)
            #expect(bundle.layoutLayer.status == .captured)

            let pixelURL = try #require(XTUIObservationStore.resolveLocalRef(bundle.pixelLayer.fullRef, for: ctx))
            let structureURL = try #require(XTUIObservationStore.resolveLocalRef(bundle.structureLayer.axTreeRef, for: ctx))
            let textURL = try #require(XTUIObservationStore.resolveLocalRef(bundle.textLayer.visibleTextRef, for: ctx))
            #expect(FileManager.default.fileExists(atPath: pixelURL.path))
            #expect(FileManager.default.fileExists(atPath: structureURL.path))
            #expect(FileManager.default.fileExists(atPath: textURL.path))

            let reviewURL = try #require(XTUIObservationStore.resolveLocalRef(reviewRef, for: ctx))
            #expect(FileManager.default.fileExists(atPath: reviewURL.path))
            let reviewData = try Data(contentsOf: reviewURL)
            let review = try JSONDecoder().decode(XTUIReviewRecord.self, from: reviewData)
            #expect(review.bundleRef == bundleRef)
            #expect(review.verdict == .ready)
            #expect(review.confidence == .high)
            #expect(review.issueCodes.isEmpty)
            #expect(review.interactiveTargetCount > 0)

            let projectSnapshot = try await ToolExecutor.execute(
                call: ToolCall(tool: .project_snapshot, args: [:]),
                projectRoot: fixture.root
            )
            #expect(projectSnapshot.ok)
            let projectSummary = try #require(toolSummaryObject(projectSnapshot.output))
            let browserRuntime = try #require(jsonObject(projectSummary["browser_runtime"]))
            #expect(jsonString(browserRuntime["ui_observation_ref"]) == bundleRef)
            #expect(jsonString(browserRuntime["ui_observation_status"]) == XTUIObservationBundleStatus.captured.rawValue)
            #expect(jsonString(browserRuntime["ui_review_ref"]) == reviewRef)
            #expect(jsonString(browserRuntime["ui_review_verdict"]) == XTUIReviewVerdict.ready.rawValue)
            let uiReview = try #require(jsonObject(projectSummary["ui_review"]))
            #expect(jsonString(uiReview["review_ref"]) == reviewRef)
            #expect(jsonString(uiReview["verdict"]) == XTUIReviewVerdict.ready.rawValue)
            #expect(jsonString(uiReview["confidence"]) == XTUIReviewConfidence.high.rawValue)
            #expect(jsonBool(uiReview["sufficient_evidence"]) == true)
            #expect(toolBody(projectSnapshot.output).contains("ui_review=ref="))

            let rawLog = try rawLogEntries(for: ctx)
            let uiReviewEntry = try #require(rawLog.last(where: { ($0["type"] as? String) == "ui_review" }))
            #expect(uiReviewEntry["surface"] as? String == "browser_page")
            #expect(uiReviewEntry["action"] as? String == "snapshot")
            #expect(uiReviewEntry["project_id"] as? String == AXProjectRegistryStore.projectId(forRoot: fixture.root))
            #expect(uiReviewEntry["session_id"] as? String == jsonString(summary["browser_runtime_session_id"]))
            #expect(uiReviewEntry["bundle_ref"] as? String == bundleRef)
            #expect(uiReviewEntry["bundle_status"] as? String == XTUIObservationBundleStatus.captured.rawValue)
            #expect(uiReviewEntry["review_ref"] as? String == reviewRef)
            #expect(uiReviewEntry["verdict"] as? String == XTUIReviewVerdict.ready.rawValue)
            #expect(uiReviewEntry["confidence"] as? String == XTUIReviewConfidence.high.rawValue)
            #expect(uiReviewEntry["sufficient_evidence"] as? Bool == true)
            #expect(uiReviewEntry["objective_ready"] as? Bool == true)
            #expect((uiReviewEntry["issue_codes"] as? [String])?.isEmpty == true)
            #expect(uiReviewEntry["summary"] as? String == review.summary)
            #expect(uiReviewEntry["review_error"] as? String == "")
            #expect(uiReviewEntry["audit_ref"] as? String == review.auditRef)
        }
    }

    @Test
    func browserSnapshotProducesPartialUIObservationBundleWhenScreenRecordingIsMissing() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "xt-w3-37-browser-ui-observation-partial")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makeXTW337PermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-xt-w3-37-partial"
                )
            }
            DeviceAutomationTools.installBrowserOpenProviderForTesting { _ in true }
            DeviceAutomationTools.installUIObservationProviderForTesting { _ in
                XTDeviceUIObservationResult(
                    snapshot: XTW337BrowserUIObservationTests.makeUISnapshot(
                        appName: "Safari",
                        bundleID: "com.apple.Safari",
                        windowTitle: "Example Login"
                    ),
                    matchedElements: []
                )
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetBrowserOpenProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            config = config.settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Self.activeRuntimeSurfaceDate()
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            _ = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string("https://example.com/account")
                    ]
                ),
                projectRoot: fixture.root
            )

            let snapshot = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("snapshot")
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(snapshot.ok)
            let summary = try #require(toolSummaryObject(snapshot.output))
            let bundleRef = try #require(jsonString(summary["ui_observation_bundle_ref"]))
            let reviewRef = try #require(jsonString(summary["ui_review_ref"]))
            #expect(jsonString(summary["ui_observation_status"]) == XTUIObservationBundleStatus.partial.rawValue)
            #expect(jsonNumber(summary["ui_observation_captured_layers"]) == 4)
            #expect(jsonString(summary["ui_review_verdict"]) == XTUIReviewVerdict.attentionNeeded.rawValue)
            #expect(jsonString(summary["ui_review_confidence"]) == XTUIReviewConfidence.medium.rawValue)
            #expect(jsonBool(summary["ui_review_sufficient_evidence"]) == true)
            #expect(jsonBool(summary["ui_review_objective_ready"]) == false)
            #expect(jsonArray(summary["ui_review_issue_codes"])?.contains(where: { jsonString($0) == "pixel_capture_missing" }) == true)

            let bundleURL = try #require(XTUIObservationStore.resolveLocalRef(bundleRef, for: ctx))
            let bundleData = try Data(contentsOf: bundleURL)
            let bundle = try JSONDecoder().decode(XTUIObservationBundle.self, from: bundleData)
            #expect(bundle.captureStatus == .partial)
            #expect(bundle.pixelLayer.status == .unavailable)
            #expect(bundle.structureLayer.status == .captured)
            #expect(bundle.runtimeLayer.status == .captured)
            #expect(bundle.layoutLayer.status == .captured)

            let reviewURL = try #require(XTUIObservationStore.resolveLocalRef(reviewRef, for: ctx))
            let reviewData = try Data(contentsOf: reviewURL)
            let review = try JSONDecoder().decode(XTUIReviewRecord.self, from: reviewData)
            #expect(review.verdict == .attentionNeeded)
            #expect(review.issueCodes.contains("pixel_capture_missing"))
        }
    }

    @Test
    func browserSnapshotFlagsMissingCriticalActionOnLoginFlow() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "xt-w3-37-browser-ui-observation-critical-action")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makeXTW337PermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .granted,
                    auditRef: "audit-xt-w3-37-critical-action"
                )
            }
            DeviceAutomationTools.installBrowserOpenProviderForTesting { _ in true }
            DeviceAutomationTools.installUIObservationProviderForTesting { _ in
                XTDeviceUIObservationResult(
                    snapshot: XTW337BrowserUIObservationTests.makeUISnapshot(
                        appName: "Google Chrome",
                        bundleID: "com.google.Chrome",
                        windowTitle: "Sign In",
                        focusedElement: XTDeviceUIElementSnapshot(
                            role: "AXStaticText",
                            subrole: "",
                            title: "Welcome back",
                            elementDescription: "Use your workspace account",
                            valuePreview: "",
                            identifier: "login-intro",
                            help: "",
                            childCount: 0
                        )
                    ),
                    matchedElements: []
                )
            }
            DeviceAutomationTools.installScreenCaptureProviderForTesting {
                makeXTW337TestCGImage(width: 10, height: 8)
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetBrowserOpenProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
                DeviceAutomationTools.resetScreenCaptureProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            config = config.settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Self.activeRuntimeSurfaceDate()
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            _ = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string("https://example.com/login")
                    ]
                ),
                projectRoot: fixture.root
            )

            let snapshot = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("snapshot"),
                        "probe_depth": .string("deep")
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(snapshot.ok)
            let summary = try #require(toolSummaryObject(snapshot.output))
            #expect(jsonString(summary["ui_review_verdict"]) == XTUIReviewVerdict.attentionNeeded.rawValue)
            #expect(jsonArray(summary["ui_review_issue_codes"])?.contains(where: { jsonString($0) == "interactive_target_missing" }) == true)
            #expect(jsonArray(summary["ui_review_issue_codes"])?.contains(where: { jsonString($0) == "critical_action_not_visible" }) == true)

            let reviewRef = try #require(jsonString(summary["ui_review_ref"]))
            let reviewURL = try #require(XTUIObservationStore.resolveLocalRef(reviewRef, for: ctx))
            let reviewData = try Data(contentsOf: reviewURL)
            let review = try JSONDecoder().decode(XTUIReviewRecord.self, from: reviewData)
            #expect(review.interactiveTargetCount == 0)
            #expect(review.criticalActionExpected == true)
            #expect(review.criticalActionVisible == false)
            #expect(review.issueCodes.contains("interactive_target_missing"))
            #expect(review.issueCodes.contains("critical_action_not_visible"))
        }
    }

    private static func makeUISnapshot(
        appName: String = "Google Chrome",
        bundleID: String = "com.google.Chrome",
        windowTitle: String = "Sign In",
        focusedElement: XTDeviceUIElementSnapshot? = XTDeviceUIElementSnapshot(
            role: "AXButton",
            subrole: "",
            title: "Sign In",
            elementDescription: "Primary sign in action",
            valuePreview: "",
            identifier: "login-submit",
            help: "Submit login form",
            childCount: 2
        )
    ) -> XTDeviceUIObservationSnapshot {
        XTDeviceUIObservationSnapshot(
            frontmostAppName: appName,
            frontmostBundleID: bundleID,
            frontmostPID: 4242,
            focusedWindowTitle: windowTitle,
            focusedWindowRole: "AXWindow",
            focusedWindowSubrole: "AXStandardWindow",
            focusedElement: focusedElement
        )
    }
}

@MainActor
private func makeXTW337TestCGImage(width: Int, height: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var data = [UInt8](repeating: 255, count: height * bytesPerRow)
    for pixel in stride(from: 0, to: data.count, by: bytesPerPixel) {
        data[pixel] = 30
        data[pixel + 1] = 140
        data[pixel + 2] = 220
        data[pixel + 3] = 255
    }
    guard let context = CGContext(
        data: &data,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    return context.makeImage()
}

private func makeXTW337PermissionReadiness(
    accessibility: AXTrustedAutomationPermissionStatus,
    automation: AXTrustedAutomationPermissionStatus,
    screenRecording: AXTrustedAutomationPermissionStatus,
    auditRef: String
) -> AXTrustedAutomationPermissionOwnerReadiness {
    AXTrustedAutomationPermissionOwnerReadiness(
        schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
        ownerID: "owner-xt",
        ownerType: "xterminal_app",
        bundleID: "com.xterminal.app",
        installState: "ready",
        mode: "managed_or_prompted",
        accessibility: accessibility,
        automation: automation,
        screenRecording: screenRecording,
        fullDiskAccess: .missing,
        inputMonitoring: .missing,
        canPromptUser: true,
        managedByMDM: false,
        overallState: "partial",
        openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
        auditRef: auditRef
    )
}

private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
    guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return [] }
    let data = try Data(contentsOf: ctx.rawLogURL)
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    return try text
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { line in
            guard let lineData = String(line).data(using: .utf8) else {
                throw CocoaError(.coderInvalidValue)
            }
            guard let object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                throw CocoaError(.coderReadCorrupt)
            }
            return object
        }
}
