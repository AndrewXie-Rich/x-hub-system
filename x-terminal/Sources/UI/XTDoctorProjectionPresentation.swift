import Foundation

struct XTDoctorProjectionSummary: Equatable {
    var title: String
    var lines: [String]
}

private struct XTDoctorProjectAutomationContinuityProjection: Equatable {
    var automationContextSource: String?
    var memorySource: String?
    var memoryFreshness: String?
    var runID: String?
    var runState: String?
    var currentStepTitle: String?
    var currentStepState: String?
    var verificationContract: XTAutomationVerificationContract?
    var retryVerificationContract: XTAutomationVerificationContract?
    var blockerPresent: Bool?
    var retryReasonPresent: Bool?
}

enum XTDoctorRouteTruthPresentation {
    static func summary(projection: AXModelRouteTruthProjection) -> XTDoctorProjectionSummary {
        XTDoctorProjectionSummary(
            title: "这次实际路由",
            lines: [
                configuredRouteLine(projection),
                actualRouteLine(projection),
                fallbackReasonLine(projection),
                routeStateLine(projection),
                denyCodeLine(projection),
                budgetExportPostureLine(projection),
                projectionLine(projection)
            ]
        )
    }

    private static func configuredRouteLine(_ projection: AXModelRouteTruthProjection) -> String {
        let completeness = normalizedToken(projection.completeness)
        let bindingText = observedBindingText(projection.winningBinding)

        if completeness == "partial_counts_only" {
            return summaryLine("你设定的目标", "XT 目前只有事件计数，还没有单次目标路由记录。")
        }

        if completeness.hasPrefix("partial_") || completeness == "unknown" {
            if let bindingText {
                return summaryLine("你设定的目标", "Hub 还没把完整路由记录带下来；XT 目前只拿到结果投影，最近一次可见绑定是 \(bindingText)。")
            }
            return summaryLine("你设定的目标", "Hub 还没把完整路由记录带下来；XT 目前只知道最近一次结果投影。")
        }

        if let bindingText {
            return summaryLine("你设定的目标", bindingText)
        }

        return summaryLine("你设定的目标", "未回报")
    }

    private static func actualRouteLine(_ projection: AXModelRouteTruthProjection) -> String {
        let actualRoute = XTRouteTruthPresentation.actualRouteText(
            executionPath: unknownAsEmpty(projection.routeResult.routeSource),
            runtimeProvider: unknownAsEmpty(projection.winningBinding.provider),
            actualModelId: unknownAsEmpty(projection.winningBinding.modelID)
        )
        return summaryLine("这次实际命中", actualRoute)
    }

    private static func fallbackReasonLine(_ projection: AXModelRouteTruthProjection) -> String {
        let fallbackApplied = normalizedToken(projection.routeResult.fallbackApplied)
        let reasonCode = effectiveRouteReasonCode(projection)
        let reasonText = routeReasonText(reasonCode)

        switch fallbackApplied {
        case "true":
            if let reasonText {
                return summaryLine("没按预期走的原因", reasonText)
            }
            return summaryLine("没按预期走的原因", "已经发生回退，但原因暂时还不清楚")
        case "false":
            if let reasonText {
                return summaryLine("没按预期走的原因", "这次还没进入回退；最近停在 \(reasonText)")
            }
            return summaryLine("没按预期走的原因", "这次没有发生回退")
        default:
            if let reasonText {
                return summaryLine("没按预期走的原因", reasonText)
            }
            return summaryLine("没按预期走的原因", "暂未回报")
        }
    }

    private static func routeStateLine(_ projection: AXModelRouteTruthProjection) -> String {
        summaryLine(
            "当前状态说明",
            XTRouteTruthPresentation.routeStateText(
                executionPath: unknownAsEmpty(projection.routeResult.routeSource),
                routeReasonCode: unknownAsEmpty(effectiveRouteReasonCode(projection))
            )
        )
    }

    private static func denyCodeLine(_ projection: AXModelRouteTruthProjection) -> String {
        guard let denyCode = explicitDenyCode(
            projection.routeResult.denyCode,
            routeReasonCode: effectiveRouteReasonCode(projection)
        ) else {
            return summaryLine("明确拦截原因", "这次没有明确拦截原因")
        }

        return summaryLine("明确拦截原因", denyCodeText(denyCode))
    }

    private static func effectiveRouteReasonCode(_ projection: AXModelRouteTruthProjection) -> String? {
        firstMeaningfulToken(
            projection.routeResult.fallbackReason,
            projection.routeResult.routeReasonCode
        )
    }

    private static func budgetExportPostureLine(_ projection: AXModelRouteTruthProjection) -> String {
        let trust = trustLevelText(projection.requestSnapshot.trustLevel)
        let budget = firstMeaningfulToken(
            projection.constraintSnapshot.budgetClass,
            projection.requestSnapshot.budgetClass
        ) ?? "unknown"
        let remotePolicy = remotePolicyText(
            request: projection.requestSnapshot,
            constraints: projection.constraintSnapshot
        )
        let userPref = allowedStateText(projection.constraintSnapshot.remoteAllowedAfterUserPref)

        return "远端额度与导出状态：设备信任 \(trust) · 预算档位 \(budgetClassText(budget)) · 系统策略 \(remotePolicy) · 用户偏好 \(userPref)"
    }

    private static func projectionLine(_ projection: AXModelRouteTruthProjection) -> String {
        "数据来源：来源 \(projectionSourceText(projection.projectionSource)) · 完整度 \(completenessText(projection.completeness))"
    }

    private static func observedBindingText(_ binding: AXModelRouteTruthWinningBinding) -> String? {
        let provider = normalizedMeaningfulValue(binding.provider)
        let modelID = normalizedMeaningfulValue(binding.modelID)

        if let provider, let modelID {
            return "\(provider) -> \(modelID)"
        }
        if let modelID {
            return modelID
        }
        if let provider {
            return provider
        }
        return nil
    }

    private static func routeReasonText(_ raw: String?) -> String? {
        XTRouteTruthPresentation.routeReasonDisplayText(unknownAsEmpty(raw)) ?? normalizedMeaningfulValue(raw)
    }

    private static func explicitDenyCode(_ raw: String?, routeReasonCode: String?) -> String? {
        guard let token = normalizedMeaningfulValue(raw)?.lowercased() else { return nil }
        let routeReason = normalizedMeaningfulValue(routeReasonCode)?.lowercased()

        if token.contains("deny") || token.contains("denied") || token.contains("blocked") {
            return token
        }
        if let routeReason, token != routeReason {
            return token
        }
        return nil
    }

    private static func denyCodeText(_ raw: String) -> String {
        XTRouteTruthPresentation.denyCodeText(raw) ?? routeReasonText(raw) ?? raw
    }

    private static func remotePolicyText(
        request: AXModelRouteTruthRequestSnapshot,
        constraints: AXModelRouteTruthConstraintSnapshot
    ) -> String {
        if boolish(constraints.policyBlockedRemote) == true {
            return "已拦截"
        }
        if let allowed = boolish(constraints.remoteAllowedAfterPolicy) {
            return allowed ? "已允许" : "已拦截"
        }
        if let allowed = boolish(request.remoteAllowedByPolicy) {
            return allowed ? "已允许" : "已拦截"
        }
        return "未回报"
    }
}

