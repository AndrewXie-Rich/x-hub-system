import Foundation

struct XTGuardrailMessage: Equatable, Sendable {
    var summary: String
    var nextStep: String?

    var text: String {
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNextStep = nextStep?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanNextStep.isEmpty else { return cleanSummary }
        guard !cleanSummary.isEmpty else { return cleanNextStep }
        return cleanSummary + " " + cleanNextStep
    }
}

struct XTGuardrailRepairHint: Equatable, Sendable {
    var destination: XTProjectGovernanceDestination
    var buttonTitle: String
    var helpText: String
}

enum XTGuardrailMessagePresentation {
    static func awaitingApprovalMessage(
        toolLabel: String,
        target: String?,
        requiredCapability: String = "",
        denyCode: String = ""
    ) -> XTGuardrailMessage {
        let cleanedToolLabel = normalizedToolLabel(toolLabel)
        let cleanedCapability = normalized(requiredCapability)
        let cleanedDenyCode = normalized(denyCode)
        let targetSuffix = targetClause(target)
        let humanCapability = XTHubGrantPresentation.capabilityLabel(
            capability: cleanedCapability,
            modelId: ""
        )

        if !cleanedCapability.isEmpty || cleanedDenyCode == "grant_required" {
            if cleanedCapability.isEmpty {
                return XTGuardrailMessage(
                    summary: "运行\(cleanedToolLabel)\(targetSuffix)前，还需要先通过 Hub 授权。",
                    nextStep: "先在 Hub 或 Supervisor 里批准授权，再重试。"
                )
            }
            return XTGuardrailMessage(
                summary: "运行\(cleanedToolLabel)\(targetSuffix)前，还需要先批准 \(humanCapability) 的 Hub 授权。",
                nextStep: "先在 Hub 或 Supervisor 里批准授权，再重试。"
            )
        }

        return XTGuardrailMessage(
            summary: "运行\(cleanedToolLabel)\(targetSuffix)前，还需要先通过本地审批。",
            nextStep: "先在 X-Terminal 里批准，让受治理工具继续执行。"
        )
    }

    static func awaitingApprovalBody(
        toolLabel: String,
        target: String?,
        requiredCapability: String = "",
        denyCode: String = ""
    ) -> String {
        awaitingApprovalMessage(
            toolLabel: toolLabel,
            target: target,
            requiredCapability: requiredCapability,
            denyCode: denyCode
        ).text
    }

    static func blockedBody(
        tool: ToolName? = nil,
        toolLabel: String,
        denyCode: String,
        policySource: String = "",
        policyReason: String = "",
        requiredCapability: String = "",
        fallbackSummary: String = "",
        fallbackDetail: String = ""
    ) -> String {
        if let explanation = explanation(
            tool: tool,
            toolLabel: toolLabel,
            denyCode: denyCode,
            policySource: policySource,
            policyReason: policyReason,
            requiredCapability: requiredCapability
        ) {
            return explanation.text
        }

        if let preferred = preferredFallback(
            summary: fallbackSummary,
            detail: fallbackDetail,
            denyCode: denyCode
        ) {
            return preferred
        }

        let cleanedToolLabel = normalizedToolLabel(toolLabel)
        if !cleanedToolLabel.isEmpty {
            return "在继续执行\(cleanedToolLabel)之前，这个动作已被拦下。"
        }
        return "这个动作被治理策略拦下了。"
    }

    static func blockedSummary(
        tool: ToolName? = nil,
        toolLabel: String,
        denyCode: String,
        policySource: String = "",
        policyReason: String = "",
        requiredCapability: String = "",
        fallbackSummary: String = "",
        fallbackDetail: String = ""
    ) -> String? {
        let cleanedDenyCode = normalized(denyCode)
        let cleanedPolicySource = normalized(policySource)
        let cleanedPolicyReason = normalized(policyReason)
        let cleanedCapability = normalized(requiredCapability)
        guard !cleanedDenyCode.isEmpty
            || !cleanedPolicySource.isEmpty
            || !cleanedPolicyReason.isEmpty
            || !cleanedCapability.isEmpty else {
            return nil
        }
        return blockedBody(
            tool: tool,
            toolLabel: toolLabel,
            denyCode: denyCode,
            policySource: policySource,
            policyReason: policyReason,
            requiredCapability: requiredCapability,
            fallbackSummary: fallbackSummary,
            fallbackDetail: fallbackDetail
        )
    }

