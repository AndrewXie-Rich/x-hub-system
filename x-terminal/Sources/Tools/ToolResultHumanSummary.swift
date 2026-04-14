import Foundation

enum ToolResultHumanSummary {
    static func structuredSummary(for result: ToolResult) -> [String: JSONValue]? {
        let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
        guard case .object(let summary)? = parsed.summary else { return nil }
        return summary
    }

    static func isBrowserSecretFillSuccess(_ result: ToolResult) -> Bool {
        guard result.tool == .deviceBrowserControl,
              result.ok,
              let summary = structuredSummary(for: result) else {
            return false
        }
        return string(summary["browser_runtime_driver_state"]) == "secret_vault_applescript_fill"
    }

    static func isBrowserUIObservationSuccess(_ result: ToolResult) -> Bool {
        guard result.tool == .deviceBrowserControl,
              result.ok,
              let summary = structuredSummary(for: result) else {
            return false
        }
        return string(summary["action"]) == "snapshot"
            && string(summary["ui_observation_bundle_ref"]) != nil
    }

    static func specializedSummary(for result: ToolResult) -> String? {
        if result.ok, isBrowserSecretFillSuccess(result) {
            return browserSecretFillSuccessBody(for: result)
        }
        if result.ok, isBrowserUIObservationSuccess(result) {
            return browserUIObservationSuccessBody(for: result)
        }

        switch result.tool {
        case .deviceBrowserControl:
            guard !result.ok else { return nil }
            let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
            let summary = object(parsed.summary)
            let detail = normalizedDiagnostic(parsed.body.isEmpty ? result.output : parsed.body)
            return browserControlFailureBody(summary: summary, detail: detail)
        default:
            return nil
        }
    }