enum XTDoctorDurableCandidateMirrorPresentation {
    static func summary(
        projection: XTUnifiedDoctorDurableCandidateMirrorProjection
    ) -> XTDoctorProjectionSummary {
        var lines = [
            "当前状态：\(statusText(projection.status))",
            "镜像目标：\(targetText(projection.target))",
            "本地存储角色：\(displayToken(projection.localStoreRole))",
            "边界说明：XT 本地候选只作为缓存、兜底和编辑缓冲；真正的持久写入仍走 Hub Writer + Gate。"
        ]

        if let errorCode = normalizedMeaningfulValue(projection.errorCode) {
            lines.append("当前原因：\(reasonText(errorCode))")
        }

        return XTDoctorProjectionSummary(
            title: "记忆候选镜像",
            lines: lines
        )
    }

    private static func statusText(_ status: SupervisorDurableCandidateMirrorStatus) -> String {
        switch status {
        case .notNeeded:
            return "当前不需要向 Hub 镜像 durable candidates"
        case .pending:
            return "已进入 Hub 镜像队列"
        case .mirroredToHub:
            return "已镜像到 Hub"
        case .localOnly:
            return "当前只保留 XT 本地候选"
        case .hubMirrorFailed:
            return "尝试写入 Hub，但镜像失败"
        }
    }

    private static func targetText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case XTSupervisorDurableCandidateMirror.mirrorTarget:
            return "Hub 候选容器（影子线程）"
        default:
            return displayToken(raw)
        }
    }

    private static func reasonText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "remote_route_not_preferred":
            return "当前远端路径不是首选"
        case "runtime_not_running":
            return "Hub 远端运行时还没启动"
        case "hub_append_failed":
            return "Hub 追加写入没有成功完成"
        case "candidate_payload_empty":
            return "候选内容为空，Hub 无法接收"
        case "supervisor_candidate_session_participation_invalid":
            return "候选会话参与状态不合法"
        case "supervisor_candidate_session_participation_denied":
            return "候选不允许进入受限写入会话"
        case "supervisor_candidate_scope_mismatch":
            return "候选写入范围和记录范围不一致"
        default:
            return XTDoctorRouteTruthPresentation.summaryTextFallback(raw)
        }
    }
}

enum XTDoctorHubMemoryPromptProjectionPresentation {
    static func summary(
        projection: HubMemoryPromptProjectionSnapshot
    ) -> XTDoctorProjectionSummary {
        XTDoctorProjectionSummary(
            title: "Hub Prompt 装配",
            lines: [
                "Canonical facts：\(projection.canonicalItemCount) 条稳定事实进入本轮 prompt",
                "Recent raw context：\(projection.workingSetTurnCount) 条近期原文窗口进入本轮 prompt",
                runtimeTruthLine(projection),
                "来源：\(projectionSourceText(projection.projectionSource))"
            ]
        )
    }

    private static func runtimeTruthLine(
        _ projection: HubMemoryPromptProjectionSnapshot
    ) -> String {
        guard projection.runtimeTruthItemCount > 0 else {
            return "Governed runtime truth：本轮没有注入额外的运行时真相对象"
        }
        let kinds = projection.runtimeTruthSourceKinds.isEmpty
            ? "source kinds 未回报"
            : projection.runtimeTruthSourceKinds.joined(separator: ", ")
        return "Governed runtime truth：\(projection.runtimeTruthItemCount) 条对象，来源 \(kinds)"
    }

    private static func projectionSourceText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "hub_generate_done_metadata":
            return "Hub generate done metadata"
        case "hub_memory_route_prompt_projection":
            return "Hub memory route prompt projection"
        default:
            return displayToken(raw)
        }
    }
}

enum XTDoctorProjectMemoryReadinessPresentation {
    static func summary(
        projection: XTProjectMemoryAssemblyReadiness
    ) -> XTDoctorProjectionSummary {
        var lines = [
            summaryLine(
                "当前状态",
                projection.ready
                    ? "Project AI 最近一次 memory 装配当前可判定为就绪"
                    : "Project AI 最近一次 memory 装配当前需要关注"
            ),
            summaryLine("状态行", projection.statusLine)
        ]

        if let topIssue = projection.topIssue {
            lines.append(summaryLine("首要问题", topIssue.summary))
            lines.append(summaryLine("问题详情", topIssue.detail))
        } else {
            lines.append(summaryLine("装配结论", "当前没有发现 continuity floor、resolution 缺失或 projection drift 问题。"))
        }

        if !projection.issueCodes.isEmpty {
            lines.append(
                summaryLine(
                    "问题代码",
                    projection.issueCodes
                        .map(projectMemoryIssueText)
                        .joined(separator: "、")
                )
            )
        }

        lines.append("边界说明：这里只是 XT 对 Project AI memory 装配的 explainability 投影，不替代 Hub memory truth、grant、gate 或 audit 主链。")

        return XTDoctorProjectionSummary(
            title: "Project Memory 装配",
            lines: lines
        )
    }

    static func projectMemoryIssueText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "project_memory_usage_missing":
            return "缺少最近一次真实 usage"
        case "project_recent_dialogue_floor_not_met":
            return "近期对话底线未达标"
        case "project_memory_resolution_missing":
            return "machine-readable resolution 缺失"
        case "memory_resolution_projection_drift":
            return "projection drift"
        default:
            return XTMemorySourceTruthPresentation.humanizeToken(raw)
        }
    }
}

enum XTDoctorGovernanceRuntimeReadinessPresentation {
    static func summary(detailLines: [String]) -> XTDoctorProjectionSummary? {
        guard let snapshot = AXProjectGovernanceRuntimeReadinessSnapshot(
            detailLines: detailLines
        ) else {
            return nil
        }

        var lines = [
            summaryLine(
                "A-Tier 配置",
                "\(displayToken(snapshot.configuredExecutionTier)) · 生效 \(displayToken(snapshot.effectiveExecutionTier))"
            ),
            summaryLine(
                "Runtime Surface",
                "配置 \(displayToken(snapshot.configuredRuntimeSurfaceMode)) · 生效 \(displayToken(snapshot.effectiveRuntimeSurfaceMode)) · 收束 \(governanceOverrideDisplayToken(snapshot.runtimeSurfaceOverrideMode))"
            ),
            summaryLine(
                "Trusted Automation",
                displayToken(snapshot.trustedAutomationState)
            ),
            summaryLine(
                "Effective Surface",
                snapshot.effectiveSurfaceCapabilityLabelsResolved.isEmpty
                    ? "当前未打开 A4 surface"
                    : snapshot.effectiveSurfaceCapabilityLabelsResolved.joined(separator: " / ")
            ),
            summaryLine(
                "Runtime Ready",
                snapshot.runtimeReadyLine
            )
        ]

        lines += snapshot.componentProjections.map { component in
            summaryLine(
                component.key.displayName,
                "\(component.state.displayName) · \(component.summaryLine)"
            )
        }

        lines.append(
            summaryLine(
                "结论",
                snapshot.summaryLine
            )
        )

        if let missingSummary = snapshot.missingSummaryLine {
            lines.append(summaryLine("缺口", missingSummary.replacingOccurrences(of: "缺口：", with: "")))
        }

        lines.append(
            "边界说明：这里只表达 A-Tier configured 和 runtime ready 的当前差值，不替代 Hub grant、tool policy、TTL、kill-switch 或 audit 主链。"
        )

        return XTDoctorProjectionSummary(
            title: "Governance Runtime Ready",
            lines: lines
        )
    }
}

