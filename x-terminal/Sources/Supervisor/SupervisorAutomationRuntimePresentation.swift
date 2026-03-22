import Foundation

enum SupervisorAutomationRuntimeTextTone: Equatable {
    case primary
    case secondary
    case success
    case warning
    case danger
}

enum SupervisorAutomationRuntimeLineStyle: Equatable {
    case caption
    case caption2
}

struct SupervisorAutomationRuntimeLinePresentation: Equatable, Identifiable {
    var id: String
    var text: String
    var tone: SupervisorAutomationRuntimeTextTone
    var style: SupervisorAutomationRuntimeLineStyle
    var isSelectable: Bool
    var lineLimit: Int?
}

struct SupervisorAutomationRuntimeControlPresentation: Equatable {
    var selfIterateEnabled: Bool
    var maxAutoRetryDepth: Int
    var summaryLine: SupervisorAutomationRuntimeLinePresentation
    var boundedRetryLine: SupervisorAutomationRuntimeLinePresentation
}

struct SupervisorAutomationRuntimePresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var statusLine: String
    var contractText: String?
    var nextSafeActionText: String?
    var statusAction: SupervisorAutomationRuntimeActionDescriptor
    var projectLine: SupervisorAutomationRuntimeLinePresentation?
    var recipeLine: SupervisorAutomationRuntimeLinePresentation?
    var goalLine: SupervisorAutomationRuntimeLinePresentation?
    var controls: SupervisorAutomationRuntimeControlPresentation?
    var detailRows: [SupervisorAutomationRuntimeLinePresentation]
    var primaryActions: [SupervisorAutomationRuntimeActionDescriptor]
    var advanceActions: [SupervisorAutomationRuntimeActionDescriptor]
    var emptyStateText: String?
}

enum SupervisorAutomationRuntimePresentationMapper {
    struct Input: Equatable {
        var project: AXProjectEntry?
        var recipe: AXAutomationRecipeRuntimeBinding?
        var statusLine: String
        var lastLaunchRef: String
        var selfIterateEnabled: Bool
        var maxAutoRetryDepth: Int
        var currentCheckpoint: XTAutomationRunCheckpoint?
        var latestExecutionReport: XTAutomationRunExecutionReport?
        var latestRetryPackage: XTAutomationRetryPackage?
        var recoveryDecision: XTAutomationRestartRecoveryDecision?
        var trustedStatus: AXTrustedAutomationProjectStatus?
        var trustedRequiredPermissions: [String]
        var retryTrigger: String
    }

