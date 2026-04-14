import Foundation

enum XTPendingApprovalPresentation {
    enum PendingBatchPrimaryAction: Equatable, Sendable {
        case approveAndExecute
        case approveRunnableSubset
        case reviewGrantStatus
        case reviewBlockedStatus
    }

    struct PendingBatchPresentation: Equatable, Sendable {
        var totalCallCount: Int
        var governedCount: Int
        var localApprovalRequiredCount: Int
        var grantRequiredCount: Int
        var otherGovernedBlockedCount: Int
        var plainPendingCount: Int

        var runnableAfterApprovalCount: Int {
            max(0, totalCallCount - grantRequiredCount - otherGovernedBlockedCount)
        }

        var primaryAction: PendingBatchPrimaryAction {
            if grantRequiredCount == 0, otherGovernedBlockedCount == 0 {
                return .approveAndExecute
            }
            if runnableAfterApprovalCount > 0 {
                return .approveRunnableSubset
            }
            if grantRequiredCount > 0, otherGovernedBlockedCount == 0 {
                return .reviewGrantStatus
            }
            return .reviewBlockedStatus
        }

        var primaryActionTitle: String {
            switch primaryAction {
            case .approveAndExecute:
                return "批准并执行"
            case .approveRunnableSubset:
                return "批准可放行项"
            case .reviewGrantStatus:
                return "继续检查授权状态"
            case .reviewBlockedStatus:
                return "继续检查阻塞状态"
            }
        }

        var primaryActionSystemImage: String {
            switch primaryAction {
            case .approveAndExecute:
                return "checkmark"
            case .approveRunnableSubset:
                return "checkmark.circle"
            case .reviewGrantStatus, .reviewBlockedStatus:
                return "arrow.clockwise"
            }
        }

        var subtitle: String {
            let normalizedCount = max(1, totalCallCount)
            if governedCount == 0 {
                return "\(normalizedCount) 个工具调用等待你确认"
            }

            switch primaryAction {
            case .approveAndExecute:
                return "\(normalizedCount) 个工具调用等待你确认，其中 \(governedCount) 个来自受治理 skill"
            case .approveRunnableSubset:
                var blockers: [String] = []
                if grantRequiredCount > 0 {
                    blockers.append("\(grantRequiredCount) 个仍需先完成 Hub grant")
                }
                if otherGovernedBlockedCount > 0 {
                    blockers.append("\(otherGovernedBlockedCount) 个仍受治理状态限制")
                }
                let blockerSuffix = blockers.isEmpty ? "" : "；" + blockers.joined(separator: "，")
                return "\(normalizedCount) 个工具调用等待处理，其中 \(governedCount) 个来自受治理 skill\(blockerSuffix)"
            case .reviewGrantStatus:
                return "\(normalizedCount) 个待处理项都来自受治理 skill，当前仍在等待 Hub grant"
            case .reviewBlockedStatus:
                return "\(normalizedCount) 个待处理项都来自受治理 skill，当前仍受治理状态限制"
            }
        }

        var footerNote: String {
            switch primaryAction {
            case .approveAndExecute:
                if totalCallCount == 1 {
                    return "批准后会立即执行当前这条待处理动作；拒绝只会继续拦下这次动作，不影响其它对话。"
                }
                return "批准后会立即执行当前这些待处理动作；拒绝只会继续拦下对应动作，不影响其它对话。"
            case .approveRunnableSubset:
                return "批准后会先放行当前可执行的动作；仍需 Hub grant 或其它治理解阻的项会继续阻塞，并把原因写回当前对话。"
            case .reviewGrantStatus:
                return "这批动作仍需先在 Hub / Supervisor 完成 grant，本地批准不会直接放行；继续后会把待授权状态写回当前对话。"
            case .reviewBlockedStatus:
                return "这批动作仍受当前治理状态限制，本地批准不会直接放行；继续后会把阻塞原因写回当前对话。"
            }
        }

        var hubDisconnectedNote: String {
            switch primaryAction {
            case .approveAndExecute:
                return "Hub 未连接，连上后才能批准并执行。"
            case .approveRunnableSubset:
                return "Hub 未连接，连上后才能继续处理并放行可执行项。"
            case .reviewGrantStatus:
                return "Hub 未连接，连上后才能检查 grant 状态并继续处理。"
            case .reviewBlockedStatus:
                return "Hub 未连接，连上后才能检查阻塞状态并继续处理。"
            }
        }
    }

