import Foundation

extension ChatSessionModel {
    func routeDecisionText(_ decision: HubRouteDecision) -> String {
        if decision.preferRemote {
            return decision.allowFileFallback
                ? "优先走远端；远端路由失败时允许回落到本地 file IPC"
                : "只走远端；不再回落到本地"
        }
        if decision.requiresRemote {
            return "直接失败并拦下（\(decision.remoteUnavailableReasonCode ?? "remote_unavailable")）"
        }
        return "只走本地 file IPC"
    }

    func sandboxModeDisplayText(_ mode: ToolSandboxMode) -> String {
        switch mode {
        case .host:
            return "宿主环境"
        case .sandbox:
            return "沙箱环境"
        }
    }

    func localizedPassFail(_ ok: Bool) -> String {
        ok ? "通过" : "失败"
    }

    func hubRouteSelfCheckNameText(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "auto_remote_preferred":
            return "auto 模式在有远端 profile 时优先走远端"
        case "auto_no_remote_file_only":
            return "auto 模式在没有远端 profile 时直接走本地 file IPC"
        case "grpc_remote_only":
            return "grpc 模式在有远端 profile 时只走远端"
        case "grpc_missing_profile_fail_closed":
            return "grpc 模式在没有远端 profile 时直接 fail-closed"
        case "file_forces_local":
            return "fileIPC 模式始终只走本地"
        case "fallback_on_route_unavailable":
            return "远端路由不可用时允许在 auto 模式下回落"
        case "fallback_on_timeout":
            return "远端超时时允许在 auto 模式下回落"
        case "no_fallback_on_model_not_found":
            return "`model_not_found` 不应自动回落"
        case "no_fallback_on_api_key_missing":
            return "`api_key_missing` 不应自动回落"
        case "pending_grants_auto_fallback_truth":
            return "pending grant 快照会披露 auto 回落真相"
        case "pending_grants_grpc_fail_closed_truth":
            return "grpc 模式下 pending grant 快照保持 fail-closed"
        default:
            return raw
        }
    }

    func hubRouteSelfCheckDetailText(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "auto + remote profile => remote first, file fallback allowed":
            return "auto 模式下如果存在远端 profile，会先走远端，并且保留 file IPC 回落。"
        case "auto + no remote profile => direct file route":
            return "auto 模式下如果没有远端 profile，会直接走本地 file IPC。"
        case "grpc + remote profile => remote only (no silent fallback)":
            return "grpc 模式下如果存在远端 profile，只走远端，不允许静默回落。"
        case "grpc + no remote profile => fail closed (hub_env_missing)":
            return "grpc 模式下如果没有远端 profile，会直接 fail-closed（hub_env_missing）。"
        case "file mode => local file ipc only":
            return "fileIPC 模式只走本地。"
        case "remote route unavailable should fallback in auto":
            return "远端路由不可用时，auto 模式应该允许回落。"
        case "timeout should fallback in auto":
            return "远端超时时，auto 模式应该允许回落。"
        case "model_not_found should surface error without fallback":
            return "`model_not_found` 应该直接报错，不做自动回落。"
        case "api_key_missing should surface error without fallback":
            return "`api_key_missing` 应该直接报错，不做自动回落。"
        case "pending grant source truth should disclose auto fallback + remote unavailable reason":
            return "pending grant 快照需要明确写出 auto 回落和远端不可用原因。"
        case "pending grant snapshot should stay fail-closed in grpc mode":
            return "grpc 模式下 pending grant 快照必须保持 fail-closed。"
        default:
            return raw
        }
    }

    func frontstageHighRiskGrantRuntimeStatus(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "当前有效授权：无" }
        if trimmed == "active grants: (none)" {
            return "当前有效授权：无"
        }
        guard trimmed.hasPrefix("active grants:") else {
            return trimmed
        }

        let body = trimmed
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .map { frontstageHighRiskGrantRuntimeLine(String($0)) }
        guard !body.isEmpty else { return "当前有效授权：无" }
        return "当前有效授权：\n" + body.joined(separator: "\n")
    }

    func frontstageHighRiskGrantRuntimeLine(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("- ") else { return trimmed }
        let payload = String(trimmed.dropFirst(2))
        let parts = payload.split(separator: " ", omittingEmptySubsequences: true)
        var grantId = ""
        var capability = ""
        var remaining = ""
        for part in parts {
            let token = String(part)
            if token.hasPrefix("grant=") {
                grantId = String(token.dropFirst("grant=".count))
            } else if token.hasPrefix("capability=") {
                capability = String(token.dropFirst("capability=".count))
            } else if token.hasPrefix("remaining=") {
                remaining = String(token.dropFirst("remaining=".count))
            }
        }
        guard !grantId.isEmpty || !capability.isEmpty || !remaining.isEmpty else {
            return trimmed
        }
        let remainingText = remaining.hasSuffix("s")
            ? "\(remaining.dropLast()) 秒"
            : remaining
        return "- 授权 ID：\(grantId.isEmpty ? "未记录" : grantId) · 能力：\(highRiskGrantCapabilityText(capability)) · 剩余：\(remainingText.isEmpty ? "未知" : remainingText)"
    }

    func frontstageHighRiskGrantBypassScanReport(_ report: ToolExecutor.HighRiskGrantBypassScanReport) -> String {
        let header = """
高风险授权旁路扫描：\(report.ok ? "未发现问题" : "发现风险")
- 扫描到的工具事件：\(report.scannedToolEvents)
- 联网抓取请求：\(report.webFetchEvents)
- 被授权闸门拦下：\(report.deniedEvents)
- 旁路风险记录：\(report.bypassCount)
"""
        guard !report.findings.isEmpty else { return header }

        let lines = report.findings.prefix(6).map { finding in
            let ts: String
            if finding.createdAt > 0 {
                let date = Date(timeIntervalSince1970: finding.createdAt)
                let fmt = DateFormatter()
                fmt.dateFormat = "MM-dd HH:mm:ss"
                ts = fmt.string(from: date)
            } else {
                ts = "时间未知"
            }
            return "- [\(ts)] \(frontstageHighRiskGrantFindingDetail(finding.detail))"
        }
        return header + "\n" + lines.joined(separator: "\n")
    }

    func frontstageHighRiskGrantSelfTestSummary(
        checks: [ToolExecutor.HighRiskGrantSelfCheck],
        scan: ToolExecutor.HighRiskGrantBypassScanReport
    ) -> String {
        let passCount = checks.filter(\.ok).count
        let total = checks.count
        let status = passCount == total ? "通过" : "失败"
        let lines = checks.map { check in
            "- [\(localizedPassFail(check.ok))] \(frontstageHighRiskGrantSelfCheckName(check.name))：\(frontstageHighRiskGrantSelfCheckDetail(check.detail))"
        }

        return """
高风险授权自检：\(status) (\(passCount)/\(total))
\(lines.joined(separator: "\n"))

\(frontstageHighRiskGrantBypassScanReport(scan))
"""
    }

    func highRiskGrantCapabilityText(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "capability_web_fetch", "web_fetch":
            return "联网抓取（web_fetch）"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未知能力" : raw
        }
    }

    func frontstageHighRiskGrantFindingDetail(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "bypass_grant_execution: web_fetch ok=true but input.grant_id is missing" {
            return "联网抓取请求已经执行成功，但输入里缺少 `grant_id`。"
        }
        return trimmed
    }

    func frontstageHighRiskGrantSelfCheckName(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "registered grant is accepted":
            return "已登记的授权会被接受"
        case "expired grant is denied":
            return "过期授权会被拒绝"
        case "missing grant is denied":
            return "缺少授权会被拒绝"
        default:
            return raw
        }
    }

    func frontstageHighRiskGrantSelfCheckDetail(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("state=") {
            let state = String(trimmed.dropFirst("state=".count))
            return "结果：\(frontstageHighRiskGrantValidationStateText(state))"
        }
        return trimmed
    }

    func frontstageHighRiskGrantValidationStateText(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "valid":
            return "有效"
        case "expired":
            return "已过期"
        case "missing":
            return "缺失"
        case "invalid":
            return "无效"
        case "bridgedisabled", "bridge_disabled":
            return "桥接未启用"
        default:
            return raw
        }
    }

    func trustedAutomationModeText(_ mode: AXProjectAutomationMode) -> String {
        switch mode {
        case .standard:
            return "标准模式"
        case .trustedAutomation:
            return "Trusted Automation（设备级自动化）"
        }
    }

    func trustedAutomationStateText(_ state: AXTrustedAutomationProjectState) -> String {
        switch state {
        case .off:
            return "已关闭"
        case .armed:
            return "已布防，等待权限就绪"
        case .active:
            return "已激活，可用于设备执行"
        case .blocked:
            return "配置未完成，暂不可用"
        }
    }

    func trustedAutomationWorkspaceBindingStateText(_ status: AXTrustedAutomationProjectStatus) -> String {
        if status.boundDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "未绑定"
        }
        let currentHash = status.workspaceBindingHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedHash = status.expectedWorkspaceBindingHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentHash.isEmpty, !expectedHash.isEmpty else {
            return "未写入"
        }
        return currentHash == expectedHash ? "已匹配" : "未匹配"
    }

    func trustedAutomationPermissionListText(_ values: [String]) -> String {
        let labels = values.map(trustedAutomationPermissionDisplayName).filter { !$0.isEmpty }
        return labels.isEmpty ? "无" : labels.joined(separator: "、")
    }

    func trustedAutomationSettingsActionListText(_ values: [String]) -> String {
        let labels = values.map(trustedAutomationSettingsActionDisplayText).filter { !$0.isEmpty }
        return labels.isEmpty ? "无" : labels.joined(separator: "、")
    }

    func trustedAutomationMissingPrerequisitesText(_ values: [String]) -> String {
        let labels = values.map(trustedAutomationMissingPrerequisiteText).filter { !$0.isEmpty }
        return labels.isEmpty ? "无" : labels.joined(separator: "；")
    }

    func trustedAutomationPermissionDisplayName(_ raw: String) -> String {
        guard let key = AXTrustedAutomationPermissionKey.parseCommandToken(raw) else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch key {
        case .accessibility:
            return "辅助功能"
        case .automation:
            return "自动化"
        case .screenRecording:
            return "屏幕录制"
        case .fullDiskAccess:
            return "完全磁盘访问"
        case .inputMonitoring:
            return "输入监控"
        }
    }

    func trustedAutomationPermissionStatusText(_ status: AXTrustedAutomationPermissionStatus) -> String {
        switch status {
        case .granted:
            return "已授权"
        case .missing:
            return "未授权"
        case .denied:
            return "已拒绝"
        case .managed:
            return "由系统或组织托管"
        }
    }

    func trustedAutomationSettingsActionDisplayText(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "privacy_accessibility":
            return "辅助功能"
        case "privacy_automation":
            return "自动化"
        case "privacy_screen_recording":
            return "屏幕录制"
        case "privacy_full_disk_access":
            return "完全磁盘访问"
        case "privacy_input_monitoring":
            return "输入监控"
        case "system", "settings":
            return "系统设置"
        default:
            return raw
        }
    }

    func trustedAutomationMissingPrerequisiteText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "trusted_automation_mode_off":
            return "当前项目还没开启 Trusted Automation"
        case "trusted_automation_project_not_bound":
            return "还没有绑定设备 ID"
        case "trusted_automation_workspace_mismatch":
            return "当前工作区和绑定记录不一致"
        case "trusted_automation_device_tool_groups_missing":
            return "还没有配置设备工具组"
        case "trusted_automation_surface_not_enabled":
            return "当前项目还没打开设备自动化入口"
        default:
            if trimmed.hasPrefix("trusted_automation_required_device_tool_group_missing:") {
                let group = String(trimmed.dropFirst("trusted_automation_required_device_tool_group_missing:".count))
                return "缺少必需的设备工具组：\(group)"
            }
            if trimmed.hasPrefix("permission_"), trimmed.hasSuffix("_missing") {
                let permission = String(
                    trimmed
                        .dropFirst("permission_".count)
                        .dropLast("_missing".count)
                )
                return "缺少权限：\(trustedAutomationPermissionDisplayName(permission))"
            }
            return trimmed
        }
    }

    func trustedAutomationOwnerTypeText(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "xterminal_app":
            return "X-Terminal App"
        default:
            return raw
        }
    }

    func trustedAutomationInstallStateText(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ready":
            return "安装位置正常"
        case "degraded":
            return "安装位置不符合推荐"
        default:
            return raw
        }
    }

    func trustedAutomationOverallStateText(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ready":
            return "已就绪"
        case "partial":
            return "部分就绪"
        case "missing":
            return "未就绪"
        default:
            return raw
        }
    }

    func yesNoText(_ value: Bool) -> String {
        value ? "是" : "否"
    }
}
