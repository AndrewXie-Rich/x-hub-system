import Foundation
import Testing
@testable import XTerminal

@MainActor
struct XTW330BrowserRuntimeEvidenceTests {
    private let permissionGate = TrustedAutomationPermissionTestGate.shared

    @Test
    func browserRuntimeProducesBoundedGapEvidenceAndCaptureArtifactWhenRequested() async throws {
        try await permissionGate.run {
            let fixture = ToolExecutorProjectFixture(name: "xt-w3-30-browser-runtime-evidence")
            defer { fixture.cleanup() }

            let probe = BrowserOpenEvidenceProbe()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makeBrowserRuntimeEvidencePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-xt-w3-30-a-browser-evidence"
                )
            }
            DeviceAutomationTools.installBrowserOpenProviderForTesting { url in
                probe.record(url)
                return true
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetBrowserOpenProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            config = config.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_500_000)
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            let firstURL = "https://example.com/browser-runtime/open"
            let secondURL = "https://example.com/browser-runtime/next"

            let open = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string(firstURL)
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(open.ok)
            let openSummary = try #require(toolSummaryObject(open.output))
            let sessionID = try #require(jsonString(openSummary["browser_runtime_session_id"]))

            let navigate = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("navigate"),
                        "session_id": .string(sessionID),
                        "url": .string(secondURL)
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(navigate.ok)

            let snapshot = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("snapshot"),
                        "session_id": .string(sessionID)
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(snapshot.ok)

            let click = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("click"),
                        "session_id": .string(sessionID),
                        "selector": .string("#submit")
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(!click.ok)
            let clickSummary = try #require(toolSummaryObject(click.output))
            #expect(jsonString(clickSummary["deny_code"]) == XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue)

            let typed = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("type"),
                        "session_id": .string(sessionID),
                        "selector": .string("input[name=email]"),
                        "text": .string("user@example.com")
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(!typed.ok)
            let typedSummary = try #require(toolSummaryObject(typed.output))
            #expect(jsonString(typedSummary["deny_code"]) == XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue)

            let upload = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("upload"),
                        "session_id": .string(sessionID),
                        "selector": .string("input[type=file]"),
                        "path": .string("/tmp/xt_w3_30_upload_evidence.txt")
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(!upload.ok)
            let uploadSummary = try #require(toolSummaryObject(upload.output))
            #expect(jsonString(uploadSummary["deny_code"]) == XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue)

            let projectSnapshot = try await ToolExecutor.execute(
                call: ToolCall(tool: .project_snapshot, args: [:]),
                projectRoot: fixture.root
            )
            #expect(projectSnapshot.ok)
            let projectSnapshotSummary = try #require(toolSummaryObject(projectSnapshot.output))
            let browserRuntimeObject = try #require(jsonObject(projectSnapshotSummary["browser_runtime"]))

            let sessionData = try Data(contentsOf: ctx.browserRuntimeSessionURL)
            let session = try JSONDecoder().decode(XTBrowserRuntimeSession.self, from: sessionData)
            let snapshotFiles = try FileManager.default.contentsOfDirectory(
                at: ctx.browserRuntimeSnapshotsDir,
                includingPropertiesForKeys: nil
            )
            let actionLogText = try String(contentsOf: ctx.browserRuntimeActionLogURL, encoding: .utf8)
            let actionLogLines = actionLogText
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let managedDriverRejectCode = XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue
            let rejectCodeCount = actionLogLines.filter { $0.contains("\"reject_code\":\"\(managedDriverRejectCode)\"") }.count
            let projectRawLogText = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
            let managedProfilePath = XTBrowserRuntimeStore.managedProfilePath(for: ctx, session: session)
            let sessionRef = ".xterminal/browser_runtime/session.json"
            let snapshotsRef = ".xterminal/browser_runtime/snapshots/"
            let actionLogRef = ".xterminal/browser_runtime/action_log.jsonl"
            let rawLogRef = ".xterminal/raw_log.jsonl"
            let managedProfileRef = ".xterminal/browser_runtime/profiles/\(session.profileID)"

