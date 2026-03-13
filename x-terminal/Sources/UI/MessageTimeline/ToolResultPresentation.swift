import Foundation

enum ToolResultPresentation {
    static func shouldSurfaceSuccessfulTimelineCard(call: ToolCall, result: ToolResult) -> Bool {
        guard result.ok else { return false }
        guard call.tool == .deviceBrowserControl else { return false }
        return ToolResultHumanSummary.isBrowserSecretFillSuccess(result)
    }

    static func shouldShowTimelineCard(for result: ToolResult) -> Bool {
        if !result.ok {
            return true
        }
        return ToolResultHumanSummary.isBrowserSecretFillSuccess(result)
    }

    static func title(for result: ToolResult) -> String {
        if result.ok, ToolResultHumanSummary.isBrowserSecretFillSuccess(result) {
            return "Credential filled from Secret Vault"
        }
        return "\(toolDisplayName(result.tool)) needs attention"
    }

    static func body(for result: ToolResult) -> String {
        ToolResultHumanSummary.body(for: result)
    }

    static func iconName(for result: ToolResult) -> String {
        if result.ok, ToolResultHumanSummary.isBrowserSecretFillSuccess(result) {
            return "checkmark.shield.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    static func structuredSummary(for result: ToolResult) -> [String: JSONValue]? {
        ToolResultHumanSummary.structuredSummary(for: result)
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
        case .agentImportRecord:
            return "Agent import record"
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

}
