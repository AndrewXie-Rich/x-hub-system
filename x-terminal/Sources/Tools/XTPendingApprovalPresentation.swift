import Foundation

enum XTPendingApprovalPresentation {
    static func iconName(for tool: ToolName) -> String {
        switch tool {
        case .read_file:
            return "doc.text"
        case .write_file:
            return "pencil"
        case .delete_path:
            return "trash"
        case .move_path:
            return "arrow.right.doc.on.clipboard"
        case .list_dir:
            return "folder"
        case .search, .skills_search:
            return "magnifyingglass"
        case .summarize:
            return "text.alignleft"
        case .run_command:
            return "terminal"
        case .process_start:
            return "play.rectangle"
        case .process_status:
            return "waveform.path.ecg.rectangle"
        case .process_logs:
            return "text.justify.left"
        case .process_stop:
            return "stop.circle"
        case .git_status, .git_diff, .git_apply_check, .git_apply:
            return "arrow.triangle.branch"
        case .git_commit:
            return "checkmark.circle"
        case .git_push:
            return "arrow.up.circle"
        case .pr_create:
            return "arrowshape.turn.up.right.circle"
        case .ci_read:
            return "list.bullet.clipboard"
        case .ci_trigger:
            return "bolt.badge.clock"
        case .session_list:
            return "list.bullet.rectangle"
        case .session_resume:
            return "play.circle"
        case .session_compact:
            return "archivebox"
        case .agentImportRecord:
            return "checklist"
        case .memory_snapshot:
            return "memorychip"
        case .project_snapshot:
            return "folder.badge.gearshape"
        case .deviceUIObserve:
            return "eye"
        case .deviceUIAct:
            return "hand.tap"
        case .deviceUIStep:
            return "point.3.connected.trianglepath.dotted"
        case .deviceClipboardRead, .deviceClipboardWrite:
            return "list.clipboard"
        case .deviceScreenCapture:
            return "camera.viewfinder"
        case .deviceBrowserControl:
            return "safari"
        case .deviceAppleScript:
            return "apple.logo"
        case .need_network, .bridge_status, .web_fetch, .web_search, .browser_read:
            return "network"
        }
    }

    static func displayToolName(for tool: ToolName) -> String {
        switch tool {
        case .read_file:
            return "read file"
        case .write_file:
            return "write file"
        case .delete_path:
            return "delete path"
        case .move_path:
            return "move path"
        case .list_dir:
            return "list directory"
        case .search:
            return "search"
        case .run_command:
            return "run command"
        case .process_start:
            return "start process"
        case .process_status:
            return "process status"
        case .process_logs:
            return "process logs"
        case .process_stop:
            return "stop process"
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
            return "apply patch"
        case .pr_create:
            return "create pull request"
        case .ci_read:
            return "read CI"
        case .ci_trigger:
            return "trigger CI"
        case .session_list:
            return "session list"
        case .session_resume:
            return "resume session"
        case .session_compact:
            return "compact session"
        case .agentImportRecord:
            return "agent import record"
        case .memory_snapshot:
            return "memory snapshot"
        case .project_snapshot:
            return "project snapshot"
        case .deviceUIObserve:
            return "UI observe"
        case .deviceUIAct:
            return "UI action"
        case .deviceUIStep:
            return "UI step"
        case .deviceClipboardRead:
            return "clipboard read"
        case .deviceClipboardWrite:
            return "clipboard write"
        case .deviceScreenCapture:
            return "screen capture"
        case .deviceBrowserControl:
            return "browser control"
        case .deviceAppleScript:
            return "AppleScript"
        case .need_network:
            return "network access"
        case .bridge_status:
            return "bridge status"
        case .skills_search:
            return "skills search"
        case .summarize:
            return "summarize"
        case .web_fetch:
            return "web fetch"
        case .web_search:
            return "web search"
        case .browser_read:
            return "browser read"
        }
    }

    static func displayToolName(raw: String, tool: ToolName?) -> String {
        if let tool {
            return displayToolName(for: tool)
        }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "tool runtime" : cleaned
    }

    static func approvalMessage(for toolCall: ToolCall) -> XTGuardrailMessage {
        XTGuardrailMessagePresentation.awaitingApprovalMessage(
            toolLabel: displayToolName(for: toolCall.tool),
            target: approvalTarget(for: toolCall)
        )
    }

