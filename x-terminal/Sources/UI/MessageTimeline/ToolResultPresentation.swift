import Foundation

enum ToolResultPresentation {
    static func shouldSurfaceSuccessfulTimelineCard(call: ToolCall, result: ToolResult) -> Bool {
        guard result.ok else { return false }
        guard call.tool == .deviceBrowserControl else { return false }
        return isBrowserSecretFillSuccess(result)
    }

    static func shouldShowTimelineCard(for result: ToolResult) -> Bool {
        if !result.ok {
            return true
        }
        return isBrowserSecretFillSuccess(result)
    }

    static func title(for result: ToolResult) -> String {
        if result.ok, isBrowserSecretFillSuccess(result) {
            return "Credential filled from Secret Vault"
        }
        return "\(toolDisplayName(result.tool)) needs attention"
    }

    static func body(for result: ToolResult) -> String {
        if result.ok, isBrowserSecretFillSuccess(result) {
            return browserSecretFillSuccessBody(for: result)
        }
        return failureBody(for: result)
    }

    static func iconName(for result: ToolResult) -> String {
        if result.ok, isBrowserSecretFillSuccess(result) {
            return "checkmark.shield.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    static func structuredSummary(for result: ToolResult) -> [String: JSONValue]? {
        let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
        guard case .object(let summary)? = parsed.summary else { return nil }
        return summary
    }

    private static func isBrowserSecretFillSuccess(_ result: ToolResult) -> Bool {
        guard result.tool == .deviceBrowserControl,
              result.ok,
              let summary = structuredSummary(for: result) else {
            return false
        }
        return string(summary["browser_runtime_driver_state"]) == "secret_vault_applescript_fill"
    }

    private static func browserSecretFillSuccessBody(for result: ToolResult) -> String {
        let summary = structuredSummary(for: result) ?? [:]
        let selector = string(summary["selector"])
        let tagName = string(summary["browser_fill_tag_name"])
        let target = selector ?? (tagName.map { "<\($0)>" })
        if let target {
            return "The active browser field \(target) was filled using a Secret Vault credential."
        }
        return "The active browser field was filled using a Secret Vault credential."
    }

    private static func failureBody(for result: ToolResult) -> String {
        let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
        let summary = object(parsed.summary)
        let detail = normalizedDiagnostic(parsed.body.isEmpty ? result.output : parsed.body)
        let lower = detail.lowercased()

        switch result.tool {
        case .deviceBrowserControl:
            return browserControlFailureBody(summary: summary, detail: detail)
        case .git_status:
            if lower.contains("not a git repository") {
                return "Current folder is not a git repository, so git status cannot run here."
            }
            return detail.isEmpty ? "Git status could not be read." : "Git status could not be read: \(detail)"
        case .git_diff:
            if lower.contains("not a git repository") {
                return "Current folder is not a git repository, so git diff cannot run here."
            }
            return detail.isEmpty ? "Git diff could not be generated." : "Git diff could not be generated: \(detail)"
        case .run_command:
            return detail.isEmpty ? "The command did not finish successfully." : "The command did not finish successfully: \(detail)"
        case .read_file:
            if lower.contains("no such file") {
                return "The target file could not be found."
            }
            return detail.isEmpty ? "The file could not be read." : "The file could not be read: \(detail)"
        case .write_file, .git_apply, .git_apply_check:
            if lower.contains("permission denied") {
                return "The change was blocked because this path is not writable."
            }
            return detail.isEmpty ? "The requested change could not be applied." : "The requested change could not be applied: \(detail)"
        case .need_network, .web_fetch, .web_search, .browser_read, .bridge_status:
            if lower.contains("grant") || lower.contains("denied") || lower.contains("blocked") {
                return "Network access is currently blocked by the active policy or grant gate."
            }
            return detail.isEmpty ? "The network action could not be completed." : "The network action could not be completed: \(detail)"
        default:
            return detail.isEmpty ? "This tool call failed. Open Diagnostics for the raw output." : detail
        }
    }

    private static func browserControlFailureBody(summary: [String: JSONValue]?, detail: String) -> String {
        guard let summary else {
            return detail.isEmpty ? "The browser action could not be completed." : detail
        }

        let denyCode = string(summary["deny_code"]) ?? ""
        let selector = string(summary["selector"])
        let secretReason = string(summary["secret_reason_code"])
        let hasSecretRef = bool(summary["secret_ref_only"]) == true
            || string(summary["secret_item_id"]) != nil
            || string(summary["secret_name"]) != nil

        if hasSecretRef {
            switch denyCode {
            case XTDeviceAutomationRejectCode.browserSecretReferenceInvalid.rawValue:
                return "The browser fill was blocked because the Secret Vault reference is incomplete. Provide `secret_item_id` or `secret_scope + secret_name`."
            case XTDeviceAutomationRejectCode.browserSecretSelectorMissing.rawValue:
                return "The browser fill was blocked because Secret Vault-backed typing requires a DOM selector."
            case XTDeviceAutomationRejectCode.browserSecretBeginUseFailed.rawValue:
                if let reason = secretVaultReasonText(secretReason) {
                    return "Hub did not authorize this credential use. \(reason)"
                }
                return "Hub did not authorize this credential use."
            case XTDeviceAutomationRejectCode.browserSecretRedeemFailed.rawValue:
                if let reason = secretVaultReasonText(secretReason) {
                    return "XT could not redeem the credential lease. \(reason)"
                }
                return "XT could not redeem the credential lease."
            case XTDeviceAutomationRejectCode.browserSecretFillUnavailable.rawValue:
                return "The credential was resolved, but XT could not control the current browser window."
            case XTDeviceAutomationRejectCode.browserSecretFillFailed.rawValue:
                if secretReason == "selector_not_found", let selector {
                    return "The credential was resolved, but the page does not contain the target field \(selector)."
                }
                if let reason = secretVaultReasonText(secretReason) {
                    return "The credential was resolved, but XT could not fill the browser field. \(reason)"
                }
                return "The credential was resolved, but XT could not fill the browser field."
            case XTDeviceAutomationRejectCode.browserSecretPlaintextForbidden.rawValue:
                return "Sensitive browser fields must use a Secret Vault reference instead of plaintext input."
            default:
                break
            }
        }

        if denyCode == XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue {
            return "XT can open the page, but managed browser click/type automation is not available for this path yet."
        }
        if denyCode == XTDeviceAutomationRejectCode.browserSessionNoActiveURL.rawValue {
            return "XT has no active browser URL for this session, so the browser action was blocked."
        }
        if denyCode == XTDeviceAutomationRejectCode.browserSessionMissing.rawValue {
            return "The browser session is missing, so XT could not continue the browser action."
        }
        return detail.isEmpty ? "The browser action could not be completed." : detail
    }

    private static func secretVaultReasonText(_ raw: String?) -> String? {
        guard let token = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }

        switch token {
        case "secret_vault_item_not_found":
            return "The referenced credential is no longer available in Hub."
        case "secret_vault_use_token_not_found":
            return "The one-time credential lease expired or was already consumed."
        case "secret_vault_decrypt_failed":
            return "Hub could not decrypt the stored credential."
        case "selector_not_found":
            return "The target field could not be found in the current page."
        default:
            return "Reason: \(token)."
        }
    }

