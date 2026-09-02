import Foundation

extension SupervisorManager {
    func heartbeatGovernedReviewSummaryLine(
        project: AXProjectEntry,
        candidate: SupervisorHeartbeatReviewCandidate
    ) -> String {
        let cause = capped(
            heartbeatGovernedReviewCauseLabel(candidate: candidate),
            maxChars: 40
        )
        return "• \(project.displayName)：已排队\(heartbeatGovernedReviewLevelLabel(candidate.reviewLevel))（\(heartbeatGovernedReviewRunKindLabel(candidate.runKind)) · \(cause)）"
    }

    func heartbeatGovernedReviewContentLines(
        _ signal: HeartbeatGovernedReviewSignal
    ) -> [String] {
        ([signal.summaryLine, signal.detailLine] + [signal.projectMemoryStatusLine].compactMap { $0 })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func heartbeatGovernedReviewDetailLine(
        candidate: SupervisorHeartbeatReviewCandidate,
        portfolioCard: SupervisorPortfolioProjectCard? = nil
    ) -> String {
        var lines = [
            "• 依据：\(capped(supervisorGovernedReviewGovernanceReason(candidate: candidate), maxChars: 120))"
        ]
        if let priorityReason = heartbeatPortfolioPriorityReasonLine(
            card: portfolioCard,
            lead: "为什么先看"
        ) {
            lines.append("• \(priorityReason)")
        }
        return lines.joined(separator: "\n")
    }

    func heartbeatGovernedReviewProjectMemoryTokenLine(
        from artifact: XTHeartbeatMemoryProjectionArtifact?
    ) -> String? {
        guard let context = artifact?.rawPayload.projectMemoryContext else { return nil }

        let source = heartbeatGovernedReviewTrimmedToken(context.diagnosticsSource)
        var parts: [String] = []
        if !source.isEmpty {
            parts.append("project_memory_truth_source=\(source)")
        }
        if let effectiveResolution = context.effectiveResolution {
            let effectiveDepth = heartbeatGovernedReviewTrimmedToken(effectiveResolution.effectiveDepth)
            if !effectiveDepth.isEmpty {
                parts.append("project_memory_truth_effective_depth=\(effectiveDepth)")
            }
            let trigger = heartbeatGovernedReviewTrimmedToken(effectiveResolution.trigger)
            if !trigger.isEmpty {
                parts.append("project_memory_truth_trigger=\(trigger)")
            }
            let servingObjects = effectiveResolution.selectedServingObjects
                .map(heartbeatGovernedReviewTrimmedToken)
                .filter { !$0.isEmpty }
            if !servingObjects.isEmpty {
                parts.append(
                    "project_memory_truth_serving_objects=\(servingObjects.prefix(3).joined(separator: ","))"
                )
            }
        }
        parts.append(
            "project_memory_truth_heartbeat_digest_present=\(context.heartbeatDigestWorkingSetPresent)"
        )
        let visibility = heartbeatGovernedReviewTrimmedToken(context.heartbeatDigestVisibility)
        if !visibility.isEmpty {
            parts.append("project_memory_truth_heartbeat_digest_visibility=\(visibility)")
        }
        let digestReasonCodes = context.heartbeatDigestReasonCodes
            .map(heartbeatGovernedReviewTrimmedToken)
            .filter { !$0.isEmpty }
        if !digestReasonCodes.isEmpty {
            parts.append(
                "project_memory_truth_heartbeat_digest_reason_codes=\(digestReasonCodes.prefix(3).joined(separator: ","))"
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    func heartbeatGovernedReviewProjectMemoryStatusLine(
        from artifact: XTHeartbeatMemoryProjectionArtifact?
    ) -> String? {
        guard let context = artifact?.rawPayload.projectMemoryContext else { return nil }

        let source = heartbeatGovernedReviewTrimmedToken(context.diagnosticsSource)
        let sourceText: String
        switch source {
        case "latest_coder_usage":
            sourceText = "Project AI 最近一轮 memory truth 来自 latest coder usage"
        case "config_only":
            sourceText = "当前还只有 config-only baseline，最近一轮 coder usage 尚未回写"
        case "":
            sourceText = "Project AI 最近一轮 memory truth 尚不明确"
        default:
            sourceText = "Project AI 最近一轮 memory truth 来自 \(source)"
        }

        var detailParts: [String] = []
        if let effectiveResolution = context.effectiveResolution {
            let effectiveDepth = heartbeatGovernedReviewTrimmedToken(effectiveResolution.effectiveDepth)
            if !effectiveDepth.isEmpty {
                detailParts.append("effective depth=\(effectiveDepth)")
            }
            let trigger = heartbeatGovernedReviewTrimmedToken(effectiveResolution.trigger)
            if !trigger.isEmpty {
                detailParts.append("触发原因：\(XTProjectMemoryTriggerPresentation.annotated(trigger))")
            }
            let servingObjects = effectiveResolution.selectedServingObjects
                .map(heartbeatGovernedReviewTrimmedToken)
                .filter { !$0.isEmpty }
            if !servingObjects.isEmpty {
                detailParts.append("serving=\(servingObjects.prefix(3).joined(separator: ", "))")
            }
        }
        let visibility = heartbeatGovernedReviewTrimmedToken(context.heartbeatDigestVisibility)
        if context.heartbeatDigestWorkingSetPresent {
            detailParts.append("heartbeat digest 已在 Project AI working set 中")
        } else if !visibility.isEmpty {
            detailParts.append("heartbeat digest 尚未进入 Project AI working set（visibility=\(visibility)）")
        } else {
            detailParts.append("heartbeat digest 尚未进入 Project AI working set")
        }

        return "• 记忆供给：\(sourceText)\(detailParts.isEmpty ? "。" : "，\(detailParts.joined(separator: "；"))。")"
    }

    func heartbeatGovernedReviewProjectMemoryMetadataText(
        from artifact: XTHeartbeatMemoryProjectionArtifact?
    ) -> String? {
        guard let context = artifact?.rawPayload.projectMemoryContext else { return nil }

        var parts: [String] = []
        switch heartbeatGovernedReviewTrimmedToken(context.diagnosticsSource) {
        case "latest_coder_usage":
            parts.append("latest coder usage")
        case "config_only":
            parts.append("config baseline")
        case let source where !source.isEmpty:
            parts.append(source)
        default:
            break
        }

        if let effectiveDepth = context.effectiveResolution.map({ heartbeatGovernedReviewTrimmedToken($0.effectiveDepth) }),
           !effectiveDepth.isEmpty {
            parts.append("depth=\(effectiveDepth)")
        }
        if let trigger = context.effectiveResolution.map({ heartbeatGovernedReviewTrimmedToken($0.trigger) }),
           !trigger.isEmpty {
            parts.append("trigger=\(XTProjectMemoryTriggerPresentation.label(trigger))")
        }

        parts.append(context.heartbeatDigestWorkingSetPresent ? "digest已进project" : "digest未进project")
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func heartbeatGovernedReviewTrimmedToken(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func heartbeatGovernedReviewCauseLabel(
        candidate: SupervisorHeartbeatReviewCandidate
    ) -> String {
        let normalizedReason = candidate.policyReason
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedReason.contains("heartbeat_anomaly=weak_done_claim") {
            return "完成声明证据偏弱"
        }
        if normalizedReason.contains("heartbeat_anomaly=weak_blocker") {
            return "blocker 解释偏弱"
        }
        if normalizedReason.contains("heartbeat_anomaly=missing_heartbeat") {
            return "心跳缺失"
        }
        if normalizedReason.contains("heartbeat_anomaly=stale_repeat") {
            return "长时间重复无新进展"
        }
        if normalizedReason.contains("heartbeat_anomaly=hollow_progress") {
            return "进展声明证据偏弱"
        }
        if normalizedReason.contains("heartbeat_anomaly=queue_stall") {
            return "队列卡住"
        }
        if normalizedReason.contains("heartbeat_anomaly=route_flaky") {
            return "模型路由抖动"
        }
        if normalizedReason.contains("heartbeat_anomaly=drift_suspected") {
            return "疑似偏航"
        }
        if normalizedReason.contains("heartbeat_quality_degraded") {
            return "heartbeat 质量下降"
        }
        if normalizedReason.contains("event_trigger=blocker_detected") {
            return "检测到 blocker"
        }

        switch candidate.trigger {
        case .periodicHeartbeat:
            return "heartbeat 周期到点"
        case .periodicPulse:
            return "周期 pulse 到点"
        case .failureStreak:
            return "连续失败"
        case .noProgressWindow:
            return "长时间无进展"
        case .blockerDetected:
            return "检测到 blocker"
        case .planDrift:
            return "计划出现偏航"
        case .preHighRiskAction:
            return "高风险动作前复核"
        case .preDoneSummary:
            return "完成前复核"
        case .manualRequest:
            return "手动请求"
        case .userOverride:
            return "显式 override"
        }
    }

    func heartbeatGovernedReviewOperationHint(
        _ signal: HeartbeatGovernedReviewSignal
    ) -> String {
        let levelLabel = heartbeatGovernedReviewLevelLabel(signal.reviewLevel)
        switch signal.reviewLevel {
        case .r1Pulse:
            return "点开这条提醒会直接打开项目，查看为什么这次 \(levelLabel) 已经被系统排队。"
        case .r2Strategic:
            return "点开这条提醒会直接打开项目，查看这次 \(levelLabel) 的触发原因，并等待 safe point guidance。"
        case .r3Rescue:
            return "点开这条提醒会直接打开项目，优先关注这次 \(levelLabel) 的触发原因，并准备接管或重规划。"
        }
    }

    func heartbeatGovernedReviewNotificationNextStep(
        _ signal: HeartbeatGovernedReviewSignal
    ) -> String {
        switch signal.reviewLevel {
        case .r1Pulse:
            return "打开项目并查看这次脉冲审查为何被排队。"
        case .r2Strategic:
            return "打开项目并查看这次治理审查为何被排队。"
        case .r3Rescue:
            return "打开项目并优先处理这次救援审查。"
        }
    }

    func heartbeatGovernedReviewDigestWhyImportantText(
        _ signal: HeartbeatGovernedReviewSignal
    ) -> String {
        let base = "这说明系统判断需要额外复盘，避免在无进展或高风险时继续盲跑。"
        let memoryLine = signal.projectMemoryStatusLine ?? ""
        let metadata = signal.projectMemoryMetadataText ?? ""

        if memoryLine.contains("latest coder usage") || metadata.contains("latest coder usage") {
            return "\(base) 这次治理判断已对齐到 Project AI 最近一轮 latest coder usage memory truth，避免 Supervisor 和 coder 各看各的。"
        }
        if memoryLine.contains("config-only baseline") || metadata.contains("config baseline") {
            return "\(base) 当前还只有 config-only baseline，后续仍要等 recent coder usage 回写 memory truth，避免把配置基线误当成最新执行真相。"
        }
        if !memoryLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !metadata.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(base) 当前治理判断已附带 Project AI 的记忆供给真相，不是只按静态配置盲审。"
        }
        return base
    }

    func heartbeatGovernedReviewDigestNextStepText(
        _ signal: HeartbeatGovernedReviewSignal
    ) -> String {
        let base = heartbeatGovernedReviewNotificationNextStep(signal)
        let memoryLine = signal.projectMemoryStatusLine ?? ""
        let metadata = signal.projectMemoryMetadataText ?? ""
        if memoryLine.contains("heartbeat digest 已在 Project AI working set 中")
            || metadata.contains("digest已进project") {
            return "\(base) 系统会沿这份 memory truth 在 safe point 注入 guidance，不再额外重复灌入同一份 heartbeat digest。"
        }
        if !memoryLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !metadata.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(base) 系统会继续沿当前治理链把 heartbeat digest 补进 Project AI working set，而不是绕过既有 review / gate 边界。"
        }
        return base
    }

    func heartbeatGovernedReviewVoicePresentation(
        _ signal: HeartbeatGovernedReviewSignal
    ) -> SupervisorGovernanceSignalVoicePresentation {
        let headlineText: String
        switch signal.reviewLevel {
        case .r1Pulse:
            headlineText = "治理脉冲已排队"
        case .r2Strategic:
            headlineText = "治理审查已排队"
        case .r3Rescue:
            headlineText = "救援审查已排队"
        }

        let detailText = "\(signal.projectName) 因为\(signal.causeLabel)，系统已经排队\(heartbeatGovernedReviewLevelLabel(signal.reviewLevel))。"
        let metadataText = ([heartbeatGovernedReviewRunKindLabel(signal.runKind), signal.causeLabel] + [signal.projectMemoryMetadataText].compactMap { $0 })
            .joined(separator: " · ")
        let actionText: String
        switch signal.reviewLevel {
        case .r1Pulse:
            actionText = "打开项目并查看这次脉冲审查"
        case .r2Strategic:
            actionText = "打开项目并查看这次治理审查"
        case .r3Rescue:
            actionText = "打开项目并优先处理这次救援审查"
        }

        return SupervisorGovernanceSignalVoicePresentation(
            trigger: signal.reviewLevel == .r3Rescue ? .blocked : .completed,
            headlineText: headlineText,
            detailText: detailText,
            metadataText: metadataText,
            actionText: actionText,
            fingerprint: [
                signal.projectId,
                signal.trigger.rawValue,
                signal.runKind.rawValue,
                signal.reviewLevel.rawValue,
                signal.causeLabel,
                signal.projectMemoryMetadataText ?? ""
            ].joined(separator: "|")
        )
    }
}