    static func approvalMessage(
        toolName: String,
        tool: ToolName?,
        toolSummary: String,
        requiredCapability: String = "",
        denyCode: String = ""
    ) -> XTGuardrailMessage {
        XTGuardrailMessagePresentation.awaitingApprovalMessage(
            toolLabel: displayToolName(raw: toolName, tool: tool),
            target: normalizedToolSummary(toolSummary),
            requiredCapability: requiredCapability,
            denyCode: denyCode
        )
    }

    static func actionSummary(for toolCall: ToolCall) -> String {
        switch toolCall.tool {
        case .read_file:
            return sentence("Read", target: previewValue(for: toolCall, keys: ["path"], includeLabel: true), fallback: "Read a file")
        case .write_file:
            return sentence("Write to", target: previewValue(for: toolCall, keys: ["path"], includeLabel: true), fallback: "Write a file")
        case .delete_path:
            return sentence("Delete", target: previewValue(for: toolCall, keys: ["path"], includeLabel: true), fallback: "Delete a path")
        case .move_path:
            return sentence("Move", target: previewValue(for: toolCall, keys: ["from", "to"], includeLabel: true), fallback: "Move a path")
        case .list_dir:
            return sentence("List files in", target: previewValue(for: toolCall, keys: ["path"], includeLabel: true), fallback: "List a directory")
        case .search:
            return sentence("Search for", target: previewValue(for: toolCall, keys: ["pattern", "query"], includeLabel: true), fallback: "Search project files")
        case .skills_search:
            return sentence("Search skills for", target: previewValue(for: toolCall, keys: ["query"], includeLabel: true), fallback: "Search skills")
        case .run_command:
            return sentence("Run", target: previewValue(for: toolCall, keys: ["command"], includeLabel: true), fallback: "Run a command")
        case .process_start:
            return sentence("Start process", target: previewValue(for: toolCall, keys: ["name", "process_id", "command"], includeLabel: true), fallback: "Start a managed process")
        case .process_status:
            return sentence("Inspect process", target: previewValue(for: toolCall, keys: ["process_id"], includeLabel: true), fallback: "Inspect managed process status")
        case .process_logs:
            return sentence("Read process logs for", target: previewValue(for: toolCall, keys: ["process_id"], includeLabel: true), fallback: "Read managed process logs")
        case .process_stop:
            return sentence("Stop process", target: previewValue(for: toolCall, keys: ["process_id"], includeLabel: true), fallback: "Stop a managed process")
        case .git_status:
            return "Check git status"
        case .git_diff:
            return "Inspect git diff"
        case .git_commit:
            return sentence("Create commit", target: previewValue(for: toolCall, keys: ["message"], includeLabel: true), fallback: "Create a git commit")
        case .git_push:
            return sentence("Push git branch", target: previewValue(for: toolCall, keys: ["remote", "branch"], includeLabel: true), fallback: "Push git changes")
        case .git_apply_check:
            return "Validate a patch before apply"
        case .git_apply:
            return "Apply a patch"
        case .pr_create:
            return sentence("Create pull request", target: previewValue(for: toolCall, keys: ["title", "base", "head"], includeLabel: true), fallback: "Create a pull request")
        case .ci_read:
            return sentence("Read CI status", target: previewValue(for: toolCall, keys: ["workflow", "branch"], includeLabel: true), fallback: "Read CI status")
        case .ci_trigger:
            return sentence("Trigger CI workflow", target: previewValue(for: toolCall, keys: ["workflow", "ref"], includeLabel: true), fallback: "Trigger a CI workflow")
        case .session_list:
            return "List sessions"
        case .session_resume:
            return sentence("Resume", target: previewValue(for: toolCall, keys: ["session_id"], includeLabel: true), fallback: "Resume a session")
        case .session_compact:
            return sentence("Compact", target: previewValue(for: toolCall, keys: ["session_id"], includeLabel: true), fallback: "Compact a session")
        case .agentImportRecord:
            return sentence("Import staged agent record", target: previewValue(for: toolCall, keys: ["staging_id"], includeLabel: true), fallback: "Import a staged agent record")
        case .memory_snapshot:
            return sentence("Capture memory snapshot", target: previewValue(for: toolCall, keys: ["mode"], includeLabel: true), fallback: "Capture a memory snapshot")
        case .project_snapshot:
            return "Capture a project snapshot"
        case .deviceUIObserve:
            return sentence("Capture UI observation", target: previewValue(for: toolCall, keys: ["selector", "path"], includeLabel: true), fallback: "Capture a UI observation")
        case .deviceUIAct:
            if let action = stringValue(toolCall.args["action"]) {
                return sentence("Run UI action \(action)", target: previewValue(for: toolCall, keys: ["selector", "target", "path", "text"], includeLabel: true), fallback: "Run a UI action")
            }
            return sentence("Run a UI action", target: previewValue(for: toolCall, keys: ["selector", "target", "path", "text"], includeLabel: true), fallback: "Run a UI action")
        case .deviceUIStep:
            return sentence("Advance UI automation", target: previewValue(for: toolCall, keys: ["step", "selector", "target"], includeLabel: true), fallback: "Advance UI automation")
        case .deviceClipboardRead:
            return "Read the clipboard"
        case .deviceClipboardWrite:
            return sentence("Write clipboard", target: previewValue(for: toolCall, keys: ["text"], includeLabel: true), fallback: "Write the clipboard")
        case .deviceScreenCapture:
            return "Capture the screen"
        case .deviceBrowserControl:
            return browserActionSummary(for: toolCall)
        case .deviceAppleScript:
            return sentence("Run AppleScript", target: previewValue(for: toolCall, keys: ["script", "path"], includeLabel: true), fallback: "Run AppleScript")
        case .need_network:
            return "Request network access"
        case .bridge_status:
            return "Check bridge status"
        case .summarize:
            return sentence("Summarize", target: previewValue(for: toolCall, keys: ["url", "path", "text"], includeLabel: true), fallback: "Summarize content")
        case .web_fetch:
            return sentence("Fetch", target: previewValue(for: toolCall, keys: ["url"], includeLabel: false), fallback: "Fetch a web page")
        case .web_search:
            return sentence("Search the web for", target: previewValue(for: toolCall, keys: ["query"], includeLabel: true), fallback: "Search the web")
        case .browser_read:
            return sentence("Read browser page", target: previewValue(for: toolCall, keys: ["url"], includeLabel: false), fallback: "Read the browser page")
        }
    }