    static func toolResultBody(
        tool: ToolName,
        summary: [String: JSONValue],
        detail: String
    ) -> String? {
        let denyCode = string(summary["deny_code"]) ?? ""
        let policySource = string(summary["policy_source"]) ?? ""
        let runtimeSurfacePolicyReason = string(summary["runtime_surface_policy_reason"]) ?? ""
        let policyReason: String
        if policySource == "project_autonomy_policy", !runtimeSurfacePolicyReason.isEmpty {
            policyReason = runtimeSurfacePolicyReason
        } else {
            policyReason = string(summary["policy_reason"]) ?? ""
        }
        let requiredCapability = string(summary["required_capability"]) ?? ""

        guard !denyCode.isEmpty || !policySource.isEmpty else { return nil }

        let toolLabel = toolLabel(for: tool)
        let body = blockedBody(
            tool: tool,
            toolLabel: toolLabel,
            denyCode: denyCode,
            policySource: policySource,
            policyReason: policyReason,
            requiredCapability: requiredCapability,
            fallbackSummary: "",
            fallbackDetail: detail
        )

        if normalized(denyCode) == "governance_capability_denied"
            || normalized(policySource) == "project_governance" {
            if let truthLine = XTGovernanceTruthPresentation.truthLine(
                configuredExecutionTier: string(summary["execution_tier"]),
                effectiveExecutionTier: string(summary["effective_execution_tier"]),
                configuredSupervisorTier: string(summary["supervisor_intervention_tier"])
                    ?? string(summary["configured_supervisor_tier"]),
                effectiveSupervisorTier: string(summary["effective_supervisor_intervention_tier"])
                    ?? string(summary["effective_supervisor_tier"]),
                reviewPolicyMode: string(summary["review_policy_mode"]),
                progressHeartbeatSeconds: int(summary["progress_heartbeat_sec"]),
                reviewPulseSeconds: int(summary["review_pulse_sec"]),
                brainstormReviewSeconds: int(summary["brainstorm_review_sec"]),
                compatSource: string(summary["governance_compat_source"])
                    ?? string(summary["compat_source"])
            ) {
                return "\(truthLine) \(body)"
            }
        }

        return body
    }

    static func repairHint(
        denyCode: String,
        policySource: String = "",
        policyReason: String = ""
    ) -> XTGuardrailRepairHint? {
        let cleanedDenyCode = normalized(denyCode)
        let cleanedPolicySource = normalized(policySource)
        let cleanedPolicyReason = normalized(policyReason)

        if cleanedDenyCode == "governance_capability_denied" || cleanedPolicySource == "project_governance" {
            return XTGuardrailRepairHint(
                destination: .executionTier,
                buttonTitle: "打开执行档位",
                helpText: executionTierHelpText(minimumTier: recommendedExecutionTier(for: cleanedPolicyReason))
            )
        }

        if cleanedDenyCode == "autonomy_policy_denied"
            || cleanedPolicySource == "project_autonomy_policy"
            || cleanedPolicySource == "trusted_automation_device_gate" {
            return XTGuardrailRepairHint(
                destination: .overview,
                buttonTitle: "打开治理设置",
                helpText: "打开项目设置 -> 项目治理，检查当前运行面限制、可信自动化状态和生效策略。"
            )
        }

        return nil
    }

