import Foundation

struct XTToolRuntimePolicyDecision: Equatable, Sendable {
    var allowed: Bool
    var denyCode: String
    var detail: String
    var policySource: String
    var policyReason: String

    static func allow() -> XTToolRuntimePolicyDecision {
        XTToolRuntimePolicyDecision(
            allowed: true,
            denyCode: "",
            detail: "",
            policySource: "",
            policyReason: ""
        )
    }

    static func deny(
        code: String,
        detail: String,
        policySource: String,
        policyReason: String
    ) -> XTToolRuntimePolicyDecision {
        XTToolRuntimePolicyDecision(
            allowed: false,
            denyCode: code,
            detail: detail,
            policySource: policySource,
            policyReason: policyReason
        )
    }
}

private func xtRuntimeSurfacePolicyReason(_ reason: String) -> String {
    switch reason {
    case "autonomy_mode=manual":
        return "runtime_surface_effective=manual"
    case "autonomy_mode=guided":
        return "runtime_surface_effective=guided"
    case "autonomy_ttl_expired":
        return "runtime_surface_ttl_expired"
    default:
        return reason
    }
}

func xtToolRuntimePolicyDecision(
    call: ToolCall,
    projectRoot: URL? = nil,
    config: AXProjectConfig,
    effectiveAutonomy: AXProjectAutonomyEffectivePolicy? = nil,
    resolvedGovernance: AXProjectResolvedGovernanceState? = nil
) -> XTToolRuntimePolicyDecision {
    let governanceState = xtRuntimeGovernanceState(
        projectRoot: projectRoot,
        config: config,
        effectiveAutonomy: effectiveAutonomy,
        resolvedGovernance: resolvedGovernance
    )
    if let deny = xtGovernanceCapabilityDenyDecision(
        for: call,
        governance: governanceState
    ) {
        return deny
    }

    if let autonomySurface = xtAutonomySurface(for: call.tool) {
        let effective = effectiveAutonomy ?? config.effectiveAutonomyPolicy()
        if let deny = xtAutonomyPolicyDenyDecision(
            for: call.tool,
            surface: autonomySurface,
            config: config,
            effective: effective
        ) {
            return deny
        }
    }

    let grantedTools = ToolPolicy.grantedTools(
        profileRaw: config.toolProfile,
        allowTokens: ToolPolicy.normalizePolicyTokens(config.toolAllow),
        denyTokens: ToolPolicy.normalizePolicyTokens(config.toolDeny)
    )
    let allowedTools = ToolPolicy.usableTools(grantedTools)
    let requiredTools = ToolPolicy.runtimeRequiredTools(for: call.tool)
    guard !requiredTools.isSubset(of: allowedTools) else {
        return .allow()
    }
    let missingTools = ToolPolicy.sortedTools(requiredTools.subtracting(grantedTools))

    let detail: String
    if missingTools.isEmpty {
        detail = "project tool policy blocks \(call.tool.rawValue); dependent tools are not jointly enabled (profile=\(config.toolProfile))"
    } else if missingTools.count == 1, missingTools[0] == call.tool {
        detail = "project tool policy blocks tool \(call.tool.rawValue) (profile=\(config.toolProfile))"
    } else {
        let missingTokens = missingTools.map(\.rawValue).joined(separator: ",")
        detail = "project tool policy blocks \(call.tool.rawValue); missing required tools \(missingTokens) (profile=\(config.toolProfile))"
    }

    return .deny(
        code: "tool_policy_denied",
        detail: detail,
        policySource: "project_tool_policy",
        policyReason: "tool_not_allowed"
    )
}

