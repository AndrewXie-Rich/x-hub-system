import Foundation

extension ChatSessionModel {
    func assistantToolOutcomeLines(toolResults: [ToolResult]) -> [String] {
        var seen: Set<String> = []
        var lines: [String] = []

        for result in toolResults {
            let summary: String
            if shouldIncludeToolFailureInAssistant(result) {
                summary = assistantToolFailureSummary(for: result)
            } else if shouldIncludeToolSuccessInAssistant(result) {
                summary = assistantToolSuccessSummary(for: result)
            } else {
                continue
            }
            let trimmedSummary = summary
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSummary.isEmpty else { continue }
            if seen.insert(trimmedSummary).inserted {
                lines.append(trimmedSummary)
            }
        }

        return lines
    }

    func shouldIncludeToolFailureInAssistant(_ result: ToolResult) -> Bool {
        guard !result.ok else { return false }
        if result.id.hasPrefix("bootstrap_") || result.id.hasPrefix("auto_diff_after_") {
            return false
        }
        switch assistantToolFailureImpact(for: result) {
        case .blocking:
            return true
        case .diagnostic:
            return false
        }
    }

    enum AssistantToolFailureImpact {
        case blocking
        case diagnostic
    }

    func shouldIncludeToolSuccessInAssistant(_ result: ToolResult) -> Bool {
        guard result.ok else { return false }
        if result.id.hasPrefix("bootstrap_") || result.id.hasPrefix("auto_diff_after_") {
            return false
        }
        return !assistantToolSuccessSummary(for: result).isEmpty
    }

    func assistantToolFailureImpact(for result: ToolResult) -> AssistantToolFailureImpact {
        switch result.tool {
        case .git_status,
             .git_diff,
             .ci_read,
             .process_status,
             .process_logs,
             .session_list,
             .session_resume,
             .session_compact,
             .agentImportRecord,
             .memory_snapshot,
             .project_snapshot,
             .bridge_status,
             .projectDiagnostics,
             .lspDiagnostics,
             .checkRun,
             .buildRun,
             .testRun:
            return .diagnostic
        case .read_file,
             .write_file,
             .delete_path,
             .move_path,
             .list_dir,
             .search,
             .skills_search,
             .skills_pin,
             .skillsExecuteRunner,
             .summarize,
             .run_command,
             .process_start,
             .process_stop,
             .git_commit,
             .git_push,
             .git_apply,
             .git_apply_check,
             .pr_create,
             .ci_trigger,
             .need_network,
             .web_fetch,
             .web_search,
             .browser_read,
             .deviceUIObserve,
             .deviceUIAct,
             .deviceUIStep,
             .deviceClipboardRead,
             .deviceClipboardWrite,
             .deviceScreenCapture,
             .deviceBrowserControl,
             .deviceAppleScript,
             .supervisorVoicePlayback,
             .run_local_task:
            return .blocking
        }
    }

    func assistantToolFailureSummary(for result: ToolResult) -> String {
        let detail = normalizedAssistantToolDiagnostic(result.output)
        let lower = detail.lowercased()

        switch result.tool {
        case .git_status:
            if lower.contains("not a git repository") {
                return "当前目录不是 Git 仓库，无法执行 git status。"
            }
            return detail.isEmpty ? "git status 执行失败。" : "git status 执行失败：\(detail)"
        case .git_diff:
            if lower.contains("not a git repository") {
                return "当前目录不是 Git 仓库，无法生成 git diff。"
            }
            return detail.isEmpty ? "git diff 执行失败。" : "git diff 执行失败：\(detail)"
        case .run_command:
            return detail.isEmpty ? "命令执行失败。" : "命令执行失败：\(detail)"
        case .read_file:
            if lower.contains("governed readable roots")
                || lower.contains("path_outside_governed_read_roots")
                || lower.contains("project root") {
                return "目标文件超出当前项目允许范围，无法读取。"
            }
            if lower.contains("no such file") {
                return "目标文件不存在，读取失败。"
            }
            return detail.isEmpty ? "文件读取失败。" : "文件读取失败：\(detail)"
        case .list_dir:
            if lower.contains("governed readable roots")
                || lower.contains("path_outside_governed_read_roots")
                || lower.contains("project root") {
                return "目标目录超出当前项目允许范围，无法读取。"
            }
            if lower.contains("permission denied") {
                return "目录读取被拒绝，当前路径不可读。"
            }
            return detail.isEmpty ? "目录读取失败。" : "目录读取失败：\(detail)"
        case .write_file:
            if lower.contains("permission denied") {
                return "文件写入被拒绝，当前路径不可写。"
            }
            return detail.isEmpty ? "文件写入失败。" : "文件写入失败：\(detail)"
        case .delete_path:
            if lower.contains("permission denied") {
                return "路径删除被拒绝，当前目标不可写。"
            }
            return detail.isEmpty ? "路径删除失败。" : "路径删除失败：\(detail)"
        case .move_path:
            if lower.contains("permission denied") {
                return "路径移动被拒绝，当前目标不可写。"
            }
            return detail.isEmpty ? "路径移动失败。" : "路径移动失败：\(detail)"
        case .process_start:
            return detail.isEmpty ? "托管进程启动失败。" : "托管进程启动失败：\(detail)"
        case .process_status:
            return detail.isEmpty ? "托管进程状态读取失败。" : "托管进程状态读取失败：\(detail)"
        case .process_logs:
            return detail.isEmpty ? "托管进程日志读取失败。" : "托管进程日志读取失败：\(detail)"
        case .process_stop:
            return detail.isEmpty ? "托管进程停止失败。" : "托管进程停止失败：\(detail)"
        case .git_apply, .git_apply_check:
            if lower.contains("permission denied") {
                return "补丁应用被拒绝，当前路径不可写。"
            }
            return detail.isEmpty ? "补丁应用失败。" : "补丁应用失败：\(detail)"
        case .need_network, .web_fetch, .web_search, .browser_read, .bridge_status:
            if lower.contains("grant") || lower.contains("denied") || lower.contains("blocked") {
                return "联网操作被当前策略或授权门控拦住了。"
            }
            return detail.isEmpty ? "联网操作失败。" : "联网操作失败：\(detail)"
        case .supervisorVoicePlayback:
            return detail.isEmpty ? "Supervisor 语音播放失败。" : "Supervisor 语音播放失败：\(detail)"
        case .run_local_task:
            return detail.isEmpty ? "本地模型任务执行失败。" : "本地模型任务执行失败：\(detail)"
        default:
            return detail.isEmpty ? "\(result.tool.rawValue) 执行失败。" : "\(result.tool.rawValue) 执行失败：\(detail)"
        }
    }