enum XTDoctorSupervisorReviewTriggerPresentation {
    static func summary(
        projection: XTUnifiedDoctorSupervisorReviewTriggerProjection
    ) -> XTDoctorProjectionSummary {
        var lines = [
            summaryLine(
                "Review Policy",
                reviewPolicyLine(projection)
            )
        ]

        if let eventFollowUpCadenceLabel = normalizedMeaningfulValue(projection.eventFollowUpCadenceLabel) {
            lines.append(
                summaryLine(
                    "事件跟进节奏",
                    eventFollowUpCadenceText(eventFollowUpCadenceLabel)
                )
            )
        }

        if !projection.mandatoryReviewTriggers.isEmpty {
            lines.append(
                summaryLine(
                    "硬检查点",
                    projection.mandatoryReviewTriggers
                        .map(reviewTriggerText)
                        .joined(separator: "、")
                )
            )
        }

        if !projection.effectiveEventReviewTriggers.isEmpty {
            lines.append(
                summaryLine(
                    "事件触发",
                    projection.effectiveEventReviewTriggers
                        .map(reviewTriggerText)
                        .joined(separator: "、")
                )
            )
        }

        if !projection.derivedReviewTriggers.isEmpty {
            lines.append(
                summaryLine(
                    "派生触发",
                    projection.derivedReviewTriggers
                        .map(reviewTriggerText)
                        .joined(separator: "、")
                )
            )
        }

        if projection.activeCandidateAvailable {
            lines.append(
                summaryLine(
                    "当前候选",
                    activeCandidateText(projection)
                )
            )
        } else if projection.queuedReviewTrigger != nil
                    || projection.queuedReviewRunKind != nil
                    || projection.queuedReviewLevel != nil {
            lines.append(
                summaryLine(
                    "排队中的 Review",
                    queuedReviewText(projection)
                )
            )
        } else {
            lines.append(summaryLine("当前候选", "当前没有激活中的 review candidate"))
        }

        if let latestReviewText = latestReviewText(projection) {
            lines.append(summaryLine("最近落盘 Review", latestReviewText))
        }

        if let cadenceFootprintLine = cadenceFootprintLine(projection) {
            lines.append(summaryLine("节奏足迹", cadenceFootprintLine))
        }

        lines.append(
            summaryLine(
                "结论",
                projection.summaryLine.replacingOccurrences(of: "Review Trigger：", with: "")
            )
        )
        lines.append(
            "边界说明：这里只表达 XT 目前看到的 review policy / trigger / candidate / queue explainability，不替代 Supervisor review scheduler、review note authority、guidance injection authority、Hub audit、grant、TTL、kill-switch 或 clamp。"
        )

        return XTDoctorProjectionSummary(
            title: "Supervisor Review Trigger",
            lines: lines
        )
    }

    private static func reviewPolicyLine(
        _ projection: XTUnifiedDoctorSupervisorReviewTriggerProjection
    ) -> String {
        let policyText = normalizedMeaningfulValue(projection.reviewPolicyMode)
            .flatMap(AXProjectReviewPolicyMode.init(rawValue:))
            .map(\.localizedDisplayName)
            ?? "未回报"
        let eventDrivenText = projection.eventDrivenReviewEnabled ? "event-driven 开启" : "event-driven 关闭"
        return "\(policyText) · \(eventDrivenText)"
    }

    private static func activeCandidateText(
        _ projection: XTUnifiedDoctorSupervisorReviewTriggerProjection
    ) -> String {
        var parts: [String] = []
        if let trigger = normalizedMeaningfulValue(projection.activeCandidateTrigger) {
            parts.append(reviewTriggerText(trigger))
        }
        if let runKind = normalizedMeaningfulValue(projection.activeCandidateRunKind) {
            parts.append(runKindText(runKind))
        }
        if let reviewLevel = normalizedMeaningfulValue(projection.activeCandidateReviewLevel) {
            parts.append(reviewLevelText(reviewLevel))
        }
        if let activeCandidatePriority = projection.activeCandidatePriority {
            parts.append("priority \(activeCandidatePriority)")
        }
        if projection.activeCandidateQueued == true {
            parts.append("已进入治理排队")
        }
        return parts.isEmpty ? "当前没有激活中的 review candidate" : parts.joined(separator: " · ")
    }

    private static func queuedReviewText(
        _ projection: XTUnifiedDoctorSupervisorReviewTriggerProjection
    ) -> String {
        let parts = [
            normalizedMeaningfulValue(projection.queuedReviewTrigger).map(reviewTriggerText),
            normalizedMeaningfulValue(projection.queuedReviewRunKind).map(runKindText),
            normalizedMeaningfulValue(projection.queuedReviewLevel).map(reviewLevelText)
        ].compactMap { $0 }
        return parts.isEmpty ? "当前没有排队中的 review" : parts.joined(separator: " · ")
    }

    private static func latestReviewText(
        _ projection: XTUnifiedDoctorSupervisorReviewTriggerProjection
    ) -> String? {
        let trigger = normalizedMeaningfulValue(projection.latestReviewTrigger).map(reviewTriggerText)
        let level = normalizedMeaningfulValue(projection.latestReviewLevel).map(reviewLevelText)
        let source = normalizedMeaningfulValue(projection.latestReviewSource).map(latestReviewSourceText)
        let atMs = projection.latestReviewAtMs.map { "at \($0) ms" }
        let parts = [source, trigger, level, atMs].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func cadenceFootprintLine(
        _ projection: XTUnifiedDoctorSupervisorReviewTriggerProjection
    ) -> String? {
        var parts: [String] = []
        if let lastPulseReviewAtMs = projection.lastPulseReviewAtMs {
            parts.append("pulse \(lastPulseReviewAtMs) ms")
        }
        if let lastBrainstormReviewAtMs = projection.lastBrainstormReviewAtMs {
            parts.append("brainstorm \(lastBrainstormReviewAtMs) ms")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func latestReviewSourceText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "review_note_store":
            return "review note store"
        case "schedule_state":
            return "schedule 记录"
        default:
            return displayToken(raw)
        }
    }

    private static func eventFollowUpCadenceText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "cadence=", with: "")
    }

    private static func reviewTriggerText(_ raw: String) -> String {
        AXProjectReviewTrigger(rawValue: raw)?.localizedDisplayName ?? displayToken(raw)
    }

    private static func runKindText(_ raw: String) -> String {
        HeartbeatRecoveryUserFacingText.queuedReviewRunKindText(
            SupervisorReviewRunKind(rawValue: raw)
        ) ?? displayToken(raw)
    }

    private static func reviewLevelText(_ raw: String) -> String {
        HeartbeatRecoveryUserFacingText.queuedReviewLevelText(
            SupervisorReviewLevel(rawValue: raw)
        )
    }
}

