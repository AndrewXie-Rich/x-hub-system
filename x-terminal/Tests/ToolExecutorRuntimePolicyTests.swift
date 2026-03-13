import Foundation
import Testing
@testable import XTerminal

struct ToolExecutorRuntimePolicyTests {
    private static let permissionGate = TrustedAutomationPermissionTestGate.shared

    @Test
    func writeFileFailsClosedWhenProjectToolPolicyDeniesMutation() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-write-file-deny")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingToolPolicy(deny: ["write_file"])
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .write_file,
                args: [
                    "path": .string("README.md"),
                    "content": .string("hello")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "tool_policy_denied")
        #expect(jsonString(summary["policy_source"]) == "project_tool_policy")
        #expect(jsonString(summary["policy_reason"]) == "tool_not_allowed")
        #expect(toolBody(result.output).contains("write_file"))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("README.md").path))
    }

    @Test
    func writeFileFailsClosedWhenExecutionTierIsPlanOnly() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-governance-write-deny")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s1MilestoneReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .write_file,
                args: [
                    "path": .string("README.md"),
                    "content": .string("hello")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "governance_capability_denied")
        #expect(jsonString(summary["policy_source"]) == "project_governance")
        #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_repo_write")
        #expect(jsonString(summary["effective_execution_tier"]) == AXProjectExecutionTier.a1Plan.rawValue)
        #expect(toolBody(result.output).contains("write_file"))
    }

    @Test
    func deviceUIStepFailsClosedWhenCompositeRuntimeDependenciesAreMissing() async throws {
        try await Self.permissionGate.run {
            let fixture = ToolExecutorProjectFixture(name: "runtime-policy-device-step-deny")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-runtime-policy-device-step-deny"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingHubMemoryPreference(enabled: false)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe", "device.ui.act"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            config = config.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date()
            )
            config = config.settingToolPolicy(deny: ["device.ui.observe", "device.ui.act"])
            config = config.settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s2PeriodicReview
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIStep,
                    args: [
                        "action": .string("press_focused"),
                        "target_title": .string("Continue")
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = try #require(toolSummaryObject(result.output))
            #expect(jsonString(summary["deny_code"]) == "tool_policy_denied")
            #expect(jsonString(summary["policy_source"]) == "project_tool_policy")
            #expect(jsonString(summary["policy_reason"]) == "tool_not_allowed")
            let requiredTools = jsonArray(summary["required_tools"]) ?? []
            #expect(requiredTools.contains(where: { jsonString($0) == ToolName.deviceUIStep.rawValue }))
            #expect(requiredTools.contains(where: { jsonString($0) == ToolName.deviceUIObserve.rawValue }))
            #expect(requiredTools.contains(where: { jsonString($0) == ToolName.deviceUIAct.rawValue }))
            #expect(toolBody(result.output).contains("device.ui.observe"))
            #expect(toolBody(result.output).contains("device.ui.act"))
        }
    }

    @Test
    func deviceBrowserControlFailsClosedWhenAutonomyPolicyDisallowsBrowserRuntime() async throws {
        try await Self.permissionGate.run {
            let fixture = ToolExecutorProjectFixture(name: "runtime-policy-browser-autonomy-deny")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-runtime-policy-browser-autonomy-deny"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingHubMemoryPreference(enabled: false)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            config = config.settingAutonomyPolicy(
                mode: .guided,
                allowBrowserRuntime: false,
                updatedAt: Date()
            )
            config = config.settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s2PeriodicReview
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string("https://example.com")
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = try #require(toolSummaryObject(result.output))
            #expect(jsonString(summary["deny_code"]) == "autonomy_policy_denied")
            #expect(jsonString(summary["policy_source"]) == "project_autonomy_policy")
            #expect(jsonString(summary["policy_reason"]) == "surface=browser_runtime_disallowed")
            #expect(jsonString(summary["autonomy_effective_mode"]) == AXProjectAutonomyMode.guided.rawValue)
            #expect(toolBody(result.output).contains("browser_runtime"))
        }
    }

    @Test
    func deviceClipboardReadFailsClosedWhenAutonomyPolicyTTLExpires() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-device-autonomy-expired")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.clipboard.read"],
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
        )
        config = config.settingAutonomyPolicy(
            mode: .trustedOpenClawMode,
            ttlSeconds: 60,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        config = config.settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .deviceClipboardRead,
                args: [:]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "autonomy_policy_denied")
        #expect(jsonString(summary["policy_source"]) == "project_autonomy_policy")
        #expect(jsonString(summary["policy_reason"]) == "autonomy_ttl_expired")
        #expect(jsonString(summary["autonomy_effective_mode"]) == AXProjectAutonomyMode.manual.rawValue)
        #expect(toolBody(result.output).contains("device.clipboard.read"))
    }

    @Test
    func deviceClipboardReadFailsClosedWhenHubPublishedClampGuidedApplies() async throws {
        try await Self.permissionGate.run {
            let fixture = ToolExecutorProjectFixture(name: "runtime-policy-hub-clamp-guided")
            let originalMode = HubAIClient.transportMode()
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_runtime_policy_hub_clamp_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)

            defer {
                fixture.cleanup()
                HubAIClient.setTransportMode(originalMode)
                HubPaths.clearPinnedBaseDirOverride()
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                try? FileManager.default.removeItem(at: hubBase)
            }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-runtime-policy-hub-clamp-guided"
                )
            }

            HubAIClient.setTransportMode(.fileIPC)
            HubPaths.setPinnedBaseDirOverride(hubBase)

            let projectId = AXProjectRegistryStore.projectId(forRoot: fixture.root)
            let snapshot: [String: Any] = [
                "schema_version": "autonomy_policy_overrides_status.v1",
                "updated_at_ms": 1_773_321_000_000,
                "items": [
                    [
                        "project_id": projectId,
                        "override_mode": "clamp_guided",
                        "updated_at_ms": 1_773_321_000_000,
                        "reason": "hub_browser_only",
                        "audit_ref": "audit-runtime-policy-hub-clamp-guided",
                    ]
                ],
            ]
            let snapshotData = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
            try snapshotData.write(to: hubBase.appendingPathComponent("autonomy_policy_overrides_status.json"), options: .atomic)

            let ctx = AXProjectContext(root: fixture.root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.clipboard.read"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            config = config.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                ttlSeconds: 600,
                updatedAt: Date()
            )
            config = config.settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s2PeriodicReview
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceClipboardRead, args: [:]),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = try #require(toolSummaryObject(result.output))
            #expect(jsonString(summary["deny_code"]) == "autonomy_policy_denied")
            #expect(jsonString(summary["policy_source"]) == "project_autonomy_policy")
            #expect(jsonString(summary["policy_reason"]) == "hub_override=clamp_guided")
            #expect(jsonString(summary["autonomy_effective_mode"]) == AXProjectAutonomyMode.guided.rawValue)
            #expect(jsonString(summary["autonomy_hub_override_mode"]) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue)
            #expect(jsonString(summary["autonomy_local_override_mode"]) == AXProjectAutonomyHubOverrideMode.none.rawValue)
            #expect(jsonString(summary["autonomy_remote_override_mode"]) == AXProjectAutonomyHubOverrideMode.clampGuided.rawValue)
            #expect(jsonString(summary["autonomy_remote_override_source"]) == "hub_autonomy_policy_overrides_file")
        }
    }

    @Test
    func deviceClipboardReadFailsClosedWhenExecutionTierIsBelowOpenClaw() async throws {
        try await Self.permissionGate.run {
            let fixture = ToolExecutorProjectFixture(name: "runtime-policy-governance-device-deny")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .granted,
                    auditRef: "audit-runtime-policy-governance-device-deny"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.clipboard.read"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            config = config.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                ttlSeconds: 600,
                updatedAt: Date()
            )
            config = config.settingProjectGovernance(
                executionTier: .a3DeliverAuto,
                supervisorInterventionTier: .s3StrategicCoach
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceClipboardRead, args: [:]),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = try #require(toolSummaryObject(result.output))
            #expect(jsonString(summary["deny_code"]) == "governance_capability_denied")
            #expect(jsonString(summary["policy_source"]) == "project_governance")
            #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_device_tools")
            #expect(jsonString(summary["effective_execution_tier"]) == AXProjectExecutionTier.a3DeliverAuto.rawValue)
        }
    }
}

private func makePermissionReadiness(
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
