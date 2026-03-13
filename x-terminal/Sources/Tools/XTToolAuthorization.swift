import Foundation

enum XTToolAuthorizationDisposition: String, Equatable {
    case allow
    case ask
    case deny
}

struct XTToolAuthorizationBlockedCall: Equatable {
    var call: ToolCall
    var decision: XTToolAuthorizationDecision
}

struct XTApprovedToolExecutionPlan: Equatable {
    var runnableCalls: [ToolCall]
    var blockedCalls: [XTToolAuthorizationBlockedCall]
}

struct XTToolAuthorizationDecision: Equatable {
    var disposition: XTToolAuthorizationDisposition
    var risk: ToolRisk
    var denyCode: String
    var detail: String
    var policySource: String
    var policyReason: String
    var runtimePolicyDecision: XTToolRuntimePolicyDecision?
    var runtimeEffectiveAutonomy: AXProjectAutonomyEffectivePolicy?
    var deviceGateDecision: XTDeviceAutomationGateDecision?

    static func allow(risk: ToolRisk = .safe) -> XTToolAuthorizationDecision {
        XTToolAuthorizationDecision(
            disposition: .allow,
            risk: risk,
            denyCode: "",
            detail: "",
            policySource: "",
            policyReason: "",
            runtimePolicyDecision: nil,
            runtimeEffectiveAutonomy: nil,
            deviceGateDecision: nil
        )
    }

    static func allowAutoApproved(policySource: String, policyReason: String) -> XTToolAuthorizationDecision {
        XTToolAuthorizationDecision(
            disposition: .allow,
            risk: .safe,
            denyCode: "",
            detail: "",
            policySource: policySource,
            policyReason: policyReason,
            runtimePolicyDecision: nil,
            runtimeEffectiveAutonomy: nil,
            deviceGateDecision: nil
        )
    }

    static func ask(risk: ToolRisk, policySource: String = "", policyReason: String = "") -> XTToolAuthorizationDecision {
        XTToolAuthorizationDecision(
            disposition: .ask,
            risk: risk,
            denyCode: "",
            detail: "",
            policySource: policySource,
            policyReason: policyReason,
            runtimePolicyDecision: nil,
            runtimeEffectiveAutonomy: nil,
            deviceGateDecision: nil
        )
    }

    static func denyRuntime(
        _ decision: XTToolRuntimePolicyDecision,
        effectiveAutonomy: AXProjectAutonomyEffectivePolicy
    ) -> XTToolAuthorizationDecision {
        XTToolAuthorizationDecision(
            disposition: .deny,
            risk: .safe,
            denyCode: decision.denyCode,
            detail: decision.detail,
            policySource: decision.policySource,
            policyReason: decision.policyReason,
            runtimePolicyDecision: decision,
            runtimeEffectiveAutonomy: effectiveAutonomy,
            deviceGateDecision: nil
        )
    }

    static func denyDevice(
        _ decision: XTDeviceAutomationGateDecision,
        tool: ToolName,
        gateTool: ToolName
    ) -> XTToolAuthorizationDecision {
        return XTToolAuthorizationDecision(
            disposition: .deny,
            risk: .safe,
            denyCode: decision.rejectCode?.rawValue ?? XTDeviceAutomationRejectCode.toolNotSupported.rawValue,
            detail: xtDeviceAutomationGateDeniedDetail(tool: tool, gateTool: gateTool, decision: decision),
            policySource: "trusted_automation_device_gate",
            policyReason: decision.requiredDeviceToolGroup.isEmpty
                ? "device_gate_failed"
                : "required_device_tool_group=\(decision.requiredDeviceToolGroup)",
            runtimePolicyDecision: nil,
            runtimeEffectiveAutonomy: nil,
            deviceGateDecision: decision
        )
    }

    var shouldRunImmediately: Bool {
        disposition == .allow
    }

    var needsApproval: Bool {
        disposition == .ask
    }

    var isDenied: Bool {
        disposition == .deny
    }
}

func xtApprovedToolExecutionPlan(
    calls: [ToolCall],
    config: AXProjectConfig,
    projectRoot: URL
) async -> XTApprovedToolExecutionPlan {
    var runnableCalls: [ToolCall] = []
    var blockedCalls: [XTToolAuthorizationBlockedCall] = []

    for call in calls {
        let decision = await xtToolAuthorizationDecision(
            call: call,
            config: config,
            projectRoot: projectRoot
        )
        if decision.isDenied {
            blockedCalls.append(XTToolAuthorizationBlockedCall(call: call, decision: decision))
        } else {
            // User approval overrides ask/alwaysConfirm, but never deny.
            runnableCalls.append(call)
        }
    }

    return XTApprovedToolExecutionPlan(
        runnableCalls: runnableCalls,
        blockedCalls: blockedCalls
    )
}

