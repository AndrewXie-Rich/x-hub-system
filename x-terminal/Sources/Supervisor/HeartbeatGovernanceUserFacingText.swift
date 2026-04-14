import Foundation

enum HeartbeatGovernanceUserFacingText {
    static func qualityBandText(_ raw: String?) -> String {
        switch normalizedToken(raw) {
        case HeartbeatQualityBand.strong.rawValue:
            return "强"
        case HeartbeatQualityBand.usable.rawValue:
            return "可用"
        case HeartbeatQualityBand.weak.rawValue:
            return "偏弱"
        case HeartbeatQualityBand.hollow.rawValue:
            return "空转"
        default:
            return humanizedMeaningfulText(raw) ?? "未回报"
        }
    }

    static func projectPhaseText(_ raw: String?) -> String {
        switch normalizedToken(raw) {
        case HeartbeatProjectPhase.explore.rawValue:
            return "探索"
        case HeartbeatProjectPhase.plan.rawValue:
            return "规划"
        case HeartbeatProjectPhase.build.rawValue:
            return "构建"
        case HeartbeatProjectPhase.verify.rawValue:
            return "验证"
        case HeartbeatProjectPhase.release.rawValue:
            return "发布"
        default:
            return humanizedMeaningfulText(raw) ?? "未回报"
        }
    }

    static func executionStatusText(_ raw: String?) -> String {
        switch normalizedToken(raw) {
        case HeartbeatExecutionStatus.active.rawValue:
            return "推进中"
        case HeartbeatExecutionStatus.blocked.rawValue:
            return "已阻塞"
        case HeartbeatExecutionStatus.stalled.rawValue:
            return "停滞"
        case HeartbeatExecutionStatus.doneCandidate.rawValue:
            return "完成候选"
        default:
            return humanizedMeaningfulText(raw) ?? "未回报"
        }
    }

    static func riskTierText(_ raw: String?) -> String {
        switch normalizedToken(raw) {
        case HeartbeatRiskTier.low.rawValue:
            return "低"
        case HeartbeatRiskTier.medium.rawValue:
            return "中"
        case HeartbeatRiskTier.high.rawValue:
            return "高"
        case HeartbeatRiskTier.critical.rawValue:
            return "极高"
        default:
            return humanizedMeaningfulText(raw) ?? "未回报"
        }
    }

    static func cadenceDimensionText(_ raw: String?) -> String {
        switch normalizedToken(raw) {
        case SupervisorCadenceDimension.progressHeartbeat.rawValue:
            return "进度心跳"
        case SupervisorCadenceDimension.reviewPulse.rawValue:
            return "脉冲复盘"
        case SupervisorCadenceDimension.brainstormReview.rawValue:
            return "无进展复盘"
        default:
            return humanizedMeaningfulText(raw) ?? "未回报"
        }
    }

    static func digestVisibilityText(_ raw: String?) -> String? {
        switch normalizedToken(raw) {
        case XTHeartbeatDigestVisibilityDecision.shown.rawValue:
            return "显示给用户"
        case XTHeartbeatDigestVisibilityDecision.suppressed.rawValue:
            return "当前压制"
        default:
            return humanizedMeaningfulText(raw)
        }
    }