    private static func explanation(
        tool: ToolName?,
        toolLabel: String,
        denyCode: String,
        policySource: String,
        policyReason: String,
        requiredCapability: String
    ) -> XTGuardrailMessage? {
        let cleanedDenyCode = normalized(denyCode)
        let cleanedPolicySource = normalized(policySource)
        let cleanedPolicyReason = normalized(policyReason)
        let cleanedCapability = normalized(requiredCapability)
        let cleanedToolLabel = normalizedToolLabel(toolLabel)
        let humanCapability = XTHubGrantPresentation.capabilityLabel(
            capability: cleanedCapability,
            modelId: ""
        )

        switch cleanedDenyCode {
        case "grant_required":
            let summary: String
            if cleanedCapability.isEmpty {
                summary = "继续这个动作前，仍然需要先通过 Hub 授权。"
            } else {
                summary = "继续这个动作前，仍然需要先通过 \(humanCapability) 的 Hub 授权。"
            }
            return XTGuardrailMessage(
                summary: summary,
                nextStep: "先在 Hub 或 Supervisor 里批准授权，再重试。"
            )
        case "grant_denied", "voice_grant_denied":
            let summary: String
            if cleanedCapability.isEmpty {
                summary = "Hub 授权被拒绝了，所以这个动作没有执行。"
            } else {
                summary = "\(humanCapability) 的 Hub 授权被拒绝了，所以这个动作没有执行。"
            }
            return XTGuardrailMessage(
                summary: summary,
                nextStep: "调整请求范围，或先批准新的授权，再重试。"
            )
        case "local_approval_required":
            return XTGuardrailMessage(
                summary: "继续这个动作前，仍然需要本地审批。",
                nextStep: "先在 X-Terminal 里批准，让受治理工具继续执行。"
            )
        case "local_approval_denied", "user_rejected_pending_tool_approval":
            return XTGuardrailMessage(
                summary: "本地审批被拒绝了，所以这个动作没有执行。",
                nextStep: "先确认这个请求仍然合理，再决定是否重试。"
            )
        case "governance_capability_denied":
            return governanceExplanation(policyReason: cleanedPolicyReason)
        case "autonomy_policy_denied":
            return runtimeSurfaceExplanation(policyReason: cleanedPolicyReason)
        case "tool_policy_denied":
            return XTGuardrailMessage(
                summary: "项目工具策略禁止执行\(cleanedToolLabel)。",
                nextStep: "先在项目工具策略里放行这个工具，再重试。"
            )
        case XTDeviceAutomationRejectCode.trustedAutomationModeOff.rawValue:
            return XTGuardrailMessage(
                summary: "这个项目还没有开启可信设备权限。",
                nextStep: "先打开可信自动化，并把项目绑定到设备，再重试。"
            )
        case XTDeviceAutomationRejectCode.trustedAutomationProjectNotBound.rawValue:
            return XTGuardrailMessage(
                summary: "这个项目还没有绑定到已配对设备。",
                nextStep: "先把项目绑定到已配对设备，再重试。"
            )
        case XTDeviceAutomationRejectCode.trustedAutomationWorkspaceMismatch.rawValue:
            return XTGuardrailMessage(
                summary: "当前项目文件夹和已配对设备的绑定已经不匹配了。",
                nextStep: "重新绑定项目，让工作区哈希与当前根目录一致。"
            )
        case XTDeviceAutomationRejectCode.trustedAutomationSurfaceNotEnabled.rawValue:
            return XTGuardrailMessage(
                summary: "这个项目还没有开启设备自动化运行面。",
                nextStep: "先开启受治理的设备权限，再重试。"
            )
        case XTDeviceAutomationRejectCode.deviceAutomationToolNotArmed.rawValue:
            return XTGuardrailMessage(
                summary: "这个项目还没有启用所需的设备能力。",
                nextStep: "先在项目设置里启用缺失的设备工具组，再重试。"
            )
        case XTDeviceAutomationRejectCode.systemPermissionMissing.rawValue:
            return XTGuardrailMessage(
                summary: "执行这个设备动作所需的 macOS 权限还没授予。",
                nextStep: "先授予缺失的系统权限，再重试。"
            )
        case XTDeviceAutomationRejectCode.uiObservationRequired.rawValue:
            return XTGuardrailMessage(
                summary: "这个 UI 动作继续前，需要一份新的 UI 观察结果。",
                nextStep: "先执行一次观察步骤，再重试这个动作。"
            )
        case XTDeviceAutomationRejectCode.uiObservationExpired.rawValue:
            return XTGuardrailMessage(
                summary: "上一份 UI 观察已经过期。",
                nextStep: "先采集新的 UI 观察结果，再重试。"
            )
        case XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue:
            return XTGuardrailMessage(
                summary: "当前路径暂时还不能使用受治理的浏览器点击/输入自动化。",
                nextStep: "先改用打开或读取流程，或者先手动执行。"
            )
        case XTDeviceAutomationRejectCode.browserSessionMissing.rawValue:
            return XTGuardrailMessage(
                summary: "浏览器会话不存在。",
                nextStep: "先打开或重新打开页面，再重试。"
            )
        case XTDeviceAutomationRejectCode.browserSessionNoActiveURL.rawValue:
            return XTGuardrailMessage(
                summary: "当前浏览器会话里没有活动页面。",
                nextStep: "先打开一个页面，再重试。"
            )
        case "path_outside_governed_read_roots":
            return XTGuardrailMessage(
                summary: "这次读取超出了项目目录和受治理可读根目录范围。",
                nextStep: "把路径加入受治理可读根目录，或把文件移回项目范围内。"
            )
        case "path_write_outside_project_root":
            return XTGuardrailMessage(
                summary: "即使启用了受治理可读根目录，写入也仍然只能发生在项目根目录内。",
                nextStep: "把写入目标放回项目目录内，再重试。"
            )
        case "payload.command_not_allowed":
            return XTGuardrailMessage(
                summary: "这次技能请求要求执行的命令不在受治理白名单里。",
                nextStep: "改用允许的命令，或先更新技能契约，再重试。"
            )
        case "command_outside_governed_repo_allowlist":
            return XTGuardrailMessage(
                summary: "这个项目只能自动运行受治理的仓库构建/测试命令。",
                nextStep: "先在本地批准这个命令，或改成白名单内的构建/测试命令。"
            )
        case "unsupported_skill_id", "skill_mapping_missing", "skill_not_registered":
            return XTGuardrailMessage(
                summary: "这个技能还没有接入受治理运行时。",
                nextStep: "先安装或注册这个技能，再重试。"
            )
        default:
            break
        }

        if cleanedDenyCode.hasPrefix("payload.") {
            return XTGuardrailMessage(
                summary: "这次技能请求缺少必填字段，或 payload 字段不合法。",
                nextStep: "先检查技能输入 payload，再重试。"
            )
        }

        switch cleanedPolicySource {
        case "project_governance":
            return governanceExplanation(policyReason: cleanedPolicyReason)
        case "project_autonomy_policy":
            return runtimeSurfaceExplanation(policyReason: cleanedPolicyReason)
        case "project_tool_policy":
            return XTGuardrailMessage(
                summary: "项目工具策略禁止执行\(cleanedToolLabel)。",
                nextStep: "先在项目工具策略里放行这个工具，再重试。"
            )
        case "trusted_automation_device_gate":
            return XTGuardrailMessage(
                summary: "可信设备权限拦下了这个动作。",
                nextStep: "先检查项目设备权限和 macOS 系统授权，再重试。"
            )
        case "governed_path_scope":
            return XTGuardrailMessage(
                summary: "这个动作超出了项目的受治理路径范围。",
                nextStep: "把目标移回允许范围内，或更新受治理可读根目录。"
            )
        case "governed_command_guard":
            return XTGuardrailMessage(
                summary: "这个项目只能自动运行受治理的仓库构建/测试命令。",
                nextStep: "先在本地批准这个命令，或改成白名单内的构建/测试命令。"
            )
        default:
            return nil
        }
    }

