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
        for: call.tool,
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
    let governance = xtRuntimeGovernanceState(
        projectRoot: projectRoot,
        config: config,
        effectiveAutonomy: effectiveAutonomy,
        resolvedGovernance: nil
    )
    return [
        "tool": .string(call.tool.rawValue),
        "ok": .bool(false),
        "project_id": .string(AXProjectRegistryStore.projectId(forRoot: projectRoot)),
        "deny_code": .string(decision.denyCode),
        "policy_source": .string(decision.policySource),
        "policy_reason": .string(decision.policyReason),
        "tool_profile": .string(config.toolProfile),
        "tool_allow": .array(config.toolAllow.map(JSONValue.string)),
        "tool_deny": .array(config.toolDeny.map(JSONValue.string)),
        "required_tools": .array(requiredTools.map(JSONValue.string)),
        "autonomy_mode": .string(config.autonomyMode.rawValue),
        "autonomy_effective_mode": .string(autonomy.effectiveMode.rawValue),
        "autonomy_hub_override_mode": .string(autonomy.hubOverrideMode.rawValue),
        "autonomy_local_override_mode": .string(autonomy.localOverrideMode.rawValue),
        "autonomy_remote_override_mode": .string(autonomy.remoteOverrideMode.rawValue),
        "autonomy_remote_override_source": .string(autonomy.remoteOverrideSource),
        "autonomy_remote_override_updated_at_ms": .number(Double(autonomy.remoteOverrideUpdatedAtMs)),
        "autonomy_ttl_sec": .number(Double(config.autonomyTTLSeconds)),
        "autonomy_remaining_sec": .number(Double(autonomy.remainingSeconds)),
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
    case repoBuildTest = "repo_build_test"
    case gitApply = "git_apply"
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

private func xtGovernanceCapability(for tool: ToolName) -> XTGovernanceCapabilityKind? {
    switch tool {
    case .write_file:
        return .repoWrite
    case .run_command:
        return .repoBuildTest
    case .git_apply, .git_apply_check:
        return .gitApply
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
    for tool: ToolName,
    governance: AXProjectResolvedGovernanceState
) -> XTToolRuntimePolicyDecision? {
    guard let capability = xtGovernanceCapability(for: tool) else { return nil }

    let allowed: Bool
    let reason: String
    switch capability {
    case .repoWrite:
        allowed = governance.capabilityBundle.allowRepoWrite
        reason = "execution_tier_missing_repo_write"
    case .repoBuildTest:
        allowed = governance.capabilityBundle.allowRepoBuild || governance.capabilityBundle.allowRepoTest
        reason = "execution_tier_missing_repo_build_test"
    case .gitApply:
        allowed = governance.capabilityBundle.allowGitApply
        reason = "execution_tier_missing_git_apply"
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
        detail: "project governance blocks \(tool.rawValue) under execution tier \(governance.effectiveBundle.executionTier.rawValue)",
        policySource: "project_governance",
        policyReason: reason
    )
}

private func xtAutonomyPolicyDenyDecision(
    for tool: ToolName,
    surface: XTAutonomySurface,
    config: AXProjectConfig,
    effective: AXProjectAutonomyEffectivePolicy
) -> XTToolRuntimePolicyDecision? {
    if effective.killSwitchEngaged {
        return .deny(
            code: "autonomy_policy_denied",
            detail: "autonomy policy kill_switch blocks \(tool.rawValue)",
            policySource: "project_autonomy_policy",
            policyReason: "hub_override=kill_switch"
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
    if effective.expired {
        reason = "autonomy_ttl_expired"
    } else if effective.hubOverrideMode == .clampManual {
        reason = "hub_override=clamp_manual"
    } else if effective.hubOverrideMode == .clampGuided,
              config.autonomyMode == .trustedOpenClawMode,
              effective.effectiveMode == .guided {
        reason = "hub_override=clamp_guided"
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
        detail: "autonomy policy blocks \(tool.rawValue) on surface \(surface.rawValue) (configured=\(config.autonomyMode.rawValue), effective=\(effective.effectiveMode.rawValue))",
        policySource: "project_autonomy_policy",
        policyReason: reason
    )
}