    static func map(input: Input) -> SupervisorAutomationRuntimePresentation {
        let trimmedLastLaunchRef = trimmed(input.lastLaunchRef)
        let actionContext = SupervisorAutomationRuntimeActionResolver.Context(
            hasSelectedProject: input.project != nil,
            hasRecipe: input.recipe != nil,
            hasLastLaunchRef: !trimmedLastLaunchRef.isEmpty
        )
        let currentRunMatchesSelection = !trimmedLastLaunchRef.isEmpty
            && input.currentCheckpoint?.runID == trimmedLastLaunchRef
        let iconName = automationIconName(
            recipe: input.recipe,
            currentRunMatchesSelection: currentRunMatchesSelection
        )
        let iconTone = automationIconTone(
            recipe: input.recipe,
            checkpoint: input.currentCheckpoint,
            currentRunMatchesSelection: currentRunMatchesSelection
        )
        let statusAction = SupervisorAutomationRuntimeActionResolver.descriptor(
            for: .status,
            context: actionContext
        )
        let contract = guidanceContract(input: input, currentRunMatchesSelection: currentRunMatchesSelection)
        let primaryActions = [
            SupervisorAutomationRuntimeActionResolver.descriptor(
                for: .start,
                context: actionContext
            ),
            SupervisorAutomationRuntimeActionResolver.descriptor(
                for: .recover,
                context: actionContext
            ),
            SupervisorAutomationRuntimeActionResolver.descriptor(
                for: .cancel,
                context: actionContext
            ),
        ]
        let advanceActions = SupervisorAutomationRuntimeActionResolver.advanceDescriptors(
            context: actionContext
        )

        guard let project = input.project else {
            return SupervisorAutomationRuntimePresentation(
                iconName: iconName,
                iconTone: iconTone,
                title: "自动化执行",
                statusLine: input.statusLine,
                contractText: contract.map(SupervisorGuidanceContractLinePresentation.contractLine),
                nextSafeActionText: contract.map(SupervisorGuidanceContractLinePresentation.nextSafeActionLine),
                statusAction: statusAction,
                projectLine: nil,
                recipeLine: nil,
                goalLine: nil,
                controls: nil,
                detailRows: [],
                primaryActions: primaryActions,
                advanceActions: advanceActions,
                emptyStateText: "先选中一个具体项目，再查看自动化执行。当前 Home 视图不会直接启动项目级运行。"
            )
        }

        var detailRows: [SupervisorAutomationRuntimeLinePresentation] = []

        if let recipe = input.recipe,
           !recipe.requiredDeviceToolGroups.isEmpty {
            detailRows.append(
                line(
                    id: "required_device_tool_groups",
                    text: "所需设备能力：\(localizedDeviceToolGroups(recipe.requiredDeviceToolGroups))",
                    tone: .secondary,
                    lineLimit: 2
                )
            )
        }

        if let trustedStatus = input.trustedStatus {
            detailRows.append(
                line(
                    id: "trusted_automation",
                    text: "可信设备权限：\(humanizedTrustedAutomationState(trustedStatus.state))",
                    tone: trustedAutomationTone(trustedStatus.state)
                )
            )

            if !input.trustedRequiredPermissions.isEmpty {
                detailRows.append(
                    line(
                        id: "required_permissions",
                        text: "待补系统权限：\(localizedPermissionKeys(input.trustedRequiredPermissions))",
                        tone: .secondary
                    )
                )
            }

            if !trustedStatus.armedDeviceToolGroups.isEmpty {
                detailRows.append(
                    line(
                        id: "armed_device_tool_groups",
                        text: "已启用设备能力：\(localizedDeviceToolGroups(trustedStatus.armedDeviceToolGroups))",
                        tone: .secondary,
                        lineLimit: 2
                    )
                )
            }

            if !trustedStatus.missingPrerequisites.isEmpty {
                detailRows.append(
                    line(
                        id: "trusted_missing",
                        text: "待补前置条件：\(localizedTrustedPrerequisites(trustedStatus.missingPrerequisites))",
                        tone: .warning,
                        lineLimit: 2
                    )
                )
            }

            if !trustedStatus.missingRequiredDeviceToolGroups.isEmpty {
                detailRows.append(
                    line(
                        id: "missing_required_device_groups",
                        text: "缺少必需设备能力：\(localizedDeviceToolGroups(trustedStatus.missingRequiredDeviceToolGroups))",
                        tone: .warning,
                        lineLimit: 2
                    )
                )
            }
        }

        detailRows.append(
            line(
                id: "last_launch",
                text: "最近一次运行：\(trimmedLastLaunchRef.isEmpty ? "暂无" : trimmedLastLaunchRef)",
                tone: .secondary,
                isSelectable: true
            )
        )

        if currentRunMatchesSelection,
           let report = input.latestExecutionReport {
            detailRows.append(
                line(
                    id: "execution",
                    text: "执行状态：\(humanizedRunState(report.finalState)) · 已执行 \(report.executedActionCount)/\(report.totalActionCount)",
                    tone: .secondary
                )
            )

            if let lineage = report.lineage {
                detailRows.append(
                    line(
                        id: "lineage",
                        text: "运行链：\(lineage.lineageID) · 根运行 \(lineage.rootRunID) · 重试深度 \(lineage.retryDepth)",
                        tone: .secondary,
                        isSelectable: true
                    )
                )
                if !lineage.parentRunID.isEmpty {
                    detailRows.append(
                        line(
                            id: "parent_run",
                            text: "父运行：\(lineage.parentRunID)",
                            tone: .secondary,
                            isSelectable: true
                        )
                    )
                }
            }

            let handoffPath = trimmed(report.handoffArtifactPath)
            if !handoffPath.isEmpty {
                detailRows.append(
                    line(
                        id: "handoff",
                        text: "交接产物：\(handoffPath)",
                        tone: .secondary,
                        isSelectable: true
                    )
                )
            }

            if let verification = report.verificationReport,
               verification.required {
                detailRows.append(
                    line(
                        id: "verify",
                        text: "验证：\(verification.passedCommandCount)/\(verification.commandCount) · \(verification.detail)",
                        tone: verification.ok ? .secondary : .warning
                    )
                )
            }
        }

        if currentRunMatchesSelection,
           let checkpoint = input.currentCheckpoint {
            let retryText = checkpoint.retryAfterSeconds > 0
                ? " · \(checkpoint.retryAfterSeconds) 秒后可重试"
                : ""
            detailRows.append(
                line(
                    id: "checkpoint",
                    text: "检查点：\(humanizedRunState(checkpoint.state)) · 第 \(checkpoint.attempt) 次\(retryText)",
                    tone: .secondary
                )
            )
        } else if !trimmedLastLaunchRef.isEmpty {
            detailRows.append(
                line(
                    id: "checkpoint_hint",
                    text: "检查点：可以用“状态”或“恢复”从最近日志重建最新状态",
                    tone: .secondary
                )
            )
        }

        if let retryPackage = input.latestRetryPackage,
           retryPackage.projectID == project.projectId {
            detailRows.append(
                line(
                    id: "retry",
                    text: "重试策略：\(retryPackage.retryStrategy) · 来源 \(retryPackage.sourceRunID)",
                    tone: .secondary
                )
            )

            if let lineage = retryPackage.lineage {
                detailRows.append(
                    line(
                        id: "retry_lineage",
                        text: "重试链：\(lineage.lineageID) · 根运行 \(lineage.rootRunID) · 重试深度 \(lineage.retryDepth)",
                        tone: .secondary,
                        isSelectable: true
                    )
                )
                if !lineage.parentRunID.isEmpty {
                    detailRows.append(
                        line(
                            id: "retry_parent_run",
                            text: "重试父运行：\(lineage.parentRunID)",
                            tone: .secondary,
                            isSelectable: true
                        )
                    )
                }
            }

            let planningMode = trimmed(retryPackage.planningMode)
            if !planningMode.isEmpty {
                detailRows.append(
                    line(
                        id: "retry_planning_mode",
                        text: "重试规划模式：\(humanizedPlanningMode(planningMode))",
                        tone: .secondary
                    )
                )
            }

            let planningSummary = trimmed(retryPackage.planningSummary)
            if !planningSummary.isEmpty {
                detailRows.append(
                    line(
                        id: "retry_planning_summary",
                        text: "重试规划摘要：\(planningSummary)",
                        tone: .secondary,
                        lineLimit: 3
                    )
                )
            }

            if let revisedVerifyCommands = retryPackage.revisedVerifyCommands,
               !revisedVerifyCommands.isEmpty {
                detailRows.append(
                    line(
                        id: "retry_revised_verify_commands",
                        text: "重试验证命令：\(revisedVerifyCommands.joined(separator: " || "))",
                        tone: .secondary,
                        lineLimit: 2
                    )
                )
            }

            let runtimePatchOverlayKeys = xtAutomationRuntimePatchOverlayKeys(
                retryPackage.runtimePatchOverlay
            )
            if !runtimePatchOverlayKeys.isEmpty {
                detailRows.append(
                    line(
                        id: "retry_runtime_patch_overlay_keys",
                        text: "运行时补丁键：\(runtimePatchOverlayKeys.joined(separator: ", "))",
                        tone: .secondary,
                        isSelectable: true
                    )
                )
            }

            let recipeProposalArtifactPath = trimmed(retryPackage.recipeProposalArtifactPath)
            if !recipeProposalArtifactPath.isEmpty {
                detailRows.append(
                    line(
                        id: "retry_recipe_proposal_artifact",
                        text: "重试配方提案：\(recipeProposalArtifactPath)",
                        tone: .secondary,
                        isSelectable: true
                    )
                )
            }

            let planningArtifactPath = trimmed(retryPackage.planningArtifactPath)
            if !planningArtifactPath.isEmpty {
                detailRows.append(
                    line(
                        id: "retry_planning_artifact",
                        text: "重试规划产物：\(planningArtifactPath)",
                        tone: .secondary,
                        isSelectable: true
                    )
                )
            }

            let retryTrigger = trimmed(input.retryTrigger)
            detailRows.append(
                line(
                    id: "retry_trigger",
                    text: "重试触发：\(humanizedRetryTrigger(retryTrigger))",
                    tone: .secondary
                )
            )
            detailRows.append(
                line(
                    id: "retry_handoff",
                    text: "来源交接产物：\(retryPackage.sourceHandoffArtifactPath)",
                    tone: .secondary,
                    isSelectable: true
                )
            )
        }

        if currentRunMatchesSelection,
           let decision = input.recoveryDecision {
            let holdReason = trimmed(decision.holdReason).isEmpty ? "无" : trimmed(decision.holdReason)
            detailRows.append(
                line(
                    id: "recovery",
                    text: "恢复决策：\(humanizedRecoveryAction(decision.decision))（\(holdReason)）",
                    tone: .secondary
                )
            )
        }

        return SupervisorAutomationRuntimePresentation(
            iconName: iconName,
            iconTone: iconTone,
            title: "自动化执行",
            statusLine: input.statusLine,
            contractText: contract.map(SupervisorGuidanceContractLinePresentation.contractLine),
            nextSafeActionText: contract.map(SupervisorGuidanceContractLinePresentation.nextSafeActionLine),
            statusAction: statusAction,
            projectLine: line(
                id: "project",
                text: "项目：\(project.displayName) (\(project.projectId))",
                tone: .primary,
                style: .caption,
                isSelectable: true
            ),
            recipeLine: line(
                id: "recipe",
                text: "执行配方：\(input.recipe?.ref ?? "(未激活)")",
                tone: input.recipe == nil ? .warning : .secondary
            ),
            goalLine: trimmed(input.recipe?.goal).isEmpty
                ? nil
                : line(
                    id: "goal",
                    text: "目标：\(trimmed(input.recipe?.goal))",
                    tone: .secondary,
                    lineLimit: 2
                ),
            controls: SupervisorAutomationRuntimeControlPresentation(
                selfIterateEnabled: input.selfIterateEnabled,
                maxAutoRetryDepth: max(1, input.maxAutoRetryDepth),
                summaryLine: line(
                    id: "self_iterate",
                    text: "自动自迭代：\(input.selfIterateEnabled ? "已开启" : "已关闭") · 最大自动重试深度 \(max(1, input.maxAutoRetryDepth))",
                    tone: input.selfIterateEnabled ? .warning : .secondary
                ),
                boundedRetryLine: line(
                    id: "bounded_auto_retry_only",
                    text: "受控自动重试：当前只会生成受控运行补丁和重试提案，不会擅自改写整体计划。",
                    tone: .secondary
                )
            ),
            detailRows: detailRows,
            primaryActions: primaryActions,
            advanceActions: advanceActions,
            emptyStateText: nil
        )
    }

