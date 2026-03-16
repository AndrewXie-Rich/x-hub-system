import Foundation

struct XTGuardrailMessage: Equatable, Sendable {
    var summary: String
    var nextStep: String?

    var text: String {
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNextStep = nextStep?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanNextStep.isEmpty else { return cleanSummary }
        guard !cleanSummary.isEmpty else { return cleanNextStep }
        return cleanSummary + " " + cleanNextStep
    }
}

enum XTGuardrailMessagePresentation {
    static func awaitingApprovalMessage(
        toolLabel: String,
        target: String?,
        requiredCapability: String = "",
        denyCode: String = ""
    ) -> XTGuardrailMessage {
        let cleanedToolLabel = normalizedToolLabel(toolLabel)
        let cleanedCapability = normalized(requiredCapability)
        let cleanedDenyCode = normalized(denyCode)
        let targetSuffix = targetClause(target)
        let humanCapability = XTHubGrantPresentation.capabilityLabel(
            capability: cleanedCapability,
            modelId: ""
        )

        if !cleanedCapability.isEmpty || cleanedDenyCode == "grant_required" {
            if cleanedCapability.isEmpty {
                return XTGuardrailMessage(
                    summary: "Waiting for Hub grant approval before running \(cleanedToolLabel)\(targetSuffix).",
                    nextStep: "Approve the grant in Hub or Supervisor before retrying."
                )
            }
            return XTGuardrailMessage(
                summary: "Waiting for Hub grant approval for \(humanCapability) before running \(cleanedToolLabel)\(targetSuffix).",
                nextStep: "Approve the grant in Hub or Supervisor before retrying."
            )
        }

        return XTGuardrailMessage(
            summary: "Waiting for local approval before running \(cleanedToolLabel)\(targetSuffix).",
            nextStep: "Approve it in X-Terminal to let the guarded tool run."
        )
    }

    static func awaitingApprovalBody(
        toolLabel: String,
        target: String?,
        requiredCapability: String = "",
        denyCode: String = ""
    ) -> String {
        awaitingApprovalMessage(
            toolLabel: toolLabel,
            target: target,
            requiredCapability: requiredCapability,
            denyCode: denyCode
        ).text
    }

    static func blockedBody(
        tool: ToolName? = nil,
        toolLabel: String,
        denyCode: String,
        policySource: String = "",
        policyReason: String = "",
        requiredCapability: String = "",
        fallbackSummary: String = "",
        fallbackDetail: String = ""
    ) -> String {
        if let explanation = explanation(
            tool: tool,
            toolLabel: toolLabel,
            denyCode: denyCode,
            policySource: policySource,
            policyReason: policyReason,
            requiredCapability: requiredCapability
        ) {
            return explanation.text
        }

        if let preferred = preferredFallback(
            summary: fallbackSummary,
            detail: fallbackDetail,
            denyCode: denyCode
        ) {
            return preferred
        }

        let cleanedToolLabel = normalizedToolLabel(toolLabel)
        if !cleanedToolLabel.isEmpty {
            return "This action was blocked before \(cleanedToolLabel) could continue."
        }
        return "This action was blocked by a guarded policy check."
    }

    static func toolResultBody(
        tool: ToolName,
        summary: [String: JSONValue],
        detail: String
    ) -> String? {
        let denyCode = string(summary["deny_code"]) ?? ""
        let policySource = string(summary["policy_source"]) ?? ""
        let runtimeSurfacePolicyReason = string(summary["runtime_surface_policy_reason"]) ?? ""
        let policyReason: String
        if policySource == "project_autonomy_policy", !runtimeSurfacePolicyReason.isEmpty {
            policyReason = runtimeSurfacePolicyReason
        } else {
            policyReason = string(summary["policy_reason"]) ?? ""
        }
        let requiredCapability = string(summary["required_capability"]) ?? ""

        guard !denyCode.isEmpty || !policySource.isEmpty else { return nil }

        let toolLabel = toolLabel(for: tool)
        return blockedBody(
            tool: tool,
            toolLabel: toolLabel,
            denyCode: denyCode,
            policySource: policySource,
            policyReason: policyReason,
            requiredCapability: requiredCapability,
            fallbackSummary: "",
            fallbackDetail: detail
        )
    }

