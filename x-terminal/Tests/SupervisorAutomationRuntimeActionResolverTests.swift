import Foundation
import Testing
@testable import XTerminal

struct SupervisorAutomationRuntimeActionResolverTests {

    @Test
    func actionsStayDisabledWithoutProjectSelection() {
        let context = SupervisorAutomationRuntimeActionResolver.Context(
            hasSelectedProject: false,
            hasRecipe: false,
            hasLastLaunchRef: false
        )

        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .status, context: context)
                .isEnabled == false
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .start, context: context)
                .isEnabled == false
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .recover, context: context)
                .isEnabled == false
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .cancel, context: context)
                .isEnabled == false
        )
    }

    @Test
    func startRequiresActiveRecipeAndRecoverFlowRequiresLaunchRef() {
        let context = SupervisorAutomationRuntimeActionResolver.Context(
            hasSelectedProject: true,
            hasRecipe: true,
            hasLastLaunchRef: false
        )

        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .start, context: context)
                .isEnabled
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .recover, context: context)
                .isEnabled == false
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.advanceDescriptors(context: context)
                .allSatisfy { $0.isEnabled == false }
        )
    }

    @Test
    func launchRefEnablesRecoverCancelAndAdvanceControls() {
        let context = SupervisorAutomationRuntimeActionResolver.Context(
            hasSelectedProject: true,
            hasRecipe: false,
            hasLastLaunchRef: true
        )

        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .recover, context: context)
                .isEnabled
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .cancel, context: context)
                .isEnabled
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.advanceDescriptors(context: context)
                .allSatisfy { $0.isEnabled }
        )
    }

    @Test
    func a4RuntimeReadinessHoldBlocksStartRecoverAndAdvanceButNotCancel() {
        let context = SupervisorAutomationRuntimeActionResolver.Context(
            hasSelectedProject: true,
            hasRecipe: true,
            hasLastLaunchRef: true,
            runtimeReadiness: makeBlockedA4RuntimeReadinessSnapshot()
        )

        let start = SupervisorAutomationRuntimeActionResolver.descriptor(for: .start, context: context)
        let recover = SupervisorAutomationRuntimeActionResolver.descriptor(for: .recover, context: context)
        let cancel = SupervisorAutomationRuntimeActionResolver.descriptor(for: .cancel, context: context)
        let advance = SupervisorAutomationRuntimeActionResolver.descriptor(for: .advance(.delivered), context: context)

        #expect(start.isEnabled == false)
        #expect(recover.isEnabled == false)
        #expect(cancel.isEnabled)
        #expect(advance.isEnabled == false)
        #expect(start.helpText.contains("A4 Agent 已配置") == true)
        #expect(recover.helpText.contains("缺口：执行面被收束到 guided") == true)
        #expect(cancel.helpText == "取消当前自动化运行")
        #expect(advance.helpText.contains("runtime ready") == true)
    }

    @Test
    func commandsMapToStableAutomationCliSurface() {
        #expect(
            SupervisorAutomationRuntimeActionResolver.command(for: .status)
                == "/automation status"
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.command(for: .start)
                == "/automation start"
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.command(for: .advance(.delivered))
                == "/automation advance delivered"
        )
    }
}

private func makeBlockedA4RuntimeReadinessSnapshot() -> AXProjectGovernanceRuntimeReadinessSnapshot {
    let detailLines = [
        "project_governance_runtime_readiness_schema_version=\(AXProjectGovernanceRuntimeReadinessSnapshot.currentSchemaVersion)",
        "project_governance_configured_execution_tier=\(AXProjectExecutionTier.a4OpenClaw.rawValue)",
        "project_governance_effective_execution_tier=\(AXProjectExecutionTier.a4OpenClaw.rawValue)",
        "project_governance_configured_runtime_surface_mode=\(AXProjectRuntimeSurfaceMode.trustedOpenClawMode.rawValue)",
        "project_governance_effective_runtime_surface_mode=\(AXProjectRuntimeSurfaceMode.guided.rawValue)",
        "project_governance_runtime_surface_override_mode=\(AXProjectRuntimeSurfaceHubOverrideMode.clampGuided.rawValue)",
        "project_governance_trusted_automation_state=\(AXTrustedAutomationProjectState.blocked.rawValue)",
        "project_governance_requires_a4_runtime_ready=true",
        "project_governance_runtime_ready=false",
        "project_governance_runtime_readiness_state=\(AXProjectGovernanceRuntimeReadinessState.blocked.rawValue)",
        "project_governance_runtime_readiness_summary=A4 Agent 已配置，但 runtime ready 还没完成。",
        "project_governance_missing_readiness=runtime_surface_clamped_guided,trusted_automation_not_ready",
        "project_governance_runtime_readiness_missing_summary=缺口：执行面被收束到 guided / 受治理自动化未就绪"
    ]
    return AXProjectGovernanceRuntimeReadinessSnapshot(detailLines: detailLines)!
}