            #expect(probe.snapshotURLs() == [firstURL, secondURL])
            #expect(session.sessionID == sessionID)
            #expect(session.currentURL == secondURL)
            #expect(session.transport == "system_default_browser_bridge")
            #expect(snapshotFiles.count == 3)
            #expect(actionLogLines.count == 6)
            #expect(rejectCodeCount == 3)
            #expect(projectRawLogText.contains("\"reject_code\":\"\(managedDriverRejectCode)\""))
            #expect(jsonString(browserRuntimeObject["session_id"]) == sessionID)
            #expect(jsonString(browserRuntimeObject["current_url"]) == secondURL)

            let verificationResults = makeVerificationResults(
                session: session,
                browserRuntimeObject: browserRuntimeObject,
                managedProfilePath: managedProfilePath,
                snapshotCount: snapshotFiles.count,
                actionLogLines: actionLogLines,
                rejectCodeCount: rejectCodeCount,
                projectRawLogText: projectRawLogText
            )
            #expect(verificationResults.allSatisfy { $0.status == "pass" })

            let actionSurface = [
                BrowserRuntimeActionEvidence(
                    action: "open",
                    actionMode: XTBrowserRuntimeActionMode.interactive.rawValue,
                    state: "delivered",
                    exercised: true,
                    denyCode: nil,
                    auditLogged: actionLogLines.contains(where: { $0.contains("\"action\":\"open\"") && $0.contains("\"ok\":true") })
                ),
                BrowserRuntimeActionEvidence(
                    action: "navigate",
                    actionMode: XTBrowserRuntimeActionMode.interactive.rawValue,
                    state: "delivered",
                    exercised: true,
                    denyCode: nil,
                    auditLogged: actionLogLines.contains(where: { $0.contains("\"action\":\"navigate\"") && $0.contains("\"ok\":true") })
                ),
                BrowserRuntimeActionEvidence(
                    action: "snapshot",
                    actionMode: XTBrowserRuntimeActionMode.readOnly.rawValue,
                    state: "delivered",
                    exercised: true,
                    denyCode: nil,
                    auditLogged: actionLogLines.contains(where: { $0.contains("\"action\":\"snapshot\"") && $0.contains("\"ok\":true") })
                ),
                BrowserRuntimeActionEvidence(
                    action: "extract",
                    actionMode: XTBrowserRuntimeActionMode.readOnly.rawValue,
                    state: "delegated_read_surface_not_exercised_in_capture",
                    exercised: false,
                    denyCode: nil,
                    auditLogged: false
                ),
                BrowserRuntimeActionEvidence(
                    action: "click",
                    actionMode: XTBrowserRuntimeActionMode.interactive.rawValue,
                    state: "fail_closed_driver_unavailable",
                    exercised: true,
                    denyCode: managedDriverRejectCode,
                    auditLogged: actionLogLines.contains(where: { $0.contains("\"action\":\"click\"") && $0.contains("\"reject_code\":\"\(managedDriverRejectCode)\"") })
                ),
                BrowserRuntimeActionEvidence(
                    action: "type",
                    actionMode: XTBrowserRuntimeActionMode.interactive.rawValue,
                    state: "fail_closed_driver_unavailable",
                    exercised: true,
                    denyCode: managedDriverRejectCode,
                    auditLogged: actionLogLines.contains(where: { $0.contains("\"action\":\"type\"") && $0.contains("\"reject_code\":\"\(managedDriverRejectCode)\"") })
                ),
                BrowserRuntimeActionEvidence(
                    action: "upload",
                    actionMode: XTBrowserRuntimeActionMode.interactiveWithUpload.rawValue,
                    state: "fail_closed_driver_unavailable",
                    exercised: true,
                    denyCode: managedDriverRejectCode,
                    auditLogged: actionLogLines.contains(where: { $0.contains("\"action\":\"upload\"") && $0.contains("\"reject_code\":\"\(managedDriverRejectCode)\"") })
                ),
            ]