    static func body(for result: ToolResult) -> String {
        if let specialized = specializedSummary(for: result) {
            return specialized
        }

        let parsed = ToolExecutor.parseStructuredToolOutput(result.output)
        let summary = object(parsed.summary)
        let detail = normalizedDiagnostic(parsed.body.isEmpty ? result.output : parsed.body)
        let structuredReasonSignals = [
            summary.flatMap { string($0["reason"]) },
            summary.flatMap { string($0["reason_code"]) },
            summary.flatMap { string($0["deny_code"]) }
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        let lower = [detail, structuredReasonSignals]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()

        if let summary,
           let guardrailBody = XTGuardrailMessagePresentation.toolResultBody(
            tool: result.tool,
            summary: summary,
            detail: detail
           ) {
            return guardrailBody
        }

        switch result.tool {
        case .git_status:
            if lower.contains("not a git repository") {
                return "当前目录不是 Git 仓库，无法在这里查看 Git 状态。"
            }
            return detail.isEmpty ? "无法读取 Git 状态。" : "无法读取 Git 状态：\(detail)"
        case .git_diff:
            if lower.contains("not a git repository") {
                return "当前目录不是 Git 仓库，无法在这里生成 Git diff。"
            }
            return detail.isEmpty ? "无法生成 Git diff。" : "无法生成 Git diff：\(detail)"
        case .run_command:
            return detail.isEmpty ? "命令未能成功完成。" : "命令未能成功完成：\(detail)"
        case .read_file:
            if lower.contains("no such file") {
                return "找不到目标文件。"
            }
            return detail.isEmpty ? "无法读取该文件。" : "无法读取该文件：\(detail)"
        case .write_file, .delete_path, .move_path, .git_apply, .git_apply_check:
            if lower.contains("permission denied") {
                return "当前路径不可写，此次改动已被阻止。"
            }
            return detail.isEmpty ? "请求的改动未能应用。" : "请求的改动未能应用：\(detail)"
        case .git_commit:
            if let preferred = gitFailureBody(summary: summary, tool: .git_commit) {
                return preferred
            }
            return detail.isEmpty ? "无法创建 Git 提交。" : "无法创建 Git 提交：\(detail)"
        case .git_push:
            if let preferred = gitFailureBody(summary: summary, tool: .git_push) {
                return preferred
            }
            return detail.isEmpty ? "无法完成 Git 推送。" : "无法完成 Git 推送：\(detail)"
        case .process_start:
            return detail.isEmpty ? "无法启动托管进程。" : "无法启动托管进程：\(detail)"
        case .process_status, .process_logs:
            return detail.isEmpty ? "无法读取托管进程状态。" : "无法读取托管进程状态：\(detail)"
        case .process_stop:
            return detail.isEmpty ? "无法停止托管进程。" : "无法停止托管进程：\(detail)"
        case .pr_create:
            if let preferred = githubDeliveryFailureBody(summary: summary, toolLabel: "Pull Request") {
                return preferred
            }
            return detail.isEmpty ? "无法创建 Pull Request。" : "无法创建 Pull Request：\(detail)"
        case .ci_read:
            if let preferred = githubDeliveryFailureBody(summary: summary, toolLabel: "CI 状态") {
                return preferred
            }
            return detail.isEmpty ? "无法读取 CI 状态。" : "无法读取 CI 状态：\(detail)"
        case .ci_trigger:
            if let preferred = githubDeliveryFailureBody(summary: summary, toolLabel: "CI 工作流") {
                return preferred
            }
            return detail.isEmpty ? "无法触发 CI 工作流。" : "无法触发 CI 工作流：\(detail)"
        case .agentImportRecord:
            if lower.contains("missing_agent_staging_id") || lower.contains("missing_agent_import_locator") {
                return "Hub 导入审查需要 staging id，或需要像“最新项目导入”这样的选择器。"
            }
            if lower.contains("missing_agent_project_id") {
                return "这次 Hub 导入审查需要 project id，但 XT 无法从当前活动项目中自动推断。"
            }
            if lower.contains("missing_agent_skill_id") {
                return "这次 Hub 导入审查需要 skill id，才能定位到最近一次匹配的导入记录。"
            }
            if lower.contains("skills_record_file_ipc_not_supported") {
                return "Hub 导入审查需要当前设备上有可用的 Hub 运行时连接。"
            }
            return detail.isEmpty ? "无法加载 Hub 导入记录。" : "无法加载 Hub 导入记录：\(detail)"
        case .skills_pin:
            if result.ok {
                return detail.isEmpty ? "Hub 已更新技能可用性。" : detail
            }
            if lower.contains("missing_project_id") {
                return "project scope 的技能启用请求必须带上 project_id。"
            }
            if lower.contains("package_not_found") {
                return "Hub 还没有这个技能包，不能直接启用；需要先让包进入受治理技能仓库。"
            }
            if lower.contains("skill_package_mismatch") {
                return "这次技能启用请求里的 skill_id 和 package_sha256 对不上。"
            }
            if lower.contains("official_skill_review_blocked") {
                return "Hub 已自动审查该官方技能包，但当前 official_skills doctor 结果还不是 ready；请先在 Hub 查看 doctor 或 lifecycle 结果并修复后再重试。"
            }
            if lower.contains("trusted_automation_project_not_bound") || lower.contains("trusted_automation_workspace_mismatch") {
                return "当前 Hub 侧 trusted automation 绑定不满足这次技能启用请求。"
            }
            return detail.isEmpty ? "无法更新技能可用性。" : "无法更新技能可用性：\(detail)"
        case .need_network, .web_fetch, .web_search, .browser_read, .bridge_status:
            if lower.contains("grant") || lower.contains("denied") || lower.contains("blocked") {
                return "当前网络访问被现行策略或授权闸门拦截。"
            }
            return detail.isEmpty ? "网络操作未能完成。" : "网络操作未能完成：\(detail)"
        case .supervisorVoicePlayback:
            return detail.isEmpty ? "Supervisor 语音播放未能完成。" : "Supervisor 语音播放未能完成：\(detail)"
        case .run_local_task:
            return detail.isEmpty ? "本地模型任务未能完成。" : "本地模型任务未能完成：\(detail)"
        default:
            return detail.isEmpty ? "这次工具调用失败了。可打开诊断查看原始输出。" : detail
        }
    }

    private static func browserSecretFillSuccessBody(for result: ToolResult) -> String {
        let summary = structuredSummary(for: result) ?? [:]
        let selector = string(summary["selector"])
        let tagName = string(summary["browser_fill_tag_name"])
        let target = selector ?? (tagName.map { "<\($0)>" })
        if let target {
            return "已使用 Secret Vault 凭据填充浏览器中的 \(target) 字段。"
        }
        return "已使用 Secret Vault 凭据填充当前浏览器输入框。"
    }

    private static func browserUIObservationSuccessBody(for result: ToolResult) -> String {
        let summary = structuredSummary(for: result) ?? [:]
        let status = string(summary["ui_observation_status"]) ?? XTUIObservationBundleStatus.partial.rawValue
        let probeDepth = string(summary["ui_observation_probe_depth"]) ?? XTUIObservationProbeDepth.standard.rawValue
        let url = string(summary["browser_runtime_current_url"]) ?? string(summary["url"])
        let capturedLayers = Int((number(summary["ui_observation_captured_layers"]) ?? 0).rounded())
        let reviewVerdict = string(summary["ui_review_verdict"])
        let reviewSummary = string(summary["ui_review_summary"])

        let prefix: String
        switch status {
        case XTUIObservationBundleStatus.captured.rawValue:
            prefix = "已采集浏览器 UI 观察包"
        default:
            prefix = "已采集部分浏览器 UI 观察包"
        }

        if let url, !url.isEmpty {
            var body = "\(prefix)：\(url)，使用 \(probeDepth) 探测（\(capturedLayers) 层）。"
            if let reviewVerdict {
                body += "审查结论：\(reviewVerdict)。"
            }
            if let reviewSummary {
                body += "审查摘要：\(reviewSummary)。"
            }
            return body
        }
        var body = "\(prefix)，使用 \(probeDepth) 探测（\(capturedLayers) 层）。"
        if let reviewVerdict {
            body += "审查结论：\(reviewVerdict)。"
        }
        if let reviewSummary {
            body += "审查摘要：\(reviewSummary)。"
        }
        return body
    }

    private static func browserControlFailureBody(summary: [String: JSONValue]?, detail: String) -> String? {
        guard let summary else {
            return detail.isEmpty ? "浏览器操作未能完成。" : "浏览器操作未能完成：\(detail)"
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
                return "由于 Secret Vault 引用不完整，浏览器填充已被阻止。请提供 `secret_item_id`，或同时提供 `secret_scope` 和 `secret_name`。"
            case XTDeviceAutomationRejectCode.browserSecretSelectorMissing.rawValue:
                return "使用 Secret Vault 填充浏览器字段时，必须提供 DOM selector。"
            case XTDeviceAutomationRejectCode.browserSecretBeginUseFailed.rawValue:
                if let reason = secretVaultReasonText(secretReason) {
                    return "Hub 未授权此次凭据使用。\(reason)"
                }
                return "Hub 未授权此次凭据使用。"
            case XTDeviceAutomationRejectCode.browserSecretRedeemFailed.rawValue:
                if let reason = secretVaultReasonText(secretReason) {
                    return "XT 无法兑换这次凭据租约。\(reason)"
                }
                return "XT 无法兑换这次凭据租约。"
            case XTDeviceAutomationRejectCode.browserSecretFillUnavailable.rawValue:
                return "凭据已解析，但 XT 当前无法控制这个浏览器窗口。"
            case XTDeviceAutomationRejectCode.browserSecretFillFailed.rawValue:
                if secretReason == "selector_not_found", let selector {
                    return "凭据已解析，但当前页面里找不到目标字段 \(selector)。"
                }
                if let reason = secretVaultReasonText(secretReason) {
                    return "凭据已解析，但 XT 无法填充浏览器字段。\(reason)"
                }
                return "凭据已解析，但 XT 无法填充浏览器字段。"
            case XTDeviceAutomationRejectCode.browserSecretPlaintextForbidden.rawValue:
                return "敏感浏览器字段必须使用 Secret Vault 引用，不能直接输入明文。"
            default:
                break
            }
        }

        if denyCode == XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue {
            return "XT 可以打开页面，但这条路径暂时还不支持托管浏览器点击/输入自动化。"
        }
        if denyCode == XTDeviceAutomationRejectCode.browserSessionNoActiveURL.rawValue {
            return "当前会话没有可用的浏览器 URL，因此浏览器操作已被阻止。"
        }
        if denyCode == XTDeviceAutomationRejectCode.browserSessionMissing.rawValue {
            return "浏览器会话已丢失，XT 无法继续执行该操作。"
        }
        if let guardrailBody = XTGuardrailMessagePresentation.toolResultBody(
            tool: .deviceBrowserControl,
            summary: summary,
            detail: detail
        ) {
            return guardrailBody
        }

        if !denyCode.isEmpty || !detail.isEmpty {
            return detail.isEmpty ? "浏览器操作未能完成。" : "浏览器操作未能完成：\(detail)"
        }
        return nil
    }