    private static func explanation(
        tool: ToolName?,
        toolLabel: String,
        denyCode: String,
        policySource: String,
        policyReason: String,
        requiredCapability: String
    ) -> XTGuardrailMessage? {
        let cleanedDenyCode = normalized(denyCode)
        let cleanedPolicySource = normalized(policySource)
        let cleanedPolicyReason = normalized(policyReason)
        let cleanedCapability = normalized(requiredCapability)
        let cleanedToolLabel = normalizedToolLabel(toolLabel)
        let humanCapability = XTHubGrantPresentation.capabilityLabel(
            capability: cleanedCapability,
            modelId: ""
        )

        switch cleanedDenyCode {
        case "grant_required":
            let summary: String
            if cleanedCapability.isEmpty {
                summary = "Hub grant approval is still required before this action can continue."
            } else {
                summary = "Hub grant approval for \(humanCapability) is still required before this action can continue."
            }
            return XTGuardrailMessage(
                summary: summary,
                nextStep: "Approve the grant in Hub or Supervisor before retrying."
            )
        case "grant_denied", "voice_grant_denied":
            let summary: String
            if cleanedCapability.isEmpty {
                summary = "Hub grant approval was denied, so this action did not run."
            } else {
                summary = "Hub grant approval for \(humanCapability) was denied, so this action did not run."
            }
            return XTGuardrailMessage(
                summary: summary,
                nextStep: "Adjust the request scope or approve a new grant before retrying."
            )
        case "local_approval_required":
            return XTGuardrailMessage(
                summary: "Local approval is still required before this action can continue.",
                nextStep: "Approve it in X-Terminal to let the guarded tool run."
            )
        case "local_approval_denied", "user_rejected_pending_tool_approval":
            return XTGuardrailMessage(
                summary: "Local approval was denied, so this action did not run.",
                nextStep: "Review the request and retry only if it is still appropriate."
            )
        case "governance_capability_denied":
            return governanceExplanation(policyReason: cleanedPolicyReason)
        case "autonomy_policy_denied":
            return autonomyExplanation(policyReason: cleanedPolicyReason)
        case "tool_policy_denied":
            return XTGuardrailMessage(
                summary: "Project tool policy blocks \(cleanedToolLabel).",
                nextStep: "Allow this tool in the project tool policy before retrying."
            )
        case XTDeviceAutomationRejectCode.trustedAutomationModeOff.rawValue:
            return XTGuardrailMessage(
                summary: "Trusted device authority is off for this project.",
                nextStep: "Turn on trusted automation and pair the project with a device before retrying."
            )
        case XTDeviceAutomationRejectCode.trustedAutomationProjectNotBound.rawValue:
            return XTGuardrailMessage(
                summary: "This project is not bound to a paired device yet.",
                nextStep: "Bind the project to a paired device before retrying."
            )
        case XTDeviceAutomationRejectCode.trustedAutomationWorkspaceMismatch.rawValue:
            return XTGuardrailMessage(
                summary: "The paired-device binding no longer matches this project folder.",
                nextStep: "Re-bind the project so the workspace hash matches the current root."
            )
        case XTDeviceAutomationRejectCode.trustedAutomationSurfaceNotEnabled.rawValue:
            return XTGuardrailMessage(
                summary: "Device automation surfaces are not enabled for this project.",
                nextStep: "Enable governed device authority before retrying."
            )
        case XTDeviceAutomationRejectCode.deviceAutomationToolNotArmed.rawValue:
            return XTGuardrailMessage(
                summary: "The required device capability is not armed for this project.",
                nextStep: "Arm the missing device tool group in project settings before retrying."
            )
        case XTDeviceAutomationRejectCode.systemPermissionMissing.rawValue:
            return XTGuardrailMessage(
                summary: "macOS permissions required for this device action are missing.",
                nextStep: "Grant the missing system permissions, then retry."
            )
        case XTDeviceAutomationRejectCode.uiObservationRequired.rawValue:
            return XTGuardrailMessage(
                summary: "This UI action needs a fresh UI observation before it can continue.",
                nextStep: "Run an observe step first, then retry the action."
            )
        case XTDeviceAutomationRejectCode.uiObservationExpired.rawValue:
            return XTGuardrailMessage(
                summary: "The last UI observation is stale.",
                nextStep: "Capture a fresh UI observation before retrying."
            )
        case XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue:
            return XTGuardrailMessage(
                summary: "Managed browser click/type automation is not available for this path yet.",
                nextStep: "Use open or read flows for now, or keep the action manual."
            )
        case XTDeviceAutomationRejectCode.browserSessionMissing.rawValue:
            return XTGuardrailMessage(
                summary: "The browser session is missing.",
                nextStep: "Open or re-open the page before retrying."
            )
        case XTDeviceAutomationRejectCode.browserSessionNoActiveURL.rawValue:
            return XTGuardrailMessage(
                summary: "The browser session has no active page.",
                nextStep: "Open a page before retrying."
            )
        case "path_outside_governed_read_roots":
            return XTGuardrailMessage(
                summary: "This read is outside the project and governed readable roots.",
                nextStep: "Add the path to governed readable roots or move the file into scope."
            )
        case "path_write_outside_project_root":
            return XTGuardrailMessage(
                summary: "Writes stay inside the project root even when governed readable roots are enabled.",
                nextStep: "Write inside the project or move the target file into the project root."
            )
        case "payload.command_not_allowed":
            return XTGuardrailMessage(
                summary: "This skill request asked for a command outside the governed allowlist.",
                nextStep: "Use an allowed command or update the skill contract before retrying."
            )
        case "command_outside_governed_repo_allowlist":
            return XTGuardrailMessage(
                summary: "Only governed repo build and test commands can auto-run for this project.",
                nextStep: "Approve this command locally or switch to an allowlisted build/test command."
            )
        case "unsupported_skill_id", "skill_mapping_missing", "skill_not_registered":
            return XTGuardrailMessage(
                summary: "This skill is not connected to a governed runtime yet.",
                nextStep: "Install or register the skill before retrying."
            )
        default:
            break
        }

        if cleanedDenyCode.hasPrefix("payload.") {
            return XTGuardrailMessage(
                summary: "This skill request is missing required or valid payload fields.",
                nextStep: "Review the skill input payload and retry."
            )
        }

        switch cleanedPolicySource {
        case "project_governance":
            return governanceExplanation(policyReason: cleanedPolicyReason)
        case "project_autonomy_policy":
            return autonomyExplanation(policyReason: cleanedPolicyReason)
        case "project_tool_policy":
            return XTGuardrailMessage(
                summary: "Project tool policy blocks \(cleanedToolLabel).",
                nextStep: "Allow this tool in the project tool policy before retrying."
            )
        case "trusted_automation_device_gate":
            return XTGuardrailMessage(
                summary: "Trusted device authority blocked this action.",
                nextStep: "Check project device authority and macOS permissions before retrying."
            )
        case "governed_path_scope":
            return XTGuardrailMessage(
                summary: "This action is outside the governed path scope for the project.",
                nextStep: "Move the target back into scope or update the governed readable roots."
            )
        case "governed_command_guard":
            return XTGuardrailMessage(
                summary: "Only governed repo build and test commands can auto-run for this project.",
                nextStep: "Approve this command locally or switch to an allowlisted build/test command."
            )
        default:
            return nil
        }
    }