            let evidence = XTW330ABrowserRuntimeEvidence(
                schemaVersion: "xt_w3_30_a_browser_runtime_evidence.v1",
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                status: "bounded_gap",
                claimScope: ["XT-W3-30-A", "XT-OC-G1"],
                claim: "Browser runtime session/profile/snapshot/audit chain is live; click/type/upload are frozen as fail-closed managed actions until a real managed browser driver is implemented.",
                contractSchemaVersion: XTBrowserRuntimeSession.currentSchemaVersion,
                transport: session.transport,
                runtimeArtifacts: BrowserRuntimeArtifactEvidence(
                    sessionPath: sessionRef,
                    snapshotDirectory: snapshotsRef,
                    actionLogPath: actionLogRef,
                    rawLogPath: rawLogRef,
                    projectSnapshotVisible: jsonString(browserRuntimeObject["session_id"]) == sessionID,
                    managedProfileID: session.profileID,
                    managedProfilePath: managedProfileRef,
                    snapshotCount: snapshotFiles.count,
                    actionLogEventCount: actionLogLines.count,
                    rejectCodeCount: rejectCodeCount
                ),
                actionSurface: actionSurface,
                verificationResults: verificationResults,
                boundedGaps: [
                    BrowserRuntimeGapEvidence(
                        id: "managed_driver_missing",
                        severity: "high",
                        currentBehavior: "click/type/upload return device_browser_managed_driver_unavailable and are audited",
                        requiredNextStep: "connect device.browser.control interactive actions to a real managed browser driver"
                    ),
                    BrowserRuntimeGapEvidence(
                        id: "extract_not_require_real_covered",
                        severity: "medium",
                        currentBehavior: "extract delegates to browser_read and was not exercised in this offline capture",
                        requiredNextStep: "add require-real extract evidence with Hub grant and fresh memory recheck"
                    )
                ],
                sourceRefs: [
                    "x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md:252",
                    "x-terminal/Sources/Tools/BrowserRuntime/XTBrowserRuntimeSession.swift:9",
                    "x-terminal/Sources/Tools/ToolExecutor.swift:1749",
                    "x-terminal/Sources/Tools/ToolProtocol.swift:252",
                    "x-terminal/Tests/ToolExecutorDeviceAutomationToolsTests.swift:1472",
                    "x-terminal/Tests/XTW330BrowserRuntimeEvidenceTests.swift:1"
                ]
            )

            #expect(evidence.runtimeArtifacts.actionLogEventCount == 6)
            #expect(evidence.actionSurface.count == 7)
            #expect(evidence.boundedGaps.count == 2)

            guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_30_CAPTURE_DIR"],
                  !captureDir.isEmpty else {
                return
            }

            let destination = URL(fileURLWithPath: captureDir)
                .appendingPathComponent("xt_w3_30_a_browser_runtime_evidence.v1.json")
            try writeJSON(evidence, to: destination)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    private func makeVerificationResults(
        session: XTBrowserRuntimeSession,
        browserRuntimeObject: [String: JSONValue],
        managedProfilePath: String,
        snapshotCount: Int,
        actionLogLines: [String],
        rejectCodeCount: Int,
        projectRawLogText: String
    ) -> [BrowserRuntimeVerificationResult] {
        let profileScoped = session.profileID.hasPrefix("managed_profile_")
            && managedProfilePath.contains("/browser_runtime/profiles/")
        let runtimeVisible = jsonString(browserRuntimeObject["session_id"]) == session.sessionID
            && jsonString(browserRuntimeObject["transport"]) == session.transport
        let deliveredChain = snapshotCount >= 3
            && actionLogLines.contains(where: { $0.contains("\"action\":\"open\"") && $0.contains("\"ok\":true") })
            && actionLogLines.contains(where: { $0.contains("\"action\":\"navigate\"") && $0.contains("\"ok\":true") })
            && actionLogLines.contains(where: { $0.contains("\"action\":\"snapshot\"") && $0.contains("\"ok\":true") })
        let managedActionsFailClosed = rejectCodeCount == 3
            && actionLogLines.contains(where: { $0.contains("\"action\":\"click\"") })
            && actionLogLines.contains(where: { $0.contains("\"action\":\"type\"") })
            && actionLogLines.contains(where: { $0.contains("\"action\":\"upload\"") })
        let failuresAudited = projectRawLogText.contains("\"reject_code\":\"\(XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue)\"")

        return [
            BrowserRuntimeVerificationResult(
                name: "session_profile_snapshot_chain",
                status: deliveredChain ? "pass" : "fail",
                detail: deliveredChain ? "open/navigate/snapshot persisted session + snapshots + action log" : "browser runtime persistence chain incomplete"
            ),
            BrowserRuntimeVerificationResult(
                name: "managed_profile_namespace_allocated",
                status: profileScoped ? "pass" : "fail",
                detail: profileScoped ? "managed profile namespace lives under project browser_runtime/profiles" : "managed profile path contract missing"
            ),
            BrowserRuntimeVerificationResult(
                name: "project_snapshot_visibility",
                status: runtimeVisible ? "pass" : "fail",
                detail: runtimeVisible ? "project_snapshot exposes browser_runtime object" : "browser runtime missing from project_snapshot"
            ),
            BrowserRuntimeVerificationResult(
                name: "managed_actions_fail_closed",
                status: managedActionsFailClosed ? "pass" : "fail",
                detail: managedActionsFailClosed ? "click/type/upload return stable managed-driver-unavailable deny" : "interactive managed action deny path drifted"
            ),
            BrowserRuntimeVerificationResult(
                name: "failed_attempts_audited",
                status: failuresAudited ? "pass" : "fail",
                detail: failuresAudited ? "failed interactive actions are present in project raw log with reject_code" : "failed interactive actions were not fully audited"
            )
        ]
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }
}

