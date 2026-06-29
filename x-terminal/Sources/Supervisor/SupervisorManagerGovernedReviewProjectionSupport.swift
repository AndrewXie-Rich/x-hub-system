import Foundation

extension SupervisorManager {
    func heartbeatGovernedReviewLevelLabel(
        _ level: SupervisorReviewLevel
    ) -> String {
        switch level {
        case .r1Pulse:
            return "脉冲审查"
        case .r2Strategic:
            return "战略审查"
        case .r3Rescue:
            return "救援审查"
        }
    }

    func heartbeatGovernedReviewRunKindLabel(
        _ runKind: SupervisorReviewRunKind
    ) -> String {
        switch runKind {
        case .pulse:
            return "周期脉冲"
        case .brainstorm:
            return "无进展复盘"
        case .eventDriven:
            return "事件触发"
        case .manual:
            return "手动请求"
        }
    }

    func projectionGovernedReviewLookupBlob(
        _ projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> String {
        [
            projection.status,
            projection.trigger,
            projection.topline,
            projection.criticalBlocker,
            projection.nextBestAction,
            projection.cardSummary,
            projection.ttsScript.joined(separator: " "),
            projection.evidenceRefs.joined(separator: " ")
        ]
        .map(normalizedLookupKey)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    func projectionLookupContains(
        _ lookupBlob: String,
        tokens: [String]
    ) -> Bool {
        tokens.contains { token in
            let normalized = normalizedLookupKey(token)
            return !normalized.isEmpty && lookupBlob.contains(normalized)
        }
    }

    func projectionLooksLikeGovernedReview(
        _ projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> Bool {
        guard projection.pendingGrantCount == 0 else { return false }
        let lookupBlob = projectionGovernedReviewLookupBlob(projection)
        guard projectionLookupContains(lookupBlob, tokens: [
            "治理审查",
            "战略审查",
            "救援审查",
            "脉冲审查",
            "governed review",
            "governance review",
            "strategic governance review",
            "rescue governance review",
            "pulse governance review",
            "review_level_hint=r1_pulse",
            "review_level_hint=r2_strategic",
            "review_level_hint=r3_rescue"
        ]) else {
            return false
        }

        return projectionLookupContains(lookupBlob, tokens: [
            "已排队",
            "queued",
            "status=queued",
            "attention_required",
            "attention required"
        ])
    }

    func projectionGovernedReviewLevel(
        _ projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> SupervisorReviewLevel? {
        guard projectionLooksLikeGovernedReview(projection) else { return nil }
        let lookupBlob = projectionGovernedReviewLookupBlob(projection)
        if projectionLookupContains(lookupBlob, tokens: [
            "救援审查",
            "r3_rescue",
            "rescue review",
            "rescue governance review"
        ]) {
            return .r3Rescue
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "脉冲审查",
            "r1_pulse",
            "pulse review",
            "pulse governance review"
        ]) {
            return .r1Pulse
        }
        return .r2Strategic
    }

    func projectionGovernedReviewRunKindLabel(
        _ projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> String {
        let lookupBlob = projectionGovernedReviewLookupBlob(projection)
        if projectionLookupContains(lookupBlob, tokens: [
            "无进展复盘",
            "brainstorm",
            "no progress",
            "no-progress"
        ]) {
            return "无进展复盘"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "手动请求",
            "manual request",
            "review_run_kind=manual"
        ]) {
            return "手动请求"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "周期脉冲",
            "periodic pulse",
            "pulse cadence",
            "pulse review",
            "review_run_kind=pulse"
        ]) {
            return "周期脉冲"
        }
        return "事件触发"
    }

    func projectionGovernedReviewCauseLabel(
        _ projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> String {
        let lookupBlob = projectionGovernedReviewLookupBlob(projection)
        if projectionLookupContains(lookupBlob, tokens: [
            "完成声明证据偏弱",
            "weak completion evidence",
            "weak_done_claim"
        ]) {
            return "完成声明证据偏弱"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "blocker 解释偏弱",
            "weak blocker evidence",
            "weak_blocker"
        ]) {
            return "blocker 解释偏弱"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "心跳缺失",
            "missing heartbeat",
            "missing_heartbeat"
        ]) {
            return "心跳缺失"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "长时间重复无新进展",
            "repeated stale heartbeat",
            "stale_repeat"
        ]) {
            return "长时间重复无新进展"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "进展声明证据偏弱",
            "weak progress evidence",
            "hollow_progress"
        ]) {
            return "进展声明证据偏弱"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "队列卡住",
            "queue stalled",
            "queue_stall"
        ]) {
            return "队列卡住"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "模型路由抖动",
            "model route instability",
            "route_flaky"
        ]) {
            return "模型路由抖动"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "疑似偏航",
            "suspected drift",
            "drift_suspected"
        ]) {
            return "疑似偏航"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "heartbeat 质量下降",
            "degraded heartbeat quality",
            "heartbeat_quality_degraded"
        ]) {
            return "heartbeat 质量下降"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "检测到 blocker",
            "blocker detected",
            "blocker_detected"
        ]) {
            return "检测到 blocker"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "长时间无进展",
            "long no progress",
            "no progress"
        ]) {
            return "长时间无进展"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "高风险动作前复核",
            "pre-high-risk checkpoint",
            "pre_high_risk_action"
        ]) {
            return "高风险动作前复核"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "完成前复核",
            "pre-done verification",
            "pre_done_summary"
        ]) {
            return "完成前复核"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "heartbeat 周期到点",
            "heartbeat cadence due",
            "periodic heartbeat"
        ]) {
            return "heartbeat 周期到点"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "周期 pulse 到点",
            "pulse cadence due",
            "periodic pulse"
        ]) {
            return "周期 pulse 到点"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "连续失败",
            "repeated failures",
            "failure streak"
        ]) {
            return "连续失败"
        }
        if projectionLookupContains(lookupBlob, tokens: [
            "显式 override",
            "explicit override",
            "user override"
        ]) {
            return "显式 override"
        }
        let runKind = projectionGovernedReviewRunKindLabel(projection)
        if runKind == "无进展复盘" {
            return "长时间无进展"
        }
        if runKind == "周期脉冲" {
            return "周期 pulse 到点"
        }
        if runKind == "手动请求" {
            return "手动请求"
        }
        return "治理信号变化"
    }

    func projectionGovernedReviewVoicePresentation(
        from projection: HubIPCClient.SupervisorBriefProjectionSnapshot,
        projectName: String
    ) -> SupervisorGovernanceSignalVoicePresentation? {
        guard let reviewLevel = projectionGovernedReviewLevel(projection) else { return nil }

        let displayProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "当前项目"
            : projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let causeLabel = projectionGovernedReviewCauseLabel(projection)
        let runKindLabel = projectionGovernedReviewRunKindLabel(projection)
        let headlineText: String
        let actionText: String
        let trigger: SupervisorVoiceJobTrigger
        switch reviewLevel {
        case .r1Pulse:
            headlineText = "治理脉冲已排队"
            actionText = "打开项目并查看这次脉冲审查"
            trigger = .completed
        case .r2Strategic:
            headlineText = "治理审查已排队"
            actionText = "打开项目并查看这次治理审查"
            trigger = .completed
        case .r3Rescue:
            headlineText = "救援审查已排队"
            actionText = "打开项目并优先处理这次救援审查"
            trigger = .blocked
        }

        let detailText = "\(displayProjectName) 因为\(causeLabel)，Hub 已排队\(heartbeatGovernedReviewLevelLabel(reviewLevel))。"
        let metadataText = "\(runKindLabel) · \(causeLabel)"
        let fingerprint = [
            projection.projectId,
            projection.projectionId,
            reviewLevel.rawValue,
            runKindLabel,
            causeLabel
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "|")

        return SupervisorGovernanceSignalVoicePresentation(
            trigger: trigger,
            headlineText: headlineText,
            detailText: detailText,
            metadataText: metadataText,
            actionText: actionText,
            fingerprint: fingerprint
        )
    }
}