    private static func guidanceContract(
        input: Input,
        currentRunMatchesSelection: Bool
    ) -> SupervisorGuidanceContractSummary? {
        let holdReason = trimmed(input.latestExecutionReport?.holdReason)
        let detail = trimmed(input.latestExecutionReport?.detail)
        let trustedState = input.trustedStatus?.state

        if trustedState == .blocked {
            let blocker = firstNonEmpty([
                input.trustedStatus?.missingPrerequisites.first,
                input.trustedRequiredPermissions.first,
                "trusted_automation_blocked"
            ]) ?? "trusted_automation_blocked"
            return SupervisorGuidanceContractSummary(
                kind: .incidentRecovery,
                trigger: "Automation Runtime",
                reviewLevel: "",
                verdict: "",
                summary: firstNonEmpty([
                    detail,
                    "trusted automation blocked"
                ]) ?? "trusted automation blocked",
                primaryBlocker: blocker,
                currentState: "trusted_automation_blocked",
                nextStep: "",
                nextSafeAction: "inspect_incident_and_replan",
                recommendedActions: [],
                workOrderRef: "",
                effectiveSupervisorTier: "",
                effectiveWorkOrderDepth: ""
            )
        }

        guard currentRunMatchesSelection,
              let checkpoint = input.currentCheckpoint else {
            return nil
        }

        let status = checkpoint.state
        let statusToken = status.rawValue
        let summary = firstNonEmpty([
            detail,
            holdReason,
            input.statusLine
        ]) ?? input.statusLine

        if status == .blocked {
            let blocker = firstNonEmpty([holdReason, detail]) ?? "automation_blocked"
            let lowered = blocker.lowercased()
            if lowered.contains("grant") || lowered.contains("authorization") {
                return SupervisorGuidanceContractSummary(
                    kind: .grantResolution,
                    trigger: "Automation Runtime",
                    reviewLevel: "",
                    verdict: "",
                    summary: summary,
                    primaryBlocker: blocker,
                    currentState: statusToken,
                    nextStep: "",
                    nextSafeAction: "open_hub_grants",
                    recommendedActions: [],
                    workOrderRef: "",
                    effectiveSupervisorTier: "",
                    effectiveWorkOrderDepth: ""
                )
            }

            if lowered.contains("input") || lowered.contains("instruction") || lowered.contains("review") {
                return SupervisorGuidanceContractSummary(
                    kind: .awaitingInstruction,
                    trigger: "Automation Runtime",
                    reviewLevel: "",
                    verdict: "",
                    summary: summary,
                    primaryBlocker: blocker,
                    currentState: statusToken,
                    nextStep: "",
                    nextSafeAction: "clarify_with_user",
                    recommendedActions: [],
                    workOrderRef: "",
                    effectiveSupervisorTier: "",
                    effectiveWorkOrderDepth: ""
                )
            }

            return SupervisorGuidanceContractSummary(
                kind: .incidentRecovery,
                trigger: "Automation Runtime",
                reviewLevel: "",
                verdict: "",
                summary: summary,
                primaryBlocker: blocker,
                currentState: statusToken,
                nextStep: "",
                nextSafeAction: "inspect_incident_and_replan",
                recommendedActions: [],
                workOrderRef: "",
                effectiveSupervisorTier: "",
                effectiveWorkOrderDepth: ""
            )
        }

        if status == .failed {
            return SupervisorGuidanceContractSummary(
                kind: .incidentRecovery,
                trigger: "Automation Runtime",
                reviewLevel: "",
                verdict: "",
                summary: summary,
                primaryBlocker: firstNonEmpty([holdReason, detail]) ?? "automation_failed",
                currentState: statusToken,
                nextStep: "",
                nextSafeAction: "inspect_incident_and_replan",
                recommendedActions: [],
                workOrderRef: "",
                effectiveSupervisorTier: "",
                effectiveWorkOrderDepth: ""
            )
        }

        if status == .takeover || status == .downgraded {
            return SupervisorGuidanceContractSummary(
                kind: .supervisorReplan,
                trigger: "Automation Runtime",
                reviewLevel: "",
                verdict: "",
                summary: summary,
                primaryBlocker: firstNonEmpty([holdReason, detail]) ?? statusToken,
                currentState: statusToken,
                nextStep: "",
                nextSafeAction: "apply_supervisor_replan",
                recommendedActions: [],
                workOrderRef: "",
                effectiveSupervisorTier: "",
                effectiveWorkOrderDepth: ""
            )
        }

        return nil
    }