    private static func normalizedDiagnostic(_ raw: String) -> String {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let firstLine = lines.first else { return "" }

        var cleaned = firstLine
        if cleaned.lowercased().hasPrefix("fatal:") {
            cleaned = String(cleaned.dropFirst("fatal:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleaned.lowercased().hasPrefix("error:") {
            cleaned = String(cleaned.dropFirst("error:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let collapsed = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.count <= 180 {
            return collapsed
        }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 180)
        return String(collapsed[..<end]) + "..."
    }

    private static func toolDisplayName(_ tool: ToolName) -> String {
        switch tool {
        case .read_file:
            return "Read file"
        case .write_file:
            return "Write file"
        case .list_dir:
            return "List files"
        case .search:
            return "Search"
        case .run_command:
            return "Run command"
        case .git_status:
            return "Git status"
        case .git_diff:
            return "Git diff"
        case .git_apply_check:
            return "Patch check"
        case .git_apply:
            return "Apply patch"
        case .session_list:
            return "Session list"
        case .session_resume:
            return "Resume session"
        case .session_compact:
            return "Compact session"
        case .memory_snapshot:
            return "Memory snapshot"
        case .project_snapshot:
            return "Project snapshot"
        case .deviceUIObserve:
            return "Observe UI"
        case .deviceUIAct:
            return "Act on UI"
        case .deviceUIStep:
            return "Step UI"
        case .deviceClipboardRead:
            return "Read clipboard"
        case .deviceClipboardWrite:
            return "Write clipboard"
        case .deviceScreenCapture:
            return "Capture screen"
        case .deviceBrowserControl:
            return "Control browser"
        case .deviceAppleScript:
            return "Run AppleScript"
        case .need_network:
            return "Request network"
        case .bridge_status:
            return "Check bridge"
        case .skills_search:
            return "Search skills"
        case .summarize:
            return "Summarize content"
        case .web_fetch:
            return "Fetch web content"
        case .web_search:
            return "Search the web"
        case .browser_read:
            return "Read browser page"
        }
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bool(_ value: JSONValue?) -> Bool? {
        guard case .bool(let flag)? = value else { return nil }
        return flag
    }

    private static func object(_ value: JSONValue?) -> [String: JSONValue]? {
        guard case .object(let object)? = value else { return nil }
        return object
    }
}