enum XTDoctorSupervisorGuidanceContinuityPresentation {
    static func summary(
        projection: XTUnifiedDoctorSupervisorGuidanceContinuityProjection
    ) -> XTDoctorProjectionSummary {
        var lines = [
            summaryLine(
                "连续性载体",
                projection.reviewGuidanceCarrierPresent
                    ? "本次 Supervisor memory 装配已带上 review / guidance carrier"
                    : "本次 Supervisor memory 装配还没带上 review / guidance carrier"
            ),
            summaryLine(
                "最近 Review",
                reviewStatusText(
                    available: projection.latestReviewNoteAvailable,
                    actualized: projection.latestReviewNoteActualized
                )
            )
        ]

        if projection.latestGuidanceAvailable
            || projection.latestGuidanceAckStatus != nil
            || projection.latestGuidanceDeliveryMode != nil
            || projection.latestGuidanceInterventionMode != nil
            || projection.latestGuidanceSafePointPolicy != nil {
            lines.append(
                summaryLine(
                    "最近 Guidance",
                    guidanceStatusText(
                        label: "latest guidance",
                        available: projection.latestGuidanceAvailable,
                        actualized: projection.latestGuidanceActualized,
                        ackStatus: projection.latestGuidanceAckStatus,
                        ackRequired: projection.latestGuidanceAckRequired,
                        deliveryMode: projection.latestGuidanceDeliveryMode,
                        interventionMode: projection.latestGuidanceInterventionMode,
                        safePointPolicy: projection.latestGuidanceSafePointPolicy
                    )
                )
            )
        }

        if projection.pendingAckGuidanceAvailable
            || projection.pendingAckGuidanceAckStatus != nil
            || projection.pendingAckGuidanceDeliveryMode != nil
            || projection.pendingAckGuidanceInterventionMode != nil
            || projection.pendingAckGuidanceSafePointPolicy != nil {
            lines.append(
                summaryLine(
                    "待确认 Guidance",
                    guidanceStatusText(
                        label: "pending guidance",
                        available: projection.pendingAckGuidanceAvailable,
                        actualized: projection.pendingAckGuidanceActualized,
                        ackStatus: projection.pendingAckGuidanceAckStatus,
                        ackRequired: projection.pendingAckGuidanceAckRequired,
                        deliveryMode: projection.pendingAckGuidanceDeliveryMode,
                        interventionMode: projection.pendingAckGuidanceInterventionMode,
                        safePointPolicy: projection.pendingAckGuidanceSafePointPolicy
                    )
                )
            )
        }

        if !projection.renderedRefs.isEmpty {
            lines.append(
                summaryLine(
                    "实际挂载引用",
                    projection.renderedRefs.map(renderedRefText).joined(separator: "、")
                )
            )
        }

        lines.append(
            summaryLine(
                "结论",
                projection.summaryLine.replacingOccurrences(of: "Review / Guidance：", with: "")
            )
        )
        lines.append(
            "边界说明：这里只表达 Supervisor 最近一次 review / guidance / ack / safe-point 连续性投影，不替代 review note、guidance injection、Hub audit 或实时中断 authority。"
        )

        return XTDoctorProjectionSummary(
            title: "Supervisor Review / Guidance",
            lines: lines
        )
    }

    private static func reviewStatusText(
        available: Bool,
        actualized: Bool
    ) -> String {
        guard available else {
            return "当前没有 latest review note"
        }
        return actualized
            ? "已发现 latest review note，且这次已带入 Supervisor memory"
            : "已发现 latest review note，但这次没有带入 Supervisor memory"
    }

    private static func guidanceStatusText(
        label: String,
        available: Bool,
        actualized: Bool,
        ackStatus: String?,
        ackRequired: Bool?,
        deliveryMode: String?,
        interventionMode: String?,
        safePointPolicy: String?
    ) -> String {
        var parts: [String] = []
        if available {
            parts.append(actualized ? "已带入 Supervisor memory" : "当前存在，但这次没有带入")
        } else {
            parts.append("当前没有 \(label)")
        }

        if let ackStatus = normalizedMeaningfulValue(ackStatus) {
            parts.append("ack \(ackStatusText(ackStatus))")
        }
        if let ackRequired {
            parts.append(ackRequired ? "需要 ack" : "ack 可选")
        }
        if let deliveryMode = normalizedMeaningfulValue(deliveryMode) {
            parts.append("投递 \(deliveryModeText(deliveryMode))")
        }
        if let interventionMode = normalizedMeaningfulValue(interventionMode) {
            parts.append("介入 \(interventionModeText(interventionMode))")
        }
        if let safePointPolicy = normalizedMeaningfulValue(safePointPolicy) {
            parts.append("safe point \(safePointPolicyText(safePointPolicy))")
        }
        return parts.joined(separator: " · ")
    }

    private static func ackStatusText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "pending":
            return "待确认"
        case "accepted":
            return "已接受"
        case "deferred":
            return "已暂缓"
        case "rejected":
            return "已拒绝"
        default:
            return raw
        }
    }

    private static func deliveryModeText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "context_append":
            return "上下文追加"
        case "priority_insert":
            return "优先插入"
        case "replan_request":
            return "请求重规划"
        case "stop_signal":
            return "停止信号"
        default:
            return displayToken(raw)
        }
    }

    private static func interventionModeText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "observe_only":
            return "仅观察"
        case "suggest_next_safe_point":
            return "安全点建议"
        case "replan_next_safe_point":
            return "安全点重规划"
        case "stop_immediately":
            return "立即停止"
        default:
            return displayToken(raw)
        }
    }

    private static func safePointPolicyText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "next_tool_boundary":
            return "下一个工具边界"
        case "next_step_boundary":
            return "下一步边界"
        case "checkpoint_boundary":
            return "检查点边界"
        case "immediate":
            return "立即"
        default:
            return displayToken(raw)
        }
    }

    private static func renderedRefText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "latest_review_note":
            return "latest review note"
        case "latest_guidance":
            return "latest guidance"
        case "pending_ack_guidance":
            return "pending guidance"
        default:
            return displayToken(raw)
        }
    }
}