func xtToolAuthorizationDecision(
    call: ToolCall,
    config: AXProjectConfig,
    projectRoot: URL
) async -> XTToolAuthorizationDecision {
    let deviceGateTools = xtToolAuthorizationDeviceGateTools(for: call.tool)
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
            guard decision.allowed else {
                return .denyDevice(decision, tool: call.tool, gateTool: gateTool)
            }
        }
    }

    let autonomyState = await xtResolveProjectAutonomyPolicy(
        projectRoot: projectRoot,
        config: config
    )
    let runtimePolicyDecision = xtToolRuntimePolicyDecision(
        call: call,
        projectRoot: projectRoot,
        config: config,
        effectiveAutonomy: autonomyState.effectivePolicy
    )
    guard runtimePolicyDecision.allowed else {
        return .denyRuntime(
            runtimePolicyDecision,
            effectiveAutonomy: autonomyState.effectivePolicy
        )
    }

    let effectiveRisk: ToolRisk
    if ToolPolicy.isAlwaysConfirm(call: call) {
        effectiveRisk = .alwaysConfirm
    } else {
        effectiveRisk = ToolPolicy.risk(for: call)
    }

    if effectiveRisk == .needsConfirm,
       xtProjectGovernedAutoApprovalEnabled(
        projectRoot: projectRoot,
        config: config,
        effectiveAutonomy: autonomyState.effectivePolicy
       ) {
        return .allowAutoApproved(
            policySource: "project_governed_auto_approval",
            policyReason: "governed_device_authority"
        )
    }

    switch effectiveRisk {
    case .safe:
        return .allow(risk: effectiveRisk)
    case .needsConfirm, .alwaysConfirm:
        return .ask(
            risk: effectiveRisk,
            policySource: effectiveRisk == .alwaysConfirm ? "always_confirm_guard" : "",
            policyReason: effectiveRisk == .alwaysConfirm ? "dangerous_run_command" : ""
        )
    }
}

func xtToolAuthorizationDeniedSummary(
    call: ToolCall,
    projectRoot: URL,
    config: AXProjectConfig,
    decision: XTToolAuthorizationDecision
) -> [String: JSONValue] {
    if let runtimePolicyDecision = decision.runtimePolicyDecision {
        return xtToolRuntimePolicyDeniedSummary(
            call: call,
            projectRoot: projectRoot,
            config: config,
            decision: runtimePolicyDecision,
            effectiveAutonomy: decision.runtimeEffectiveAutonomy
        )
    }

    if let deviceGateDecision = decision.deviceGateDecision {
        var summary = xtDeviceAutomationSummaryBase(
            call: call,
            projectRoot: projectRoot,
            decision: deviceGateDecision,
            ok: false
        )
        summary["deny_code"] = .string(decision.denyCode)
        return summary
    }

    return [
        "tool": .string(call.tool.rawValue),
        "ok": .bool(false),
        "project_id": .string(AXProjectRegistryStore.projectId(forRoot: projectRoot)),
        "deny_code": .string(decision.denyCode.isEmpty ? "tool_authorization_denied" : decision.denyCode),
        "policy_source": .string(decision.policySource),
        "policy_reason": .string(decision.policyReason),
        "tool_profile": .string(config.toolProfile),
        "tool_allow": .array(config.toolAllow.map(JSONValue.string)),
        "tool_deny": .array(config.toolDeny.map(JSONValue.string)),
    ]
}

func xtToolAuthorizationDeniedOutput(
    call: ToolCall,
    projectRoot: URL,
    config: AXProjectConfig,
    decision: XTToolAuthorizationDecision
) -> String {
    ToolExecutor.structuredOutput(
        summary: xtToolAuthorizationDeniedSummary(
            call: call,
            projectRoot: projectRoot,
            config: config,
            decision: decision
        ),
        body: decision.detail
    )
}

func xtDeviceAutomationSummaryBase(
    call: ToolCall,
    projectRoot: URL,
    decision: XTDeviceAutomationGateDecision,
    ok: Bool
) -> [String: JSONValue] {
    let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
    let requiredPermissions = AXTrustedAutomationPermissionOwnerReadiness.requiredPermissionKeys(
        forDeviceToolGroups: [decision.requiredDeviceToolGroup]
    )
    return [
        "tool": .string(call.tool.rawValue),
        "ok": .bool(ok),
        "project_id": .string(projectId),
        "device_tool_group": .string(decision.requiredDeviceToolGroup),
        "side_effect_class": .string(DeviceAutomationTools.sideEffectClass(for: call.tool)),
        "paired_device_id": .string(decision.trustedAutomationStatus.boundDeviceID),
        "trusted_automation_state": .string(decision.trustedAutomationStatus.state.rawValue),
        "trusted_automation_ready": .bool(decision.trustedAutomationStatus.trustedAutomationReady),
        "trusted_automation_permission_owner_ready": .bool(decision.trustedAutomationStatus.permissionOwnerReady),
        "trusted_automation_missing_prerequisites": .array(
            decision.trustedAutomationStatus.missingPrerequisites.map(JSONValue.string)
        ),
        "trusted_automation_required_permissions": .array(requiredPermissions.map(JSONValue.string)),
        "permission_owner_audit_ref": .string(decision.permissionReadiness.auditRef),
    ]
}

func xtDeviceAutomationGateDeniedDetail(
    tool: ToolName,
    gateTool: ToolName,
    decision: XTDeviceAutomationGateDecision
) -> String {
    if tool == .deviceUIStep {
        let requiredToken = decision.requiredDeviceToolGroup.isEmpty
            ? gateTool.rawValue
            : decision.requiredDeviceToolGroup
        return "device.ui.step requires \(requiredToken): \(decision.detail)"
    }
    return decision.detail
}

private func xtToolAuthorizationDeviceGateTools(for tool: ToolName) -> [ToolName] {
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