func xtToolRuntimePolicyDeniedSummary(
    call: ToolCall,
    projectRoot: URL,
    config: AXProjectConfig,
    decision: XTToolRuntimePolicyDecision,
    effectiveAutonomy: AXProjectAutonomyEffectivePolicy? = nil
) -> [String: JSONValue] {
    let requiredTools = ToolPolicy.sortedTools(ToolPolicy.runtimeRequiredTools(for: call.tool)).map(\.rawValue)
    let autonomy = effectiveAutonomy ?? config.effectiveAutonomyPolicy()
    let configuredAutonomySurfaces = config.configuredAutonomySurfaceLabels
    let governance = xtRuntimeGovernanceState(
        projectRoot: projectRoot,
        config: config,
        effectiveAutonomy: effectiveAutonomy,
        resolvedGovernance: nil
    )
    let runtimeSurfaceObject: JSONValue = .object([
        "configured_surface": .string(config.autonomyMode.rawValue),
        "effective_surface": .string(autonomy.effectiveMode.rawValue),
        "hub_override_surface": .string(autonomy.hubOverrideMode.rawValue),
        "local_override_surface": .string(autonomy.localOverrideMode.rawValue),
        "remote_override_surface": .string(autonomy.remoteOverrideMode.rawValue),
        "remote_override_source": .string(autonomy.remoteOverrideSource),
        "remote_override_updated_at_ms": .number(Double(autonomy.remoteOverrideUpdatedAtMs)),
        "ttl_sec": .number(Double(config.autonomyTTLSeconds)),
        "remaining_sec": .number(Double(autonomy.remainingSeconds)),
        "expired": .bool(autonomy.expired),
        "kill_switch_engaged": .bool(autonomy.killSwitchEngaged),
        "configured_surfaces": .array(configuredAutonomySurfaces.map(JSONValue.string)),
        "effective_surfaces": .array(autonomy.allowedSurfaceLabels.map(JSONValue.string)),
        "updated_at_ms": .number(Double(config.autonomyUpdatedAtMs)),
    ])
    let autonomyPolicyObject: JSONValue = .object([
        "configured_mode": .string(config.autonomyMode.rawValue),
        "effective_mode": .string(autonomy.effectiveMode.rawValue),
        "hub_override_mode": .string(autonomy.hubOverrideMode.rawValue),
        "local_override_mode": .string(autonomy.localOverrideMode.rawValue),
        "remote_override_mode": .string(autonomy.remoteOverrideMode.rawValue),
        "remote_override_source": .string(autonomy.remoteOverrideSource),
        "remote_override_updated_at_ms": .number(Double(autonomy.remoteOverrideUpdatedAtMs)),
        "ttl_sec": .number(Double(config.autonomyTTLSeconds)),
        "remaining_sec": .number(Double(autonomy.remainingSeconds)),
        "expired": .bool(autonomy.expired),
        "kill_switch_engaged": .bool(autonomy.killSwitchEngaged),
        "configured_surfaces": .array(configuredAutonomySurfaces.map(JSONValue.string)),
        "effective_surfaces": .array(autonomy.allowedSurfaceLabels.map(JSONValue.string)),
        "updated_at_ms": .number(Double(config.autonomyUpdatedAtMs)),
    ])
    return [
        "tool": .string(call.tool.rawValue),
        "ok": .bool(false),
        "project_id": .string(AXProjectRegistryStore.projectId(forRoot: projectRoot)),
        "deny_code": .string(decision.denyCode),
        "policy_source": .string(decision.policySource),
        "policy_reason": .string(decision.policyReason),
        "runtime_surface_policy_reason": .string(
            decision.policySource == "project_autonomy_policy"
                ? xtRuntimeSurfacePolicyReason(decision.policyReason)
                : ""
        ),
        "tool_profile": .string(config.toolProfile),
        "tool_allow": .array(config.toolAllow.map(JSONValue.string)),
        "tool_deny": .array(config.toolDeny.map(JSONValue.string)),
        "required_tools": .array(requiredTools.map(JSONValue.string)),
        "runtime_surface": runtimeSurfaceObject,
        "autonomy_policy": autonomyPolicyObject,
        "runtime_surface_configured": .string(config.autonomyMode.rawValue),
        "runtime_surface_effective": .string(autonomy.effectiveMode.rawValue),
        "runtime_surface_hub_override": .string(autonomy.hubOverrideMode.rawValue),
        "runtime_surface_local_override": .string(autonomy.localOverrideMode.rawValue),
        "runtime_surface_remote_override": .string(autonomy.remoteOverrideMode.rawValue),
        "runtime_surface_remote_override_source": .string(autonomy.remoteOverrideSource),
        "runtime_surface_remote_override_updated_at_ms": .number(Double(autonomy.remoteOverrideUpdatedAtMs)),
        "runtime_surface_ttl_sec": .number(Double(config.autonomyTTLSeconds)),
        "runtime_surface_remaining_sec": .number(Double(autonomy.remainingSeconds)),
        "runtime_surface_expired": .bool(autonomy.expired),
        "runtime_surface_kill_switch_engaged": .bool(autonomy.killSwitchEngaged),
        "runtime_surface_configured_surfaces": .array(configuredAutonomySurfaces.map(JSONValue.string)),
        "runtime_surface_effective_surfaces": .array(autonomy.allowedSurfaceLabels.map(JSONValue.string)),
        "runtime_surface_updated_at_ms": .number(Double(config.autonomyUpdatedAtMs)),
        "autonomy_mode": .string(config.autonomyMode.rawValue),
        "autonomy_effective_mode": .string(autonomy.effectiveMode.rawValue),
        "autonomy_hub_override_mode": .string(autonomy.hubOverrideMode.rawValue),
        "autonomy_local_override_mode": .string(autonomy.localOverrideMode.rawValue),
        "autonomy_remote_override_mode": .string(autonomy.remoteOverrideMode.rawValue),
        "autonomy_remote_override_source": .string(autonomy.remoteOverrideSource),
        "autonomy_remote_override_updated_at_ms": .number(Double(autonomy.remoteOverrideUpdatedAtMs)),
        "autonomy_ttl_sec": .number(Double(config.autonomyTTLSeconds)),
        "autonomy_remaining_sec": .number(Double(autonomy.remainingSeconds)),
        "autonomy_expired": .bool(autonomy.expired),
        "autonomy_kill_switch_engaged": .bool(autonomy.killSwitchEngaged),
        "autonomy_configured_surfaces": .array(configuredAutonomySurfaces.map(JSONValue.string)),
        "autonomy_effective_surfaces": .array(autonomy.allowedSurfaceLabels.map(JSONValue.string)),
        "autonomy_updated_at_ms": .number(Double(config.autonomyUpdatedAtMs)),
        "execution_tier": .string(governance.configuredBundle.executionTier.rawValue),
        "effective_execution_tier": .string(governance.effectiveBundle.executionTier.rawValue),
        "supervisor_intervention_tier": .string(governance.configuredBundle.supervisorInterventionTier.rawValue),
        "effective_supervisor_intervention_tier": .string(governance.effectiveBundle.supervisorInterventionTier.rawValue),
        "governance_allowed_capabilities": .array(governance.capabilityBundle.allowedCapabilityLabels.map(JSONValue.string)),
    ]
}