enum XTDoctorSupervisorSafePointTimelinePresentation {
    static func summary(
        projection: XTUnifiedDoctorSupervisorSafePointTimelineProjection
    ) -> XTDoctorProjectionSummary {
        var lines: [String] = []

        if let liveStateSource = normalizedMeaningfulValue(projection.liveStateSource) {
            lines.append(summaryLine("状态来源", liveStateSourceText(liveStateSource)))
        }

        if projection.pendingGuidanceAvailable {
            var pendingParts: [String] = []
            if let injectionId = normalizedMeaningfulValue(projection.pendingGuidanceInjectionId) {
                pendingParts.append("injection \(injectionId)")
            }
            if let deliveryMode = normalizedMeaningfulValue(projection.pendingGuidanceDeliveryMode) {
                pendingParts.append("投递 \(deliveryModeText(deliveryMode))")
            }
            if let interventionMode = normalizedMeaningfulValue(projection.pendingGuidanceInterventionMode) {
                pendingParts.append("介入 \(interventionModeText(interventionMode))")
            }
            if let safePointPolicy = normalizedMeaningfulValue(projection.pendingGuidanceSafePointPolicy) {
                pendingParts.append("safe point \(safePointPolicyText(safePointPolicy))")
            }
            lines.append(summaryLine("待投递 Guidance", pendingParts.joined(separator: " · ")))
        } else {
            lines.append(summaryLine("待投递 Guidance", "当前没有待确认 guidance"))
        }

        if projection.flowStep != nil
            || projection.toolResultsCount != nil
            || projection.verifyRunIndex != nil
            || projection.finalizeOnly != nil
            || projection.checkpointReached != nil {
            var runtimeParts: [String] = []
            if let flowStep = projection.flowStep {
                runtimeParts.append("step \(flowStep)")
            }
            if let toolResultsCount = projection.toolResultsCount {
                runtimeParts.append("tool 结果 \(toolResultsCount)")
            }
            if let verifyRunIndex = projection.verifyRunIndex {
                runtimeParts.append("verify \(verifyRunIndex)")
            }
            if let finalizeOnly = projection.finalizeOnly {
                runtimeParts.append(finalizeOnly ? "finalize-only" : "非 finalize-only")
            }
            if let checkpointReached = projection.checkpointReached {
                runtimeParts.append(checkpointReached ? "checkpoint 已到" : "checkpoint 未到")
            }
            lines.append(summaryLine("当前执行位置", runtimeParts.joined(separator: " · ")))
        }

        var postureParts: [String] = []
        if let promptVisibleNow = projection.promptVisibleNow {
            postureParts.append(promptVisibleNow ? "当前 prompt 已可见" : "当前 prompt 还不可见")
        }
        if let visibleFromPreRunMemory = projection.visibleFromPreRunMemory, visibleFromPreRunMemory {
            postureParts.append("run 前已存在")
        }
        if let deliverableNow = projection.deliverableNow {
            postureParts.append(deliverableNow ? "当前可投递" : "当前不可投递")
        }
        if let shouldPauseToolBatchAfterBoundary = projection.shouldPauseToolBatchAfterBoundary,
           shouldPauseToolBatchAfterBoundary {
            postureParts.append("工具边界后应暂停剩余 batch")
        } else if projection.pauseRecorded == true {
            postureParts.append("工具边界暂停已记录")
        }
        if !postureParts.isEmpty {
            lines.append(summaryLine("投递姿态", postureParts.joined(separator: " · ")))
        }

        if let deliveryState = normalizedMeaningfulValue(projection.deliveryState) {
            lines.append(summaryLine("当前判定", deliveryStateText(deliveryState)))
        }

        if let executionGate = normalizedMeaningfulValue(projection.executionGate) {
            lines.append(summaryLine("执行闸门", executionGateText(executionGate)))
        }

        lines.append(
            summaryLine(
                "结论",
                projection.summaryLine.replacingOccurrences(of: "Safe Point：", with: "")
            )
        )
        lines.append(
            "边界说明：这里只表达 XT 当前看到的 guidance safe-point 投递时机与批次暂停姿态，不替代 Supervisor 中断 authority、Hub scheduler、grant、TTL、kill-switch 或 clamp。"
        )

        return XTDoctorProjectionSummary(
            title: "Supervisor Safe Point",
            lines: lines
        )
    }

    private static func liveStateSourceText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "pending_tool_approval":
            return "当前根据 pending tool approval 恢复 live safe-point state"
        case "no_live_flow":
            return "当前只有 pending guidance，没有可恢复的 live flow"
        default:
            return displayToken(raw)
        }
    }

    private static func deliveryStateText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "already_visible_pre_run_memory":
            return "这条 pending guidance 在本轮 run 开始前就已存在，并且已经可见于 prompt memory"
        case "already_visible_in_prompt_memory":
            return "这条 pending guidance 已经可见于当前 prompt memory"
        case "deliverable_now":
            return "当前已经到达 safe point，可以立刻把 guidance 投递给 Project AI"
        case "waiting_next_tool_boundary":
            return "当前还在等下一个工具边界"
        case "waiting_next_step_boundary":
            return "当前还在等下一步边界"
        case "waiting_checkpoint_boundary":
            return "当前还在等 checkpoint 边界"
        case "pending_guidance_no_live_flow":
            return "当前存在 pending guidance，但缺少 live flow，无法判断已经走到哪一个边界"
        default:
            return displayToken(raw)
        }
    }

    private static func executionGateText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "final_only_until_ack":
            return "final only until ack"
        case "normal":
            return "normal"
        default:
            return displayToken(raw)
        }
    }

    private static func deliveryModeText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "context_append":
            return "上下文追加"
        case "priority_insert":
            return "优先插入"
        case "replan_request":
            return "请求重规划"
        case "stop_signal":
            return "停止信号"
        default:
            return displayToken(raw)
        }
    }

    private static func interventionModeText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "observe_only":
            return "仅观察"
        case "suggest_next_safe_point":
            return "安全点建议"
        case "replan_next_safe_point":
            return "安全点重规划"
        case "stop_immediately":
            return "立即停止"
        default:
            return displayToken(raw)
        }
    }

    private static func safePointPolicyText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "next_tool_boundary":
            return "下一个工具边界"
        case "next_step_boundary":
            return "下一步边界"
        case "checkpoint_boundary":
            return "检查点边界"
        case "immediate":
            return "立即"
        default:
            return displayToken(raw)
        }
    }
}

enum XTDoctorSkillDoctorTruthPresentation {
    static func summary(
        projection: XTUnifiedDoctorSkillDoctorTruthProjection
    ) -> XTDoctorProjectionSummary {
        var lines = [
            summaryLine("项目能力画像", profileContextLine(projection.effectiveProfileSnapshot)),
            summaryLine("当前可直接运行", listText(projection.effectiveProfileSnapshot.runnableNowProfiles)),
            summaryLine("能力分层", capabilityBandLine(projection.effectiveProfileSnapshot)),
            summaryLine("技能计数", skillCountLine(projection))
        ]

        if projection.grantRequiredSkillCount > 0 {
            lines.append(summaryLine("待 Hub grant", previewText(projection.grantRequiredSkillPreview)))
        }

        if projection.approvalRequiredSkillCount > 0 {
            lines.append(summaryLine("待本地确认", previewText(projection.approvalRequiredSkillPreview)))
        }

        if projection.blockedSkillCount > 0 {
            lines.append(summaryLine("当前阻塞", previewText(projection.blockedSkillPreview)))
        }

        lines.append(
            "边界说明：这里只是 XT 基于 project effective skill profile + typed readiness 生成的 doctor 投影，不替代 Hub grant / revocation / registry 主真相。"
        )

        return XTDoctorProjectionSummary(
            title: "技能 Doctor Truth",
            lines: lines
        )
    }

    private static func profileContextLine(
        _ snapshot: XTProjectEffectiveSkillProfileSnapshot
    ) -> String {
        let localAutoApprove = snapshot.localAutoApproveEnabled ? "本地自动批准已开启" : "本地自动批准关闭"
        let trustedAutomation = snapshot.trustedAutomationReady ? "trusted automation 已就绪" : "trusted automation 未就绪"
        return "执行层级 \(displayToken(snapshot.executionTier)) · runtime surface \(displayToken(snapshot.runtimeSurfaceMode)) · Hub 覆盖 \(displayToken(snapshot.hubOverrideMode)) · \(localAutoApprove) · \(trustedAutomation)"
    }