    private static func governanceExplanation(
        policyReason: String
    ) -> XTGuardrailMessage {
        switch true {
        case policyReason.contains("repo_write"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow file writes for this project.",
                nextStep: "Raise the execution tier to A2+ or keep the action read-only."
            )
        case policyReason.contains("repo_delete_move"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow delete or move operations for this project.",
                nextStep: "Raise the execution tier to A2+ before deleting, moving, or renaming paths."
            )
        case policyReason.contains("repo_build_test"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow command execution for this project.",
                nextStep: "Raise the execution tier to A2+ before running build or test commands."
            )
        case policyReason.contains("repo_build"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow build commands for this project.",
                nextStep: "Raise the execution tier to A2+ before running governed build commands."
            )
        case policyReason.contains("repo_test"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow test commands for this project.",
                nextStep: "Raise the execution tier to A2+ before running governed test commands."
            )
        case policyReason.contains("git_apply"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow patch application for this project.",
                nextStep: "Raise the execution tier to A2+ before applying patches."
            )
        case policyReason.contains("git_commit"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow git commit for this project.",
                nextStep: "Raise the execution tier to A3+ before creating commits."
            )
        case policyReason.contains("git_push"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow git push for this project.",
                nextStep: "Raise the execution tier to A4 before pushing to remotes."
            )
        case policyReason.contains("pr_create"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow pull request creation for this project.",
                nextStep: "Raise the execution tier to A3+ before creating pull requests."
            )
        case policyReason.contains("ci_read"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow CI status reads for this project.",
                nextStep: "Raise the execution tier to A3+ before reading remote CI state."
            )
        case policyReason.contains("ci_trigger"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow CI trigger actions for this project.",
                nextStep: "Raise the execution tier to A4 before dispatching CI workflows."
            )
        case policyReason.contains("managed_processes"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow managed background processes for this project.",
                nextStep: "Raise the execution tier to A2+ before starting, inspecting, or stopping managed processes."
            )
        case policyReason.contains("process_autorestart"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow process auto-restart for this project.",
                nextStep: "Raise the execution tier to A3+ before enabling restart_on_exit."
            )
        case policyReason.contains("browser_runtime"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow browser automation for this project.",
                nextStep: "Raise the execution tier to A4 or switch to a lower-risk path."
            )
        case policyReason.contains("device_tools"):
            return XTGuardrailMessage(
                summary: "Project governance tier does not allow device-level tools for this project.",
                nextStep: "Raise the execution tier to A4 before using device authority."
            )
        default:
            return XTGuardrailMessage(
                summary: "Project governance blocks this action at the current execution tier.",
                nextStep: "Raise the execution tier or choose a lower-risk path before retrying."
            )
        }
    }