private final class BrowserOpenEvidenceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String] = []

    func record(_ url: URL) {
        lock.lock()
        urls.append(url.absoluteString)
        lock.unlock()
    }

    func snapshotURLs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

private struct XTW330ABrowserRuntimeEvidence: Codable, Equatable {
    var schemaVersion: String
    var generatedAt: String
    var status: String
    var claimScope: [String]
    var claim: String
    var contractSchemaVersion: String
    var transport: String
    var runtimeArtifacts: BrowserRuntimeArtifactEvidence
    var actionSurface: [BrowserRuntimeActionEvidence]
    var verificationResults: [BrowserRuntimeVerificationResult]
    var boundedGaps: [BrowserRuntimeGapEvidence]
    var sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case status
        case claimScope = "claim_scope"
        case claim
        case contractSchemaVersion = "contract_schema_version"
        case transport
        case runtimeArtifacts = "runtime_artifacts"
        case actionSurface = "action_surface"
        case verificationResults = "verification_results"
        case boundedGaps = "bounded_gaps"
        case sourceRefs = "source_refs"
    }
}

private struct BrowserRuntimeArtifactEvidence: Codable, Equatable {
    var sessionPath: String
    var snapshotDirectory: String
    var actionLogPath: String
    var rawLogPath: String
    var projectSnapshotVisible: Bool
    var managedProfileID: String
    var managedProfilePath: String
    var snapshotCount: Int
    var actionLogEventCount: Int
    var rejectCodeCount: Int

    enum CodingKeys: String, CodingKey {
        case sessionPath = "session_path"
        case snapshotDirectory = "snapshot_directory"
        case actionLogPath = "action_log_path"
        case rawLogPath = "raw_log_path"
        case projectSnapshotVisible = "project_snapshot_visible"
        case managedProfileID = "managed_profile_id"
        case managedProfilePath = "managed_profile_path"
        case snapshotCount = "snapshot_count"
        case actionLogEventCount = "action_log_event_count"
        case rejectCodeCount = "reject_code_count"
    }
}

private struct BrowserRuntimeActionEvidence: Codable, Equatable {
    var action: String
    var actionMode: String
    var state: String
    var exercised: Bool
    var denyCode: String?
    var auditLogged: Bool

    enum CodingKeys: String, CodingKey {
        case action
        case actionMode = "action_mode"
        case state
        case exercised
        case denyCode = "deny_code"
        case auditLogged = "audit_logged"
    }
}

private struct BrowserRuntimeVerificationResult: Codable, Equatable {
    var name: String
    var status: String
    var detail: String
}

private struct BrowserRuntimeGapEvidence: Codable, Equatable {
    var id: String
    var severity: String
    var currentBehavior: String
    var requiredNextStep: String

    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case currentBehavior = "current_behavior"
        case requiredNextStep = "required_next_step"
    }
}

private func makeBrowserRuntimeEvidencePermissionReadiness(
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
