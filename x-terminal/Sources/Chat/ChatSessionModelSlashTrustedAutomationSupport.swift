import Foundation

extension ChatSessionModel {
    func handleSlashTrustedAutomation(args: [String], ctx: AXProjectContext, config: AXProjectConfig?) -> String {
        guard var cfg = (config ?? (try? AXProjectStore.loadOrCreateConfig(for: ctx))) else {
            return projectConfigUpdateUnavailableText()
        }

        let workspaceHash = xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        let currentDeviceId = cfg.trustedAutomationDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "status"

        switch command {
        case "status", "show", "list":
            return slashTrustedAutomationText(config: cfg, ctx: ctx)
        case "doctor", "diag", "diagnose", "check":
            return slashTrustedAutomationDoctorText(config: cfg, ctx: ctx)
        case "off", "disable":
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .standard,
                deviceId: currentDeviceId,
                deviceToolGroups: cfg.deviceToolGroups,
                workspaceBindingHash: workspaceHash
            )
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已关闭当前项目的 Trusted Automation 绑定。\n\n" + slashTrustedAutomationText(config: cfg, ctx: ctx)
        case "open":
            let target = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if target == "system" || target == "settings" {
                XTSystemSettingsLinks.openSystemSettings()
                return "已尝试打开系统设置。\n\n" + slashTrustedAutomationDoctorText(config: cfg, ctx: ctx)
            }
            guard let permissionKey = AXTrustedAutomationPermissionKey.parseCommandToken(target) else {
                return slashTrustedAutomationUsageText()
            }
            XTSystemSettingsLinks.openPrivacyAction(permissionKey.openSettingsAction)
            return "已尝试打开“\(trustedAutomationPermissionDisplayName(permissionKey.rawValue))”设置。\n\n" + slashTrustedAutomationDoctorText(config: cfg, ctx: ctx)
        case "arm", "bind", "on", "enable":
            let deviceId = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedDeviceId = deviceId.isEmpty
                ? xtTrustedAutomationSuggestedDeviceID(existing: [currentDeviceId])
                : xtTrustedAutomationNormalizeDeviceID(deviceId)
            guard !resolvedDeviceId.isEmpty else {
                return slashTrustedAutomationUsageText()
            }
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: resolvedDeviceId,
                deviceToolGroups: cfg.deviceToolGroups.isEmpty ? xtTrustedAutomationDefaultDeviceToolGroups() : cfg.deviceToolGroups,
                workspaceBindingHash: workspaceHash
            )
            activeConfig = cfg
            try? AXProjectStore.saveConfig(cfg, for: ctx)
            return "已为当前项目绑定 Trusted Automation 设备：\(resolvedDeviceId)。\n\n" + slashTrustedAutomationText(config: cfg, ctx: ctx)
        default:
            return slashTrustedAutomationUsageText()
        }
    }

    func slashTrustedAutomationText(config: AXProjectConfig?, ctx: AXProjectContext) -> String {
        let cfg = config ?? .default(forProjectRoot: ctx.root)
        let readiness = AXTrustedAutomationPermissionOwnerReadiness.current()
        let status = cfg.trustedAutomationStatus(forProjectRoot: ctx.root, permissionReadiness: readiness)
        let groups = status.deviceToolGroups.isEmpty ? "(none)" : status.deviceToolGroups.joined(separator: ", ")
        let deviceId = status.boundDeviceID.isEmpty ? "(none)" : status.boundDeviceID
        let requiredPermissions = AXTrustedAutomationPermissionOwnerReadiness.requiredPermissionKeys(forDeviceToolGroups: status.deviceToolGroups)
        let repairActions = readiness.suggestedOpenSettingsActions(forDeviceToolGroups: status.deviceToolGroups)
        let workspaceBindingState = trustedAutomationWorkspaceBindingStateText(status)
        let missingText = trustedAutomationMissingPrerequisitesText(status.missingPrerequisites)
        let groupsText = groups == "(none)" ? "无" : groups
        let deviceLabel = deviceId == "(none)" ? "未绑定" : deviceId

        return """
Trusted Automation：
- 当前模式：\(trustedAutomationModeText(status.mode))
- 当前状态：\(trustedAutomationStateText(status.state))
- 绑定设备：\(deviceLabel)
- 工作区绑定：\(workspaceBindingState)
- 权限宿主已就绪：\(yesNoText(status.permissionOwnerReady))
- 设备工具组：\(groupsText)
- 需要权限：\(trustedAutomationPermissionListText(requiredPermissions))
- 可直接打开的设置：\(trustedAutomationSettingsActionListText(repairActions))
- 仍缺少前提：\(missingText)

\(slashTrustedAutomationUsageText())
"""
    }

    func slashTrustedAutomationDoctorText(config: AXProjectConfig?, ctx: AXProjectContext) -> String {
        let cfg = config ?? .default(forProjectRoot: ctx.root)
        let readiness = AXTrustedAutomationPermissionOwnerReadiness.current()
        let status = cfg.trustedAutomationStatus(forProjectRoot: ctx.root, permissionReadiness: readiness)
        let requirementStatuses = readiness.requirementStatuses(forDeviceToolGroups: status.deviceToolGroups)
        let permissionLines: String
        if requirementStatuses.isEmpty {
            permissionLines = "- 权限要求：无"
        } else {
            permissionLines = requirementStatuses.map { requirement in
                let tools = requirement.requiredByDeviceToolGroups.isEmpty
                    ? "无"
                    : requirement.requiredByDeviceToolGroups.joined(separator: ", ")
                return "- \(trustedAutomationPermissionDisplayName(requirement.key.rawValue))：\(trustedAutomationPermissionStatusText(requirement.status)) · 关联工具组：\(tools)"
            }.joined(separator: "\n")
        }
        let repairActions = readiness.suggestedOpenSettingsActions(forDeviceToolGroups: status.deviceToolGroups)

        return """
Trusted Automation 自检：
- 权限宿主 ID：\(readiness.ownerID)
- 宿主类型：\(trustedAutomationOwnerTypeText(readiness.ownerType))
- Bundle ID：\(readiness.bundleID)
- 安装状态：\(trustedAutomationInstallStateText(readiness.installState))
- 总体状态：\(trustedAutomationOverallStateText(readiness.overallState))
- 可主动拉起授权：\(yesNoText(readiness.canPromptUser))
- 受 MDM 管理：\(yesNoText(readiness.managedByMDM))
- 审计锚点：\(readiness.auditRef)
\(permissionLines)
- 可直接打开的设置：\(trustedAutomationSettingsActionListText(repairActions))

\(slashTrustedAutomationUsageText())
"""
    }

    func slashTrustedAutomationUsageText() -> String {
        """
命令：
- /trusted-automation status
- /trusted-automation doctor
- /trusted-automation arm [paired_device_id]
- /trusted-automation off
- /trusted-automation open <accessibility|automation|screen_recording|full_disk_access|input_monitoring|system>
"""
    }
}
