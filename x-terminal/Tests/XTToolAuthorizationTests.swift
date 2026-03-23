import Foundation
import Testing
@testable import XTerminal

struct XTToolAuthorizationTests {
    private static let permissionGate = TrustedAutomationPermissionTestGate.shared

    @Test
    func dangerousRunCommandRequiresAlwaysConfirmApproval() async {
        let fixture = ToolExecutorProjectFixture(name: "tool-authorization-dangerous-run-command")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
        let decision = await xtToolAuthorizationDecision(
            call: ToolCall(
                tool: .run_command,
                args: ["command": .string("sudo echo hello")]
            ),
            config: config,
            projectRoot: fixture.root
        )

        #expect(decision.disposition == .ask)
        #expect(decision.risk == .alwaysConfirm)
        #expect(decision.policySource == "always_confirm_guard")
        #expect(decision.policyReason == "dangerous_run_command")
    }

    @Test
    func governedAutoApprovalAllowsGovernedRepoTestRunCommandWhenProjectAuthorityIsActive() async {
        let fixture = ToolExecutorProjectFixture(name: "tool-authorization-governed-auto-approve-run")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date()
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)

        let decision = await xtToolAuthorizationDecision(
            call: ToolCall(
                tool: .run_command,
                args: ["command": .string("swift test --filter SmokeTests")]
            ),
            config: config,
            projectRoot: fixture.root
        )

