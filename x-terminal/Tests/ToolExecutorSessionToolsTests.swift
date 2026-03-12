import Foundation
import Testing
@testable import XTerminal

struct ToolExecutorSessionToolsTests {

    @MainActor
    @Test
    func sessionResumeAndListEmitStructuredState() async throws {
        let fixture = ToolExecutorProjectFixture(name: "session-runtime")
        defer { fixture.cleanup() }

        let resume = try await ToolExecutor.execute(
            call: ToolCall(tool: .session_resume, args: [:]),
            projectRoot: fixture.root
        )

        #expect(resume.ok)
        let resumeSummary = toolSummaryObject(resume.output)
        #expect(resumeSummary != nil)
        guard let resumeSummary else { return }

        let sessionID = jsonString(resumeSummary["session_id"])
        #expect(sessionID != nil)
        #expect(jsonString(resumeSummary["state_after"]) == AXSessionRuntimeState.planning.rawValue)
        #expect(jsonNumber(resumeSummary["pending_tool_call_count"]) == 0)

        let listed = try await ToolExecutor.execute(
            call: ToolCall(tool: .session_list, args: ["limit": .number(5)]),
            projectRoot: fixture.root
        )

        #expect(listed.ok)
        let listSummary = toolSummaryObject(listed.output)
        #expect(listSummary != nil)
        guard let listSummary else { return }

        #expect(jsonNumber(listSummary["session_count"]) == 1)
        let sessions = jsonArray(listSummary["sessions"])
        #expect(sessions?.count == 1)
        let firstSession = sessions?.first.flatMap(jsonObject)
        #expect(jsonString(firstSession?["id"]) == sessionID)
        #expect(toolBody(listed.output).contains(sessionID ?? ""))
    }

    @MainActor
    @Test
    func sessionCompactAndProjectSnapshotReflectCurrentProject() async throws {
        let fixture = ToolExecutorProjectFixture(name: "project-snapshot")
        defer { fixture.cleanup() }
        let ctx = AXProjectContext(root: fixture.root)
        var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
        cfg = cfg.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.clipboard.read", "device.clipboard.write"],
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
        )
        try AXProjectStore.saveConfig(cfg, for: ctx)

        let resumed = try await ToolExecutor.execute(
            call: ToolCall(tool: .session_resume, args: [:]),
            projectRoot: fixture.root
        )
        let resumedSummary = toolSummaryObject(resumed.output)
        guard let resumedSummary,
              let sessionID = jsonString(resumedSummary["session_id"]) else {
            #expect(Bool(false))
            return
        }

        let compacted = try await ToolExecutor.execute(
            call: ToolCall(tool: .session_compact, args: ["session_id": .string(sessionID)]),
            projectRoot: fixture.root
        )

        #expect(compacted.ok)
        let compactSummary = toolSummaryObject(compacted.output)
        #expect(compactSummary != nil)
        guard let compactSummary else { return }

        #expect(jsonString(compactSummary["session_id"]) == sessionID)
        let compactMeta = jsonObject(compactSummary["summary"])
        #expect(jsonNumber(compactMeta?["files"]) == 0)
        #expect(jsonNumber(compactMeta?["additions"]) == 0)
        #expect(jsonNumber(compactMeta?["deletions"]) == 0)

        let snapshot = try await ToolExecutor.execute(
            call: ToolCall(tool: .project_snapshot, args: [:]),
            projectRoot: fixture.root
        )

        #expect(snapshot.ok)
        let snapshotSummary = toolSummaryObject(snapshot.output)
        if let snapshotSummary {
            #expect(jsonString(snapshotSummary["tool_profile"]) == ToolPolicy.defaultProfile.rawValue)
            let session = jsonObject(snapshotSummary["session"])
            #expect(jsonString(session?["id"]) == sessionID)
            let effectiveTools = jsonArray(snapshotSummary["effective_tools"])
            #expect(effectiveTools?.contains(where: { jsonString($0) == ToolName.project_snapshot.rawValue }) == true)
            #expect(effectiveTools?.contains(where: { jsonString($0) == ToolName.deviceClipboardRead.rawValue }) == true)
            #expect(effectiveTools?.contains(where: { jsonString($0) == ToolName.deviceClipboardWrite.rawValue }) == true)
            #expect(jsonString(snapshotSummary["trusted_automation_mode"]) == AXProjectAutomationMode.trustedAutomation.rawValue)
            #expect(jsonString(snapshotSummary["trusted_automation_state"]) == AXTrustedAutomationProjectState.active.rawValue)
            #expect(jsonArray(snapshotSummary["trusted_automation_required_permissions"])?.isEmpty == true)
            #expect(jsonArray(snapshotSummary["trusted_automation_open_settings_actions"])?.isEmpty == true)
            let autonomy = jsonObject(snapshotSummary["autonomy_policy"])
            #expect(jsonString(autonomy?["configured_mode"]) == AXProjectAutonomyMode.manual.rawValue)
            #expect(jsonString(autonomy?["effective_mode"]) == AXProjectAutonomyMode.manual.rawValue)
            #expect(jsonString(autonomy?["hub_override_mode"]) == AXProjectAutonomyHubOverrideMode.none.rawValue)
            #expect(jsonArray(autonomy?["configured_surfaces"])?.isEmpty == true)
            #expect(jsonArray(autonomy?["effective_surfaces"])?.isEmpty == true)
        } else {
            let body = toolBody(snapshot.output)
            #expect(body.contains("trusted_automation_mode=trusted_automation"))
            #expect(body.contains("trusted_automation_state=active"))
            #expect(body.contains(ToolName.deviceClipboardRead.rawValue))
            #expect(body.contains("trusted_automation_required_permissions=(none)"))
            #expect(body.contains("autonomy_mode=manual"))
            #expect(body.contains("autonomy_effective_mode=manual"))
        }
    }

    @MainActor
    @Test
    func projectSnapshotIncludesBrowserRuntimeStateWhenManagedSessionExists() async throws {
        try await TrustedAutomationPermissionTestGate.shared.run {
            let fixture = ToolExecutorProjectFixture(name: "project-snapshot-browser-runtime")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makeProjectSnapshotPermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-project-snapshot-browser-runtime"
                )
            }
            DeviceAutomationTools.installBrowserOpenProviderForTesting { _ in true }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetBrowserOpenProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = cfg.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_600_000)
            )
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let url = "https://example.com/project-snapshot"
            let open = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string(url)
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(open.ok)

            let snapshot = try await ToolExecutor.execute(
                call: ToolCall(tool: .project_snapshot, args: [:]),
                projectRoot: fixture.root
            )

            #expect(snapshot.ok)
            let summary = try #require(toolSummaryObject(snapshot.output))
            let browserRuntime = try #require(jsonObject(summary["browser_runtime"]))
            #expect(jsonString(browserRuntime["current_url"]) == url)
            #expect(jsonString(browserRuntime["transport"]) == "system_default_browser_bridge")
            #expect(jsonString(browserRuntime["action_mode"]) == XTBrowserRuntimeActionMode.interactive.rawValue)
            #expect((jsonString(browserRuntime["session_id"]) ?? "").isEmpty == false)
            #expect(toolBody(snapshot.output).contains("browser_runtime=session="))
            #expect(toolBody(snapshot.output).contains(url))
        }
    }
}

private func makeProjectSnapshotPermissionReadiness(
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