    private static func governanceExplanation(
        policyReason: String
    ) -> XTGuardrailMessage {
        switch true {
        case policyReason.contains("repo_write"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许写文件。",
                nextStep: executionTierNextStep(
                    minimumTier: .a2RepoAuto,
                    action: "写文件"
                )
            )
        case policyReason.contains("repo_delete_move"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许删除、移动或重命名路径。",
                nextStep: executionTierNextStep(
                    minimumTier: .a2RepoAuto,
                    action: "删除、移动或重命名路径"
                )
            )
        case policyReason.contains("repo_build_test"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许运行构建或测试命令。",
                nextStep: executionTierNextStep(
                    minimumTier: .a2RepoAuto,
                    action: "运行构建或测试命令"
                )
            )
        case policyReason.contains("repo_build"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许运行构建命令。",
                nextStep: executionTierNextStep(
                    minimumTier: .a2RepoAuto,
                    action: "运行受治理的构建命令"
                )
            )
        case policyReason.contains("repo_test"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许运行测试命令。",
                nextStep: executionTierNextStep(
                    minimumTier: .a2RepoAuto,
                    action: "运行受治理的测试命令"
                )
            )
        case policyReason.contains("git_apply"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许应用补丁。",
                nextStep: executionTierNextStep(
                    minimumTier: .a2RepoAuto,
                    action: "应用补丁"
                )
            )
        case policyReason.contains("git_commit"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许创建 Git 提交。",
                nextStep: executionTierNextStep(
                    minimumTier: .a3DeliverAuto,
                    action: "创建提交"
                )
            )
        case policyReason.contains("git_push"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许 Git 推送。",
                nextStep: executionTierNextStep(
                    minimumTier: .a4OpenClaw,
                    action: "向远端推送"
                )
            )
        case policyReason.contains("pr_create"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许创建 Pull Request。",
                nextStep: executionTierNextStep(
                    minimumTier: .a3DeliverAuto,
                    action: "创建 Pull Request"
                )
            )
        case policyReason.contains("ci_read"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许读取远端 CI 状态。",
                nextStep: executionTierNextStep(
                    minimumTier: .a3DeliverAuto,
                    action: "读取远端 CI 状态"
                )
            )
        case policyReason.contains("ci_trigger"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许触发 CI。",
                nextStep: executionTierNextStep(
                    minimumTier: .a4OpenClaw,
                    action: "触发 CI 工作流"
                )
            )
        case policyReason.contains("managed_processes"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许受治理的后台进程。",
                nextStep: executionTierNextStep(
                    minimumTier: .a2RepoAuto,
                    action: "启动、查看或停止受治理进程"
                )
            )
        case policyReason.contains("process_autorestart"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许进程自动重启。",
                nextStep: executionTierNextStep(
                    minimumTier: .a3DeliverAuto,
                    action: "启用 restart_on_exit"
                )
            )
        case policyReason.contains("browser_runtime"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许浏览器自动化。",
                nextStep: executionTierNextStep(
                    minimumTier: .a4OpenClaw,
                    action: "使用浏览器自动化"
                )
            )
        case policyReason.contains("device_tools"):
            return XTGuardrailMessage(
                summary: "当前项目执行档位不允许设备级工具。",
                nextStep: executionTierNextStep(
                    minimumTier: .a4OpenClaw,
                    action: "使用设备权限"
                )
            )
        default:
            return XTGuardrailMessage(
                summary: "当前执行档位拦下了这个动作。",
                nextStep: executionTierNextStep(
                    minimumTier: recommendedExecutionTier(for: policyReason),
                    action: "重试这个动作"
                )
            )
        }
    }