        #expect(decision.disposition == .allow)
        #expect(decision.risk == .safe)
        #expect(decision.policySource == "project_governed_auto_approval")
        #expect(decision.policyReason == "governed_repo_command_allowlist")
    }

    @Test
    func governedAutoApprovalAllowsGovernedLocalBackupCommandWhenProjectAuthorityIsActive() async {
        let fixture = ToolExecutorProjectFixture(name: "tool-authorization-governed-auto-approve-backup")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date()
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)

        let decision = await xtToolAuthorizationDecision(
            call: ToolCall(
                tool: .run_command,
                args: [
                    "command": .string(
                        #"mkdir -p .ax-backups && /usr/bin/tar -czf ".ax-backups/project-backup-$(/bin/date +%Y%m%d-%H%M%S).tgz" --exclude .git --exclude .build --exclude .ax-backups ."#
                    )
                ]
            ),
            config: config,
            projectRoot: fixture.root
        )

        #expect(decision.disposition == .allow)
        #expect(decision.risk == .safe)
        #expect(decision.policySource == "project_governed_auto_approval")
        #expect(decision.policyReason == "governed_repo_command_allowlist")
    }

    @Test
    func governedAutoApprovalKeepsNonGovernedRunCommandManualEvenWhenProjectAuthorityIsActive() async {
        let fixture = ToolExecutorProjectFixture(name: "tool-authorization-governed-auto-approve-run-manual")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date()
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)

        let decision = await xtToolAuthorizationDecision(
            call: ToolCall(
                tool: .run_command,
                args: ["command": .string("echo hello")]
            ),
            config: config,
            projectRoot: fixture.root
        )

        #expect(decision.disposition == .ask)
        #expect(decision.risk == .needsConfirm)
        #expect(decision.policySource == "governed_command_guard")
        #expect(decision.policyReason == "command_outside_governed_repo_allowlist")
    }

    @Test
    func governedAutoApprovalStillKeepsDangerousRunCommandManual() async {
        let fixture = ToolExecutorProjectFixture(name: "tool-authorization-governed-auto-approve-dangerous")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date()
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)

        let decision = await xtToolAuthorizationDecision(
            call: ToolCall(
                tool: .run_command,
                args: ["command": .string("sudo echo hello")]
            ),
            config: config,
            projectRoot: fixture.root
        )

        #expect(decision.disposition == .ask)
        #expect(decision.risk == .alwaysConfirm)
        #expect(decision.policySource == "always_confirm_guard")
        #expect(decision.policyReason == "dangerous_run_command")
    }

    @Test
    func writeFileIsDeniedByProjectToolPolicy() async {
        let fixture = ToolExecutorProjectFixture(name: "tool-authorization-write-file-deny")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
            .settingToolPolicy(deny: ["write_file"])
        let call = ToolCall(
            tool: .write_file,
            args: [
                "path": .string("README.md"),
                "content": .string("hello")
            ]
        )
        let decision = await xtToolAuthorizationDecision(
            call: call,
            config: config,
            projectRoot: fixture.root
        )

        #expect(decision.disposition == .deny)
        #expect(decision.denyCode == "tool_policy_denied")
        #expect(decision.policySource == "project_tool_policy")
        let summary = xtToolAuthorizationDeniedSummary(
            call: call,
            projectRoot: fixture.root,
            config: config,
            decision: decision
        )
        #expect(jsonString(summary["deny_code"]) == "tool_policy_denied")
        #expect(jsonString(summary["policy_source"]) == "project_tool_policy")
        #expect(jsonString(summary["policy_reason"]) == "tool_not_allowed")
    }

    @Test
    func deviceGatePrecedesProjectToolPolicyForUntrustedClipboardRead() async {
        let fixture = ToolExecutorProjectFixture(name: "tool-authorization-device-gate-precedence")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingToolPolicy(deny: ["device.clipboard.read"])
        let call = ToolCall(tool: .deviceClipboardRead, args: [:])
        let decision = await xtToolAuthorizationDecision(
            call: call,
            config: config,
            projectRoot: fixture.root
        )

        #expect(decision.disposition == .deny)
        #expect(decision.denyCode == XTDeviceAutomationRejectCode.trustedAutomationModeOff.rawValue)
        #expect(decision.policySource == "trusted_automation_device_gate")
        #expect(decision.runtimePolicyDecision == nil)
        let summary = xtToolAuthorizationDeniedSummary(
            call: call,
            projectRoot: fixture.root,
            config: config,
            decision: decision
        )
        #expect(jsonString(summary["deny_code"]) == XTDeviceAutomationRejectCode.trustedAutomationModeOff.rawValue)
        #expect(jsonString(summary["trusted_automation_state"]) == AXTrustedAutomationProjectState.off.rawValue)
    }

    @Test
    func deviceUIStepRequiresBothObserveAndActDeviceGates() async {
        await Self.permissionGate.run {
            let fixture = ToolExecutorProjectFixture(name: "tool-authorization-device-step-gates")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makeToolAuthorizationPermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-tool-authorization-device-step-gates"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let config = AXProjectConfig
                .default(forProjectRoot: fixture.root)
                .settingTrustedAutomationBinding(
                    mode: .trustedAutomation,
                    deviceId: "device_xt_001",
                    deviceToolGroups: ["device.ui.observe"],
                    workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
                )
            let call = ToolCall(
                tool: .deviceUIStep,
                args: [
                    "action": .string("press_focused"),
                    "target_title": .string("Continue")
                ]
            )
            let decision = await xtToolAuthorizationDecision(
                call: call,
                config: config,
                projectRoot: fixture.root
            )

            #expect(decision.disposition == .deny)
            #expect(decision.denyCode == XTDeviceAutomationRejectCode.deviceAutomationToolNotArmed.rawValue)
            #expect(decision.policySource == "trusted_automation_device_gate")
            #expect(decision.policyReason == "required_device_tool_group=device.ui.act")
            #expect(decision.detail.contains("device.ui.step requires device.ui.act"))
        }
    }

    @Test
    func deviceUIStepNeedsApprovalWhenDeviceGatesAndToolPolicyPass() async {
        await Self.permissionGate.run {
            let fixture = ToolExecutorProjectFixture(name: "tool-authorization-device-step-ask")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makeToolAuthorizationPermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-tool-authorization-device-step-ask"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let config = AXProjectConfig
                .default(forProjectRoot: fixture.root)
                .settingTrustedAutomationBinding(
                    mode: .trustedAutomation,
                    deviceId: "device_xt_001",
                    deviceToolGroups: ["device.ui.observe", "device.ui.act"],
                    workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
                )
                .settingRuntimeSurfacePolicy(
                    mode: .trustedOpenClawMode,
                    updatedAt: Date()
                )
            let decision = await xtToolAuthorizationDecision(
                call: ToolCall(
                    tool: .deviceUIStep,
                    args: [
                        "action": .string("press_focused"),
                        "target_title": .string("Continue")
                    ]
                ),
                config: config,
                projectRoot: fixture.root
            )

            #expect(decision.disposition == .ask)
            #expect(decision.risk == .needsConfirm)
            #expect(decision.policySource.isEmpty)
            #expect(decision.policyReason.isEmpty)
        }
    }

    @Test
    func governedAutoApprovalAllowsDeviceBrowserControlWhenDeviceAuthorityIsActive() async {
        await Self.permissionGate.run {
            let fixture = ToolExecutorProjectFixture(name: "tool-authorization-device-browser-auto-approve")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makeToolAuthorizationPermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-tool-authorization-device-browser-auto-approve"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let config = AXProjectConfig
                .default(forProjectRoot: fixture.root)
                .settingTrustedAutomationBinding(
                    mode: .trustedAutomation,
                    deviceId: "device_xt_001",
                    deviceToolGroups: ["device.browser.control"],
                    workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
                )
                .settingRuntimeSurfacePolicy(
                    mode: .trustedOpenClawMode,
                    updatedAt: Date()
                )
                .settingGovernedAutoApproveLocalToolCalls(enabled: true)

            let decision = await xtToolAuthorizationDecision(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string("https://example.com")
                    ]
                ),
                config: config,
                projectRoot: fixture.root
            )

            #expect(decision.disposition == .allow)
            #expect(decision.risk == .safe)
            #expect(decision.policySource == "project_governed_auto_approval")
            #expect(decision.policyReason == "governed_device_authority")
        }
    }

    @Test
    func approvedExecutionPlanRerunsGuardsAndOnlyExecutesNonDeniedCalls() async {
        let fixture = ToolExecutorProjectFixture(name: "tool-authorization-approved-plan")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
            .settingToolPolicy(deny: ["write_file"])
        let calls = [
            ToolCall(
                id: "blocked_write",
                tool: .write_file,
                args: [
                    "path": .string("README.md"),
                    "content": .string("hello")
                ]
            ),
            ToolCall(
                id: "approved_dangerous_run",
                tool: .run_command,
                args: ["command": .string("sudo echo hello")]
            ),
        ]

        let plan = await xtApprovedToolExecutionPlan(
            calls: calls,
            config: config,
            projectRoot: fixture.root
        )

        #expect(plan.runnableCalls.map(\.id) == ["approved_dangerous_run"])
        #expect(plan.blockedCalls.map(\.call.id) == ["blocked_write"])
        #expect(plan.blockedCalls.first?.decision.denyCode == "tool_policy_denied")
    }
}

private func makeToolAuthorizationPermissionReadiness(
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