    static func supplementaryReason(
        _ rawReason: String,
        primaryMessage: XTGuardrailMessage
    ) -> String? {
        let cleaned = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let normalized = cleaned.lowercased()
        if normalized == "waiting for local governed approval"
            || normalized == "waiting for local approval" {
            return nil
        }

        let primarySummary = primaryMessage.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryText = primaryMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primarySummary.isEmpty,
           cleaned.localizedCaseInsensitiveContains(primarySummary) {
            return nil
        }
        if !primaryText.isEmpty,
           primaryText.localizedCaseInsensitiveContains(cleaned) {
            return nil
        }

        return cleaned
    }

    static func approvalFooterNote(callCount: Int) -> String {
        let normalizedCount = max(1, callCount)
        if normalizedCount == 1 {
            return "Approve runs the queued guarded action now. Reject keeps the rest of the conversation intact."
        }
        return "Approve runs all queued guarded actions now. Reject keeps the rest of the conversation intact."
    }

    private static func browserActionSummary(for toolCall: ToolCall) -> String {
        let action = stringValue(toolCall.args["action"]) ?? ""
        let target = previewValue(
            for: toolCall,
            keys: ["url", "selector", "target", "text", "path"],
            includeLabel: true
        )

        if action == "open_url",
           let url = stringValue(toolCall.args["url"]) {
            return "Open \(url) in the browser"
        }
        if !action.isEmpty {
            return sentence("Run browser action \(action)", target: target, fallback: "Run browser control")
        }
        return sentence("Run browser control", target: target, fallback: "Run browser control")
    }