    private static func automationIconName(
        recipe: AXAutomationRecipeRuntimeBinding?,
        currentRunMatchesSelection: Bool
    ) -> String {
        if recipe == nil {
            return "bolt.slash.circle"
        }
        return currentRunMatchesSelection ? "bolt.circle.fill" : "bolt.circle"
    }

    private static func automationIconTone(
        recipe: AXAutomationRecipeRuntimeBinding?,
        checkpoint: XTAutomationRunCheckpoint?,
        currentRunMatchesSelection: Bool
    ) -> SupervisorHeaderControlTone {
        guard recipe != nil else { return .neutral }
        guard currentRunMatchesSelection, let checkpoint else { return .accent }

        switch checkpoint.state {
        case .queued, .running:
            return .accent
        case .blocked, .takeover, .downgraded:
            return .warning
        case .delivered:
            return .success
        case .failed:
            return .danger
        }
    }

    private static func trustedAutomationTone(
        _ state: AXTrustedAutomationProjectState
    ) -> SupervisorAutomationRuntimeTextTone {
        switch state {
        case .active:
            return .success
        case .off:
            return .secondary
        case .armed, .blocked:
            return .warning
        }
    }

    private static func line(
        id: String,
        text: String,
        tone: SupervisorAutomationRuntimeTextTone,
        style: SupervisorAutomationRuntimeLineStyle = .caption2,
        isSelectable: Bool = false,
        lineLimit: Int? = nil
    ) -> SupervisorAutomationRuntimeLinePresentation {
        SupervisorAutomationRuntimeLinePresentation(
            id: id,
            text: text,
            tone: tone,
            style: style,
            isSelectable: isSelectable,
            lineLimit: lineLimit
        )
    }

