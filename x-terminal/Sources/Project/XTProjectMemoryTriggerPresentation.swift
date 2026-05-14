import Foundation

enum XTProjectMemoryTriggerPresentation {
    static func normalized(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func label(_ raw: String?) -> String {
        switch normalized(raw) {
        case "", "none":
            return "暂无"
        case "manual_full_scan_request":
            return "用户要求完整扫描项目上下文"
        case "manual_review_request":
            return "用户要求先做 review / plan 梳理"
        case "manual_request":
            return "用户主动请求治理处理"
        case "resume_from_checkpoint":
            return "本轮按 checkpoint continuity 接续"
        case "restart_recovery":
            return "恢复链需要重新接续当前 run"
        case "retry_execution":
            return "自动重试链继续上次执行"
        case "persistent_blocker":
            return "当前存在结构化 blocker"
        case "verification_gap":
            return "验证状态需要优先处理"
        case "review_guidance_follow_up":
            return "带着 review guidance 跟进执行"
        case "guided_execution":
            return "带着 Supervisor guidance 执行"
        case "execution_step_follow_up":
            return "沿当前执行步骤继续"
        case "evidence_backed_execution":
            return "基于最新执行证据继续"
        case "normal_reply", "normal_execution":
            return "普通项目回复"
        case "config_only_baseline":
            return "仅配置基线"
        case "user_turn":
            return "按当前用户回合响应"
        case "portfolio_reprioritize":
            return "组合级重排优先级"
        case "pre_high_risk_action":
            return "高风险动作前先审查"
        case "heartbeat_periodic_heartbeat_review":
            return "heartbeat 触发周期进度复查"
        case "heartbeat_periodic_pulse_review":
            return "heartbeat 触发周期 pulse review"
        case "heartbeat_failure_streak_review":
            return "heartbeat 触发失败 streak review"
        case "heartbeat_no_progress_review":
            return "heartbeat 触发无进展 review"
        case "heartbeat_blocker_review":
            return "heartbeat 触发 blocker review"
        case "heartbeat_plan_drift_review":
            return "heartbeat 触发 plan drift review"
        case "heartbeat_pre_high_risk_review":
            return "heartbeat 触发高风险前复查"
        case "heartbeat_pre_done_review":
            return "heartbeat 触发完成前复查"
        case "heartbeat_manual_review_request":
            return "heartbeat 接到手动审查请求"
        case "heartbeat_user_override_review":
            return "heartbeat 接到用户覆盖审查"
        case "heartbeat_pulse_review":
            return "heartbeat 执行 pulse review"
        case "heartbeat_brainstorm_review":
            return "heartbeat 执行 brainstorm review"
        case "heartbeat_event_review":
            return "heartbeat 执行事件审查"
        case "heartbeat_manual_review":
            return "heartbeat 执行手动审查"
        case "heartbeat_governance_review", "heartbeat_governance_review_due":
            return "heartbeat 触发治理 review"
        default:
            return XTMemorySourceTruthPresentation.humanizeToken(raw)
        }
    }

    static func annotated(_ raw: String?) -> String {
        let normalized = normalized(raw)
        guard !normalized.isEmpty, normalized != "none" else {
            return "暂无"
        }
        return "\(label(normalized))（\(normalized)）"
    }

    static func detailLine(prefix: String, raw: String?) -> String? {
        let normalized = normalized(raw)
        guard !normalized.isEmpty, normalized != "none" else { return nil }
        return "\(prefix)=\(annotated(normalized))"
    }
}