    private static func runtimeSurfaceExplanation(
        policyReason: String
    ) -> XTGuardrailMessage {
        if let clamp = xtProjectGovernanceClampExplanation(
            policyReason: policyReason,
            style: .uiChinese
        ) {
            return XTGuardrailMessage(
                summary: clamp.summary,
                nextStep: clamp.nextStep
            )
        }

        switch true {
        case policyReason.contains("browser_runtime"):
            return XTGuardrailMessage(
                summary: "当前运行面不允许浏览器自动化。",
                nextStep: "恢复到允许浏览器自动化的运行面，或等待限制解除。"
            )
        case policyReason.contains("device_tools"),
             policyReason.contains("autonomy_mode=guided"),
             policyReason.contains("runtime_surface_effective=guided"),
             policyReason.contains("runtime_surface=guided"):
            return XTGuardrailMessage(
                summary: "当前运行面仍然关闭了设备级动作。",
                nextStep: "恢复完整运行面，或等待限制解除。"
            )
        default:
            return XTGuardrailMessage(
                summary: "当前运行面拦下了这个动作。",
                nextStep: "调整运行面，或等待策略限制解除。"
            )
        }
    }

    private static func executionTierNextStep(
        minimumTier: AXProjectExecutionTier,
        action: String
    ) -> String {
        let cleanedAction = action.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = cleanedAction.isEmpty ? "继续这个动作" : cleanedAction
        return "打开项目设置 -> 执行档位，把档位提升到 \(minimumTier.displayName) 或更高后，再\(suffix)。"
    }

