import Foundation
import Testing
@testable import XTerminal

@MainActor
struct XTW330AutonomyPolicySurfaceEvidenceTests {
    private let permissionGate = TrustedAutomationPermissionTestGate.shared

    @Test
    func autonomyPolicySurfaceProducesDeliveredEvidenceAndCaptureArtifactWhenRequested() async throws {
        try await permissionGate.run {
            let projectARoot = try makeProjectRoot(name: "xt-w3-30-d-project-a")
            let projectBRoot = try makeProjectRoot(name: "xt-w3-30-d-project-b")
            let ttlFixture = ToolExecutorProjectFixture(name: "xt-w3-30-d-ttl-expiry")
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt-w3-30-d-hub-\(UUID().uuidString)", isDirectory: true)
            let originalTransportMode = HubAIClient.transportMode()
            var appModel: AppModel? = nil

            defer {
                HubAIClient.setTransportMode(originalTransportMode)
                HubPaths.clearPinnedBaseDirOverride()
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetBrowserOpenProviderForTesting()
                try? FileManager.default.removeItem(at: projectARoot)
                try? FileManager.default.removeItem(at: projectBRoot)
                try? FileManager.default.removeItem(at: hubBase)
                ttlFixture.cleanup()
            }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makeAutonomyPolicyEvidencePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-xt-w3-30-d-autonomy-policy"
                )
            }
            DeviceAutomationTools.installBrowserOpenProviderForTesting { _ in true }
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.fileIPC)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            appModel = AppModel()
            let auditAppModel = try #require(appModel)
            HubPaths.setPinnedBaseDirOverride(hubBase)

            let projectACtx = AXProjectContext(root: projectARoot)
            var projectAConfig = try AXProjectStore.loadOrCreateConfig(for: projectACtx)
            projectAConfig = projectAConfig.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_project_a",
                deviceToolGroups: ["device.browser.control", "device.clipboard.read"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: projectARoot)
            )
            try AXProjectStore.saveConfig(projectAConfig, for: projectACtx)

            let projectBCtx = AXProjectContext(root: projectBRoot)
            _ = try AXProjectStore.loadOrCreateConfig(for: projectBCtx)

            let projectAEntry = makeProjectEntry(root: projectARoot)
            let projectBEntry = makeProjectEntry(root: projectBRoot)
            auditAppModel.registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 1_773_700_000,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: projectAEntry.projectId,
                projects: [projectAEntry, projectBEntry]
            )

            auditAppModel.selectedProjectId = projectAEntry.projectId
            try await waitUntil("app model loads project A") {
                auditAppModel.projectContext?.root.standardizedFileURL == projectARoot.standardizedFileURL
                    && auditAppModel.projectConfig != nil
            }

            auditAppModel.setProjectAutonomyPolicy(
                mode: .trustedOpenClawMode,
                ttlSeconds: 600
            )
            auditAppModel.setProjectAutonomyPolicy(hubOverrideMode: .clampGuided)
            let localClampConfig = try AXProjectStore.loadOrCreateConfig(for: projectACtx)
            let localClampRawLog = try rawLogEntries(for: projectACtx)
            let localClampAuditRow = try #require(
                localClampRawLog.last(where: {
                    ($0["type"] as? String) == "project_autonomy_policy"
                        && ($0["project_id"] as? String) == projectAEntry.projectId
                        && ($0["hub_override_mode"] as? String) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue
                })
            )

            auditAppModel.setProjectAutonomyPolicy(hubOverrideMode: AXProjectAutonomyHubOverrideMode.none)
            let clearedLocalConfig = try AXProjectStore.loadOrCreateConfig(for: projectACtx)
            #expect(clearedLocalConfig.autonomyHubOverrideMode == .none)
            appModel = nil

            try writeHubAutonomyPolicyOverrides(
                to: hubBase,
                items: [[
                    "project_id": projectAEntry.projectId,
                    "override_mode": AXProjectAutonomyHubOverrideMode.clampGuided.rawValue,
                    "updated_at_ms": 1_773_700_120_000,
                    "reason": "hub_browser_only",
                    "audit_ref": "audit-hub-xt-w3-30-d-clamp-guided",
                ]]
            )
            HubPaths.setPinnedBaseDirOverride(hubBase)
            let clampRemoteOverride = try #require(
                await HubIPCClient.requestProjectAutonomyPolicyOverride(
                    projectId: projectAEntry.projectId,
                    bypassCache: true
                )
            )
            #expect(clampRemoteOverride.overrideMode == .clampGuided)

            HubPaths.setPinnedBaseDirOverride(hubBase)
            let clampSnapshot = try await projectSnapshotSummary(for: projectARoot)
            let clampAutonomy = try #require(jsonObject(clampSnapshot["autonomy_policy"]))
            let clampRuntimeSurface = try #require(jsonObject(clampSnapshot["runtime_surface"]))
            HubPaths.setPinnedBaseDirOverride(hubBase)
            let clampBrowser = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string("https://example.com/xt-w3-30-d-guided-browser")
                    ]
                ),
                projectRoot: projectARoot
            )
            HubPaths.setPinnedBaseDirOverride(hubBase)
            let clampDevice = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceClipboardRead, args: [:]),
                projectRoot: projectARoot
            )
            let clampDeviceSummary = try #require(toolSummaryObject(clampDevice.output))
            let clampDeniedRuntimeSurface = try #require(jsonObject(clampDeviceSummary["runtime_surface"]))

            try writeHubAutonomyPolicyOverrides(
                to: hubBase,
                items: [[
                    "project_id": projectAEntry.projectId,
                    "override_mode": AXProjectAutonomyHubOverrideMode.killSwitch.rawValue,
                    "updated_at_ms": 1_773_700_180_000,
                    "reason": "hub_emergency_stop",
                    "audit_ref": "audit-hub-xt-w3-30-d-kill-switch",
                ]]
            )
            HubPaths.setPinnedBaseDirOverride(hubBase)
            let killSwitchRemoteOverride = try #require(
                await HubIPCClient.requestProjectAutonomyPolicyOverride(
                    projectId: projectAEntry.projectId,
                    bypassCache: true
                )
            )
            #expect(killSwitchRemoteOverride.overrideMode == .killSwitch)

            HubPaths.setPinnedBaseDirOverride(hubBase)
            let killSwitchSnapshot = try await projectSnapshotSummary(for: projectARoot)
            let killSwitchAutonomy = try #require(jsonObject(killSwitchSnapshot["autonomy_policy"]))
            let killSwitchRuntimeSurface = try #require(jsonObject(killSwitchSnapshot["runtime_surface"]))
            HubPaths.setPinnedBaseDirOverride(hubBase)
            let killSwitchBrowser = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string("https://example.com/xt-w3-30-d-kill-switch")
                    ]
                ),
                projectRoot: projectARoot
            )
            let killSwitchBrowserSummary = try #require(toolSummaryObject(killSwitchBrowser.output))
            let killSwitchDeniedRuntimeSurface = try #require(jsonObject(killSwitchBrowserSummary["runtime_surface"]))

            HubPaths.setPinnedBaseDirOverride(hubBase)
            let projectBRemoteOverride = await HubIPCClient.requestProjectAutonomyPolicyOverride(
                projectId: projectBEntry.projectId,
                bypassCache: true
            )
            HubPaths.setPinnedBaseDirOverride(hubBase)
            let projectBSnapshot = try await projectSnapshotSummary(for: projectBRoot)
            let projectBAutonomy = try #require(jsonObject(projectBSnapshot["autonomy_policy"]))
            let projectBRuntimeSurface = try #require(jsonObject(projectBSnapshot["runtime_surface"]))
            let projectBRawLog = try rawLogEntries(for: projectBCtx)

            let ttlCtx = AXProjectContext(root: ttlFixture.root)
            var ttlConfig = try AXProjectStore.loadOrCreateConfig(for: ttlCtx)
            ttlConfig = ttlConfig.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_ttl",
                deviceToolGroups: ["device.clipboard.read"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: ttlFixture.root)
            )
            ttlConfig = ttlConfig.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                ttlSeconds: 60,
                updatedAt: Date(timeIntervalSince1970: 1)
            )
            try AXProjectStore.saveConfig(ttlConfig, for: ttlCtx)
            let ttlSnapshot = try await projectSnapshotSummary(for: ttlFixture.root)
            let ttlAutonomy = try #require(jsonObject(ttlSnapshot["autonomy_policy"]))
            let ttlRuntimeSurface = try #require(jsonObject(ttlSnapshot["runtime_surface"]))
            let ttlDevice = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceClipboardRead, args: [:]),
                projectRoot: ttlFixture.root
            )
            let ttlDeviceSummary = try #require(toolSummaryObject(ttlDevice.output))
            let ttlDeniedRuntimeSurface = try #require(jsonObject(ttlDeviceSummary["runtime_surface"]))

            let clampConfiguredSurfaces = jsonArray(clampAutonomy["configured_surfaces"]) ?? []
            let clampEffectiveSurfaces = jsonArray(clampAutonomy["effective_surfaces"]) ?? []
            let killSwitchEffectiveSurfaces = jsonArray(killSwitchAutonomy["effective_surfaces"]) ?? []
            let projectBConfiguredSurfaces = jsonArray(projectBAutonomy["configured_surfaces"]) ?? []

            let terminalClampAuditPass =
                localClampConfig.autonomyMode == .trustedOpenClawMode
                && localClampConfig.autonomyHubOverrideMode == .clampGuided
                && (localClampAuditRow["runtime_surface_configured"] as? String) == AXProjectAutonomyMode.trustedOpenClawMode.rawValue
                && (localClampAuditRow["effective_runtime_surface"] as? String) == AXProjectAutonomyMode.guided.rawValue
                && (localClampAuditRow["previous_effective_runtime_surface"] as? String) == AXProjectAutonomyMode.trustedOpenClawMode.rawValue
                && (localClampAuditRow["runtime_surface_hub_override"] as? String) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue
                && (localClampAuditRow["runtime_surface_local_override"] as? String) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue
                && (localClampAuditRow["runtime_surface_remote_override"] as? String) == AXProjectAutonomyHubOverrideMode.none.rawValue
                && (localClampAuditRow["runtime_surface_expired"] as? Bool) == false
                && (localClampAuditRow["effective_mode"] as? String) == AXProjectAutonomyMode.guided.rawValue
                && (localClampAuditRow["previous_effective_mode"] as? String) == AXProjectAutonomyMode.trustedOpenClawMode.rawValue
                && (localClampAuditRow["project_id"] as? String) == projectAEntry.projectId
                && (localClampAuditRow["effective_hub_override_mode"] as? String) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue

            let projectSnapshotClampPass =
                jsonString(clampRuntimeSurface["configured_surface"]) == AXProjectAutonomyMode.trustedOpenClawMode.rawValue
                && jsonString(clampRuntimeSurface["effective_surface"]) == AXProjectAutonomyMode.guided.rawValue
                && jsonString(clampRuntimeSurface["remote_override_surface"]) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue
                && jsonString(clampRuntimeSurface["remote_override_source"]) == "hub_autonomy_policy_overrides_file"
                && jsonString(clampAutonomy["configured_mode"]) == AXProjectAutonomyMode.trustedOpenClawMode.rawValue
                && jsonString(clampAutonomy["effective_mode"]) == AXProjectAutonomyMode.guided.rawValue
                && jsonString(clampAutonomy["hub_override_mode"]) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue
                && jsonString(clampAutonomy["local_override_mode"]) == AXProjectAutonomyHubOverrideMode.none.rawValue
                && jsonString(clampAutonomy["remote_override_mode"]) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue
                && jsonString(clampAutonomy["remote_override_source"]) == "hub_autonomy_policy_overrides_file"
                && clampConfiguredSurfaces.count == 4
                && clampConfiguredSurfaces.contains(where: { jsonString($0) == "browser" })
                && clampConfiguredSurfaces.contains(where: { jsonString($0) == "device" })
                && clampConfiguredSurfaces.contains(where: { jsonString($0) == "connector" })
                && clampConfiguredSurfaces.contains(where: { jsonString($0) == "extension" })
                && clampEffectiveSurfaces.count == 1
                && jsonString(clampEffectiveSurfaces.first) == "browser"

            let guidedRuntimePass =
                clampBrowser.ok
                && !clampDevice.ok
                && jsonString(clampDeviceSummary["deny_code"]) == "autonomy_policy_denied"
                && jsonString(clampDeviceSummary["policy_reason"]) == "hub_override=clamp_guided"
                && jsonString(clampDeviceSummary["runtime_surface_policy_reason"]) == "hub_override=clamp_guided"
                && jsonString(clampDeniedRuntimeSurface["effective_surface"]) == AXProjectAutonomyMode.guided.rawValue
                && jsonString(clampDeniedRuntimeSurface["remote_override_surface"]) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue
                && jsonString(clampDeviceSummary["autonomy_effective_mode"]) == AXProjectAutonomyMode.guided.rawValue
                && jsonString(clampDeviceSummary["autonomy_local_override_mode"]) == AXProjectAutonomyHubOverrideMode.none.rawValue
                && jsonString(clampDeviceSummary["autonomy_remote_override_mode"]) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue

            let killSwitchPass =
                jsonString(killSwitchRuntimeSurface["effective_surface"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonBool(killSwitchRuntimeSurface["kill_switch_engaged"]) == true
                && jsonString(killSwitchAutonomy["effective_mode"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonString(killSwitchAutonomy["hub_override_mode"]) == AXProjectAutonomyHubOverrideMode.killSwitch.rawValue
                && jsonString(killSwitchAutonomy["local_override_mode"]) == AXProjectAutonomyHubOverrideMode.none.rawValue
                && jsonString(killSwitchAutonomy["remote_override_mode"]) == AXProjectAutonomyHubOverrideMode.killSwitch.rawValue
                && jsonBool(killSwitchAutonomy["kill_switch_engaged"]) == true
                && killSwitchEffectiveSurfaces.isEmpty
                && !killSwitchBrowser.ok
                && jsonString(killSwitchBrowserSummary["deny_code"]) == "autonomy_policy_denied"
                && jsonString(killSwitchBrowserSummary["policy_reason"]) == "hub_override=kill_switch"
                && jsonString(killSwitchBrowserSummary["runtime_surface_policy_reason"]) == "hub_override=kill_switch"
                && jsonString(killSwitchDeniedRuntimeSurface["effective_surface"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonBool(killSwitchDeniedRuntimeSurface["kill_switch_engaged"]) == true
                && jsonString(killSwitchBrowserSummary["autonomy_effective_mode"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonString(killSwitchBrowserSummary["autonomy_remote_override_mode"]) == AXProjectAutonomyHubOverrideMode.killSwitch.rawValue

            let ttlExpiryPass =
                jsonString(ttlRuntimeSurface["configured_surface"]) == AXProjectAutonomyMode.trustedOpenClawMode.rawValue
                && jsonString(ttlRuntimeSurface["effective_surface"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonBool(ttlRuntimeSurface["expired"]) == true
                && jsonString(ttlAutonomy["configured_mode"]) == AXProjectAutonomyMode.trustedOpenClawMode.rawValue
                && jsonString(ttlAutonomy["effective_mode"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonBool(ttlAutonomy["expired"]) == true
                && !ttlDevice.ok
                && jsonString(ttlDeviceSummary["deny_code"]) == "autonomy_policy_denied"
                && jsonString(ttlDeviceSummary["policy_reason"]) == "autonomy_ttl_expired"
                && jsonString(ttlDeviceSummary["runtime_surface_policy_reason"]) == "runtime_surface_ttl_expired"
                && jsonString(ttlDeniedRuntimeSurface["effective_surface"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonBool(ttlDeniedRuntimeSurface["expired"]) == true

            let projectIsolationPass =
                jsonString(projectBRuntimeSurface["configured_surface"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonString(projectBRuntimeSurface["effective_surface"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonString(projectBAutonomy["configured_mode"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonString(projectBAutonomy["effective_mode"]) == AXProjectAutonomyMode.manual.rawValue
                && jsonString(projectBAutonomy["hub_override_mode"]) == AXProjectAutonomyHubOverrideMode.none.rawValue
                && jsonString(projectBAutonomy["remote_override_mode"]) == AXProjectAutonomyHubOverrideMode.none.rawValue
                && projectBConfiguredSurfaces.isEmpty
                && projectBRemoteOverride == nil
                && !projectBRawLog.contains(where: { ($0["type"] as? String) == "project_autonomy_policy" })

            let evidence = XTW330DAutonomyPolicySurfaceEvidence(
                schemaVersion: "xt_w3_30_d_autonomy_policy_surface_evidence.v1",
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                status: "delivered",
                claimScope: ["XT-W3-30-D", "XT-OC-G4"],
                claim: "XT now exposes a project-scoped autonomy policy surface with explicit presets, terminal clamp audit rows, Hub-published per-project override ingestion, TTL reclaim, runtime kill-switch/clamp enforcement, and project snapshot visibility.",
                policySurface: [
                    AutonomyPolicySurfaceEvidence(
                        surface: "xt_project_autonomy_picker",
                        state: "live_terminal_clamp_surface",
                        exercised: true,
                        configuredMode: AXProjectAutonomyMode.trustedOpenClawMode.rawValue,
                        effectiveMode: AXProjectAutonomyMode.guided.rawValue,
                        policyReason: "terminal_clamp=clamp_guided"
                    ),
                    AutonomyPolicySurfaceEvidence(
                        surface: "hub_published_autonomy_override",
                        state: "live_hub_truth_source",
                        exercised: true,
                        configuredMode: AXProjectAutonomyMode.trustedOpenClawMode.rawValue,
                        effectiveMode: AXProjectAutonomyMode.guided.rawValue,
                        policyReason: "hub_override=clamp_guided"
                    ),
                    AutonomyPolicySurfaceEvidence(
                        surface: "project_snapshot_autonomy_policy",
                        state: "live_snapshot_visibility",
                        exercised: true,
                        configuredMode: jsonString(clampAutonomy["configured_mode"]) ?? "",
                        effectiveMode: jsonString(clampAutonomy["effective_mode"]) ?? "",
                        policyReason: jsonString(clampAutonomy["hub_override_mode"])
                    ),
                    AutonomyPolicySurfaceEvidence(
                        surface: "runtime_guided_browser_only",
                        state: clampBrowser.ok ? "delivered" : "fail",
                        exercised: true,
                        configuredMode: AXProjectAutonomyMode.trustedOpenClawMode.rawValue,
                        effectiveMode: AXProjectAutonomyMode.guided.rawValue,
                        policyReason: "hub_override=clamp_guided"
                    ),
                    AutonomyPolicySurfaceEvidence(
                        surface: "runtime_kill_switch_fail_closed",
                        state: killSwitchPass ? "fail_closed" : "drifted",
                        exercised: true,
                        configuredMode: AXProjectAutonomyMode.trustedOpenClawMode.rawValue,
                        effectiveMode: AXProjectAutonomyMode.manual.rawValue,
                        policyReason: "hub_override=kill_switch"
                    ),
                    AutonomyPolicySurfaceEvidence(
                        surface: "ttl_expiry_reclaim",
                        state: ttlExpiryPass ? "reclaimed_to_manual" : "drifted",
                        exercised: true,
                        configuredMode: AXProjectAutonomyMode.trustedOpenClawMode.rawValue,
                        effectiveMode: AXProjectAutonomyMode.manual.rawValue,
                        policyReason: "autonomy_ttl_expired"
                    ),
                    AutonomyPolicySurfaceEvidence(
                        surface: "project_scope_isolation",
                        state: projectIsolationPass ? "isolated" : "drifted",
                        exercised: true,
                        configuredMode: jsonString(projectBAutonomy["configured_mode"]) ?? "",
                        effectiveMode: jsonString(projectBAutonomy["effective_mode"]) ?? "",
                        policyReason: "project_local_only"
                    )
                ],
                verificationResults: [
                    AutonomyPolicyVerificationResult(
                        name: "terminal_clamp_selection_audited",
                        status: terminalClampAuditPass ? "pass" : "fail",
                        detail: terminalClampAuditPass ? "AppModel path persists project_autonomy_policy rows with effective_mode transitions and terminal clamp metadata for project A only" : "terminal clamp audit path drifted"
                    ),
                    AutonomyPolicyVerificationResult(
                        name: "project_snapshot_exposes_local_and_hub_override_state",
                        status: projectSnapshotClampPass ? "pass" : "fail",
                        detail: projectSnapshotClampPass ? "project_snapshot exposes configured/effective autonomy modes, local override, and Hub-published override state" : "project_snapshot autonomy policy surface incomplete"
                    ),
                    AutonomyPolicyVerificationResult(
                        name: "hub_remote_clamp_guided_preserves_browser_only",
                        status: guidedRuntimePass ? "pass" : "fail",
                        detail: guidedRuntimePass ? "Hub-published clamp_guided still allows browser runtime while device tools fail closed" : "guided browser-only runtime contract drifted"
                    ),
                    AutonomyPolicyVerificationResult(
                        name: "hub_remote_kill_switch_fail_closes_all_surfaces",
                        status: killSwitchPass ? "pass" : "fail",
                        detail: killSwitchPass ? "Hub-published kill_switch reclaims effective mode to manual and blocks browser runtime" : "kill-switch deny contract drifted"
                    ),
                    AutonomyPolicyVerificationResult(
                        name: "ttl_expiry_reclaims_to_manual",
                        status: ttlExpiryPass ? "pass" : "fail",
                        detail: ttlExpiryPass ? "expired autonomy snapshots as manual and runtime returns autonomy_ttl_expired" : "TTL reclaim contract drifted"
                    ),
                    AutonomyPolicyVerificationResult(
                        name: "cross_project_policy_isolation",
                        status: projectIsolationPass ? "pass" : "fail",
                        detail: projectIsolationPass ? "changing project A autonomy leaves project B in manual with no policy audit rows" : "project autonomy leaked across project boundary"
                    )
                ],
                boundedGaps: [],
                sourceRefs: [
                    "x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md:321",
                    "protocol/hub_protocol_v1.proto:457",
                    "x-hub/grpc-server/hub_grpc_server/src/services.js:1847",
                    "x-terminal/Sources/AppModel.swift:1122",
                    "x-terminal/Sources/Hub/HubIPCClient.swift:2177",
                    "x-terminal/Sources/Hub/HubPairingCoordinator.swift:2730",
                    "x-terminal/Sources/Project/AXProjectAutonomyPolicy.swift:1",
                    "x-terminal/Sources/Tools/ToolExecutor.swift:754",
                    "x-terminal/Sources/Tools/XTToolRuntimePolicy.swift:1",
                    "x-terminal/Sources/UI/ProjectSettingsView.swift:284",
                    "x-terminal/Tests/ToolExecutorRuntimePolicyTests.swift:1",
                    "x-terminal/Tests/XTW330AutonomyPolicySurfaceEvidenceTests.swift:1"
                ]
            )

            #expect(evidence.verificationResults.allSatisfy { $0.status == "pass" })
            #expect(evidence.boundedGaps.isEmpty)

            guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_30_CAPTURE_DIR"],
                  !captureDir.isEmpty else {
                return
            }

            let destination = URL(fileURLWithPath: captureDir)
                .appendingPathComponent("xt_w3_30_d_autonomy_policy_surface_evidence.v1.json")
            try writeJSON(evidence, to: destination)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    private func projectSnapshotSummary(for root: URL) async throws -> [String: JSONValue] {
        let snapshot = try await ToolExecutor.execute(
            call: ToolCall(tool: .project_snapshot, args: [:]),
            projectRoot: root
        )
        #expect(snapshot.ok)
        return try #require(toolSummaryObject(snapshot.output))
    }

    private func makeProjectRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeProjectEntry(root: URL) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: root.lastPathComponent,
            lastOpenedAt: 1_773_700_000,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }

    private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return [] }
        let data = try Data(contentsOf: ctx.rawLogURL)
        let text = try #require(String(data: data, encoding: .utf8))
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let lineData = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return nil
                }
                return object
            }
    }

    private func waitUntil(
        _ label: String,
        timeoutMs: UInt64 = 2_000,
        intervalMs: UInt64 = 50,
        condition: @escaping @MainActor @Sendable () -> Bool
    ) async throws {
        let attempts = max(1, Int(timeoutMs / intervalMs))
        for _ in 0..<attempts {
            if await MainActor.run(body: condition) {
                return
            }
            try await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        }
        Issue.record("Timed out waiting for \(label)")
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    private func writeHubAutonomyPolicyOverrides(
        to base: URL,
        items: [[String: Any]]
    ) throws {
        let payload: [String: Any] = [
            "schema_version": "autonomy_policy_overrides_status.v1",
            "updated_at_ms": items
                .compactMap { ($0["updated_at_ms"] as? NSNumber)?.int64Value }
                .max() ?? 0,
            "items": items,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: base.appendingPathComponent("autonomy_policy_overrides_status.json"), options: .atomic)
    }
}

private func makeAutonomyPolicyEvidencePermissionReadiness(
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

private struct XTW330DAutonomyPolicySurfaceEvidence: Codable, Equatable {
    var schemaVersion: String
    var generatedAt: String
    var status: String
    var claimScope: [String]
    var claim: String
    var policySurface: [AutonomyPolicySurfaceEvidence]
    var verificationResults: [AutonomyPolicyVerificationResult]
    var boundedGaps: [AutonomyPolicyGapEvidence]
    var sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case status
        case claimScope = "claim_scope"
        case claim
        case policySurface = "policy_surface"
        case verificationResults = "verification_results"
        case boundedGaps = "bounded_gaps"
        case sourceRefs = "source_refs"
    }
}

private struct AutonomyPolicySurfaceEvidence: Codable, Equatable {
    var surface: String
    var state: String
    var exercised: Bool
    var configuredMode: String
    var effectiveMode: String
    var policyReason: String?

    enum CodingKeys: String, CodingKey {
        case surface
        case state
        case exercised
        case configuredMode = "configured_mode"
        case effectiveMode = "effective_mode"
        case policyReason = "policy_reason"
    }
}

private struct AutonomyPolicyVerificationResult: Codable, Equatable {
    var name: String
    var status: String
    var detail: String
}

private struct AutonomyPolicyGapEvidence: Codable, Equatable {
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