    static func cadenceReasonText(_ raw: String?) -> String? {
        switch normalizedToken(raw) {
        case "preserve_current_runtime_cadence":
            return "沿用当前运行时治理值"
        case "configured_equals_recommended":
            return "当前配置已经等于协议建议值"
        case "clamped_by_fail_closed_governance":
            return "因 fail-closed 治理收束而降级"
        case "clamped_by_effective_governance_bundle":
            return "运行时有效治理先做了收束"
        case "clamped_to_protocol_recommended":
            return "按当前 A/S 与治理态收紧到协议建议值"
        case "adjusted_for_project_phase_explore":
            return "因项目处于 explore 阶段而放松到更合适的观察节奏"
        case "adjusted_for_project_phase_plan":
            return "因项目处于 plan 阶段而放松到更合适的规划节奏"
        case "adjusted_for_project_phase_build":
            return "因项目进入 build 阶段而收紧到更密的推进节奏"
        case "adjusted_for_project_phase_verify", "adjusted_for_verification_phase":
            return "因项目进入 verify 阶段而收紧到更密的验证节奏"
        case "adjusted_for_project_phase_release":
            return "因项目进入 release 阶段而收紧到更密的交付节奏"
        case "tightened_for_low_execution_confidence":
            return "因执行把握偏弱或 heartbeat 质量偏弱而进一步收紧"
        case "tightened_for_rescue_or_high_anomaly":
            return "因高严重度异常或救援态而进一步收紧"
        case "tightened_for_high_project_risk":
            return "因项目风险升高而进一步收紧"
        case "tightened_for_critical_project_risk":
            return "因项目处于 critical 风险而进一步收紧"
        case "tightened_for_blocked_execution_status":
            return "因执行已阻塞而进一步收紧"
        case "tightened_for_stalled_execution_status":
            return "因执行出现空转或停滞而进一步收紧"
        case "tightened_for_done_candidate_status":
            return "因进入 done candidate 而进一步收紧完成前复核"
        case "disabled_by_review_policy_off":
            return "当前策略已关闭这条节奏"
        case "disabled_by_review_policy_milestone_only":
            return "里程碑策略下不启用这条节奏"
        case "disabled_by_review_policy_periodic":
            return "周期策略下不启用脑暴复盘"
        case "cadence_disabled":
            return "当前未启用"
        case "awaiting_first_heartbeat":
            return "还没有首个 heartbeat 基线"
        case "awaiting_first_pulse_window":
            return "等待首个脉冲窗口走完"
        case "awaiting_progress_observation":
            return "还没有进展观察基线"
        case "waiting_for_heartbeat_window":
            return "当前 heartbeat 窗口尚未走完"
        case "waiting_for_pulse_window":
            return "当前脉冲窗口尚未走完"
        case "waiting_for_no_progress_window", "waiting_for_brainstorm_window":
            return "当前无进展窗口尚未走完"
        case "waiting_for_review_window":
            return "当前 review 窗口尚未走完"
        case "heartbeat_window_elapsed":
            return "heartbeat 窗口已到"
        case "pulse_review_window_elapsed":
            return "脉冲复盘窗口已到"
        case "no_progress_window_reached":
            return "无进展窗口已到"
        default:
            return humanizedMeaningfulText(raw)
        }
    }

    static func cadenceReasonTexts(_ values: [String]) -> [String] {
        var texts: [String] = []
        texts.reserveCapacity(values.count)
        for value in values {
            if let text = cadenceReasonText(value) {
                texts.append(text)
            }
        }
        return orderedUnique(texts)
    }

    static func cadenceReasonSummary(
        _ values: [String],
        empty: String = "无"
    ) -> String {
        let texts = cadenceReasonTexts(values)
        return texts.isEmpty ? empty : texts.joined(separator: "、")
    }

    static func digestReasonText(_ raw: String?) -> String? {
        switch normalizedToken(raw) {
        case "blocker_present":
            return "当前存在 blocker"
        case HeartbeatAnomalyType.weakDoneClaim.rawValue:
            return "完成声明证据偏弱"
        case HeartbeatAnomalyType.missingHeartbeat.rawValue:
            return "最近 heartbeat 超出预期窗口"
        case "open_anomalies_present":
            return "存在未关闭异常"
        case "review_candidate_active":
            return "当前有待执行复盘候选"
        case "next_review_window_active":
            return "当前 review 窗口已到"
        case "recovery_decision_active":
            return "当前已有恢复或补救决策"
        case "risk_high":
            return "当前项目风险偏高"
        case "quality_weak":
            return "heartbeat 质量偏弱"
        case "done_candidate_status":
            return "项目已进入 done candidate"
        case "project_memory_attention":
            return "Project memory 需要关注"
        case "stable_runtime_update_suppressed":
            return "当前只是稳定运行更新，暂不打扰用户"
        case "heartbeat_truth_sparse":
            return "当前 heartbeat 真相仍偏稀疏"
        default:
            return humanizedMeaningfulText(raw)
        }
    }

