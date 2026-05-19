import Foundation

enum XTAgentMode: String, Codable, CaseIterable, Sendable {
    case ask
    case plan
    case explore
    case debug
    case code
    case orchestrator

    static func parse(_ raw: String?) -> XTAgentMode? {
        let token = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        guard !token.isEmpty else { return nil }
        return XTAgentMode(rawValue: token)
    }

    static func from(call: ToolCall) -> XTAgentMode? {
        if case .string(let raw)? = call.args["agent_mode"] {
            return parse(raw)
        }
        if case .string(let raw)? = call.args["xt_agent_mode"] {
            return parse(raw)
        }
        return nil
    }
}

struct XTAgentModeCapabilityContract: Equatable, Sendable {
    var mode: XTAgentMode
    var canReadFiles: Bool
    var canWriteFiles: Bool
    var canRunShell: Bool
    var canRunDiagnostics: Bool
    var canApplyPatch: Bool
    var canSpawnLanes: Bool
    var requiresUserConfirmationBeforeFix: Bool
    var maxRiskClass: String

    static func contract(for mode: XTAgentMode) -> XTAgentModeCapabilityContract {
        switch mode {
        case .ask:
            return XTAgentModeCapabilityContract(
                mode: mode,
                canReadFiles: false,
                canWriteFiles: false,
                canRunShell: false,
                canRunDiagnostics: false,
                canApplyPatch: false,
                canSpawnLanes: false,
                requiresUserConfirmationBeforeFix: true,
                maxRiskClass: "read_only"
            )
        case .plan:
            return XTAgentModeCapabilityContract(
                mode: mode,
                canReadFiles: true,
                canWriteFiles: false,
                canRunShell: false,
                canRunDiagnostics: false,
                canApplyPatch: false,
                canSpawnLanes: false,
                requiresUserConfirmationBeforeFix: true,
                maxRiskClass: "low"
            )
        case .explore:
            return XTAgentModeCapabilityContract(
                mode: mode,
                canReadFiles: true,
                canWriteFiles: false,
                canRunShell: false,
                canRunDiagnostics: true,
                canApplyPatch: false,
                canSpawnLanes: false,
                requiresUserConfirmationBeforeFix: true,
                maxRiskClass: "low"
            )
        case .debug:
            return XTAgentModeCapabilityContract(
                mode: mode,
                canReadFiles: true,
                canWriteFiles: false,
                canRunShell: false,
                canRunDiagnostics: true,
                canApplyPatch: false,
                canSpawnLanes: false,
                requiresUserConfirmationBeforeFix: true,
                maxRiskClass: "medium"
            )
        case .code:
            return XTAgentModeCapabilityContract(
                mode: mode,
                canReadFiles: true,
                canWriteFiles: true,
                canRunShell: true,
                canRunDiagnostics: true,
                canApplyPatch: true,
                canSpawnLanes: false,
                requiresUserConfirmationBeforeFix: false,
                maxRiskClass: "high"
            )
        case .orchestrator:
            return XTAgentModeCapabilityContract(
                mode: mode,
                canReadFiles: true,
                canWriteFiles: false,
                canRunShell: false,
                canRunDiagnostics: true,
                canApplyPatch: false,
                canSpawnLanes: true,
                requiresUserConfirmationBeforeFix: true,
                maxRiskClass: "medium"
            )
        }
    }

    var jsonFields: [String: JSONValue] {
        [
            "agent_mode": .string(mode.rawValue),
            "can_read_files": .bool(canReadFiles),
            "can_write_files": .bool(canWriteFiles),
            "can_run_shell": .bool(canRunShell),
            "can_run_diagnostics": .bool(canRunDiagnostics),
            "can_apply_patch": .bool(canApplyPatch),
            "can_spawn_lanes": .bool(canSpawnLanes),
            "requires_user_confirmation_before_fix": .bool(requiresUserConfirmationBeforeFix),
            "max_risk_class": .string(maxRiskClass),
        ]
    }
}

enum XTAgentModeToolGate {
    static func denyDecisionIfNeeded(call: ToolCall) -> XTToolRuntimePolicyDecision? {
        guard let mode = XTAgentMode.from(call: call) else { return nil }
        let contract = XTAgentModeCapabilityContract.contract(for: mode)

        if isWriteTool(call.tool), !contract.canWriteFiles {
            return deny(call: call, contract: contract, reason: "mode_disallows_write", nextModes: [.code])
        }
        if isPatchTool(call.tool), !contract.canApplyPatch {
            return deny(call: call, contract: contract, reason: "mode_disallows_patch", nextModes: [.code])
        }
        if call.tool == .run_command, !contract.canRunShell {
            return deny(call: call, contract: contract, reason: "mode_disallows_shell", nextModes: [.code])
        }
        if isDiagnosticsTool(call.tool), !contract.canRunDiagnostics {
            return deny(call: call, contract: contract, reason: "mode_disallows_diagnostics", nextModes: [.explore, .debug, .code])
        }
        if isReadTool(call.tool), !contract.canReadFiles {
            return deny(call: call, contract: contract, reason: "mode_disallows_read", nextModes: [.explore, .debug, .code])
        }

        return nil
    }

    private static func deny(
        call: ToolCall,
        contract: XTAgentModeCapabilityContract,
        reason: String,
        nextModes: [XTAgentMode]
    ) -> XTToolRuntimePolicyDecision {
        let next = nextModes.map(\.rawValue).joined(separator: ",")
        return .deny(
            code: "agent_mode_contract_denied",
            detail: "agent_mode=\(contract.mode.rawValue) blocks \(call.tool.rawValue); reason=\(reason); next_allowed_modes=\(next)",
            policySource: "agent_mode_contract",
            policyReason: reason
        )
    }

    private static func isReadTool(_ tool: ToolName) -> Bool {
        switch tool {
        case .read_file, .list_dir, .search, .git_status, .git_diff, .ci_read,
             .session_list, .session_resume, .session_compact, .agentImportRecord,
             .memory_snapshot, .project_snapshot, .bridge_status, .skills_search,
             .summarize, .web_fetch, .web_search, .browser_read:
            return true
        default:
            return false
        }
    }

    private static func isWriteTool(_ tool: ToolName) -> Bool {
        switch tool {
        case .write_file, .delete_path, .move_path, .git_commit, .git_push,
             .pr_create, .ci_trigger, .process_start, .process_stop,
             .deviceUIAct, .deviceUIStep, .deviceClipboardWrite,
             .deviceBrowserControl, .deviceAppleScript:
            return true
        default:
            return false
        }
    }

    private static func isPatchTool(_ tool: ToolName) -> Bool {
        switch tool {
        case .git_apply:
            return true
        default:
            return false
        }
    }

    private static func isDiagnosticsTool(_ tool: ToolName) -> Bool {
        switch tool {
        case .projectDiagnostics, .lspDiagnostics, .checkRun, .buildRun, .testRun, .git_apply_check:
            return true
        default:
            return false
        }
    }
}