    private static func executionTierHelpText(
        minimumTier: AXProjectExecutionTier
    ) -> String {
        "打开项目设置 -> 执行档位，查看当前最低要求。这个动作至少需要 \(minimumTier.displayName)。"
    }

    private static func recommendedExecutionTier(
        for policyReason: String
    ) -> AXProjectExecutionTier {
        switch true {
        case policyReason.contains("git_push"),
             policyReason.contains("ci_trigger"),
             policyReason.contains("browser_runtime"),
             policyReason.contains("device_tools"):
            return .a4OpenClaw
        case policyReason.contains("git_commit"),
             policyReason.contains("pr_create"),
             policyReason.contains("ci_read"),
             policyReason.contains("process_autorestart"):
            return .a3DeliverAuto
        default:
            return .a2RepoAuto
        }
    }

    private static func preferredFallback(
        summary: String,
        detail: String,
        denyCode: String
    ) -> String? {
        let candidates = [summary, detail]
        for raw in candidates {
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            if !looksLikeTechnicalPolicyText(cleaned, denyCode: denyCode) {
                return cleaned
            }
        }
        return nil
    }

    private static func looksLikeTechnicalPolicyText(
        _ text: String,
        denyCode: String
    ) -> Bool {
        let lower = normalized(text)
        let denyToken = normalized(denyCode)
        if !denyToken.isEmpty && lower == denyToken {
            return true
        }

        let technicalTokens = [
            "project governance blocks",
            "runtime surface policy blocks",
            "autonomy policy blocks",
            "project tool policy blocks",
            "under execution tier",
            "configured=",
            "effective=",
            "payload.",
            "grant_required",
            "tool_not_allowed",
            "required device tool group",
            "group:device_automation",
            "workspace binding hash",
            "macos permissions required",
            "governed allowlist"
        ]
        return technicalTokens.contains(where: { lower.contains($0) })
    }

    private static func normalizedToolLabel(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "这个动作" : cleaned
    }

    private static func targetClause(_ rawTarget: String?) -> String {
        let cleaned = rawTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleaned.isEmpty else { return "" }

        let lower = cleaned.lowercased()
        let descriptivePrefixes = ["query ", "path ", "selector ", "command ", "action "]
        if descriptivePrefixes.contains(where: { lower.hasPrefix($0) }) {
            return "（\(cleaned)）"
        }
        return "（\(cleaned)）"
    }

    private static func toolLabel(for tool: ToolName) -> String {
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
            return "列出目录"
        case .search:
            return "搜索"
        case .run_command:
            return "运行命令"
        case .process_start:
            return "启动受治理进程"
        case .process_status:
            return "查看受治理进程状态"
        case .process_logs:
            return "读取受治理进程日志"
        case .process_stop:
            return "停止受治理进程"
        case .git_status:
            return "git status"
        case .git_diff:
            return "git diff"
        case .git_commit:
            return "Git 提交"
        case .git_push:
            return "Git 推送"
        case .git_apply_check:
            return "校验补丁"
        case .git_apply:
            return "应用补丁"
        case .pr_create:
            return "创建 Pull Request"
        case .ci_read:
            return "读取 CI 状态"
        case .ci_trigger:
            return "触发 CI"
        case .session_list:
            return "查看会话列表"
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
            return "UI 引导步骤"
        case .deviceClipboardRead:
            return "读取剪贴板"
        case .deviceClipboardWrite:
            return "写入剪贴板"
        case .deviceScreenCapture:
            return "屏幕截图"
        case .deviceBrowserControl:
            return "浏览器自动化"
        case .deviceAppleScript:
            return "执行 AppleScript"
        case .need_network:
            return "网络访问"
        case .bridge_status:
            return "检查桥接状态"
        case .skills_search:
            return "搜索技能"
        case .summarize:
            return "总结内容"
        case .supervisorVoicePlayback:
            return "Supervisor 语音播放"
        case .web_fetch:
            return "抓取网页"
        case .web_search:
            return "网页搜索"
        case .browser_read:
            return "浏览器读取"
        }
    }

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func int(_ value: JSONValue?) -> Int? {
        switch value {
        case .number(let number):
            return Int(number.rounded())
        case .string(let text):
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(cleaned)
        default:
            return nil
        }
    }
}