    private static func autonomyExplanation(
        policyReason: String
    ) -> XTGuardrailMessage {
        if let clamp = xtAutonomyClampExplanation(
            policyReason: policyReason,
            style: .guardrailEnglish
        ) {
            return XTGuardrailMessage(
                summary: clamp.summary,
                nextStep: clamp.nextStep
            )
        }

        switch true {
        case policyReason.contains("browser_runtime"):
            return XTGuardrailMessage(
                summary: "The current runtime surface does not allow browser automation.",
                nextStep: "Restore the guided/full runtime surface or wait for the clamp to clear."
            )
        case policyReason.contains("device_tools"),
             policyReason.contains("autonomy_mode=guided"),
             policyReason.contains("runtime_surface_effective=guided"),
             policyReason.contains("runtime_surface=guided"):
            return XTGuardrailMessage(
                summary: "The current runtime surface keeps device-level actions disabled.",
                nextStep: "Restore the full runtime surface or wait for the clamp to clear."
            )
        default:
            return XTGuardrailMessage(
                summary: "The current runtime surface blocks this action.",
                nextStep: "Adjust the runtime surface or wait for the policy clamp to clear."
            )
        }
    }

    private static func preferredFallback(
        summary: String,
        detail: String,
        denyCode: String
    ) -> String? {
        let candidates = [summary, detail]
        for raw in candidates {
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            if !looksLikeTechnicalPolicyText(cleaned, denyCode: denyCode) {
                return cleaned
            }
        }
        return nil
    }

    private static func looksLikeTechnicalPolicyText(
        _ text: String,
        denyCode: String
    ) -> Bool {
        let lower = normalized(text)
        let denyToken = normalized(denyCode)
        if !denyToken.isEmpty && lower == denyToken {
            return true
        }

        let technicalTokens = [
            "project governance blocks",
            "runtime surface policy blocks",
            "autonomy policy blocks",
            "project tool policy blocks",
            "under execution tier",
            "configured=",
            "effective=",
            "payload.",
            "grant_required",
            "tool_not_allowed",
            "required device tool group",
            "group:device_automation",
            "workspace binding hash",
            "macos permissions required",
            "governed allowlist"
        ]
        return technicalTokens.contains(where: { lower.contains($0) })
    }

    private static func normalizedToolLabel(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "this action" : cleaned
    }

    private static func targetClause(_ rawTarget: String?) -> String {
        let cleaned = rawTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleaned.isEmpty else { return "" }

        let lower = cleaned.lowercased()
        let descriptivePrefixes = ["query ", "path ", "selector ", "command ", "action "]
        if descriptivePrefixes.contains(where: { lower.hasPrefix($0) }) {
            return " for \(cleaned)"
        }
        return " on \(cleaned)"
    }

    private static func toolLabel(for tool: ToolName) -> String {
        switch tool {
        case .read_file:
            return "file read"
        case .write_file:
            return "file write"
        case .delete_path:
            return "path deletion"
        case .move_path:
            return "path move"
        case .list_dir:
            return "directory listing"
        case .search:
            return "search"
        case .run_command:
            return "command execution"
        case .process_start:
            return "managed process start"
        case .process_status:
            return "managed process status"
        case .process_logs:
            return "managed process logs"
        case .process_stop:
            return "managed process stop"
        case .git_status:
            return "git status"
        case .git_diff:
            return "git diff"
        case .git_commit:
            return "git commit"
        case .git_push:
            return "git push"
        case .git_apply_check:
            return "patch validation"
        case .git_apply:
            return "patch apply"
        case .pr_create:
            return "pull request creation"
        case .ci_read:
            return "CI status read"
        case .ci_trigger:
            return "CI trigger"
        case .session_list:
            return "session listing"
        case .session_resume:
            return "session resume"
        case .session_compact:
            return "session compaction"
        case .agentImportRecord:
            return "agent import record"
        case .memory_snapshot:
            return "memory snapshot"
        case .project_snapshot:
            return "project snapshot"
        case .deviceUIObserve:
            return "UI observation"
        case .deviceUIAct:
            return "UI action"
        case .deviceUIStep:
            return "guided UI step"
        case .deviceClipboardRead:
            return "clipboard read"
        case .deviceClipboardWrite:
            return "clipboard write"
        case .deviceScreenCapture:
            return "screen capture"
        case .deviceBrowserControl:
            return "browser automation"
        case .deviceAppleScript:
            return "AppleScript execution"
        case .need_network:
            return "network request"
        case .bridge_status:
            return "bridge status check"
        case .skills_search:
            return "skills search"
        case .summarize:
            return "content summary"
        case .web_fetch:
            return "web fetch"
        case .web_search:
            return "web search"
        case .browser_read:
            return "browser read"
        }
    }

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