    private static func capabilityBandLine(
        _ snapshot: XTProjectEffectiveSkillProfileSnapshot
    ) -> String {
        "runnable \(listText(snapshot.runnableNowProfiles)) · grant \(listText(snapshot.grantRequiredProfiles)) · local approval \(listText(snapshot.approvalRequiredProfiles)) · blocked \(listText(snapshot.blockedProfiles.map(\.profileID)))"
    }

    private static func skillCountLine(
        _ projection: XTUnifiedDoctorSkillDoctorTruthProjection
    ) -> String {
        "已安装 \(projection.installedSkillCount) · 已就绪 \(projection.readySkillCount) · 待 Hub grant \(projection.grantRequiredSkillCount) · 待本地确认 \(projection.approvalRequiredSkillCount) · 阻塞 \(projection.blockedSkillCount) · 降级 \(projection.degradedSkillCount)"
    }

    private static func previewText(
        _ previews: [XTUnifiedDoctorSkillReadinessPreview]
    ) -> String {
        let values = previews.map(previewLine)
        return values.isEmpty ? "none" : values.joined(separator: "；")
    }

    private static func previewLine(
        _ preview: XTUnifiedDoctorSkillReadinessPreview
    ) -> String {
        let title = normalizedMeaningfulValue(preview.name) ?? preview.skillID
        var parts = [
            "\(title)（\(displayToken(preview.stateLabel))）",
            "profiles \(listText(preview.capabilityProfiles))"
        ]

        if let reason = normalizedMeaningfulValue(preview.reasonCode) {
            parts.append(reason)
        }
        if let grantFloor = normalizedMeaningfulValue(preview.grantFloor) {
            parts.append("grant=\(grantFloor)")
        }
        if let approvalFloor = normalizedMeaningfulValue(preview.approvalFloor) {
            parts.append("approval=\(approvalFloor)")
        }
        if !preview.unblockActions.isEmpty {
            parts.append("unblock=\(listText(preview.unblockActions))")
        }

        return parts.joined(separator: " · ")
    }

    private static func listText(_ values: [String]) -> String {
        let normalized = orderedUnique(values.compactMap(normalizedMeaningfulValue))
        return normalized.isEmpty ? "none" : normalized.joined(separator: ", ")
    }
}

enum XTDoctorProjectAutomationContinuityPresentation {
    static func summary(detailLines: [String]) -> XTDoctorProjectionSummary? {
        guard let projection = projection(from: detailLines) else { return nil }

        var lines = [
            summaryLine("连续性来源", sourceLine(projection)),
            summaryLine("当前运行", runLine(projection))
        ]

        if let verificationContract = projection.verificationContract {
            lines.append(
                summaryLine(
                    "验证合同",
                    XTAutomationVerificationContractSupport.presentationText(
                        verificationContract,
                        includePrefix: false
                    )
                )
            )
        }

        if let retryVerificationContract = projection.retryVerificationContract {
            lines.append(
                summaryLine(
                    "重试验证合同",
                    XTAutomationVerificationContractSupport.presentationText(
                        retryVerificationContract,
                        includePrefix: false
                    )
                )
            )
        }

        if let blockerPresent = projection.blockerPresent, blockerPresent {
            lines.append("当前阻塞：已记录 blocker，需要结合 execution / retry 证据继续判断。")
        }
        if let retryReasonPresent = projection.retryReasonPresent, retryReasonPresent {
            lines.append("重试原因：已生成 retry reason，可据此继续恢复或重规划。")
        }

        lines.append("边界说明：这里只是 XT 对自动续跑状态的 explainability 投影，不替代 runtime checkpoint、retry package、grant 或 audit 主链。")

        return XTDoctorProjectionSummary(
            title: "自动续跑连续性",
            lines: lines
        )
    }

    private static func projection(
        from detailLines: [String]
    ) -> XTDoctorProjectAutomationContinuityProjection? {
        let automationContextSource = detailValue(
            "project_memory_automation_context_source",
            from: detailLines
        )
        let memorySource = detailValue("project_memory_v1_source", from: detailLines)
        let memoryFreshness = detailValue("memory_v1_freshness", from: detailLines)
        let runID = detailValue("project_memory_automation_run_id", from: detailLines)
        let runState = detailValue("project_memory_automation_run_state", from: detailLines)
        let currentStepTitle = detailValue("project_memory_automation_current_step_title", from: detailLines)
        let currentStepState = detailValue("project_memory_automation_current_step_state", from: detailLines)
        let verificationContract = decodeJSON(
            XTAutomationVerificationContract.self,
            jsonString: detailValue("project_memory_automation_verification_contract_json", from: detailLines)
        )
        let retryVerificationContract = decodeJSON(
            XTAutomationVerificationContract.self,
            jsonString: detailValue("project_memory_automation_retry_verification_contract_json", from: detailLines)
        )
        let blockerPresent = boolValue("project_memory_automation_blocker_present", from: detailLines)
        let retryReasonPresent = boolValue("project_memory_automation_retry_reason_present", from: detailLines)

        guard automationContextSource != nil
                || memorySource != nil
                || memoryFreshness != nil
                || runID != nil
                || runState != nil
                || currentStepTitle != nil
                || currentStepState != nil
                || verificationContract != nil
                || retryVerificationContract != nil
                || blockerPresent != nil
                || retryReasonPresent != nil else {
            return nil
        }

        return XTDoctorProjectAutomationContinuityProjection(
            automationContextSource: automationContextSource,
            memorySource: memorySource,
            memoryFreshness: memoryFreshness,
            runID: runID,
            runState: runState,
            currentStepTitle: currentStepTitle,
            currentStepState: currentStepState,
            verificationContract: verificationContract,
            retryVerificationContract: retryVerificationContract,
            blockerPresent: blockerPresent,
            retryReasonPresent: retryReasonPresent
        )
    }

    private static func sourceLine(_ projection: XTDoctorProjectAutomationContinuityProjection) -> String {
        let automationSource = normalizedMeaningfulValue(projection.automationContextSource) ?? "未回报"
        let memorySource = normalizedMeaningfulValue(projection.memorySource) ?? "未回报"
        let freshness = normalizedMeaningfulValue(projection.memoryFreshness) ?? "未回报"
        return "自动化 \(automationSource) · 记忆 \(memorySource) · 新鲜度 \(freshness)"
    }

    private static func runLine(_ projection: XTDoctorProjectAutomationContinuityProjection) -> String {
        var parts: [String] = []
        if let runID = normalizedMeaningfulValue(projection.runID) {
            parts.append(runID)
        } else {
            parts.append("未回报 run id")
        }
        if let runState = normalizedMeaningfulValue(projection.runState) {
            parts.append("状态 \(runState)")
        }
        if let currentStepTitle = normalizedMeaningfulValue(projection.currentStepTitle) {
            let currentStepState = normalizedMeaningfulValue(projection.currentStepState) ?? "未回报"
            parts.append("步骤 \(currentStepTitle) (\(currentStepState))")
        }
        return parts.joined(separator: " · ")
    }

    private static func detailValue(_ key: String, from detailLines: [String]) -> String? {
        guard let line = detailLines.first(where: { $0.hasPrefix("\(key)=") }) else {
            return nil
        }
        return normalizedMeaningfulValue(String(line.dropFirst(key.count + 1)))
    }

