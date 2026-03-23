import Foundation

enum ToolResultPresentation {
    static func shouldSurfaceSuccessfulTimelineCard(call: ToolCall, result: ToolResult) -> Bool {
        guard result.ok else { return false }
        guard call.tool == .deviceBrowserControl else { return false }
        return ToolResultHumanSummary.isBrowserSecretFillSuccess(result)
            || ToolResultHumanSummary.isBrowserUIObservationSuccess(result)
    }

    static func shouldShowTimelineCard(for result: ToolResult) -> Bool {
        if !result.ok {
            return true
        }
        return ToolResultHumanSummary.isBrowserSecretFillSuccess(result)
            || ToolResultHumanSummary.isBrowserUIObservationSuccess(result)
    }

    static func title(for result: ToolResult) -> String {
        if result.ok, ToolResultHumanSummary.isBrowserSecretFillSuccess(result) {
            return "已从 Secret Vault 填充凭据"
        }
        if result.ok, ToolResultHumanSummary.isBrowserUIObservationSuccess(result) {
            return "已采集浏览器 UI 观察"
        }
        return "\(toolDisplayName(result.tool))需要处理"
    }

    static func body(for result: ToolResult) -> String {
        ToolResultHumanSummary.body(for: result)
    }

    static func repairHint(for result: ToolResult) -> XTGuardrailRepairHint? {
        guard let summary = ToolResultHumanSummary.structuredSummary(for: result) else {
            return nil
        }
        return XTGuardrailMessagePresentation.repairHint(
            denyCode: string(summary["deny_code"]) ?? "",
            policySource: string(summary["policy_source"]) ?? "",
            policyReason: string(summary["runtime_surface_policy_reason"])
                ?? string(summary["policy_reason"])
                ?? ""
        )
    }

    static func iconName(for result: ToolResult) -> String {
        if result.ok, ToolResultHumanSummary.isBrowserSecretFillSuccess(result) {
            return "checkmark.shield.fill"
        }
        if result.ok, ToolResultHumanSummary.isBrowserUIObservationSuccess(result) {
            return "eye.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    static func structuredSummary(for result: ToolResult) -> [String: JSONValue]? {
        ToolResultHumanSummary.structuredSummary(for: result)
    }

    private static func toolDisplayName(_ tool: ToolName) -> String {
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
            return "查看文件列表"
        case .search:
            return "搜索"
        case .run_command:
            return "执行命令"
        case .process_start:
            return "启动进程"
        case .process_status:
            return "进程状态"
        case .process_logs:
            return "进程日志"
        case .process_stop:
            return "停止进程"
        case .git_status:
            return "Git 状态"
        case .git_diff:
            return "Git diff"
        case .git_commit:
            return "Git 提交"
        case .git_push:
            return "Git 推送"
        case .git_apply_check:
            return "补丁检查"
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
            return "Agent 导入记录"
        case .memory_snapshot:
            return "记忆快照"
        case .project_snapshot:
            return "项目快照"
        case .deviceUIObserve:
            return "观察界面"
        case .deviceUIAct:
            return "执行界面操作"
        case .deviceUIStep:
            return "分步界面操作"
        case .deviceClipboardRead:
            return "读取剪贴板"
        case .deviceClipboardWrite:
            return "写入剪贴板"
        case .deviceScreenCapture:
            return "截取屏幕"
        case .deviceBrowserControl:
            return "控制浏览器"
        case .deviceAppleScript:
            return "运行 AppleScript"
        case .need_network:
            return "申请网络访问"
        case .bridge_status:
            return "检查桥接状态"
        case .skills_search:
            return "搜索技能"
        case .summarize:
            return "总结内容"
        case .supervisorVoicePlayback:
            return "Supervisor 语音"
        case .web_fetch:
            return "抓取网页内容"
        case .web_search:
            return "搜索网页"
        case .browser_read:
            return "读取浏览器页面"
        }
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

}