    func assistantToolSuccessSummary(for result: ToolResult) -> String {
        guard result.tool == .deviceBrowserControl else { return "" }
        let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
        guard case .object(let summary)? = parsed.summary else { return "" }
        let driverState = jsonStringValue(summary["browser_runtime_driver_state"]) ?? ""
        guard driverState == "secret_vault_applescript_fill" else { return "" }
        if let selector = jsonStringValue(summary["selector"]), !selector.isEmpty {
            return "已通过 Hub Secret Vault 将凭据填入当前浏览器字段（\(selector)）。"
        }
        return "已通过 Hub Secret Vault 将凭据填入当前浏览器字段。"
    }

    func normalizedAssistantToolDiagnostic(_ raw: String) -> String {
        let parsed = ToolExecutor.parseStructuredToolOutput(raw)
        let body = parsed.summary == nil ? raw : parsed.body
        return normalizedAssistantToolDiagnosticText(
            summary: parsed.summary,
            body: body
        )
    }

    func normalizedAssistantToolDiagnosticText(
        summary: JSONValue?,
        body: String
    ) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            let normalized = normalizedAssistantToolDiagnosticLine(trimmedBody)
            if !normalized.isEmpty {
                return normalized
            }
        }

        guard case .object(let object)? = summary else { return "" }
        let candidates = [
            jsonStringValue(object["detail"]),
            jsonStringValue(object["message"]),
            jsonStringValue(object["error"]),
            jsonStringValue(object["reason"]),
            jsonStringValue(object["policy_reason"]),
            jsonStringValue(object["deny_code"]),
            jsonStringValue(object["target_path"]).map { "path=\($0)" }
        ]
        for candidate in candidates {
            let normalized = normalizedAssistantToolDiagnosticLine(candidate ?? "")
            if !normalized.isEmpty {
                return normalized
            }
        }
        return ""
    }

    func normalizedAssistantToolDiagnosticLine(_ raw: String) -> String {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let preferredLine = lines.first(where: { line in
            let lower = line.lowercased()
            if line == "{" || line == "[" || line == "}" || line == "]" {
                return false
            }
            if lower.hasPrefix("sandbox:") || lower.hasPrefix("exit: ") {
                return false
            }
            return true
        }) ?? lines.first

        guard let firstLine = preferredLine else { return "" }

        var cleaned = firstLine
        if cleaned.lowercased().hasPrefix("fatal:") {
            cleaned = String(cleaned.dropFirst("fatal:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleaned.lowercased().hasPrefix("error:") {
            cleaned = String(cleaned.dropFirst("error:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let collapsed = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.count <= 140 {
            return collapsed
        }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 140)
        return String(collapsed[..<end]) + "..."
    }

    func touchProjectActivity(ctx: AXProjectContext, eventAt: Double? = nil) {
        let update = AXProjectRegistryStore.touchActivity(forRoot: ctx.root, eventAt: eventAt, minIntervalSec: 2.0)
        guard update.changed, let entry = update.entry else { return }
        HubIPCClient.syncProject(entry)
    }

    func shortProviderTag(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.localizedCaseInsensitiveContains("hub") { return "Hub" }
        if t.localizedCaseInsensitiveContains("anthropic") || t.localizedCaseInsensitiveContains("claude") { return "Claude" }
        if t.localizedCaseInsensitiveContains("gemini") { return "Gemini" }
        if t.localizedCaseInsensitiveContains("openai") { return "OpenAI" }
        if t.localizedCaseInsensitiveContains("compatible") { return "API" }
        return t.isEmpty ? "" : t
    }

    func isDirectNetworkRequest(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return false }
        if t == "need network" || t == "联网" { return true }
        if t.hasPrefix("need network") { return true }
        if t.hasPrefix("需要联网") || t.hasPrefix("请求联网") || t.hasPrefix("打开网络") || t.hasPrefix("开启网络") { return true }
        return false
    }

    func extractNetworkSeconds(_ text: String) -> Int? {
        let t = text.lowercased()
        let patterns: [(String, Int)] = [
            ("(\\d+)\\s*(分钟|min|m)", 60),
            ("(\\d+)\\s*(小时|hr|h)", 3600),
        ]
        for (pat, mul) in patterns {
            if let r = try? NSRegularExpression(pattern: pat, options: []) {
                let range = NSRange(t.startIndex..<t.endIndex, in: t)
                if let m = r.firstMatch(in: t, options: [], range: range),
                   m.numberOfRanges > 1,
                   let r1 = Range(m.range(at: 1), in: t) {
                    if let v = Int(t[r1]) {
                        return max(60, v * mul)
                    }
                }
            }
        }
        return nil
    }

    func extractGrantTokenFromOutput(_ output: String?) -> String? {
        let text = (output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #"grant=([A-Za-z0-9_\-]+)"#) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2 else {
            return nil
        }
        let r = match.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        let token = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