    private static func boolValue(_ key: String, from detailLines: [String]) -> Bool? {
        switch detailValue(key, from: detailLines)?.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, jsonString: String?) -> T? {
        guard let jsonString,
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

enum XTDoctorHeartbeatGovernancePresentation {
    static func summary(
        projection: XTUnifiedDoctorHeartbeatGovernanceProjection
    ) -> XTDoctorProjectionSummary {
        var lines = [
            qualityLine(projection),
            lifecycleLine(projection),
            digestLine(projection),
            summaryLine(
                "当前状态",
                normalizedMeaningfulValue(projection.currentStateSummary) ?? "未回报"
            )
        ]

        if let projectMemoryLine = projectMemoryLine(projection) {
            lines.append(projectMemoryLine)
        }

        if let blocker = normalizedMeaningfulValue(projection.blockerSummary) {
            lines.append(summaryLine("当前阻塞", blocker))
        }

        lines.append(
            summaryLine(
                "下一步",
                normalizedMeaningfulValue(projection.nextStepSummary) ?? "未回报"
            )
        )
        lines.append(
            summaryLine(
                "用户看到的变化",
                normalizedMeaningfulValue(projection.digestWhatChangedText) ?? "未回报"
            )
        )
        lines.append(
            summaryLine(
                "为什么会看到 / 看不到",
                normalizedMeaningfulValue(projection.digestWhyImportantText) ?? "未回报"
            )
        )
        lines.append(
            summaryLine(
                "系统准备怎么做",
                normalizedMeaningfulValue(projection.digestSystemNextStepText) ?? "未回报"
            )
        )

        if let recoveryLine = recoveryLine(projection) {
            lines.append(recoveryLine)
        }

        lines += [
            cadenceLine(label: "进度心跳", projection: projection.progressHeartbeat),
            cadenceLine(label: "脉冲复盘", projection: projection.reviewPulse),
            cadenceLine(label: "无进展复盘", projection: projection.brainstormReview),
            nextReviewDueLine(projection.nextReviewDue)
        ]

        return XTDoctorProjectionSummary(
            title: "Heartbeat 治理",
            lines: lines
        )
    }

    private static func digestLine(
        _ projection: XTUnifiedDoctorHeartbeatGovernanceProjection
    ) -> String {
        let visibility = normalizedMeaningfulValue(projection.digestVisibility) == XTHeartbeatDigestVisibilityDecision.shown.rawValue
            ? "这条 digest 会显示给用户"
            : "这条 digest 当前会被压制"
        let reasons = HeartbeatGovernanceUserFacingText.digestReasonSummary(projection.digestReasonCodes)
        return summaryLine("Digest 决策", "\(visibility) · 原因 \(reasons)")
    }

    private static func qualityLine(
        _ projection: XTUnifiedDoctorHeartbeatGovernanceProjection
    ) -> String {
        let band = qualityBandText(projection.latestQualityBand)
        let score = projection.latestQualityScore.map { "（\($0) 分）" } ?? ""
        let anomalies = projection.openAnomalyTypes
        let weakReasons = projection.weakReasons

        var details: [String] = []
        if !anomalies.isEmpty {
            details.append("异常 \(HeartbeatGovernanceUserFacingText.anomalyTypeSummary(anomalies))")
        }
        if !weakReasons.isEmpty {
            details.append("弱项 \(HeartbeatGovernanceUserFacingText.weakReasonSummary(weakReasons))")
        }

        if projection.lastHeartbeatAtMs > 0 {
            details.append("最近心跳 \(projection.lastHeartbeatAtMs) ms")
        }

        let suffix = details.isEmpty ? "" : " · " + details.joined(separator: " · ")
        return summaryLine("最近质量", "\(band)\(score)\(suffix)")
    }

    private static func lifecycleLine(
        _ projection: XTUnifiedDoctorHeartbeatGovernanceProjection
    ) -> String {
        let status = HeartbeatGovernanceUserFacingText.executionStatusText(projection.executionStatus)
        let risk = HeartbeatGovernanceUserFacingText.riskTierText(projection.riskTier)
        let digest = normalizedMeaningfulValue(projection.statusDigest) ?? "未回报"
        return summaryLine(
            "项目态势",
            "\(digest) · 阶段 \(HeartbeatGovernanceUserFacingText.projectPhaseText(projection.projectPhase)) · 执行态 \(status) · 风险 \(risk)"
        )
    }

    private static func cadenceLine(
        label: String,
        projection: XTUnifiedDoctorHeartbeatCadenceDimensionProjection
    ) -> String {
        let configured = durationText(projection.configuredSeconds, label: "配置")
        let recommended = durationText(projection.recommendedSeconds, label: "建议")
        let effective = durationText(projection.effectiveSeconds, label: "实际")
        let cadenceSummary = [configured, recommended, effective]
            .compactMap { $0 }
            .joined(separator: " / ")
        let reasons = HeartbeatGovernanceUserFacingText.cadenceReasonSummary(projection.effectiveReasonCodes)
        return summaryLine(label, "\(cadenceSummary.isEmpty ? "未回报" : cadenceSummary) · 原因 \(reasons)")
    }

    private static func nextReviewDueLine(
        _ projection: XTUnifiedDoctorHeartbeatNextReviewDueProjection
    ) -> String {
        let kind = normalizedMeaningfulValue(projection.kind)
        guard let kind, kind != "none" else {
            return summaryLine("下一次 Review", "未回报")
        }

        let dueText: String
        switch projection.due {
        case true:
            dueText = "已到期"
        case false:
            dueText = "未到期"
        case nil:
            dueText = "到期状态未回报"
        }

        var parts = [
            HeartbeatGovernanceUserFacingText.cadenceDimensionText(kind),
            dueText
        ]
        if let atMs = projection.atMs {
            parts.append("at \(atMs) ms")
        }
        if !projection.reasonCodes.isEmpty {
            parts.append("原因 " + HeartbeatGovernanceUserFacingText.cadenceReasonSummary(projection.reasonCodes))
        }
        return summaryLine("下一次 Review", parts.joined(separator: " · "))
    }

    private static func recoveryLine(
        _ projection: XTUnifiedDoctorHeartbeatGovernanceProjection
    ) -> String? {
        guard let decision = projection.recoveryDecision else { return nil }

        let anomalyTexts = orderedUnique(decision.anomalyTypeDisplayTexts)
        let blockedReasonTexts = orderedUnique(decision.blockedLaneReasonDisplayTexts)
        let reviewMetadata = orderedUnique(
            [
                decision.queuedReviewTriggerDisplayText,
                decision.queuedReviewLevelDisplayText,
                decision.queuedReviewRunKindDisplayText
            ]
            .compactMap(normalizedMeaningfulValue)
        )
        let sourceSignals = filteredRecoverySourceSignals(
            decision.sourceSignalDisplayTexts,
            hasStructuredAnomalies: !anomalyTexts.isEmpty,
            hasStructuredBlockedReasons: !blockedReasonTexts.isEmpty,
            hasStructuredReviewMetadata: !reviewMetadata.isEmpty
        )

        var parts: [String] = []
        let systemNextStep = normalizedMeaningfulValue(decision.systemNextStepDisplayText)
        if let systemNextStep {
            parts.append(systemNextStep)
        }
        if let action = normalizedMeaningfulValue(decision.actionDisplayText) {
            parts.append("动作 \(action)")
        }
        if let urgency = normalizedMeaningfulValue(decision.urgencyDisplayText) {
            parts.append("紧急度 \(urgency)")
        }
        if let reason = normalizedMeaningfulValue(decision.reasonDisplayText) {
            parts.append("原因 \(reason)")
        }
        if decision.requiresUserAction == true {
            parts.append("需要用户动作")
        }
        if !anomalyTexts.isEmpty {
            parts.append("异常 " + anomalyTexts.joined(separator: "、"))
        }
        if !reviewMetadata.isEmpty {
            parts.append("复盘候选 " + reviewMetadata.joined(separator: " / "))
        }
        if !blockedReasonTexts.isEmpty {
            parts.append("阻塞原因 " + blockedReasonTexts.joined(separator: "、"))
        }
        if !sourceSignals.isEmpty {
            parts.append("信号 " + sourceSignals.joined(separator: "、"))
        }

        let summary = parts.isEmpty
            ? decision.doctorExplainabilityText
            : parts.joined(separator: " · ")
        return summaryLine("恢复决策", summary)
    }

    private static func projectMemoryLine(
        _ projection: XTUnifiedDoctorHeartbeatGovernanceProjection
    ) -> String? {
        let hasSignal = projection.projectMemoryReady != nil
            || normalizedMeaningfulValue(projection.projectMemoryStatusLine) != nil
            || !projection.projectMemoryIssueCodes.isEmpty
            || normalizedMeaningfulValue(projection.projectMemoryTopIssueSummary) != nil
        guard hasSignal else { return nil }

        var parts: [String] = []
        if let ready = projection.projectMemoryReady {
            parts.append(ready ? "memory 就绪" : "memory 需关注")
        }
        if let statusLine = normalizedMeaningfulValue(projection.projectMemoryStatusLine) {
            parts.append("状态 \(statusLine)")
        }
        if !projection.projectMemoryIssueCodes.isEmpty {
            parts.append(
                "问题 "
                    + projection.projectMemoryIssueCodes
                        .map(XTDoctorProjectMemoryReadinessPresentation.projectMemoryIssueText)
                        .joined(separator: "、")
            )
        }
        if let topIssue = normalizedMeaningfulValue(projection.projectMemoryTopIssueSummary) {
            parts.append("重点 \(topIssue)")
        }

        return summaryLine("Project Memory 信号", parts.joined(separator: " · "))
    }

    private static func qualityBandText(_ raw: String?) -> String {
        HeartbeatGovernanceUserFacingText.qualityBandText(raw)
    }

    private static func projectPhaseText(_ raw: String?) -> String {
        HeartbeatGovernanceUserFacingText.projectPhaseText(raw)
    }

    private static func executionStatusText(_ raw: String?) -> String {
        HeartbeatGovernanceUserFacingText.executionStatusText(raw)
    }

    private static func riskTierText(_ raw: String?) -> String {
        HeartbeatGovernanceUserFacingText.riskTierText(raw)
    }

    private static func cadenceDimensionText(_ raw: String?) -> String {
        HeartbeatGovernanceUserFacingText.cadenceDimensionText(raw)
    }

    private static func durationText(_ seconds: Int?, label: String) -> String? {
        guard let seconds else { return nil }
        return "\(label) \(seconds)s"
    }

    private static func humanizeToken(_ raw: String?) -> String {
        XTMemorySourceTruthPresentation.humanizeToken(raw)
    }

    private static func filteredRecoverySourceSignals(
        _ values: [String],
        hasStructuredAnomalies: Bool,
        hasStructuredBlockedReasons: Bool,
        hasStructuredReviewMetadata: Bool
    ) -> [String] {
        orderedUnique(values.compactMap(normalizedMeaningfulValue)).filter { value in
            if hasStructuredAnomalies, value.hasPrefix("异常 ") {
                return false
            }
            if hasStructuredBlockedReasons, value.hasPrefix("阻塞原因 ") {
                return false
            }
            if hasStructuredReviewMetadata, value.hasPrefix("复盘候选 ") {
                return false
            }
            return true
        }
    }
}

private extension XTDoctorRouteTruthPresentation {
    static func summaryTextFallback(_ raw: String) -> String {
        routeReasonText(raw) ?? XTMemorySourceTruthPresentation.humanizeToken(raw)
    }
}

private func normalizedMeaningfulValue(_ raw: String?) -> String? {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    switch trimmed.lowercased() {
    case "unknown", "none", "(none)", "n/a":
        return nil
    default:
        return trimmed
    }
}

private func normalizedToken(_ raw: String?) -> String {
    normalizedMeaningfulValue(raw)?.lowercased() ?? "unknown"
}

private func displayToken(_ raw: String?) -> String {
    normalizedMeaningfulValue(raw) ?? "未回报"
}

private func governanceOverrideDisplayToken(_ raw: String?) -> String {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "未回报" }
    if trimmed.caseInsensitiveCompare("none") == .orderedSame {
        return "none"
    }
    return displayToken(trimmed)
}

private func firstMeaningfulToken(_ values: String?...) -> String? {
    for value in values {
        if let token = normalizedMeaningfulValue(value) {
            return token
        }
    }
    return nil
}

private func unknownAsEmpty(_ raw: String?) -> String {
    normalizedMeaningfulValue(raw) ?? ""
}

private func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
        ordered.append(trimmed)
    }
    return ordered
}