    static func pendingBatchPresentation(
        calls: [ToolCall],
        activityByRequestID: [String: ProjectSkillActivityItem]
    ) -> PendingBatchPresentation {
        var governedCount = 0
        var localApprovalRequiredCount = 0
        var grantRequiredCount = 0
        var otherGovernedBlockedCount = 0
        var plainPendingCount = 0

        for call in calls {
            guard let activity = activityByRequestID[call.id] else {
                plainPendingCount += 1
                continue
            }

            governedCount += 1
            switch normalizedToken(activity.executionReadiness) {
            case XTSkillExecutionReadinessState.localApprovalRequired.rawValue:
                localApprovalRequiredCount += 1
            case XTSkillExecutionReadinessState.grantRequired.rawValue:
                grantRequiredCount += 1
            case "",
                 XTSkillExecutionReadinessState.ready.rawValue,
                 XTSkillExecutionReadinessState.degraded.rawValue:
                break
            default:
                otherGovernedBlockedCount += 1
            }
        }

        return PendingBatchPresentation(
            totalCallCount: calls.count,
            governedCount: governedCount,
            localApprovalRequiredCount: localApprovalRequiredCount,
            grantRequiredCount: grantRequiredCount,
            otherGovernedBlockedCount: otherGovernedBlockedCount,
            plainPendingCount: plainPendingCount
        )
    }

    static func pendingBatchDeltaLines(
        calls: [ToolCall],
        activityByRequestID: [String: ProjectSkillActivityItem]
    ) -> [String] {
        let activities = calls.compactMap { activityByRequestID[$0.id] }
        guard !activities.isEmpty else { return [] }

        let currentProfiles = stableUniqueIdentifiers(activities.flatMap(\.currentRunnableProfiles))
        let requestedProfiles = stableUniqueIdentifiers(activities.flatMap(\.requestedProfiles))
        let deltaProfiles = stableUniqueIdentifiers(activities.flatMap(\.deltaProfiles))
        let deltaCapabilityFamilies = stableUniqueIdentifiers(activities.flatMap(\.deltaCapabilityFamilies))
        let grantFloors = stableUniqueIdentifiers(activities.map(\.grantFloor))
        let approvalFloors = stableUniqueIdentifiers(activities.map(\.approvalFloor))

        var lines: [String] = []
        if !currentProfiles.isEmpty {
            lines.append("当前项目可直接运行：\(currentProfiles.joined(separator: ", "))")
        }
        if !requestedProfiles.isEmpty {
            lines.append("本批请求涉及：\(requestedProfiles.joined(separator: ", "))")
        }
        if !deltaProfiles.isEmpty {
            lines.append("本批新增放开：\(deltaProfiles.joined(separator: ", "))")
        }
        if !deltaCapabilityFamilies.isEmpty {
            lines.append("本批新增能力族：\(displayCapabilityFamilies(deltaCapabilityFamilies))")
        }
        if !grantFloors.isEmpty || !approvalFloors.isEmpty {
            lines.append(
                "涉及授权门槛：\(displayFloorList(grantFloors, fallback: "无额外 grant", using: displayGrantFloor)) · 涉及审批门槛：\(displayFloorList(approvalFloors, fallback: "无额外审批", using: displayApprovalFloor))"
            )
        }
        return lines
    }