private enum XTAutonomySurface: String {
    case deviceTools = "device_tools"
    case browserRuntime = "browser_runtime"
    case connectorActions = "connector_actions"
    case extensions = "extensions"
}

private enum XTGovernanceCapabilityKind: String {
    case repoWrite = "repo_write"
    case repoDeleteMove = "repo_delete_move"
    case repoBuild = "repo_build"
    case repoTest = "repo_test"
    case repoBuildTest = "repo_build_test"
    case gitApply = "git_apply"
    case gitCommit = "git_commit"
    case gitPush = "git_push"
    case prCreate = "pr_create"
    case ciRead = "ci_read"
    case ciTrigger = "ci_trigger"
    case managedProcesses = "managed_processes"
    case processAutoRestart = "process_autorestart"
    case browserRuntime = "browser_runtime"
    case deviceTools = "device_tools"
}

private func xtAutonomySurface(for tool: ToolName) -> XTAutonomySurface? {
    switch tool {
    case .deviceUIObserve,
            .deviceUIAct,
            .deviceUIStep,
            .deviceClipboardRead,
            .deviceClipboardWrite,
            .deviceScreenCapture,
            .deviceAppleScript:
        return .deviceTools
    case .deviceBrowserControl:
        return .browserRuntime
    default:
        return nil
    }
}

private func xtGovernanceCapability(for call: ToolCall) -> XTGovernanceCapabilityKind? {
    switch call.tool {
    case .write_file:
        return .repoWrite
    case .delete_path, .move_path:
        return .repoDeleteMove
    case .run_command:
        switch xtGovernedRepoCommandProfile(for: call) {
        case .build?:
            return .repoBuild
        case .test?:
            return .repoTest
        case .backup?:
            return .repoWrite
        case nil:
            return .repoBuildTest
        }
    case .process_start:
        return xtProcessStartRequestsAutoRestart(call) ? .processAutoRestart : .managedProcesses
    case .process_status, .process_logs, .process_stop:
        return .managedProcesses
    case .git_commit:
        return .gitCommit
    case .git_push:
        return .gitPush
    case .git_apply, .git_apply_check:
        return .gitApply
    case .pr_create:
        return .prCreate
    case .ci_read:
        return .ciRead
    case .ci_trigger:
        return .ciTrigger
    case .deviceBrowserControl:
        return .browserRuntime
    case .deviceUIObserve,
            .deviceUIAct,
            .deviceUIStep,
            .deviceClipboardRead,
            .deviceClipboardWrite,
            .deviceScreenCapture,
            .deviceAppleScript:
        return .deviceTools
    default:
        return nil
    }
}

private func xtRuntimeGovernanceState(
    projectRoot: URL?,
    config: AXProjectConfig,
    effectiveAutonomy: AXProjectAutonomyEffectivePolicy?,
    resolvedGovernance: AXProjectResolvedGovernanceState?
) -> AXProjectResolvedGovernanceState {
    if let resolvedGovernance {
        return resolvedGovernance
    }
    let root = projectRoot ?? URL(fileURLWithPath: "/")
    if let effectiveAutonomy {
        return xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            effectiveAutonomy: effectiveAutonomy
        )
    }
    return xtResolveProjectGovernance(
        projectRoot: root,
        config: config
    )
}