private func boolish(_ raw: String?) -> Bool? {
    switch normalizedToken(raw) {
    case "true", "yes", "allowed":
        return true
    case "false", "no", "blocked", "denied":
        return false
    default:
        return nil
    }
}

private func allowedStateText(_ raw: String?) -> String {
    guard let value = boolish(raw) else { return "未回报" }
    return value ? "已允许" : "已拦截"
}

private func summaryLine(_ label: String, _ value: String) -> String {
    "\(label)：\(value)"
}

private func trustLevelText(_ raw: String?) -> String {
    switch normalizedToken(raw) {
    case "trusted":
        return "已信任"
    case "legacy":
        return "旧授权档"
    case "untrusted":
        return "未信任"
    default:
        return displayToken(raw)
    }
}

private func budgetClassText(_ raw: String?) -> String {
    switch normalizedToken(raw) {
    case "paid":
        return "付费远端"
    case "local_only":
        return "仅本地"
    case "free":
        return "免费"
    default:
        return displayToken(raw)
    }
}

private func projectionSourceText(_ raw: String?) -> String {
    switch normalizedToken(raw) {
    case "full_route_truth":
        return "完整路由记录"
    case "incident_projection":
        return "事件投影"
    case "counts_only":
        return "计数汇总"
    default:
        return displayToken(raw)
    }
}

private func completenessText(_ raw: String?) -> String {
    switch normalizedToken(raw) {
    case "full":
        return "完整"
    case "partial_counts_only":
        return "只有计数"
    case "partial_projection_only":
        return "只有结果投影"
    case let token where token.hasPrefix("partial_"):
        return "部分"
    default:
        return displayToken(raw)
    }
}
