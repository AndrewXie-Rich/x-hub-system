import Foundation
import Testing
@testable import XTerminal

@MainActor
struct XTToolRuntimePolicyGovernanceClampTests {

    @Test
    func invalidGovernanceComboFailsClosedBeforeRuntimeClamp() {
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
        #expect(decision.denyCode == "governance_capability_denied")
        #expect(decision.policySource == "project_governance")
        #expect(decision.policyReason == "execution_tier_missing_device_tools")
        #expect(jsonString(summary["execution_tier"]) == AXProjectExecutionTier.a4OpenClaw.rawValue)
        #expect(jsonString(summary["effective_execution_tier"]) == AXProjectExecutionTier.a0Observe.rawValue)
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