private func xtGovernanceCapabilityDenyDecision(
    for call: ToolCall,
    governance: AXProjectResolvedGovernanceState
) -> XTToolRuntimePolicyDecision? {
    guard let capability = xtGovernanceCapability(for: call) else { return nil }

    let allowed: Bool
    let reason: String
    switch capability {
    case .repoWrite:
        allowed = governance.capabilityBundle.allowRepoWrite
        reason = "execution_tier_missing_repo_write"
    case .repoDeleteMove:
        allowed = governance.capabilityBundle.allowRepoDeleteMove
        reason = "execution_tier_missing_repo_delete_move"
    case .repoBuild:
        allowed = governance.capabilityBundle.allowRepoBuild
        reason = "execution_tier_missing_repo_build"
    case .repoTest:
        allowed = governance.capabilityBundle.allowRepoTest
        reason = "execution_tier_missing_repo_test"
    case .repoBuildTest:
        allowed = governance.capabilityBundle.allowRepoBuild || governance.capabilityBundle.allowRepoTest
        reason = "execution_tier_missing_repo_build_test"
    case .gitApply:
        allowed = governance.capabilityBundle.allowGitApply
        reason = "execution_tier_missing_git_apply"
    case .gitCommit:
        allowed = governance.capabilityBundle.allowGitCommit
        reason = "execution_tier_missing_git_commit"
    case .gitPush:
        allowed = governance.capabilityBundle.allowGitPush
        reason = "execution_tier_missing_git_push"
    case .prCreate:
        allowed = governance.capabilityBundle.allowPRCreate
        reason = "execution_tier_missing_pr_create"
    case .ciRead:
        allowed = governance.capabilityBundle.allowCIRead
        reason = "execution_tier_missing_ci_read"
    case .ciTrigger:
        allowed = governance.capabilityBundle.allowCITrigger
        reason = "execution_tier_missing_ci_trigger"
    case .managedProcesses:
        allowed = governance.capabilityBundle.allowManagedProcesses
        reason = "execution_tier_missing_managed_processes"
    case .processAutoRestart:
        allowed = governance.capabilityBundle.allowManagedProcesses && governance.capabilityBundle.allowProcessAutoRestart
        reason = "execution_tier_missing_process_autorestart"
    case .browserRuntime:
        allowed = governance.capabilityBundle.allowBrowserRuntime
        reason = "execution_tier_missing_browser_runtime"
    case .deviceTools:
        allowed = governance.capabilityBundle.allowDeviceTools
        reason = "execution_tier_missing_device_tools"
    }
    guard !allowed else { return nil }

    return .deny(
        code: "governance_capability_denied",
        detail: "project governance blocks \(call.tool.rawValue) under execution tier \(governance.effectiveBundle.executionTier.rawValue)",
        policySource: "project_governance",
        policyReason: reason
    )
}

private func xtProcessStartRequestsAutoRestart(_ call: ToolCall) -> Bool {
    guard call.tool == .process_start else { return false }
    switch call.args["restart_on_exit"] {
    case .bool(let flag):
        return flag
    case .string(let text):
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "true" || normalized == "1" || normalized == "yes" || normalized == "on"
    default:
        return false
    }
}

private func xtAutonomyPolicyDenyDecision(
    for tool: ToolName,
    surface: XTAutonomySurface,
    config: AXProjectConfig,
    effective: AXProjectAutonomyEffectivePolicy
) -> XTToolRuntimePolicyDecision? {
    if effective.killSwitchEngaged {
        let clamp = xtAutonomyClampExplanation(
            effective: effective,
            style: .guardrailEnglish
        )
        return .deny(
            code: "autonomy_policy_denied",
            detail: "runtime surface policy kill_switch blocks \(tool.rawValue)",
            policySource: "project_autonomy_policy",
            policyReason: clamp?.policyReason ?? AXProjectAutonomyClampKind.killSwitch.rawValue
        )
    }

    let allowed: Bool
    switch surface {
    case .deviceTools:
        allowed = effective.allowDeviceTools
    case .browserRuntime:
        allowed = effective.allowBrowserRuntime
    case .connectorActions:
        allowed = effective.allowConnectorActions
    case .extensions:
        allowed = effective.allowExtensions
    }
    guard !allowed else { return nil }

    let reason: String
    if let clamp = xtAutonomyClampExplanation(
        effective: effective,
        style: .guardrailEnglish
    ) {
        reason = clamp.policyReason
    } else if effective.effectiveMode == .manual {
        reason = "autonomy_mode=manual"
    } else if effective.effectiveMode == .guided,
              surface != .browserRuntime {
        reason = "autonomy_mode=guided"
    } else {
        reason = "surface=\(surface.rawValue)_disallowed"
    }

    return .deny(
        code: "autonomy_policy_denied",
        detail: "runtime surface policy blocks \(tool.rawValue) on surface \(surface.rawValue) (configured=\(config.autonomyMode.rawValue), effective=\(effective.effectiveMode.rawValue))",
        policySource: "project_autonomy_policy",
        policyReason: reason
    )
}