    private static func approvalTarget(for toolCall: ToolCall) -> String? {
        switch toolCall.tool {
        case .deviceBrowserControl:
            return previewValue(for: toolCall, keys: ["url", "selector", "target", "action"], includeLabel: true)
        case .process_start, .process_status, .process_logs, .process_stop:
            return previewValue(for: toolCall, keys: ["process_id", "name", "command"], includeLabel: true)
        case .git_commit:
            return previewValue(for: toolCall, keys: ["message"], includeLabel: true)
        case .git_push:
            return previewValue(for: toolCall, keys: ["remote", "branch"], includeLabel: true)
        case .pr_create:
            return previewValue(for: toolCall, keys: ["title", "base", "head"], includeLabel: true)
        case .ci_read, .ci_trigger:
            return previewValue(for: toolCall, keys: ["workflow", "branch", "ref"], includeLabel: true)
        case .deviceUIAct, .deviceUIStep, .deviceUIObserve:
            return previewValue(for: toolCall, keys: ["selector", "target", "path", "action"], includeLabel: true)
        case .deviceClipboardWrite:
            return previewValue(for: toolCall, keys: ["text"], includeLabel: true)
        case .deviceAppleScript:
            return previewValue(for: toolCall, keys: ["path", "script"], includeLabel: true)
        case .summarize:
            return previewValue(for: toolCall, keys: ["url", "path", "text"], includeLabel: true)
        case .search:
            return previewValue(for: toolCall, keys: ["pattern", "query"], includeLabel: true)
        default:
            return previewValue(
                for: toolCall,
                keys: ["url", "query", "pattern", "path", "selector", "command", "session_id", "staging_id", "mode", "action", "text"],
                includeLabel: true
            )
        }
    }

    private static func normalizedToolSummary(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return cleaned
    }

    private static func sentence(
        _ prefix: String,
        target: String?,
        fallback: String
    ) -> String {
        guard let target = target?.trimmingCharacters(in: .whitespacesAndNewlines),
              !target.isEmpty else {
            return fallback
        }

        let lower = target.lowercased()
        let descriptivePrefixes = [
            "query ",
            "path ",
            "selector ",
            "command ",
            "session ",
            "staging ",
            "mode ",
            "text ",
            "target ",
            "process ",
            "name "
        ]
        if descriptivePrefixes.contains(where: { lower.hasPrefix($0) }) {
            return "\(prefix) \(target)"
        }
        return "\(prefix) \(target)"
    }

    private static func previewValue(
        for toolCall: ToolCall,
        keys: [String],
        includeLabel: Bool
    ) -> String? {
        for key in keys {
            let cleaned = normalizedPreviewValue(toolCall.args[key], key: key, includeLabel: includeLabel)
            if let cleaned, !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
    }

    private static func normalizedPreviewValue(
        _ value: JSONValue?,
        key: String,
        includeLabel: Bool
    ) -> String? {
        let raw = stringValue(value) ?? ""
        guard !raw.isEmpty else { return nil }

        switch key {
        case "url":
            return raw
        case "query", "pattern":
            return includeLabel ? "query '\(capped(raw, maxChars: 80))'" : capped(raw, maxChars: 80)
        case "path":
            return includeLabel ? "path \(raw)" : raw
        case "selector":
            return includeLabel ? "selector \(raw)" : raw
        case "target":
            return includeLabel ? "target \(raw)" : raw
        case "command":
            return includeLabel ? "command \(capped(raw, maxChars: 96))" : capped(raw, maxChars: 96)
        case "process_id":
            return includeLabel ? "process \(raw)" : raw
        case "name":
            return includeLabel ? "name \(capped(raw, maxChars: 72))" : capped(raw, maxChars: 72)
        case "message":
            return includeLabel ? "message '\(capped(raw, maxChars: 72))'" : capped(raw, maxChars: 72)
        case "session_id":
            return includeLabel ? "session \(raw)" : raw
        case "staging_id":
            return includeLabel ? "staging \(raw)" : raw
        case "mode":
            return includeLabel ? "mode \(raw)" : raw
        case "action":
            return includeLabel ? "action \(raw)" : raw
        case "remote":
            return includeLabel ? "remote \(raw)" : raw
        case "branch":
            return includeLabel ? "branch \(raw)" : raw
        case "workflow":
            return includeLabel ? "workflow \(raw)" : raw
        case "ref":
            return includeLabel ? "ref \(raw)" : raw
        case "title":
            return includeLabel ? "title '\(capped(raw, maxChars: 72))'" : capped(raw, maxChars: 72)
        case "base":
            return includeLabel ? "base \(raw)" : raw
        case "head":
            return includeLabel ? "head \(raw)" : raw
        case "step":
            return includeLabel ? "step \(raw)" : raw
        case "script":
            return includeLabel ? "script \(capped(raw, maxChars: 64))" : capped(raw, maxChars: 64)
        case "text":
            return includeLabel ? "text '\(capped(raw, maxChars: 72))'" : capped(raw, maxChars: 72)
        default:
            return capped(raw, maxChars: 72)
        }
    }

    private static func stringValue(_ value: JSONValue?) -> String? {
        value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capped(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let end = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<end]) + "..."
    }
}
