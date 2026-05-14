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
    func activeRepoWritePlanPromotesMinimalToolProfileToCoding() throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-repo-write-plan-promotes-coding")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
            .settingToolPolicy(profile: ToolProfile.minimal.rawValue)
        try AXProjectStore.saveConfig(config, for: ctx)
        try SupervisorProjectPlanStore.upsert(
            SupervisorPlanRecord(
                schemaVersion: SupervisorPlanRecord.currentSchemaVersion,
                planId: "plan-repo-write",
                jobId: "job-1",
                projectId: AXProjectRegistryStore.projectId(forRoot: fixture.root),
                status: .active,
                currentOwner: "supervisor",
                steps: [
                    SupervisorPlanStepRecord(
                        schemaVersion: SupervisorPlanStepRecord.currentSchemaVersion,
                        stepId: "step-1",
                        title: "写入文件",
                        kind: .callSkill,
                        status: .pending,
                        skillId: "repo.write.file",
                        currentOwner: "supervisor",
                        detail: "",
                        orderIndex: 0,
                        updatedAtMs: 1
                    )
                ],
                createdAtMs: 1,
                updatedAtMs: 1,
                auditRef: "audit-plan-repo-write"
            ),
            for: ctx
        )

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)

        #expect(ToolPolicy.parseProfile(reloaded.toolProfile) == .coding)
        #expect(ToolPolicy.effectiveAllowedTools(
            profileRaw: reloaded.toolProfile,
            allowTokens: reloaded.toolAllow,
            denyTokens: reloaded.toolDeny
        ).contains(.write_file))
    }

    @Test
    func loadConfigRepairsStaleWriteFilePolicyMemoryWhenWriteFileIsAllowed() throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-repairs-stale-write-memory")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
            .settingToolPolicy(profile: ToolProfile.coding.rawValue)
        try AXProjectStore.saveConfig(config, for: ctx)

        var memory = AXMemory.new(projectName: "写文件测试", projectRoot: fixture.root.path)
        memory.currentState = [
            "write_file工具被策略阻止(profile=minimal), 代码已提供需手动创建",
            "业务目标已锁定"
        ]
        memory.nextSteps = [
            "用户需手动创建三个文件或解除write_file工具限制"
        ]
        memory.risks = [
            "write_file工具策略限制(profile=minimal)阻止自动创建文件"
        ]
        try AXProjectStore.saveMemory(memory, for: ctx)

        _ = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let repaired = try #require(AXProjectStore.loadMemoryIfPresent(for: ctx))
        let combined = (
            repaired.currentState +
                repaired.nextSteps +
                repaired.openQuestions +
                repaired.risks +
                repaired.recommendations
        ).joined(separator: "\n")

        #expect(!combined.contains("profile=minimal"))
        #expect(!combined.contains("手动创建三个文件"))
        #expect(!combined.contains("解除write_file工具限制"))
        #expect(repaired.currentState.contains("业务目标已锁定"))
        #expect(repaired.currentState.contains("当前工具策略允许在项目根目录内使用 write_file；旧的 minimal/profile 手动建文件提示已失效。"))
    }

    @Test
    func deletePathFailsClosedWhenExecutionTierDoesNotAllowRepoDeleteMove() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-delete-path-deny")
        defer { fixture.cleanup() }

        let target = fixture.root.appendingPathComponent("Sources/Legacy.swift")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "legacy".write(to: target, atomically: true, encoding: .utf8)

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s1MilestoneReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .delete_path,
                args: ["path": .string("Sources/Legacy.swift")]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "governance_capability_denied")
        #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_repo_delete_move")
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test
    func processStartFailsClosedWhenExecutionTierDoesNotAllowManagedProcesses() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-process-manage-deny")
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
                tool: .process_start,
                args: ["command": .string("printf ready")]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "governance_capability_denied")
        #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_managed_processes")
    }

    @Test
    func processAutoRestartFailsClosedWhenExecutionTierDoesNotAllowIt() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-process-autorestart-deny")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .process_start,
                args: [
                    "command": .string("printf ready"),
                    "restart_on_exit": .bool(true),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "governance_capability_denied")
        #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_process_autorestart")
    }

    @Test
    func gitCommitFailsClosedWhenExecutionTierDoesNotAllowIt() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-git-commit-deny")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: ["message": .string("commit me")]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "governance_capability_denied")
        #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_git_commit")
    }

    @Test
    func gitPushFailsClosedWhenExecutionTierDoesNotAllowIt() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-git-push-deny")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(tool: .git_push, args: [:]),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "governance_capability_denied")
        #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_git_push")
    }

    @Test
    func ciReadFailsClosedWhenExecutionTierDoesNotAllowIt() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-ci-read-deny")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .ci_read,
                args: ["workflow": .string("build")]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "governance_capability_denied")
        #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_ci_read")
    }

    @Test
    func ciTriggerFailsClosedWhenExecutionTierDoesNotAllowIt() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-ci-trigger-deny")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .ci_trigger,
                args: ["workflow": .string("build.yml")]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == "governance_capability_denied")
        #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_ci_trigger")
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
            config = config.settingRuntimeSurfacePolicy(
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
    func deviceBrowserControlFailsClosedWhenRuntimeSurfaceDisallowsBrowserRuntime() async throws {
        try await Self.permissionGate.run {
            let fixture = ToolExecutorProjectFixture(name: "runtime-policy-browser-surface-deny")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-runtime-policy-browser-surface-deny"
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
            config = config.settingRuntimeSurfacePolicy(
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
            #expect(jsonString(summary["runtime_surface_policy_reason"]) == "surface=browser_runtime_disallowed")
            let runtimeSurface = try #require(jsonObject(summary["runtime_surface"]))
            #expect(jsonString(runtimeSurface["configured_surface"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
            #expect(jsonString(runtimeSurface["effective_surface"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
            #expect(jsonBool(runtimeSurface["expired"]) == false)
            #expect(jsonArray(runtimeSurface["configured_surfaces"])?.isEmpty == true)
            #expect(jsonArray(runtimeSurface["effective_surfaces"])?.isEmpty == true)
            #expect(jsonString(summary["runtime_surface_effective"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
            #expect(jsonString(summary["autonomy_effective_mode"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
            #expect(toolBody(result.output).contains("browser_runtime"))
        }
    }

    @Test
    func deviceClipboardReadFailsClosedWhenRuntimeSurfaceTTLExpires() async throws {
        let fixture = ToolExecutorProjectFixture(name: "runtime-policy-device-surface-expired")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.clipboard.read"],
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
        )
        config = config.settingRuntimeSurfacePolicy(
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
        #expect(jsonString(summary["runtime_surface_policy_reason"]) == "runtime_surface_ttl_expired")
        let runtimeSurface = try #require(jsonObject(summary["runtime_surface"]))
        #expect(jsonString(runtimeSurface["configured_surface"]) == AXProjectRuntimeSurfaceMode.trustedOpenClawMode.rawValue)
        #expect(jsonString(runtimeSurface["effective_surface"]) == AXProjectRuntimeSurfaceMode.manual.rawValue)
        #expect(jsonBool(runtimeSurface["expired"]) == true)
        #expect(jsonArray(runtimeSurface["effective_surfaces"])?.isEmpty == true)
        #expect(jsonString(summary["runtime_surface_effective"]) == AXProjectRuntimeSurfaceMode.manual.rawValue)
        #expect(jsonString(summary["autonomy_effective_mode"]) == AXProjectRuntimeSurfaceMode.manual.rawValue)
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
            config = config.settingRuntimeSurfacePolicy(
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
            #expect(jsonString(summary["runtime_surface_policy_reason"]) == "hub_override=clamp_guided")
            let runtimeSurface = try #require(jsonObject(summary["runtime_surface"]))
            #expect(jsonString(runtimeSurface["configured_surface"]) == AXProjectRuntimeSurfaceMode.trustedOpenClawMode.rawValue)
            #expect(jsonString(runtimeSurface["effective_surface"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
            #expect(jsonString(runtimeSurface["hub_override_surface"]) == AXProjectRuntimeSurfaceHubOverrideMode.clampGuided.rawValue)
            #expect(jsonString(runtimeSurface["remote_override_surface"]) == AXProjectRuntimeSurfaceHubOverrideMode.clampGuided.rawValue)
            #expect(jsonString(runtimeSurface["remote_override_source"]) == "hub_autonomy_policy_overrides_file")
            #expect(jsonString(summary["runtime_surface_effective"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
            #expect(jsonString(summary["autonomy_effective_mode"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
            #expect(jsonString(summary["autonomy_hub_override_mode"]) == AXProjectRuntimeSurfaceHubOverrideMode.clampGuided.rawValue)
            #expect(jsonString(summary["autonomy_local_override_mode"]) == AXProjectRuntimeSurfaceHubOverrideMode.none.rawValue)
            #expect(jsonString(summary["autonomy_remote_override_mode"]) == AXProjectRuntimeSurfaceHubOverrideMode.clampGuided.rawValue)
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
            config = config.settingRuntimeSurfacePolicy(
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
