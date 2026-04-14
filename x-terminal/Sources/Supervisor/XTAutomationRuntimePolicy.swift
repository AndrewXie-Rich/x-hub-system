import Foundation

struct XTAutomationRuntimePolicyDecision: Equatable, Sendable {
    var allowed: Bool
    var denyCode: String
    var detail: String
    var preflightTool: String
    var policySource: String
    var policyReason: String

    static func allow() -> XTAutomationRuntimePolicyDecision {
        XTAutomationRuntimePolicyDecision(
            allowed: true,
            denyCode: "",
            detail: "",
            preflightTool: "",
            policySource: "",
            policyReason: ""
        )
    }

    static func deny(
        code: String,
        detail: String,
        preflightTool: String,
        policySource: String,
        policyReason: String
    ) -> XTAutomationRuntimePolicyDecision {
        XTAutomationRuntimePolicyDecision(
            allowed: false,
            denyCode: code,
            detail: detail,
            preflightTool: preflightTool,
            policySource: policySource,
            policyReason: policyReason
        )
    }
}

func xtAutomationRuntimePolicyDecision(
    recipe: AXAutomationRecipeRuntimeBinding,
    action: XTAutomationRecipeAction,
    config: AXProjectConfig,
    projectRoot: URL,
    now: Date = Date()
) async -> XTAutomationRuntimePolicyDecision {
    if !xtAutomationExecutionProfileAllowedTools(recipe.executionProfile).contains(action.tool) {
        return .deny(
            code: "automation_execution_profile_denied",
            detail: "execution_profile=\(recipe.executionProfile.rawValue) blocks tool \(action.tool.rawValue)",
            preflightTool: "execution_profile_gate",
            policySource: "execution_profile",
            policyReason: "tool_not_in_execution_profile"
        )
    }

    let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
        projectRoot: projectRoot,
        config: config,
        now: now
    )
    let automationScopedConfig = xtAutomationRecipeScopedToolPolicyConfig(
        config: config,
        recipe: recipe
    )
    let toolPolicyDecision = xtToolRuntimePolicyDecision(
        call: ToolCall(
            id: "xt_auto_policy_\(action.actionID)",
            tool: action.tool,
            args: action.args
        ),
        projectRoot: projectRoot,
        config: automationScopedConfig,
        effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
    )
    if !toolPolicyDecision.allowed {
        return .deny(
            code: "automation_tool_policy_denied",
            detail: toolPolicyDecision.detail,
            preflightTool: "project_tool_policy_gate",
            policySource: toolPolicyDecision.policySource,
            policyReason: toolPolicyDecision.policyReason
        )
    }

    let deviceGateTools = xtAutomationRuntimeDeviceGateTools(for: action.tool)
    if !deviceGateTools.isEmpty {
        let permissionReadiness = await MainActor.run {
            AXTrustedAutomationPermissionOwnerReadiness.current()
        }
        for gateTool in deviceGateTools {
            let decision = DeviceAutomationTools.evaluateGate(
                for: gateTool,
                projectRoot: projectRoot,
                config: config,
                permissionReadiness: permissionReadiness
            )
            guard !decision.allowed else { continue }
            return .deny(
                code: decision.rejectCode?.rawValue ?? XTDeviceAutomationRejectCode.toolNotSupported.rawValue,
                detail: xtDeviceAutomationGateDeniedDetail(tool: action.tool, gateTool: gateTool, decision: decision),
                preflightTool: "trusted_device_gate",
                policySource: "trusted_automation_device_gate",
                policyReason: decision.requiredDeviceToolGroup.isEmpty
                    ? "device_gate_failed"
                    : "required_device_tool_group=\(decision.requiredDeviceToolGroup)"
            )
        }
    }

    let actionCall = ToolCall(
        id: "xt_auto_policy_\(action.actionID)",
        tool: action.tool,
        args: action.args
    )
    if ToolPolicy.isAlwaysConfirm(call: actionCall) {
        return .deny(
            code: "automation_dangerous_command_denied",
            detail: "dangerous command denied for unattended automation (\(action.tool.rawValue))",
            preflightTool: "dangerous_command_gate",
            policySource: "always_confirm_guard",
            policyReason: "dangerous_run_command"
        )
    }

    return .allow()
}

private func xtAutomationRecipeScopedToolPolicyConfig(
    config: AXProjectConfig,
    recipe: AXAutomationRecipeRuntimeBinding
) -> AXProjectConfig {
    let recipeDeclaredAllowTokens = recipe.requiredToolGroups + recipe.requiredDeviceToolGroups
    let mergedAllowTokens = ToolPolicy.normalizePolicyTokens(
        config.toolAllow + recipeDeclaredAllowTokens
    )
    guard mergedAllowTokens != config.toolAllow else {
        return config
    }
    return config.settingToolPolicy(allow: mergedAllowTokens)
}

func xtAutomationExecutionProfileAllowedTools(
    _ profile: XTAutomationExecutionProfile
) -> Set<ToolName> {
    switch profile {
    case .conservative:
        return [
            .read_file,
            .list_dir,
            .search,
            .git_status,
            .git_diff,
            .git_apply_check,
            .session_list,
            .session_resume,
            .session_compact,
            .memory_snapshot,
            .project_snapshot,
            .bridge_status,
            .web_search,
        ]
    case .balanced:
        return Set(ToolName.allCases).subtracting([
            .deviceUIObserve,
            .deviceUIAct,
            .deviceUIStep,
            .deviceClipboardRead,
            .deviceClipboardWrite,
            .deviceScreenCapture,
            .deviceBrowserControl,
            .deviceAppleScript,
        ])
    case .aggressive:
        return Set(ToolName.allCases)
    }
}
private func xtAutomationRuntimeDeviceGateTools(for tool: ToolName) -> [ToolName] {
    switch tool {
    case .deviceUIStep:
        return [.deviceUIObserve, .deviceUIAct]
    case .deviceUIObserve,
         .deviceUIAct,
         .deviceClipboardRead,
         .deviceClipboardWrite,
         .deviceScreenCapture,
         .deviceBrowserControl,
         .deviceAppleScript:
        return [tool]
    default:
        return []
    }
}