    static func pendingBatchAssistantStub(
        calls: [ToolCall],
        activityByRequestID: [String: ProjectSkillActivityItem],
        isRemaining: Bool = false
    ) -> String {
        let scopeHint = "本页处理，或从首页打开对应项目"
        let lead = isRemaining ? "仍有待审批的工具操作" : "有待审批的工具操作"
        let batch = pendingBatchPresentation(
            calls: calls,
            activityByRequestID: activityByRequestID
        )
        guard batch.governedCount > 0 else {
            return "\(lead)（\(scopeHint)）。"
        }

        let deltaLines = pendingBatchDeltaLines(
            calls: calls,
            activityByRequestID: activityByRequestID
        )
        let highlight = deltaLines.first(where: { $0.hasPrefix("本批新增放开：") })
            ?? deltaLines.first(where: { $0.hasPrefix("涉及授权门槛：") })
            ?? deltaLines.first(where: { $0.hasPrefix("当前项目可直接运行：") })
            ?? pendingBatchStubFollowUp(for: batch.primaryAction)
        return "\(lead)：\(batch.subtitle)。\(sentenceFragment(highlight))（\(scopeHint)）。"
    }

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
        case .skills_pin:
            return "pin"
        case .summarize:
            return "text.alignleft"
        case .supervisorVoicePlayback:
            return "speaker.wave.2.fill"
        case .run_local_task:
            return "cpu"
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
        case .skills_pin:
            return "更新技能可用性"
        case .summarize:
            return "总结内容"
        case .supervisorVoicePlayback:
            return "Supervisor 语音"
        case .run_local_task:
            return "本地模型任务"
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
        for toolCall: ToolCall,
        activity: ProjectSkillActivityItem?
    ) -> XTGuardrailMessage {
        let guardrailContext = awaitingApprovalGuardrailContext(for: activity)
        var message = XTGuardrailMessagePresentation.awaitingApprovalMessage(
            toolLabel: displayToolName(for: toolCall.tool),
            target: approvalTarget(for: toolCall),
            requiredCapability: guardrailContext.requiredCapability,
            denyCode: guardrailContext.denyCode
        )
        if let summary = approvalProfileDeltaSummary(for: activity) {
            message.summary = "\(message.summary) \(summary)"
        }
        if let nextStep = approvalNextStep(activity: activity) {
            message.nextStep = nextStep
        }
        return message
    }

    static func approvalMessage(
        toolName: String,
        tool: ToolName?,
        toolSummary: String,
        requiredCapability: String = "",
        denyCode: String = ""
    ) -> XTGuardrailMessage {
        approvalMessage(
            toolName: toolName,
            tool: tool,
            toolSummary: toolSummary,
            activity: nil,
            requiredCapability: requiredCapability,
            denyCode: denyCode
        )
    }

    static func approvalMessage(
        toolName: String,
        tool: ToolName?,
        toolSummary: String,
        activity: ProjectSkillActivityItem?,
        requiredCapability: String = "",
        denyCode: String = ""
    ) -> XTGuardrailMessage {
        let guardrailContext = awaitingApprovalGuardrailContext(for: activity)
        var message = XTGuardrailMessagePresentation.awaitingApprovalMessage(
            toolLabel: displayToolName(raw: toolName, tool: tool),
            target: normalizedToolSummary(toolSummary),
            requiredCapability: guardrailContext.requiredCapability.isEmpty
                ? requiredCapability
                : guardrailContext.requiredCapability,
            denyCode: guardrailContext.denyCode.isEmpty
                ? denyCode
                : guardrailContext.denyCode
        )
        if let summary = approvalProfileDeltaSummary(for: activity) {
            message.summary = "\(message.summary) \(summary)"
        }
        if let nextStep = approvalNextStep(activity: activity) {
            message.nextStep = nextStep
        }
        return message
    }

    static func awaitingApprovalGuardrailContext(
        for activity: ProjectSkillActivityItem?
    ) -> (requiredCapability: String, denyCode: String) {
        guard let activity else {
            return ("", "")
        }

        let readiness = activity.executionReadiness.trimmingCharacters(in: .whitespacesAndNewlines)
        let requiredCapability = activity.requiredCapability.trimmingCharacters(in: .whitespacesAndNewlines)
        let denyCode = activity.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)

        switch readiness {
        case XTSkillExecutionReadinessState.grantRequired.rawValue:
            return (
                requiredCapability,
                denyCode.isEmpty ? "grant_required" : denyCode
            )
        case XTSkillExecutionReadinessState.localApprovalRequired.rawValue:
            return (
                "",
                denyCode
            )
        default:
            return (
                requiredCapability,
                denyCode
            )
        }
    }

    static func approvalProfileDeltaSummary(
        for activity: ProjectSkillActivityItem?
    ) -> String? {
        let summary = activity?.approvalSummary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !summary.isEmpty else { return nil }
        return summary
    }

    static func approvalProfileDeltaLines(
        for activity: ProjectSkillActivityItem?
    ) -> [String] {
        guard let activity else { return [] }
        var lines: [String] = []
        if !activity.currentRunnableProfiles.isEmpty {
            lines.append("当前可直接运行：\(activity.currentRunnableProfiles.joined(separator: ", "))")
        }
        if !activity.requestedProfiles.isEmpty {
            lines.append("本次请求：\(activity.requestedProfiles.joined(separator: ", "))")
        }
        if !activity.deltaProfiles.isEmpty {
            lines.append("新增放开：\(activity.deltaProfiles.joined(separator: ", "))")
        }
        if !activity.grantFloor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !activity.approvalFloor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(
                "授权门槛：\(displayGrantFloor(activity.grantFloor)) · 审批门槛：\(displayApprovalFloor(activity.approvalFloor))"
            )
        }
        return lines
    }

    static func governedSkillShortSummary(
        for activity: ProjectSkillActivityItem?
    ) -> String? {
        guard let activity else { return nil }
        var parts: [String] = []
        if let skill = governedSkillLabel(for: activity) {
            parts.append(skill)
        }
        let readiness = activity.executionReadiness.trimmingCharacters(in: .whitespacesAndNewlines)
        if !readiness.isEmpty {
            parts.append(displayExecutionReadiness(readiness))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func governedSkillDetailLines(
        for activity: ProjectSkillActivityItem?
    ) -> [String] {
        guard let activity else { return [] }
        var lines: [String] = []

        let requestedSkillID = activity.requestedSkillID.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSkillID = activity.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effectiveSkillID.isEmpty {
            lines.append("生效技能：\(effectiveSkillID)")
        }
        if !requestedSkillID.isEmpty, requestedSkillID != effectiveSkillID {
            lines.append("请求技能：\(requestedSkillID)")
        }

        let readiness = activity.executionReadiness.trimmingCharacters(in: .whitespacesAndNewlines)
        if !readiness.isEmpty {
            lines.append("执行就绪：\(displayExecutionReadiness(readiness))")
        }

        let grantFloor = activity.grantFloor.trimmingCharacters(in: .whitespacesAndNewlines)
        let approvalFloor = activity.approvalFloor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !grantFloor.isEmpty || !approvalFloor.isEmpty {
            lines.append("治理闸门：\(displayGrantFloor(grantFloor)) · \(displayApprovalFloor(approvalFloor))")
        }
        if !activity.requiredRuntimeSurfaces.isEmpty {
            lines.append("运行面：\(displayRuntimeSurfaceList(activity.requiredRuntimeSurfaces))")
        }
        if !activity.unblockActions.isEmpty {
            lines.append("解阻动作：\(displayUnblockActionList(activity.unblockActions))")
        }

        if !activity.intentFamilies.isEmpty {
            lines.append("意图族：\(displayIdentifierList(activity.intentFamilies))")
        }
        if !activity.capabilityFamilies.isEmpty {
            lines.append("能力族：\(displayCapabilityFamilies(activity.capabilityFamilies))")
        }
        if !activity.capabilityProfiles.isEmpty {
            lines.append("能力档位：\(displayIdentifierList(activity.capabilityProfiles))")
        }
        if !activity.hubStateDirPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("恢复上下文：已保存 Hub 执行上下文，可在批准后继续恢复执行。")
        }

        return lines
    }

    static func governedSkillLabel(
        for activity: ProjectSkillActivityItem?
    ) -> String? {
        guard let activity else { return nil }
        let requestedSkillID = activity.requestedSkillID.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSkillID = activity.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requestedSkillID.isEmpty, !effectiveSkillID.isEmpty, requestedSkillID != effectiveSkillID {
            return "\(requestedSkillID) -> \(effectiveSkillID)"
        }
        if !effectiveSkillID.isEmpty {
            return effectiveSkillID
        }
        if !requestedSkillID.isEmpty {
            return requestedSkillID
        }
        return nil
    }

    static func displayExecutionReadiness(
        _ raw: String?
    ) -> String {
        switch normalizedToken(raw) {
        case XTSkillExecutionReadinessState.ready.rawValue:
            return "可立即执行"
        case XTSkillExecutionReadinessState.grantRequired.rawValue:
            return "等待 Hub grant"
        case XTSkillExecutionReadinessState.localApprovalRequired.rawValue:
            return "等待本地审批"
        case XTSkillExecutionReadinessState.policyClamped.rawValue:
            return "受治理档位限制"
        case XTSkillExecutionReadinessState.runtimeUnavailable.rawValue:
            return "执行面暂不可用"
        case XTSkillExecutionReadinessState.hubDisconnected.rawValue:
            return "Hub 未连接"
        case XTSkillExecutionReadinessState.quarantined.rawValue:
            return "已隔离"
        case XTSkillExecutionReadinessState.revoked.rawValue:
            return "已撤销"
        case XTSkillExecutionReadinessState.notInstalled.rawValue:
            return "未安装"
        case XTSkillExecutionReadinessState.unsupported.rawValue:
            return "当前不兼容"
        case XTSkillExecutionReadinessState.degraded.rawValue:
            return "降级可用"
        case "":
            return "未知"
        default:
            return XTSkillCapabilityProfileSupport.readinessLabel(raw)
        }
    }

    static func displayGrantFloor(
        _ raw: String?
    ) -> String {
        switch normalizedToken(raw) {
        case XTSkillGrantFloor.none.rawValue, "":
            return "无额外 grant"
        case XTSkillGrantFloor.readonly.rawValue:
            return "只读 grant"
        case XTSkillGrantFloor.privileged.rawValue:
            return "高权限 grant"
        case XTSkillGrantFloor.critical.rawValue:
            return "关键级 grant"
        default:
            return normalizedToken(raw)
        }
    }

    static func displayApprovalFloor(
        _ raw: String?
    ) -> String {
        switch normalizedToken(raw) {
        case XTSkillApprovalFloor.none.rawValue, "":
            return "无额外审批"
        case XTSkillApprovalFloor.localApproval.rawValue:
            return "本地审批"
        case XTSkillApprovalFloor.hubGrant.rawValue:
            return "Hub grant"
        case XTSkillApprovalFloor.hubGrantPlusLocalApproval.rawValue:
            return "Hub grant + 本地审批"
        case XTSkillApprovalFloor.ownerConfirmation.rawValue:
            return "所有者确认"
        default:
            return normalizedToken(raw)
        }
    }

    static func displayCapabilityFamilies(
        _ rawFamilies: String
    ) -> String {
        displayCapabilityFamilies(splitIdentifiers(rawFamilies))
    }

    static func displayCapabilityFamilies(
        _ families: [String]
    ) -> String {
        let labels = splitIdentifiers(families)
            .map { XTGuardrailMessagePresentation.displayCapability($0) }
        return labels.isEmpty ? "无" : labels.joined(separator: "、")
    }

    static func displayRuntimeSurfaceList(
        _ rawValues: String
    ) -> String {
        displayRuntimeSurfaceList(splitIdentifiers(rawValues))
    }

    static func displayRuntimeSurfaceList(
        _ values: [String]
    ) -> String {
        let labels = splitIdentifiers(values)
            .map(displayRuntimeSurface)
        return labels.isEmpty ? "无" : labels.joined(separator: "、")
    }

    static func displayUnblockActionList(
        _ rawValues: String
    ) -> String {
        displayUnblockActionList(splitIdentifiers(rawValues))
    }

    static func displayUnblockActionList(
        _ values: [String]
    ) -> String {
        let labels = splitIdentifiers(values)
            .map(displayUnblockAction)
        return labels.isEmpty ? "无" : labels.joined(separator: "、")
    }

    static func displayIdentifierList(
        _ rawValues: String
    ) -> String {
        displayIdentifierList(splitIdentifiers(rawValues))
    }

    static func displayIdentifierList(
        _ values: [String]
    ) -> String {
        let normalized = splitIdentifiers(values)
        return normalized.isEmpty ? "无" : normalized.joined(separator: "、")
    }

    static func approvalNextStep(
        activity: ProjectSkillActivityItem?
    ) -> String? {
        let readiness = activity?.executionReadiness.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !readiness.isEmpty else { return nil }
        switch readiness {
        case XTSkillExecutionReadinessState.grantRequired.rawValue:
            return "先完成 Hub grant，再恢复这次受治理技能调用。"
        case XTSkillExecutionReadinessState.localApprovalRequired.rawValue:
            return "这次审批通过后，会按当前受治理路径继续执行。"
        default:
            return nil
        }
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
        case .skills_pin:
            return sentence("更新技能可用性", target: previewValue(for: toolCall, keys: ["skill_id", "package_sha256", "project_id"], includeLabel: true), fallback: "更新技能可用性")
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
        case .run_local_task:
            return sentence(
                "执行本地模型任务",
                target: previewValue(
                    for: toolCall,
                    keys: ["task_kind", "model_id", "preferred_model_id", "text", "query", "audio_path", "image_path"],
                    includeLabel: true
                ),
                fallback: "执行本地模型任务"
            )
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
        PendingBatchPresentation(
            totalCallCount: max(1, callCount),
            governedCount: 0,
            localApprovalRequiredCount: 0,
            grantRequiredCount: 0,
            otherGovernedBlockedCount: 0,
            plainPendingCount: max(1, callCount)
        ).footerNote
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
        case .run_local_task:
            return previewValue(
                for: toolCall,
                keys: ["task_kind", "model_id", "preferred_model_id", "text", "query", "audio_path", "image_path"],
                includeLabel: true
            )
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

    private static func normalizedToken(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func displayRuntimeSurface(
        _ raw: String
    ) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = trimmed.lowercased()
        let label: String
        switch token {
        case "xt_builtin":
            label = "XT 内建运行面"
        case "supervisor_runtime":
            label = "Supervisor 运行面"
        case "project_local_fs":
            label = "项目本地文件系统"
        case "project_local_runtime":
            label = "项目本地运行时"
        case "local_text_generation_runtime":
            label = "本地文本生成运行面"
        case "local_embedding_runtime":
            label = "本地向量运行面"
        case "local_speech_to_text_runtime":
            label = "本地语音转写运行面"
        case "local_text_to_speech_runtime":
            label = "本地语音合成运行面"
        case "local_vision_runtime":
            label = "本地图像理解运行面"
        case "hub_bridge_network":
            label = "Hub 桥接网络"
        case "managed_browser_runtime":
            label = "受治理浏览器运行面"
        case "trusted_device_runtime":
            label = "可信设备运行面"
        case "connector_runtime":
            label = "连接器运行面"
        case "device_browser_runtime":
            label = "设备浏览器运行面"
        default:
            return trimmed
        }
        return annotatedKnownToken(label, token: trimmed)
    }

    private static func displayUnblockAction(
        _ raw: String
    ) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = trimmed.lowercased()
        let label: String
        switch token {
        case "request_hub_grant":
            label = "请求 Hub grant"
        case "request_local_approval":
            label = "请求本地审批"
        case "approve_local_skill_request":
            label = "批准本地技能请求"
        case "open_model_settings":
            label = "打开模型设置"
        case "open_project_settings":
            label = "打开项目设置"
        case "open_trusted_automation_doctor":
            label = "打开可信自动化诊断"
        case "reconnect_hub":
            label = "重连 Hub"
        case "open_skill_governance_surface":
            label = "打开技能治理面板"
        case "refresh_resolved_cache":
            label = "刷新解析缓存"
        case "install_baseline":
            label = "安装基线技能"
        case "pin_package_project":
            label = "固定到当前项目"
        case "pin_package_global":
            label = "固定到全局"
        case "retry_dispatch":
            label = "重新派发"
        default:
            return trimmed
        }
        return annotatedKnownToken(label, token: trimmed)
    }

    private static func annotatedKnownToken(
        _ label: String,
        token: String
    ) -> String {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return label }
        return "\(label)（\(trimmedToken)）"
    }

    private static func splitIdentifiers(
        _ rawValues: String
    ) -> [String] {
        rawValues
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitIdentifiers(
        _ values: [String]
    ) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stableUniqueIdentifiers(
        _ values: [String]
    ) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for value in splitIdentifiers(values) where seen.insert(value).inserted {
            ordered.append(value)
        }
        return ordered
    }

    private static func displayFloorList(
        _ values: [String],
        fallback: String,
        using display: (String?) -> String
    ) -> String {
        let normalized = stableUniqueIdentifiers(values)
        guard !normalized.isEmpty else { return fallback }
        return normalized.map { display($0) }.joined(separator: "、")
    }

    private static func pendingBatchStubFollowUp(
        for action: PendingBatchPrimaryAction
    ) -> String {
        switch action {
        case .approveAndExecute:
            return "批准后会直接继续当前可放行项"
        case .approveRunnableSubset:
            return "可先放行当前可执行项，仍待 Hub grant 或治理解阻的项会继续保留"
        case .reviewGrantStatus:
            return "本地批准不会直接放行，先处理 Hub grant"
        case .reviewBlockedStatus:
            return "本地批准不会直接放行，先处理治理阻塞"
        }
    }

    private static func sentenceFragment(
        _ raw: String
    ) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = trimmed.last,
              ["。", "!", "！", "?", "？"].contains(String(last)) {
            trimmed.removeLast()
        }
        return trimmed
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
