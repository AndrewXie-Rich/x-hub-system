import Foundation
import Testing
@testable import XTerminal

struct XTTrustedAutomationPreauthorizationTests {
    @Test
    func openClawPreauthorizationBindsDeviceArmsDefaultGroupsAndRefreshesRuntimeSurface() {
        let fixture = ToolExecutorProjectFixture(name: "trusted-automation-preauth-openclaw")
        defer { fixture.cleanup() }
        let ctx = AXProjectContext(root: fixture.root)
        let now = Date(timeIntervalSince1970: 5_000)
        let expiredRuntimeDate = Date(timeIntervalSince1970: 10)
        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingProjectGovernance(executionTier: .a4OpenClaw)
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: expiredRuntimeDate
            )

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makePreauthorizationPermissionReadiness(ownerID: "owner-openclaw")
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let result = xtTrustedAutomationPreauthorizedConfig(
            ctx: ctx,
            config: config,
            now: now,
            reason: "test"
        )

        #expect(result.eligible)
        #expect(result.didUpdate)
        #expect(result.refreshedRuntimeSurface)
        #expect(result.updatedTrustedAutomationBinding)
        #expect(result.config.automationMode == .trustedAutomation)
        #expect(result.config.trustedAutomationDeviceId == "owner-openclaw")
        #expect(result.config.workspaceBindingHash == xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root))
        #expect(result.config.toolAllow.contains("group:device_automation"))
        #expect(result.config.deviceToolGroups == xtTrustedAutomationDefaultDeviceToolGroups())
        #expect(result.config.effectiveRuntimeSurfacePolicy(now: now).effectiveMode == .trustedOpenClawMode)
        #expect(result.config.effectiveRuntimeSurfacePolicy(now: now).expired == false)
        #expect(result.missingPrerequisites.isEmpty)
    }

    @Test
    func nonOpenClawProjectsDoNotPreauthorizeTrustedAutomation() {
        let fixture = ToolExecutorProjectFixture(name: "trusted-automation-preauth-non-openclaw")
        defer { fixture.cleanup() }
        let ctx = AXProjectContext(root: fixture.root)
        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingProjectGovernance(executionTier: .a2RepoAuto)

        let result = xtTrustedAutomationPreauthorizedConfig(
            ctx: ctx,
            config: config,
            now: Date(timeIntervalSince1970: 2_000),
            reason: "test"
        )

        #expect(result.eligible == false)
        #expect(result.didUpdate == false)
        #expect(result.config == config)
        #expect(result.config.automationMode == .standard)
        #expect(result.config.deviceToolGroups.isEmpty)
    }

    @Test
    func persistedPreauthorizationWritesConfigAndAuditLogOnlyWhenNeeded() throws {
        let fixture = ToolExecutorProjectFixture(name: "trusted-automation-preauth-persist")
        defer { fixture.cleanup() }
        let ctx = AXProjectContext(root: fixture.root)
        let now = Date(timeIntervalSince1970: 2_000)
        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        try AXProjectStore.saveConfig(config, for: ctx)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makePreauthorizationPermissionReadiness(ownerID: "owner-persist")
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let result = xtPersistTrustedAutomationPreauthorizationIfNeeded(
            ctx: ctx,
            config: config,
            now: now,
            reason: "test_persist"
        )
        let saved = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let raw = AXProjectSkillActivityStore.loadRawLogText(ctx: ctx) ?? ""

        #expect(result.didUpdate)
        #expect(saved.trustedAutomationDeviceId == "owner-persist")
        #expect(saved.automationMode == .trustedAutomation)
        #expect(raw.contains("\"type\":\"trusted_automation_preauthorization\""))
        #expect(raw.contains("\"reason\":\"test_persist\""))

        let second = xtPersistTrustedAutomationPreauthorizationIfNeeded(
            ctx: ctx,
            config: saved,
            now: now,
            reason: "test_persist_again"
        )
        #expect(second.didUpdate == false)
    }
}

private func makePreauthorizationPermissionReadiness(
    ownerID: String
) -> AXTrustedAutomationPermissionOwnerReadiness {
    AXTrustedAutomationPermissionOwnerReadiness(
        schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
        ownerID: ownerID,
        ownerType: "xterminal_app",
        bundleID: "com.xterminal.app",
        installState: "ready",
        mode: "managed_or_prompted",
        accessibility: .granted,
        automation: .granted,
        screenRecording: .granted,
        fullDiskAccess: .missing,
        inputMonitoring: .missing,
        canPromptUser: true,
        managedByMDM: false,
        overallState: "ready",
        openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
        auditRef: "audit-preauthorization-test"
    )
}