    private static func githubDeliveryFailureBody(summary: [String: JSONValue]?, toolLabel: String) -> String? {
        guard let summary else { return nil }
        let reasonCode = string(summary["reason_code"]) ?? ""
        let provider = string(summary["provider"]) ?? ""

        switch reasonCode {
        case "not_git_repository":
            return "当前目录不是 Git 仓库，无法在这里执行\(toolLabel)。"
        case "github_cli_missing":
            return "当前设备还没有安装 GitHub CLI（`gh`），因此无法执行 GitHub 交付动作。"
        case "github_auth_missing":
            return "已安装 GitHub CLI（`gh`），但当前设备还没有完成 GitHub 登录授权。"
        case "github_repo_context_unavailable":
            if let repo = string(summary["repo"]), !repo.isEmpty {
                return "XT 无法为 \(repo) 解析 GitHub 交付上下文。"
            }
            return "XT 无法从当前目录解析出 GitHub 仓库。"
        case "github_cli_execution_failed":
            return "XT 无法从当前项目启动 GitHub CLI。"
        default:
            break
        }

        if provider == "github", !reasonCode.isEmpty {
            return "GitHub 交付动作在执行\(toolLabel)前就失败了。"
        }
        return nil
    }

    private static func gitFailureBody(summary: [String: JSONValue]?, tool: ToolName) -> String? {
        guard let summary else { return nil }
        let reasonCode = string(summary["reason_code"]) ?? ""
        switch reasonCode {
        case "not_git_repository":
            switch tool {
            case .git_commit:
                return "当前目录不是 Git 仓库，无法在这里执行 Git 提交。"
            case .git_push:
                return "当前目录不是 Git 仓库，无法在这里执行 Git 推送。"
            default:
                return nil
            }
        case "git_identity_missing":
            return "Git 身份尚未配置。提交前请先设置 `user.name` 和 `user.email`。"
        case "git_commit_no_changes":
            if let paths = array(summary["paths"]), !paths.isEmpty {
                return "指定的提交路径下没有可提交的已跟踪改动。"
            }
            if bool(summary["all"]) == true {
                return "当前没有可提交的已跟踪改动。"
            }
            return "当前没有可提交的暂存改动。"
        case "git_commit_pathspec_invalid":
            return "一个或多个提交路径不在这个仓库的 Git 跟踪范围内。"
        case "git_commit_paths_with_all_unsupported":
            return "Git commit 不能同时传 `all=true` 和显式 `paths`，请选择一种方式。"
        case "git_push_detached_head":
            return "仓库当前处于 detached HEAD 状态，Git push 需要显式指定分支。"
        case "git_push_remote_missing":
            return "Git push 需要先配置远端仓库。"
        case "git_push_remote_ambiguous":
            return "当前配置了多个远端仓库，Git push 需要显式指定 remote。"
        case "git_push_branch_missing":
            return "要推送的本地分支还不存在。"
        case "git_push_remote_unreachable":
            return "XT 无法连接到已配置的 Git 远端。"
        case "git_push_non_fast_forward":
            return "远端分支已发生分叉，这次推送被拒绝。"
        case "git_push_remote_rejected":
            return "远端拒绝了这次推送。"
        default:
            return nil
        }
    }

    private static func secretVaultReasonText(_ raw: String?) -> String? {
        guard let token = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }

        switch token {
        case "secret_vault_item_not_found":
            return "引用的凭据已不在 Hub 中。"
        case "secret_vault_use_token_not_found":
            return "一次性凭据租约已过期，或已被使用。"
        case "secret_vault_decrypt_failed":
            return "Hub 无法解密这条已存储的凭据。"
        case "selector_not_found":
            return "当前页面里找不到目标字段。"
        default:
            return "原因：\(token)。"
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

    private static func string(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bool(_ value: JSONValue?) -> Bool? {
        guard case .bool(let flag)? = value else { return nil }
        return flag
    }

    private static func number(_ value: JSONValue?) -> Double? {
        guard case .number(let number)? = value else { return nil }
        return number
    }

    private static func object(_ value: JSONValue?) -> [String: JSONValue]? {
        guard case .object(let object)? = value else { return nil }
        return object
    }

    private static func array(_ value: JSONValue?) -> [JSONValue]? {
        guard case .array(let values)? = value else { return nil }
        return values
    }
}
