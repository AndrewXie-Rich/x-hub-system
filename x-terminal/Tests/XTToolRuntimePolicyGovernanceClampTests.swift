import Foundation
import Testing
@testable import XTerminal

@MainActor
struct XTToolRuntimePolicyGovernanceClampTests {

    @Test
    func explicitDualDialOpenClawGovernanceStillFailsClosedAtToolPolicy() {
        let root = makeProjectRoot(named: "runtime-governance-fail-closed")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview
        )
        config = config.settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            ttlSeconds: 600,
            updatedAt: Date()
        )

        let call = ToolCall(tool: .deviceClipboardRead, args: [:])
        let decision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: root,
            config: config
        )
        let summary = xtToolRuntimePolicyDeniedSummary(
            call: call,
            projectRoot: root,
            config: config,
            decision: decision
        )

        #expect(!decision.allowed)
        #expect(decision.denyCode == "tool_policy_denied")
        #expect(decision.policySource == "project_tool_policy")
        #expect(decision.policyReason == "tool_not_allowed")
        #expect(jsonString(summary["execution_tier"]) == AXProjectExecutionTier.a4OpenClaw.rawValue)
        #expect(jsonString(summary["effective_execution_tier"]) == AXProjectExecutionTier.a4OpenClaw.rawValue)
        #expect(jsonString(summary["review_policy_mode"]) == AXProjectReviewPolicyMode.hybrid.rawValue)
        #expect(jsonNumber(summary["progress_heartbeat_sec"]) == 600)
        #expect(jsonNumber(summary["review_pulse_sec"]) == 1200)
        #expect(jsonString(summary["governance_compat_source"]) == AXProjectGovernanceCompatSource.explicitDualDial.rawValue)
        #expect(jsonBool(summary["project_governance_runtime_ready"]) == false)
        #expect(jsonString(summary["project_governance_runtime_component_route_ready_state"]) == "ready")
        #expect(jsonString(summary["project_governance_runtime_component_capability_ready_state"]) == "ready")
        #expect(jsonString(summary["project_governance_runtime_component_grant_ready_state"]) == "blocked")
        #expect(jsonString(summary["project_governance_runtime_component_checkpoint_recovery_ready_state"]) == "ready")
        #expect(jsonString(summary["project_governance_runtime_component_evidence_export_ready_state"]) == "ready")
    }

    @Test
    func runtimeSurfaceClampDeniesBrowserRuntimeWithoutDowngradingGovernanceTier() {
        let root = makeProjectRoot(named: "runtime-governance-browser-clamp")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )
        config = config.settingRuntimeSurfacePolicy(
            mode: .guided,
            allowBrowserRuntime: false,
            updatedAt: Date()
        )

        let call = ToolCall(
            tool: .deviceBrowserControl,
            args: [
                "action": .string("open_url"),
                "url": .string("https://example.com")
            ]
        )
        let decision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: root,
            config: config
        )
        let summary = xtToolRuntimePolicyDeniedSummary(
            call: call,
            projectRoot: root,
            config: config,
            decision: decision
        )

        #expect(!decision.allowed)
        #expect(decision.denyCode == "autonomy_policy_denied")
        #expect(decision.policySource == "project_autonomy_policy")
        #expect(decision.policyReason == "surface=browser_runtime_disallowed")
        let runtimeSurface = jsonObject(summary["runtime_surface"])
        #expect(jsonString(runtimeSurface?["configured_surface"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
        #expect(jsonString(runtimeSurface?["effective_surface"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
        #expect(jsonArray(runtimeSurface?["configured_surfaces"])?.isEmpty == true)
        #expect(jsonArray(runtimeSurface?["effective_surfaces"])?.isEmpty == true)
        #expect(jsonString(summary["execution_tier"]) == AXProjectExecutionTier.a4OpenClaw.rawValue)
        #expect(jsonString(summary["effective_execution_tier"]) == AXProjectExecutionTier.a4OpenClaw.rawValue)
        #expect(jsonString(summary["runtime_surface_effective"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
        #expect(jsonString(summary["autonomy_effective_mode"]) == AXProjectRuntimeSurfaceMode.guided.rawValue)
        #expect(jsonString(summary["review_policy_mode"]) == AXProjectReviewPolicyMode.hybrid.rawValue)
        #expect(jsonString(summary["governance_compat_source"]) == AXProjectGovernanceCompatSource.explicitDualDial.rawValue)
        #expect(jsonString(summary["governance_reason"]) == "当前运行面不允许浏览器自动化。")
        #expect(jsonString(summary["blocked_summary"])?.contains("当前运行面不允许浏览器自动化。") == true)
        #expect(jsonString(summary["governance_truth"]) == XTGovernanceTruthPresentation.truthLine(from: summary))
        #expect(jsonString(summary["repair_action"])?.contains("打开治理设置：") == true)
    }

    @Test
    func governanceStillBlocksDeviceSurfaceBelowOpenClawEvenWhenRuntimeSurfacePresetIsOpenClaw() {
        let root = makeProjectRoot(named: "runtime-governance-device-floor")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )
        config = config.settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            ttlSeconds: 600,
            updatedAt: Date()
        )

        let call = ToolCall(tool: .deviceClipboardRead, args: [:])
        let decision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: root,
            config: config
        )
        let summary = xtToolRuntimePolicyDeniedSummary(
            call: call,
            projectRoot: root,
            config: config,
            decision: decision
        )

        #expect(!decision.allowed)
        #expect(decision.denyCode == "governance_capability_denied")
        #expect(decision.policySource == "project_governance")
        #expect(decision.policyReason == "execution_tier_missing_device_tools")
        #expect(jsonString(summary["execution_tier"]) == AXProjectExecutionTier.a3DeliverAuto.rawValue)
        #expect(jsonString(summary["effective_execution_tier"]) == AXProjectExecutionTier.a3DeliverAuto.rawValue)
        #expect(jsonString(summary["governance_reason"]) == "当前项目 A-Tier 不允许设备级工具。")
        #expect(jsonString(summary["blocked_summary"])?.contains("当前项目 A-Tier 不允许设备级工具。") == true)
        #expect(jsonString(summary["governance_truth"])?.contains("治理真相：当前生效 A3/S3") == true)
        #expect(jsonString(summary["repair_action"])?.contains("打开 A-Tier：") == true)
    }

    @Test
    func governanceUsesRepoTestReasonForGovernedTestCommands() {
        let root = makeProjectRoot(named: "runtime-governance-repo-test-reason")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s1MilestoneReview
        )

        let call = ToolCall(
            tool: .run_command,
            args: ["command": .string("swift test --filter SmokeTests")]
        )
        let decision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: root,
            config: config
        )
        let summary = xtToolRuntimePolicyDeniedSummary(
            call: call,
            projectRoot: root,
            config: config,
            decision: decision
        )

        #expect(!decision.allowed)
        #expect(decision.denyCode == "governance_capability_denied")
        #expect(decision.policySource == "project_governance")
        #expect(decision.policyReason == "execution_tier_missing_repo_test")
        #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_repo_test")
    }

    @Test
    func governanceUsesRepoBuildReasonForGovernedBuildCommands() {
        let root = makeProjectRoot(named: "runtime-governance-repo-build-reason")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s1MilestoneReview
        )

        let call = ToolCall(
            tool: .run_command,
            args: ["command": .string("swift build")]
        )
        let decision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: root,
            config: config
        )
        let summary = xtToolRuntimePolicyDeniedSummary(
            call: call,
            projectRoot: root,
            config: config,
            decision: decision
        )

        #expect(!decision.allowed)
        #expect(decision.denyCode == "governance_capability_denied")
        #expect(decision.policySource == "project_governance")
        #expect(decision.policyReason == "execution_tier_missing_repo_build")
        #expect(jsonString(summary["policy_reason"]) == "execution_tier_missing_repo_build")
    }

    private func makeProjectRoot(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