    private static func humanizedRunState(_ state: XTAutomationRunState) -> String {
        switch state {
        case .queued:
            return "排队中"
        case .running:
            return "运行中"
        case .blocked:
            return "受阻"
        case .takeover:
            return "等待接管"
        case .delivered:
            return "已交付"
        case .failed:
            return "失败"
        case .downgraded:
            return "已降级"
        }
    }

    private static func humanizedTrustedAutomationState(
        _ state: AXTrustedAutomationProjectState
    ) -> String {
        switch state {
        case .off:
            return "未开启"
        case .armed:
            return "已绑定，等待生效"
        case .active:
            return "已生效"
        case .blocked:
            return "已阻塞"
        }
    }

    private static func humanizedRecoveryAction(
        _ action: XTAutomationRestartRecoveryAction
    ) -> String {
        switch action {
        case .resume:
            return "继续"
        case .hold:
            return "保持挂起"
        case .scavenged:
            return "已回收"
        case .suppressed:
            return "已抑制"
        }
    }

    private static func humanizedRetryTrigger(_ raw: String) -> String {
        switch trimmed(raw) {
        case "":
            return "无"
        case "self_iterate":
            return "自迭代"
        case "manual":
            return "手动触发"
        default:
            return trimmed(raw)
        }
    }

    private static func humanizedPlanningMode(_ raw: String) -> String {
        switch trimmed(raw) {
        case "overlay_only":
            return "仅补丁叠加"
        case "":
            return "未说明"
        default:
            return trimmed(raw)
        }
    }

