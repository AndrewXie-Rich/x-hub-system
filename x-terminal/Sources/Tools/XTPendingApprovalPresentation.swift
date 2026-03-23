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
        case .supervisorVoicePlayback:
            return "speaker.wave.2.fill"
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
            return "读取文件"
        case .write_file:
            return "写入文件"
        case .delete_path:
            return "删除路径"
        case .move_path:
            return "移动路径"
        case .list_dir:
            return "查看目录"
        case .search:
            return "搜索"
        case .run_command:
            return "运行命令"
        case .process_start:
            return "启动进程"
        case .process_status:
            return "进程状态"
        case .process_logs:
            return "进程日志"
        case .process_stop:
            return "停止进程"
        case .git_status:
            return "查看 Git 状态"
        case .git_diff:
            return "查看 Git diff"
        case .git_commit:
            return "Git 提交"
        case .git_push:
            return "Git 推送"
        case .git_apply_check:
            return "补丁校验"
        case .git_apply:
            return "应用补丁"
        case .pr_create:
            return "创建 Pull Request"
        case .ci_read:
            return "读取 CI"
        case .ci_trigger:
            return "触发 CI"
        case .session_list:
            return "会话列表"
        case .session_resume:
            return "恢复会话"
        case .session_compact:
            return "压缩会话"
        case .agentImportRecord:
            return "导入代理记录"
        case .memory_snapshot:
            return "记忆快照"
        case .project_snapshot:
            return "项目快照"
        case .deviceUIObserve:
            return "UI 观察"
        case .deviceUIAct:
            return "UI 动作"
        case .deviceUIStep:
            return "UI 步进"
        case .deviceClipboardRead:
            return "读取剪贴板"
        case .deviceClipboardWrite:
            return "写入剪贴板"
        case .deviceScreenCapture:
            return "屏幕截图"
        case .deviceBrowserControl:
            return "浏览器控制"
        case .deviceAppleScript:
            return "AppleScript"
        case .need_network:
            return "网络访问"
        case .bridge_status:
            return "桥接状态"
        case .skills_search:
            return "搜索技能"
        case .summarize:
            return "总结内容"
        case .supervisorVoicePlayback:
            return "Supervisor 语音"
        case .web_fetch:
            return "抓取网页"
        case .web_search:
            return "联网搜索"
        case .browser_read:
            return "读取浏览器页面"
        }
    }

    static func displayToolName(raw: String, tool: ToolName?) -> String {
        if let tool {
            return displayToolName(for: tool)
        }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "工具运行时" : cleaned
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
            return sentence("读取", target: previewValue(for: toolCall, keys: ["path"], includeLabel: true), fallback: "读取文件")
        case .write_file:
            return sentence("写入", target: previewValue(for: toolCall, keys: ["path"], includeLabel: true), fallback: "写入文件")
        case .delete_path:
            return sentence("删除", target: previewValue(for: toolCall, keys: ["path"], includeLabel: true), fallback: "删除路径")
        case .move_path:
            return sentence("移动", target: previewValue(for: toolCall, keys: ["from", "to"], includeLabel: true), fallback: "移动路径")
        case .list_dir:
            return sentence("查看目录", target: previewValue(for: toolCall, keys: ["path"], includeLabel: true), fallback: "查看目录")
        case .search:
            return sentence("搜索", target: previewValue(for: toolCall, keys: ["pattern", "query"], includeLabel: true), fallback: "搜索项目文件")
        case .skills_search:
            return sentence("搜索技能", target: previewValue(for: toolCall, keys: ["query"], includeLabel: true), fallback: "搜索技能")
        case .run_command:
            return sentence("运行", target: previewValue(for: toolCall, keys: ["command"], includeLabel: true), fallback: "运行命令")
        case .process_start:
            return sentence("启动进程", target: previewValue(for: toolCall, keys: ["name", "process_id", "command"], includeLabel: true), fallback: "启动受治理进程")
        case .process_status:
            return sentence("查看进程", target: previewValue(for: toolCall, keys: ["process_id"], includeLabel: true), fallback: "查看受治理进程状态")
        case .process_logs:
            return sentence("查看进程日志", target: previewValue(for: toolCall, keys: ["process_id"], includeLabel: true), fallback: "查看受治理进程日志")
        case .process_stop:
            return sentence("停止进程", target: previewValue(for: toolCall, keys: ["process_id"], includeLabel: true), fallback: "停止受治理进程")
        case .git_status:
            return "查看 Git 状态"
        case .git_diff:
            return "查看 Git diff"
        case .git_commit:
            return sentence("创建 Git 提交", target: previewValue(for: toolCall, keys: ["message"], includeLabel: true), fallback: "创建 Git 提交")
        case .git_push:
            return sentence("推送 Git 分支", target: previewValue(for: toolCall, keys: ["remote", "branch"], includeLabel: true), fallback: "推送 Git 变更")
        case .git_apply_check:
            return "应用前校验补丁"
        case .git_apply:
            return "应用补丁"
        case .pr_create:
            return sentence("创建 Pull Request", target: previewValue(for: toolCall, keys: ["title", "base", "head"], includeLabel: true), fallback: "创建 Pull Request")
        case .ci_read:
            return sentence("查看 CI 状态", target: previewValue(for: toolCall, keys: ["workflow", "branch"], includeLabel: true), fallback: "查看 CI 状态")
        case .ci_trigger:
            return sentence("触发 CI 流程", target: previewValue(for: toolCall, keys: ["workflow", "ref"], includeLabel: true), fallback: "触发 CI 流程")
        case .session_list:
            return "查看会话列表"
        case .session_resume:
            return sentence("恢复", target: previewValue(for: toolCall, keys: ["session_id"], includeLabel: true), fallback: "恢复会话")
        case .session_compact:
            return sentence("压缩", target: previewValue(for: toolCall, keys: ["session_id"], includeLabel: true), fallback: "压缩会话")
        case .agentImportRecord:
            return sentence("导入暂存代理记录", target: previewValue(for: toolCall, keys: ["staging_id"], includeLabel: true), fallback: "导入暂存代理记录")
        case .memory_snapshot:
            return sentence("生成记忆快照", target: previewValue(for: toolCall, keys: ["mode"], includeLabel: true), fallback: "生成记忆快照")
        case .project_snapshot:
            return "生成项目快照"
        case .deviceUIObserve:
            return sentence("采集 UI 观察", target: previewValue(for: toolCall, keys: ["selector", "path"], includeLabel: true), fallback: "采集 UI 观察")
        case .deviceUIAct:
            if let action = stringValue(toolCall.args["action"]) {
                return sentence("执行 UI 动作 \(action)", target: previewValue(for: toolCall, keys: ["selector", "target", "path", "text"], includeLabel: true), fallback: "执行 UI 动作")
            }
            return sentence("执行 UI 动作", target: previewValue(for: toolCall, keys: ["selector", "target", "path", "text"], includeLabel: true), fallback: "执行 UI 动作")
        case .deviceUIStep:
            return sentence("推进 UI 自动化", target: previewValue(for: toolCall, keys: ["step", "selector", "target"], includeLabel: true), fallback: "推进 UI 自动化")
        case .deviceClipboardRead:
            return "读取剪贴板"
        case .deviceClipboardWrite:
            return sentence("写入剪贴板", target: previewValue(for: toolCall, keys: ["text"], includeLabel: true), fallback: "写入剪贴板")
        case .deviceScreenCapture:
            return "屏幕截图"
        case .deviceBrowserControl:
            return browserActionSummary(for: toolCall)
        case .deviceAppleScript:
            return sentence("运行 AppleScript", target: previewValue(for: toolCall, keys: ["script", "path"], includeLabel: true), fallback: "运行 AppleScript")
        case .need_network:
            return "申请网络访问"
        case .bridge_status:
            return "检查桥接状态"
        case .summarize:
            return sentence("总结", target: previewValue(for: toolCall, keys: ["url", "path", "text"], includeLabel: true), fallback: "总结内容")
        case .supervisorVoicePlayback:
            if let action = stringValue(toolCall.args["action"]) {
                return sentence("播放 Supervisor 语音 \(action)", target: previewValue(for: toolCall, keys: ["text"], includeLabel: true), fallback: "播放 Supervisor 语音")
            }
            return sentence("播放 Supervisor 语音", target: previewValue(for: toolCall, keys: ["text"], includeLabel: true), fallback: "播放 Supervisor 语音")
        case .web_fetch:
            return sentence("抓取", target: previewValue(for: toolCall, keys: ["url"], includeLabel: false), fallback: "抓取网页")
        case .web_search:
            return sentence("联网搜索", target: previewValue(for: toolCall, keys: ["query"], includeLabel: true), fallback: "联网搜索")
        case .browser_read:
            return sentence("读取浏览器页面", target: previewValue(for: toolCall, keys: ["url"], includeLabel: false), fallback: "读取浏览器页面")
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
            || normalized == "waiting for local approval"
            || cleaned == "等待本地审批"
            || cleaned == "等待本地批准" {
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
            return "批准后会立即执行当前这条待处理动作；拒绝只会继续拦下这次动作，不影响其它对话。"
        }
        return "批准后会立即执行当前这些待处理动作；拒绝只会继续拦下对应动作，不影响其它对话。"
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
            return "在浏览器中打开 \(url)"
        }
        if !action.isEmpty {
            return sentence("执行浏览器动作 \(action)", target: target, fallback: "执行浏览器控制")
        }
        return sentence("执行浏览器控制", target: target, fallback: "执行浏览器控制")
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
        case .supervisorVoicePlayback:
            return previewValue(for: toolCall, keys: ["action", "text"], includeLabel: true)
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
            "查询 ",
            "路径 ",
            "选择器 ",
            "命令 ",
            "会话 ",
            "暂存 ",
            "模式 ",
            "文本 ",
            "目标 ",
            "进程 ",
            "名称 "
        ]
        if descriptivePrefixes.contains(where: { lower.hasPrefix($0) }) {
            return "\(prefix)\(target)"
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
            return includeLabel ? "查询 '\(capped(raw, maxChars: 80))'" : capped(raw, maxChars: 80)
        case "path":
            return includeLabel ? "路径 \(raw)" : raw
        case "selector":
            return includeLabel ? "选择器 \(raw)" : raw
        case "target":
            return includeLabel ? "目标 \(raw)" : raw
        case "command":
            return includeLabel ? "命令 \(capped(raw, maxChars: 96))" : capped(raw, maxChars: 96)
        case "process_id":
            return includeLabel ? "进程 \(raw)" : raw
        case "name":
            return includeLabel ? "名称 \(capped(raw, maxChars: 72))" : capped(raw, maxChars: 72)
        case "message":
            return includeLabel ? "提交信息 '\(capped(raw, maxChars: 72))'" : capped(raw, maxChars: 72)
        case "session_id":
            return includeLabel ? "会话 \(raw)" : raw
        case "staging_id":
            return includeLabel ? "暂存 \(raw)" : raw
        case "mode":
            return includeLabel ? "模式 \(raw)" : raw
        case "action":
            return includeLabel ? "动作 \(raw)" : raw
        case "remote":
            return includeLabel ? "远端 \(raw)" : raw
        case "branch":
            return includeLabel ? "分支 \(raw)" : raw
        case "workflow":
            return includeLabel ? "流程 \(raw)" : raw
        case "ref":
            return includeLabel ? "引用 \(raw)" : raw
        case "title":
            return includeLabel ? "标题 '\(capped(raw, maxChars: 72))'" : capped(raw, maxChars: 72)
        case "base":
            return includeLabel ? "基线 \(raw)" : raw
        case "head":
            return includeLabel ? "源分支 \(raw)" : raw
        case "step":
            return includeLabel ? "步骤 \(raw)" : raw
        case "script":
            return includeLabel ? "脚本 \(capped(raw, maxChars: 64))" : capped(raw, maxChars: 64)
        case "text":
            return includeLabel ? "文本 '\(capped(raw, maxChars: 72))'" : capped(raw, maxChars: 72)
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
