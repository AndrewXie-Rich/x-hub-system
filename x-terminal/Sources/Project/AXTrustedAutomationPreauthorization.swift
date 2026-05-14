import Foundation

struct XTTrustedAutomationPreauthorizationResult: Equatable {
    var config: AXProjectConfig
    var eligible: Bool
    var didUpdate: Bool
    var refreshedRuntimeSurface: Bool
    var updatedTrustedAutomationBinding: Bool
    var deviceID: String
    var deviceToolGroups: [String]
    var missingPrerequisites: [String]
    var openSettingsActions: [String]
    var reason: String
}

func xtTrustedAutomationOpenClawPreauthorizationEligible(
    config: AXProjectConfig
) -> Bool {
    config.executionTier == .a4OpenClaw
        || config.runtimeSurfaceMode == .trustedOpenClawMode
}

func xtTrustedAutomationPreauthorizationDeviceID(
    config: AXProjectConfig,
    permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness
) -> String {
    let configured = config.trustedAutomationDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !configured.isEmpty { return configured }

    if let hubDeviceID = HubAccessKeysClient.resolveSessionContext()?.deviceID
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !hubDeviceID.isEmpty {
        return hubDeviceID
    }

    let ownerID = permissionReadiness.ownerID.trimmingCharacters(in: .whitespacesAndNewlines)
    return ownerID.isEmpty ? "local_owner" : ownerID
}

func xtTrustedAutomationPreauthorizedConfig(
    ctx: AXProjectContext,
    config: AXProjectConfig,
    now: Date = Date(),
    reason: String
) -> XTTrustedAutomationPreauthorizationResult {
    let permissionReadiness = AXTrustedAutomationPermissionOwnerReadiness.current()
    guard xtTrustedAutomationOpenClawPreauthorizationEligible(config: config) else {
        let status = config.trustedAutomationStatus(
            forProjectRoot: ctx.root,
            permissionReadiness: permissionReadiness
        )
        return XTTrustedAutomationPreauthorizationResult(
            config: config,
            eligible: false,
            didUpdate: false,
            refreshedRuntimeSurface: false,
            updatedTrustedAutomationBinding: false,
            deviceID: status.boundDeviceID,
            deviceToolGroups: status.armedDeviceToolGroups,
            missingPrerequisites: status.missingPrerequisites,
            openSettingsActions: permissionReadiness.suggestedOpenSettingsActions(
                forDeviceToolGroups: status.armedDeviceToolGroups
            ),
            reason: reason
        )
    }

    var updated = config
    let previousRuntimeSurface = config.effectiveRuntimeSurfacePolicy(now: now)
    var refreshedRuntimeSurface = false
    if config.runtimeSurfaceMode != .trustedOpenClawMode
        || !config.runtimeSurfaceAllowDeviceTools
        || !config.runtimeSurfaceAllowBrowserRuntime
        || !config.runtimeSurfaceAllowConnectorActions
        || !config.runtimeSurfaceAllowExtensions
        || previousRuntimeSurface.expired {
        updated = updated.settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            updatedAt: now
        )
        refreshedRuntimeSurface = true
    }

    let deviceID = xtTrustedAutomationPreauthorizationDeviceID(
        config: updated,
        permissionReadiness: permissionReadiness
    )
    let desiredGroups = xtNormalizedTrustedAutomationDeviceToolGroups(
        updated.deviceToolGroups + xtTrustedAutomationDefaultDeviceToolGroups()
    )
    let beforeBinding = (
        mode: updated.automationMode,
        deviceID: updated.trustedAutomationDeviceId,
        groups: xtNormalizedTrustedAutomationDeviceToolGroups(updated.deviceToolGroups),
        workspaceHash: updated.workspaceBindingHash,
        allow: ToolPolicy.normalizePolicyTokens(updated.toolAllow)
    )
    updated = updated.settingTrustedAutomationBinding(
        mode: .trustedAutomation,
        deviceId: deviceID,
        deviceToolGroups: desiredGroups,
        workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
    )
    let afterBinding = (
        mode: updated.automationMode,
        deviceID: updated.trustedAutomationDeviceId,
        groups: xtNormalizedTrustedAutomationDeviceToolGroups(updated.deviceToolGroups),
        workspaceHash: updated.workspaceBindingHash,
        allow: ToolPolicy.normalizePolicyTokens(updated.toolAllow)
    )
    let updatedTrustedAutomationBinding = beforeBinding.mode != afterBinding.mode
        || beforeBinding.deviceID != afterBinding.deviceID
        || beforeBinding.groups != afterBinding.groups
        || beforeBinding.workspaceHash != afterBinding.workspaceHash
        || beforeBinding.allow != afterBinding.allow

    let status = updated.trustedAutomationStatus(
        forProjectRoot: ctx.root,
        permissionReadiness: permissionReadiness,
        requiredDeviceToolGroups: desiredGroups
    )
    return XTTrustedAutomationPreauthorizationResult(
        config: updated,
        eligible: true,
        didUpdate: updated != config,
        refreshedRuntimeSurface: refreshedRuntimeSurface,
        updatedTrustedAutomationBinding: updatedTrustedAutomationBinding,
        deviceID: deviceID,
        deviceToolGroups: desiredGroups,
        missingPrerequisites: status.missingPrerequisites,
        openSettingsActions: permissionReadiness.suggestedOpenSettingsActions(
            forDeviceToolGroups: desiredGroups
        ),
        reason: reason
    )
}

@discardableResult
func xtPersistTrustedAutomationPreauthorizationIfNeeded(
    ctx: AXProjectContext,
    config: AXProjectConfig,
    now: Date = Date(),
    reason: String
) -> XTTrustedAutomationPreauthorizationResult {
    let result = xtTrustedAutomationPreauthorizedConfig(
        ctx: ctx,
        config: config,
        now: now,
        reason: reason
    )
    guard result.didUpdate else { return result }
    try? AXProjectStore.saveConfig(result.config, for: ctx)
    xtRecordTrustedAutomationPreauthorization(result, ctx: ctx, now: now)
    return result
}

func xtRecordTrustedAutomationPreauthorization(
    _ result: XTTrustedAutomationPreauthorizationResult,
    ctx: AXProjectContext,
    now: Date = Date()
) {
    guard result.didUpdate else { return }
    AXProjectStore.appendRawLog(
        [
            "type": "trusted_automation_preauthorization",
            "action": "prearm_openclaw_runtime",
            "created_at": now.timeIntervalSince1970,
            "project_id": AXProjectRegistryStore.projectId(forRoot: ctx.root),
            "reason": result.reason,
            "eligible": result.eligible,
            "runtime_surface_refreshed": result.refreshedRuntimeSurface,
            "trusted_automation_binding_updated": result.updatedTrustedAutomationBinding,
            "device_id": result.deviceID,
            "device_tool_groups": result.deviceToolGroups,
            "missing_prerequisites": result.missingPrerequisites,
            "open_settings_actions": result.openSettingsActions,
            "approval_effect": "preauthorized_for_fast_local_approval",
        ],
        for: ctx
    )
}
