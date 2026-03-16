import Foundation
import Testing
@testable import XTerminal

struct XTAutomationRunExecutorTests {
    private static let permissionGate = TrustedAutomationPermissionTestGate.shared

    @Test
    func executorDeliversWhenAllRecipeActionsSucceed() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let executor = XTAutomationRunExecutor { call, _ in
            ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(call.tool.rawValue),
                        "ok": .bool(true),
                    ],
                    body: "project_root=/tmp/example"
                )
            )
        }

        let report = await executor.execute(
            runID: "run-executor-ok",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-ok",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "execute action graph",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .balanced,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:full"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Project snapshot",
                        tool: .project_snapshot,
                        successBodyContains: "project_root="
                    )
                ],
                requiresTrustedAutomation: false,
                trustedDeviceID: "",
                workspaceBindingHash: "",
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_000_000,
                lastEditAuditRef: "audit-xt-auto-executor-ok",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_000)
        )

        #expect(report.finalState == .delivered)
        #expect(report.executedActionCount == 1)
        #expect(report.succeededActionCount == 1)
        #expect(report.holdReason.isEmpty)
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func executorBlocksWhenActionExpectationFails() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let executor = XTAutomationRunExecutor { call, _ in
            ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(call.tool.rawValue),
                        "ok": .bool(true),
                    ],
                    body: "snapshot_without_expected_marker"
                )
            )
        }

        let report = await executor.execute(
            runID: "run-executor-fail",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-fail",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "execute action graph",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .balanced,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:full"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Project snapshot",
                        tool: .project_snapshot,
                        successBodyContains: "project_root="
                    )
                ],
                requiresTrustedAutomation: false,
                trustedDeviceID: "",
                workspaceBindingHash: "",
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_001_000,
                lastEditAuditRef: "audit-xt-auto-executor-fail",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_001)
        )

        #expect(report.finalState == .blocked)
        #expect(report.executedActionCount == 1)
        #expect(report.succeededActionCount == 0)
        #expect(report.holdReason == "automation_action_failed")
        #expect(report.actionResults.first?.detail == "expected_body_missing:project_root=")
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func executorUsesHumanSummaryForSecretVaultBrowserFillSuccess() async throws {
        try await Self.permissionGate.run {
            let root = try makeProjectRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-executor-secret-vault-browser-fill-ok"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            config = config.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_300_002)
            )
            config = config.settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s2PeriodicReview
            )
            config = config.settingToolPolicy(allow: ["group:device_automation"])
            try AXProjectStore.saveConfig(config, for: ctx)

            let executor = XTAutomationRunExecutor { call, _ in
                ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: ToolExecutor.structuredOutput(
                        summary: [
                            "tool": .string(call.tool.rawValue),
                            "ok": .bool(true),
                            "action": .string("type"),
                            "selector": .string("input[type=password]"),
                            "browser_runtime_driver_state": .string("secret_vault_applescript_fill"),
                        ],
                        body: "session_id=browser_session_1"
                    )
                )
            }

            let report = await executor.execute(
                runID: "run-executor-secret-vault-ok",
                recipe: AXAutomationRecipeRuntimeBinding(
                    recipeID: "xt-auto-executor-secret-vault-ok",
                    recipeVersion: 1,
                    lifecycleState: .ready,
                    goal: "fill login field",
                    triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                    deliveryTargets: ["channel://telegram/project-a"],
                    acceptancePackRef: "build/reports/acceptance.json",
                    executionProfile: .aggressive,
                    touchMode: .guidedTouch,
                    innovationLevel: .l1,
                    laneStrategy: .singleLane,
                    requiredToolGroups: ["group:device_automation"],
                    actionGraph: [
                        XTAutomationRecipeAction(
                            title: "Fill browser credential",
                            tool: .deviceBrowserControl,
                            args: [
                                "action": .string("type"),
                                "selector": .string("input[type=password]"),
                                "secret_item_id": .string("sv_project_login")
                            ]
                        )
                    ],
                    requiresTrustedAutomation: true,
                    trustedDeviceID: "device_xt_001",
                    workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root),
                    grantPolicyRef: "policy://automation-trigger/project-a",
                    rolloutStatus: .active,
                    lastEditedAtMs: 1_773_300_002_000,
                    lastEditAuditRef: "audit-xt-auto-executor-secret-vault-ok",
                    lastLaunchRef: ""
                ),
                ctx: ctx,
                now: Date(timeIntervalSince1970: 1_773_300_002)
            )

            #expect(report.finalState == .delivered)
            #expect(report.actionResults.first?.detail.contains("Secret Vault credential") == true)
            #expect(report.actionResults.first?.detail.contains("input[type=password]") == true)
        }
    }

    @Test
    func executorRunsProjectVerificationAfterMutationActionAndDeliversWhenVerifyPasses() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        try AXProjectStore.saveConfig(config, for: ctx)

        let executor = XTAutomationRunExecutor { call, _ in
            switch call.tool {
            case .write_file:
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
            case .git_diff:
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: """
                    diff --git a/README.md b/README.md
                    @@ -0,0 +1 @@
                    +hello
                    """
                )
            case .run_command:
                #expect(call.args["command"] == .string("swift test --filter SmokeTests"))
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "exit: 0\nSmokeTests passed")
            default:
                Issue.record("Unexpected tool \(call.tool.rawValue)")
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
            }
        }

        let report = await executor.execute(
            runID: "run-executor-verify-pass",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-verify-pass",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "apply patch and verify",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .balanced,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:full"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Write file",
                        tool: .write_file,
                        args: [
                            "path": .string("README.md"),
                            "content": .string("hello")
                        ]
                    )
                ],
                requiresTrustedAutomation: false,
                trustedDeviceID: "",
                workspaceBindingHash: "",
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_010_000,
                lastEditAuditRef: "audit-xt-auto-executor-verify-pass",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_010)
        )

        #expect(report.finalState == .delivered)
        #expect(report.holdReason.isEmpty)
        #expect(report.verificationReport?.required == true)
        #expect(report.verificationReport?.executed == true)
        #expect(report.verificationReport?.commandCount == 1)
        #expect(report.verificationReport?.passedCommandCount == 1)
        #expect(report.verificationReport?.detail == "verify_passed:1/1")
        #expect(report.workspaceDiffReport?.attempted == true)
        #expect(report.workspaceDiffReport?.captured == true)
        #expect(report.workspaceDiffReport?.fileCount == 1)
        #expect(report.workspaceDiffReport?.detail == "diff_captured:1_files")
        #expect(report.detail.contains("verify 1/1"))
        #expect(report.detail.contains("diff 1 files"))
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func executorBlocksWhenRequiredVerificationFails() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        try AXProjectStore.saveConfig(config, for: ctx)

        let callOrder = LockedStringCollector()
        let executor = XTAutomationRunExecutor { call, _ in
            await callOrder.append(call.tool.rawValue)
            switch call.tool {
            case .git_apply_check:
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "exit: 0\npatch clean")
            case .git_apply:
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "exit: 0\npatch applied")
            case .git_diff:
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: """
                    diff --git a/README.md b/README.md
                    @@ -1 +1 @@
                    -old
                    +new
                    """
                )
            case .run_command:
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nSmokeTests failed")
            default:
                Issue.record("Unexpected tool \(call.tool.rawValue)")
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
            }
        }

        let report = await executor.execute(
            runID: "run-executor-verify-fail",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-verify-fail",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "apply patch and verify",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .balanced,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:full"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Apply patch",
                        tool: .git_apply,
                        args: [
                            "patch": .string("--- a/README.md\n+++ b/README.md\n@@\n-old\n+new\n")
                        ]
                    )
                ],
                requiresTrustedAutomation: false,
                trustedDeviceID: "",
                workspaceBindingHash: "",
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_011_000,
                lastEditAuditRef: "audit-xt-auto-executor-verify-fail",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_011)
        )

        #expect(report.finalState == .blocked)
        #expect(report.holdReason == "automation_verify_failed")
        #expect(report.verificationReport?.required == true)
        #expect(report.verificationReport?.executed == true)
        #expect(report.verificationReport?.passedCommandCount == 0)
        #expect(report.verificationReport?.holdReason == "automation_verify_failed")
        #expect(report.verificationReport?.detail == "verify_failed:1/1 swift test --filter SmokeTests")
        #expect(report.detail == "verify_failed:1/1 swift test --filter SmokeTests")
        #expect(report.workspaceDiffReport?.captured == true)
        let values = await callOrder.values()
        #expect(values == ["git_apply_check", "git_apply", "git_diff", "run_command"])
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func executorBlocksVerificationWhenProjectToolPolicyDeniesRunCommand() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        config = config.settingToolPolicy(deny: ["run_command"])
        try AXProjectStore.saveConfig(config, for: ctx)

        let callOrder = LockedStringCollector()
        let executor = XTAutomationRunExecutor { call, _ in
            await callOrder.append(call.tool.rawValue)
            switch call.tool {
            case .write_file:
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
            case .git_diff:
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: """
                    diff --git a/README.md b/README.md
                    @@ -0,0 +1 @@
                    +hello
                    """
                )
            default:
                Issue.record("Unexpected tool \(call.tool.rawValue)")
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
            }
        }

        let report = await executor.execute(
            runID: "run-executor-verify-policy-deny",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-verify-policy-deny",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "mutation verify respects tool deny",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .balanced,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:full"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Write file",
                        tool: .write_file,
                        args: [
                            "path": .string("README.md"),
                            "content": .string("hello")
                        ]
                    )
                ],
                requiresTrustedAutomation: false,
                trustedDeviceID: "",
                workspaceBindingHash: "",
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_011_500,
                lastEditAuditRef: "audit-xt-auto-executor-verify-policy-deny",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_011.5)
        )

        #expect(report.finalState == .blocked)
        #expect(report.holdReason == "automation_tool_policy_denied")
        #expect(report.verificationReport?.required == true)
        #expect(report.verificationReport?.executed == true)
        #expect(report.verificationReport?.passedCommandCount == 0)
        #expect(report.verificationReport?.holdReason == "automation_tool_policy_denied")
        #expect(report.verificationReport?.detail == "verify_preflight_failed:1/1 swift test --filter SmokeTests")
        #expect(report.workspaceDiffReport?.captured == true)
        let values = await callOrder.values()
        #expect(values == ["write_file", "git_diff"])
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func executorBlocksWhenGitApplyPrecheckFails() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let callOrder = LockedStringCollector()
        let executor = XTAutomationRunExecutor { call, _ in
            await callOrder.append(call.tool.rawValue)
            switch call.tool {
            case .git_apply_check:
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: "exit: 1\npatch does not apply"
                )
            default:
                Issue.record("Unexpected tool \(call.tool.rawValue)")
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
            }
        }

        let report = await executor.execute(
            runID: "run-executor-precheck-fail",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-precheck-fail",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "apply patch safely",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .balanced,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:full"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Apply patch",
                        tool: .git_apply,
                        args: [
                            "patch": .string("--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-old\n+new\n")
                        ]
                    )
                ],
                requiresTrustedAutomation: false,
                trustedDeviceID: "",
                workspaceBindingHash: "",
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_012_000,
                lastEditAuditRef: "audit-xt-auto-executor-precheck-fail",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_012)
        )

        #expect(report.finalState == .blocked)
        #expect(report.holdReason == "automation_patch_check_failed")
        #expect(report.executedActionCount == 1)
        #expect(report.actionResults.first?.denyCode == "automation_patch_check_failed")
        #expect(report.actionResults.first?.detail == "exit: 1\npatch does not apply")
        #expect(report.verificationReport == nil)
        #expect(report.workspaceDiffReport == nil)
        let values = await callOrder.values()
        #expect(values == ["git_apply_check"])
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func conservativeExecutionProfileBlocksMutationToolsBeforeExecution() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let callOrder = LockedStringCollector()
        let executor = XTAutomationRunExecutor { call, _ in
            await callOrder.append(call.tool.rawValue)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
        }

        let report = await executor.execute(
            runID: "run-executor-conservative-deny",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-conservative-deny",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "read-only automation",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .conservative,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:full"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Write file",
                        tool: .write_file,
                        args: [
                            "path": .string("README.md"),
                            "content": .string("hello")
                        ]
                    )
                ],
                requiresTrustedAutomation: false,
                trustedDeviceID: "",
                workspaceBindingHash: "",
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_013_000,
                lastEditAuditRef: "audit-xt-auto-executor-conservative-deny",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_013)
        )

        #expect(report.finalState == .blocked)
        #expect(report.holdReason == "automation_execution_profile_denied")
        #expect(report.actionResults.first?.denyCode == "automation_execution_profile_denied")
        #expect(report.actionResults.first?.detail == "execution_profile=conservative blocks tool write_file")
        let values = await callOrder.values()
        #expect(values.isEmpty)
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func balancedExecutionProfileBlocksDeviceAutomationTools() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let callOrder = LockedStringCollector()
        let executor = XTAutomationRunExecutor { call, _ in
            await callOrder.append(call.tool.rawValue)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
        }

        let report = await executor.execute(
            runID: "run-executor-balanced-device-deny",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-balanced-device-deny",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "coding automation without device control",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .balanced,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:device_automation"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Click UI element",
                        tool: .deviceUIAct,
                        args: [
                            "action": .string("click"),
                            "target_title": .string("Continue")
                        ]
                    )
                ],
                requiresTrustedAutomation: true,
                trustedDeviceID: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root),
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_014_000,
                lastEditAuditRef: "audit-xt-auto-executor-balanced-device-deny",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_014)
        )

        #expect(report.finalState == .blocked)
        #expect(report.holdReason == "automation_execution_profile_denied")
        #expect(report.actionResults.first?.detail == "execution_profile=balanced blocks tool device.ui.act")
        let values = await callOrder.values()
        #expect(values.isEmpty)
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func aggressiveExecutionProfileAllowsDeviceAutomationTools() async throws {
        try await Self.permissionGate.run {
            let root = try makeProjectRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-executor-aggressive-device-allow"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            config = config.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_300_015)
            )
            config = config.settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s2PeriodicReview
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            let callOrder = LockedStringCollector()
            let executor = XTAutomationRunExecutor { call, _ in
                await callOrder.append(call.tool.rawValue)
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: ToolExecutor.structuredOutput(
                        summary: [
                            "tool": .string(call.tool.rawValue),
                            "ok": .bool(true),
                        ],
                        body: "device action ok"
                    )
                )
            }

            let report = await executor.execute(
                runID: "run-executor-aggressive-device-allow",
                recipe: AXAutomationRecipeRuntimeBinding(
                    recipeID: "xt-auto-executor-aggressive-device-allow",
                    recipeVersion: 1,
                    lifecycleState: .ready,
                    goal: "trusted device automation",
                    triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                    deliveryTargets: ["channel://telegram/project-a"],
                    acceptancePackRef: "build/reports/acceptance.json",
                    executionProfile: .aggressive,
                    touchMode: .guidedTouch,
                    innovationLevel: .l1,
                    laneStrategy: .singleLane,
                    requiredToolGroups: ["group:device_automation"],
                    actionGraph: [
                        XTAutomationRecipeAction(
                            title: "Observe UI",
                            tool: .deviceUIObserve,
                            successBodyContains: "device action ok"
                        )
                    ],
                    requiresTrustedAutomation: true,
                    trustedDeviceID: "device_xt_001",
                    workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root),
                    grantPolicyRef: "policy://automation-trigger/project-a",
                    rolloutStatus: .active,
                    lastEditedAtMs: 1_773_300_015_000,
                    lastEditAuditRef: "audit-xt-auto-executor-aggressive-device-allow",
                    lastLaunchRef: ""
                ),
                ctx: ctx,
                now: Date(timeIntervalSince1970: 1_773_300_015)
            )

            #expect(report.finalState == .delivered)
            #expect(report.holdReason.isEmpty)
            let values = await callOrder.values()
            #expect(values == ["device.ui.observe"])
            try expectHandoffArtifactExists(report: report, root: root)
        }
    }

    @Test
    func executorBlocksDangerousRunCommandForUnattendedAutomation() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let callOrder = LockedStringCollector()
        let executor = XTAutomationRunExecutor { call, _ in
            await callOrder.append(call.tool.rawValue)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
        }

        let report = await executor.execute(
            runID: "run-executor-dangerous-command-deny",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-dangerous-command-deny",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "dangerous shell must fail closed",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .aggressive,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:full"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Dangerous command",
                        tool: .run_command,
                        args: [
                            "command": .string("sudo shutdown -h now")
                        ]
                    )
                ],
                requiresTrustedAutomation: false,
                trustedDeviceID: "",
                workspaceBindingHash: "",
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_016_000,
                lastEditAuditRef: "audit-xt-auto-executor-dangerous-command-deny",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_016)
        )

        #expect(report.finalState == .blocked)
        #expect(report.holdReason == "automation_dangerous_command_denied")
        #expect(report.actionResults.first?.denyCode == "automation_dangerous_command_denied")
        let values = await callOrder.values()
        #expect(values.isEmpty)
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func executorBlocksWhenProjectToolPolicyDeniesRunCommand() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingToolPolicy(deny: ["run_command"])
        try AXProjectStore.saveConfig(config, for: ctx)

        let callOrder = LockedStringCollector()
        let executor = XTAutomationRunExecutor { call, _ in
            await callOrder.append(call.tool.rawValue)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
        }

        let report = await executor.execute(
            runID: "run-executor-tool-policy-run-command-deny",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-tool-policy-run-command-deny",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "respect project tool deny",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .balanced,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:full"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Run safe command",
                        tool: .run_command,
                        args: [
                            "command": .string("echo safe")
                        ]
                    )
                ],
                requiresTrustedAutomation: false,
                trustedDeviceID: "",
                workspaceBindingHash: "",
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_017_000,
                lastEditAuditRef: "audit-xt-auto-executor-tool-policy-run-command-deny",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_017)
        )

        #expect(report.finalState == .blocked)
        #expect(report.holdReason == "automation_tool_policy_denied")
        #expect(report.actionResults.first?.denyCode == "automation_tool_policy_denied")
        #expect(report.actionResults.first?.detail.contains("run_command") == true)
        let values = await callOrder.values()
        #expect(values.isEmpty)
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func executorBlocksWhenProjectToolPolicyDeniesWriteFile() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingToolPolicy(deny: ["write_file"])
        try AXProjectStore.saveConfig(config, for: ctx)

        let callOrder = LockedStringCollector()
        let executor = XTAutomationRunExecutor { call, _ in
            await callOrder.append(call.tool.rawValue)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
        }

        let report = await executor.execute(
            runID: "run-executor-tool-policy-write-file-deny",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-tool-policy-write-file-deny",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "respect file mutation deny",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .balanced,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:full"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Write file",
                        tool: .write_file,
                        args: [
                            "path": .string("README.md"),
                            "content": .string("hello")
                        ]
                    )
                ],
                requiresTrustedAutomation: false,
                trustedDeviceID: "",
                workspaceBindingHash: "",
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_018_000,
                lastEditAuditRef: "audit-xt-auto-executor-tool-policy-write-file-deny",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_018)
        )

        #expect(report.finalState == .blocked)
        #expect(report.holdReason == "automation_tool_policy_denied")
        #expect(report.actionResults.first?.denyCode == "automation_tool_policy_denied")
        #expect(report.actionResults.first?.detail.contains("write_file") == true)
        let values = await callOrder.values()
        #expect(values.isEmpty)
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func executorBlocksTrustedDeviceAutomationWhenProjectPolicyDeniesDeviceSurface() async throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.ui.observe"],
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
        )
        config = config.settingAutonomyPolicy(
            mode: .trustedOpenClawMode,
            updatedAt: Date(timeIntervalSince1970: 1_773_300_019)
        )
        config = config.settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )
        config = config.settingToolPolicy(deny: ["group:device_automation"])
        try AXProjectStore.saveConfig(config, for: ctx)

        let callOrder = LockedStringCollector()
        let executor = XTAutomationRunExecutor { call, _ in
            await callOrder.append(call.tool.rawValue)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
        }

        let report = await executor.execute(
            runID: "run-executor-device-policy-deny",
            recipe: AXAutomationRecipeRuntimeBinding(
                recipeID: "xt-auto-executor-device-policy-deny",
                recipeVersion: 1,
                lifecycleState: .ready,
                goal: "trusted observe respects project device deny",
                triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                deliveryTargets: ["channel://telegram/project-a"],
                acceptancePackRef: "build/reports/acceptance.json",
                executionProfile: .aggressive,
                touchMode: .guidedTouch,
                innovationLevel: .l1,
                laneStrategy: .singleLane,
                requiredToolGroups: ["group:device_automation"],
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Observe UI",
                        tool: .deviceUIObserve,
                        args: [
                            "target_title": .string("Continue")
                        ]
                    )
                ],
                requiresTrustedAutomation: true,
                trustedDeviceID: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root),
                grantPolicyRef: "policy://automation-trigger/project-a",
                rolloutStatus: .active,
                lastEditedAtMs: 1_773_300_019_000,
                lastEditAuditRef: "audit-xt-auto-executor-device-policy-deny",
                lastLaunchRef: ""
            ),
            ctx: ctx,
            now: Date(timeIntervalSince1970: 1_773_300_019)
        )

        #expect(report.finalState == .blocked)
        #expect(report.holdReason == "automation_tool_policy_denied")
        #expect(report.actionResults.first?.denyCode == "automation_tool_policy_denied")
        #expect(report.actionResults.first?.detail.contains("device.ui.observe") == true)
        let values = await callOrder.values()
        #expect(values.isEmpty)
        try expectHandoffArtifactExists(report: report, root: root)
    }

    @Test
    func executorBlocksTrustedDeviceAutomationWhenPermissionOwnerIsMissing() async throws {
        try await Self.permissionGate.run {
            let root = try makeProjectRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .missing,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-executor-device-permission-missing"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            config = config.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_300_020)
            )
            config = config.settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s2PeriodicReview
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            let callOrder = LockedStringCollector()
            let executor = XTAutomationRunExecutor { call, _ in
                await callOrder.append(call.tool.rawValue)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
            }

            let report = await executor.execute(
                runID: "run-executor-device-permission-missing",
                recipe: AXAutomationRecipeRuntimeBinding(
                    recipeID: "xt-auto-executor-device-permission-missing",
                    recipeVersion: 1,
                    lifecycleState: .ready,
                    goal: "device observe needs accessibility",
                    triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                    deliveryTargets: ["channel://telegram/project-a"],
                    acceptancePackRef: "build/reports/acceptance.json",
                    executionProfile: .aggressive,
                    touchMode: .guidedTouch,
                    innovationLevel: .l1,
                    laneStrategy: .singleLane,
                    requiredToolGroups: ["group:device_automation"],
                    actionGraph: [
                        XTAutomationRecipeAction(
                            title: "Observe UI",
                            tool: .deviceUIObserve,
                            args: [
                                "target_title": .string("Continue")
                            ]
                        )
                    ],
                    requiresTrustedAutomation: true,
                    trustedDeviceID: "device_xt_001",
                    workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root),
                    grantPolicyRef: "policy://automation-trigger/project-a",
                    rolloutStatus: .active,
                    lastEditedAtMs: 1_773_300_020_000,
                    lastEditAuditRef: "audit-xt-auto-executor-device-permission-missing",
                    lastLaunchRef: ""
                ),
                ctx: ctx,
                now: Date(timeIntervalSince1970: 1_773_300_020)
            )

            #expect(report.finalState == .blocked)
            #expect(report.holdReason == XTDeviceAutomationRejectCode.systemPermissionMissing.rawValue)
            #expect(report.actionResults.first?.denyCode == XTDeviceAutomationRejectCode.systemPermissionMissing.rawValue)
            #expect(report.actionResults.first?.detail.contains("accessibility") == true)
            let values = await callOrder.values()
            #expect(values.isEmpty)
            try expectHandoffArtifactExists(report: report, root: root)
        }
    }

    @Test
    func executorBlocksDeviceUIStepWhenTrustedAutomationIsNotArmedForActPhase() async throws {
        try await Self.permissionGate.run {
            let root = try makeProjectRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-executor-device-step-not-armed"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: root)
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            config = config.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_300_021)
            )
            config = config.settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s2PeriodicReview
            )
            try AXProjectStore.saveConfig(config, for: ctx)

            let callOrder = LockedStringCollector()
            let executor = XTAutomationRunExecutor { call, _ in
                await callOrder.append(call.tool.rawValue)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
            }

            let report = await executor.execute(
                runID: "run-executor-device-step-not-armed",
                recipe: AXAutomationRecipeRuntimeBinding(
                    recipeID: "xt-auto-executor-device-step-not-armed",
                    recipeVersion: 1,
                    lifecycleState: .ready,
                    goal: "step requires observe and act",
                    triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
                    deliveryTargets: ["channel://telegram/project-a"],
                    acceptancePackRef: "build/reports/acceptance.json",
                    executionProfile: .aggressive,
                    touchMode: .guidedTouch,
                    innovationLevel: .l1,
                    laneStrategy: .singleLane,
                    requiredToolGroups: ["group:device_automation"],
                    actionGraph: [
                        XTAutomationRecipeAction(
                            title: "Observe-act step",
                            tool: .deviceUIStep,
                            args: [
                                "action": .string("press_focused"),
                                "target_title": .string("Continue")
                            ]
                        )
                    ],
                    requiresTrustedAutomation: true,
                    trustedDeviceID: "device_xt_001",
                    workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root),
                    grantPolicyRef: "policy://automation-trigger/project-a",
                    rolloutStatus: .active,
                    lastEditedAtMs: 1_773_300_021_000,
                    lastEditAuditRef: "audit-xt-auto-executor-device-step-not-armed",
                    lastLaunchRef: ""
                ),
                ctx: ctx,
                now: Date(timeIntervalSince1970: 1_773_300_021)
            )

            #expect(report.finalState == .blocked)
            #expect(report.holdReason == XTDeviceAutomationRejectCode.deviceAutomationToolNotArmed.rawValue)
            #expect(report.actionResults.first?.denyCode == XTDeviceAutomationRejectCode.deviceAutomationToolNotArmed.rawValue)
            #expect(report.actionResults.first?.detail.contains("device.ui.act") == true)
            let values = await callOrder.values()
            #expect(values.isEmpty)
            try expectHandoffArtifactExists(report: report, root: root)
        }
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-automation-run-executor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func markAsSwiftPackage(_ root: URL) throws {
        let packageURL = root.appendingPathComponent("Package.swift")
        let package = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "Fixture",
            targets: [
                .target(name: "Fixture")
            ]
        )
        """
        try package.write(to: packageURL, atomically: true, encoding: .utf8)
    }

    private func expectHandoffArtifactExists(
        report: XTAutomationRunExecutionReport,
        root: URL
    ) throws {
        let handoffPath = try #require(report.handoffArtifactPath)
        let absolute = root.appendingPathComponent(handoffPath)
        #expect(FileManager.default.fileExists(atPath: absolute.path))
    }
}

private actor LockedStringCollector {
    private var items: [String] = []

    func append(_ value: String) {
        items.append(value)
    }

    func values() -> [String] {
        items
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