    static func digestReasonTexts(_ values: [String]) -> [String] {
        var texts: [String] = []
        texts.reserveCapacity(values.count)
        for value in values {
            if let text = digestReasonText(value) {
                texts.append(text)
            }
        }
        return orderedUnique(texts)
    }

    static func digestReasonSummary(
        _ values: [String],
        empty: String = "无"
    ) -> String {
        let texts = digestReasonTexts(values)
        return texts.isEmpty ? empty : texts.joined(separator: "、")
    }

    static func weakReasonText(_ raw: String?) -> String? {
        switch normalizedToken(raw) {
        case "freshness_low":
            return "新鲜度偏低"
        case "delta_low":
            return "变化量偏低"
        case "evidence_weak":
            return "证据偏弱"
        case "blocker_unclear":
            return "blocker 描述不清"
        case "next_action_generic":
            return "下一步过于泛化"
        case "execution_vitality_low":
            return "执行活性偏低"
        case "completion_confidence_low":
            return "完成把握偏低"
        case "project_memory_attention":
            return "Project memory 需要关注"
        default:
            return humanizedMeaningfulText(raw)
        }
    }

    static func weakReasonTexts(_ values: [String]) -> [String] {
        var texts: [String] = []
        texts.reserveCapacity(values.count)
        for value in values {
            if let text = weakReasonText(value) {
                texts.append(text)
            }
        }
        return orderedUnique(texts)
    }

    static func weakReasonSummary(
        _ values: [String],
        empty: String = "无"
    ) -> String {
        let texts = weakReasonTexts(values)
        return texts.isEmpty ? empty : texts.joined(separator: "、")
    }

    static func anomalyTypeText(_ raw: String?) -> String? {
        switch normalizedToken(raw) {
        case HeartbeatAnomalyType.missingHeartbeat.rawValue:
            return "缺失 heartbeat"
        case HeartbeatAnomalyType.staleRepeat.rawValue:
            return "重复心跳 / 无新进展"
        case HeartbeatAnomalyType.hollowProgress.rawValue:
            return "空转推进"
        case HeartbeatAnomalyType.queueStall.rawValue:
            return "队列停滞"
        case HeartbeatAnomalyType.weakBlocker.rawValue:
            return "弱 blocker"
        case HeartbeatAnomalyType.weakDoneClaim.rawValue:
            return "完成声明证据偏弱"
        case HeartbeatAnomalyType.routeFlaky.rawValue:
            return "route 波动"
        case HeartbeatAnomalyType.silentLane.rawValue:
            return "lane 静默"
        case HeartbeatAnomalyType.driftSuspected.rawValue:
            return "疑似偏航"
        default:
            return humanizedMeaningfulText(raw)
        }
    }

    static func anomalyTypeTexts(_ values: [String]) -> [String] {
        var texts: [String] = []
        texts.reserveCapacity(values.count)
        for value in values {
            if let text = anomalyTypeText(value) {
                texts.append(text)
            }
        }
        return orderedUnique(texts)
    }

    static func anomalyTypeSummary(
        _ values: [String],
        empty: String = "无"
    ) -> String {
        let texts = anomalyTypeTexts(values)
        return texts.isEmpty ? empty : texts.joined(separator: "、")
    }

    private static func normalizedMeaningfulValue(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch trimmed.lowercased() {
        case "unknown", "none", "(none)", "n/a":
            return nil
        default:
            return trimmed
        }
    }

    private static func normalizedToken(_ raw: String?) -> String {
        normalizedMeaningfulValue(raw)?.lowercased() ?? "unknown"
    }

    private static func humanizedMeaningfulText(_ raw: String?) -> String? {
        guard let value = normalizedMeaningfulValue(raw) else { return nil }
        return value.replacingOccurrences(of: "_", with: " ")
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }
}
