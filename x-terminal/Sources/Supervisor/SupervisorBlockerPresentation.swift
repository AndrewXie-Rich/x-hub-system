import Foundation

enum SupervisorBlockerPresentation {
    static func displayText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = UITroubleshootKnowledgeBase.normalizedFailureCode(trimmed)
        guard normalized != "none" else { return nil }
        return label(trimmed)
    }

    static func label(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }

        let segments = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if segments.count > 1 {
            return segments.map(labelSingle).joined(separator: " | ")
        }
        return labelSingle(trimmed)
    }

    private static func labelSingle(_ trimmed: String) -> String {
        let normalized = UITroubleshootKnowledgeBase.normalizedFailureCode(trimmed)
        switch normalized {
        case "none":
            return "none"
        case "authorization_required":
            return "授权未完成（authorization_required）"
        case "authorization_pending":
            return "授权待处理（authorization_pending）"
        case "grant_required":
            return "Hub 授权未完成（grant_required）"
        case "grant_pending":
            return "Hub 授权待处理（grant_pending）"
        case "local_approval_required":
            return "本地审批未完成（local_approval_required）"
        case "permission_denied":
            return "权限链路拒绝（permission_denied）"
        case "forbidden":
            return "访问被禁止（forbidden）"
        case "model_not_ready":
            return "模型或 provider 未就绪（model_not_ready）"
        case "connector_scope_blocked":
            return "远端导出或 connector scope 被阻断（connector_scope_blocked）"
        case "paid_model_access_blocked":
            return "付费模型资格或预算未放行（paid_model_access_blocked）"
        case "hub_connectivity_blocked":
            return "Hub 连接或配对事实未恢复（hub_connectivity_blocked）"
        case "scope_expansion":
            return "请求超出已验证范围（scope_expansion）"
        case "diagnostic_required":
            return "缺少诊断证据（diagnostic_required）"
        case "memory_context_underfed":
            return "strategic memory 供给不足（memory_context_underfed）"
        case "review_delivery":
            return "交付冻结仍待复核（review_delivery）"
        case "directed_resume_available":
            return "已有定向续推（directed_resume_available）"
        case "legacy_supervisor_runtime_unavailable":
            return "Supervisor 执行运行时当前不可用（legacy_supervisor_runtime_unavailable）"
        case "guarded_one_shot_split_plan_missing":
            return "guarded one-shot 缺少已准备的拆分方案（guarded_one_shot_split_plan_missing）"
        case "prompt_contract_confirmation_failed":
            return "拆分方案确认失败，当前不能继续启动（prompt_contract_confirmation_failed）"
        case "prompt_contract_blocked":
            return "拆分方案校验未通过，当前不能继续启动（prompt_contract_blocked）"
        case "lane_launch_execution_failed":
            return "lane 启动执行失败（lane_launch_execution_failed）"
        case "hub_ingress_source_unsupported":
            return "该远程来源暂未接入 XT（hub_ingress_source_unsupported）"
        case "hub_ingress_recipe_unavailable":
            return "项目缺少可运行的自动化配方（hub_ingress_recipe_unavailable）"
        case "hub_ingress_trigger_unresolved":
            return "入口未映射到已声明 trigger（hub_ingress_trigger_unresolved）"
        case "automation_active_run_present":
            return "项目已有进行中的 automation（automation_active_run_present）"
        case "trigger_cooldown_active":
            return "该入口仍在冷却窗口内（trigger_cooldown_active）"
        case "external_trigger_replay_detected":
            return "重复入口已被抑制（external_trigger_replay_detected）"
        case "trigger_id_missing":
            return "trigger 标识缺失（trigger_id_missing）"
        case "external_trigger_dedupe_key_missing":
            return "dedupe key 缺失（external_trigger_dedupe_key_missing）"
        case "trigger_ingress_not_allowed":
            return "该入口未被允许（trigger_ingress_not_allowed）"
        case "trusted_automation_project_not_bound":
            return "项目未绑定到当前设备（trusted_automation_project_not_bound）"
        case "project_context_missing":
            return "项目上下文缺失（project_context_missing）"
        case "xt_command_action_not_supported_yet":
            return "该 XT 指令动作尚未支持（xt_command_action_not_supported_yet）"
        case "active_recipe_missing":
            return "项目缺少可执行自动化配方（active_recipe_missing）"
        default:
            if let userVisible = XTRouteTruthPresentation.userVisibleReasonText(trimmed),
               userVisible != trimmed,
               userVisible != normalized {
                return userVisible
            }
            return trimmed
        }
    }

    static func blockerLine(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = UITroubleshootKnowledgeBase.normalizedFailureCode(trimmed)
        guard normalized != "none" else { return nil }
        return "阻塞：\(label(trimmed))"
    }
}