    private static func localizedDeviceToolGroups(_ values: [String]) -> String {
        values.map(localizedDeviceToolGroup).joined(separator: ", ")
    }

    private static func localizedDeviceToolGroup(_ raw: String) -> String {
        switch trimmed(raw) {
        case "device.ui.observe":
            return "UI 观察"
        case "device.ui.act":
            return "UI 动作"
        case "device.ui.step":
            return "UI 步进"
        case "device.browser.control":
            return "浏览器控制"
        case "device.clipboard.read":
            return "读取剪贴板"
        case "device.clipboard.write":
            return "写入剪贴板"
        case "device.screen.capture":
            return "屏幕截图"
        case "device.applescript":
            return "AppleScript"
        default:
            return raw
        }
    }

    private static func localizedPermissionKeys(_ values: [String]) -> String {
        values.map(localizedPermissionKey).joined(separator: ", ")
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            let trimmedValue = trimmed(value)
            if !trimmedValue.isEmpty {
                return trimmedValue
            }
        }
        return nil
    }

    private static func localizedPermissionKey(_ raw: String) -> String {
        switch trimmed(raw) {
        case "accessibility":
            return "辅助功能"
        case "automation":
            return "自动化"
        case "screen_recording":
            return "屏幕录制"
        case "microphone":
            return "麦克风"
        default:
            return raw
        }
    }

    private static func localizedTrustedPrerequisites(_ values: [String]) -> String {
        values.map(localizedTrustedPrerequisite).joined(separator: ", ")
    }

    private static func localizedTrustedPrerequisite(_ raw: String) -> String {
        let cleaned = trimmed(raw)
        if cleaned == "trusted_automation_mode_off" {
            return "还没开启可信设备权限"
        }
        if cleaned == "trusted_automation_project_not_bound" {
            return "还没把项目绑定到设备"
        }
        if cleaned == "trusted_automation_workspace_mismatch" {
            return "当前工作区和绑定设备不匹配"
        }
        if cleaned == "trusted_automation_device_tool_groups_missing" {
            return "还没配置设备能力"
        }
        if cleaned == "trusted_automation_surface_not_enabled" {
            return "还没开启设备自动化运行面"
        }
        let prefix = "trusted_automation_required_device_tool_group_missing:"
        if cleaned.hasPrefix(prefix) {
            let suffix = String(cleaned.dropFirst(prefix.count))
            return "缺少必需设备能力 \(localizedDeviceToolGroup(suffix))"
        }
        return raw
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
