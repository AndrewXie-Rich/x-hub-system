import Foundation

enum AXProjectResumeBriefBuilder {
    static func render(
        ctx: AXProjectContext,
        role: AXRole = .coder,
        excludingTrailingUserText excludedUserText: String? = nil
    ) -> String {
        let hasRawLog = FileManager.default.fileExists(atPath: ctx.rawLogURL.path)
        let hasRecentContext = FileManager.default.fileExists(atPath: AXRecentContextStore.jsonURL(for: ctx).path)
        if hasRawLog || hasRecentContext {
            AXRecentContextStore.bootstrapFromRawLogIfNeeded(ctx: ctx, maxTurns: 12)
        }

        let memory = AXProjectStore.loadMemoryIfPresent(for: ctx)
        let sessionSummary = loadLatestSessionSummaryIfPresent(for: ctx)
        let recent = filteredRecentContext(
            AXRecentContextStore.load(for: ctx),
            excludingTrailingUserText: excludedUserText
        )
        let executionSnapshot = AXRoleExecutionSnapshots.latestSnapshots(for: ctx)[role] ?? .empty(role: role)
        let routeMemory = AXProjectModelRouteMemoryStore.load(for: ctx, role: role)
        let decisionSnapshot = SupervisorDecisionTrackStore.load(for: ctx)
        let backgroundSnapshot = SupervisorBackgroundPreferenceTrackStore.load(for: ctx)
        let latestUIReview = XTUIReviewStore.loadLatestBrowserPageReference(for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let automationContinuity = latestAutomationContinuity(
            for: ctx,
            projectID: projectId
        )
        let heartbeatProjection = XTHeartbeatMemoryProjectionStore.load(for: ctx)
        let rails = SupervisorDecisionRailResolver.resolve(
            projectId: projectId,
            decisions: decisionSnapshot.events,
            backgroundNotes: backgroundSnapshot.notes
        )

        let goal = preferredGoal(memory: memory, sessionSummary: sessionSummary)
        let currentState = preferredCurrentState(memory: memory, sessionSummary: sessionSummary)
        let blocker = preferredBlocker(memory: memory, sessionSummary: sessionSummary)
        let nextStep = preferredNextStep(memory: memory, sessionSummary: sessionSummary)
        let latestUser = latestRecentMessage(
            from: recent,
            role: "user",
            fallback: sessionSummary?.workingSetSummary.latestUserMessage ?? ""
        )
        let latestAssistant = latestRecentMessage(
            from: recent,
            role: "assistant",
            fallback: sessionSummary?.workingSetSummary.latestAssistantMessage ?? ""
        )
        let decisionLines = importantDecisionLines(rails: rails, memory: memory)
        let preferenceLines = preferredBackgroundLines(rails: rails)
        let executionLine = executionSummaryLine(snapshot: executionSnapshot)
        let routeLine = routeMemorySummaryLine(routeMemory)
        let automationSourceLine = automationContinuitySourceLine(automationContinuity)
        let automationLine = automationContinuitySummaryLine(automationContinuity)
        let automationRecoveryHandoffLine = automationRecoveryHandoffLine(automationContinuity)
        let heartbeatLine = heartbeatRecoverySummaryLine(heartbeatProjection)
        let stageLine = stageSummary(
            goal: goal,
            currentState: currentState,
            blocker: blocker,
            nextStep: nextStep,
            latestUser: latestUser,
            latestAssistant: latestAssistant,
            executionSnapshot: executionSnapshot,
            automationContinuity: automationContinuity
        )

        let hasMeaningfulContent =
            !goal.isEmpty ||
            !currentState.isEmpty ||
            !blocker.isEmpty ||
            !nextStep.isEmpty ||
            latestUIReview != nil ||
            !latestUser.isEmpty ||
            !latestAssistant.isEmpty ||
            automationContinuity != nil ||
            executionSnapshot.hasRecord ||
            routeMemory != nil ||
            !heartbeatLine.isEmpty ||
            !decisionLines.isEmpty ||
            !preferenceLines.isEmpty

        guard hasMeaningfulContent else {
            return """
当前项目还没有足够的持久记忆可用于“接上次进度 / 项目交接摘要”。

建议先完成至少一轮有效对话，或先让系统写入 canonical memory / session summary 后再试一次。
"""
        }

        var lines: [String] = [
            "项目接续摘要（本地整理，不额外调用远端模型）",
            "",
            "阶段概览：\(stageLine)"
        ]

        if !goal.isEmpty {
            lines.append("当前目标：\(goal)")
        }
        if !currentState.isEmpty {
            lines.append("当前状态：\(currentState)")
        }
        if !blocker.isEmpty {
            lines.append("当前阻塞：\(blocker)")
        }
        if !nextStep.isEmpty {
            lines.append("建议下一步：\(nextStep)")
        }
        let uiReviewLine = XTUIReviewPromptDigest.inlineSummary(latestUIReview)
        if !uiReviewLine.isEmpty {
            lines.append("最近一次 UI review：\(uiReviewLine)")
        }
        if !executionLine.isEmpty {
            lines.append("最近一次 \(role.rawValue) 执行：\(executionLine)")
        }
        if !routeLine.isEmpty {
            lines.append("路由记忆：\(routeLine)")
        }
        if !automationSourceLine.isEmpty {
            lines.append("自动化接续来源：\(automationSourceLine)")
        }
        if !automationLine.isEmpty {
            lines.append("自动化检查点：\(automationLine)")
        }
        if !automationRecoveryHandoffLine.isEmpty {
            lines.append("自动化恢复落点：\(automationRecoveryHandoffLine)")
        }
        if !heartbeatLine.isEmpty {
            lines.append("治理恢复：\(heartbeatLine)")
        }

        let recentLines = recentConversationLines(
            latestUser: latestUser,
            latestAssistant: latestAssistant
        )
        if !decisionLines.isEmpty {
            lines.append("")
            lines.append("重要决策：")
            lines.append(contentsOf: decisionLines.map { "- \($0)" })
        }
        if !preferenceLines.isEmpty {
            lines.append("")
            lines.append("长期偏好：")
            lines.append(contentsOf: preferenceLines.map { "- \($0)" })
        }
        if !recentLines.isEmpty {
            lines.append("")
            lines.append("最近会话收尾：")
            lines.append(contentsOf: recentLines.map { "- \($0)" })
        }

        let sources = sourceLabels(
            memory: memory,
            recent: recent,
            sessionSummary: sessionSummary,
            hasAutomationCheckpoint: automationContinuity != nil,
            hasHeartbeatProjection: heartbeatProjection != nil,
            executionSnapshot: executionSnapshot,
            routeMemory: routeMemory,
            hasUIReview: latestUIReview != nil,
            hasDecisionTrack: !rails.decisionTrack.isEmpty,
            hasBackgroundPreferenceTrack: rails.resolutions.contains { $0.preferredBackgroundNote != nil }
        )
        if !sources.isEmpty {
            lines.append("")
            lines.append("来源：\(sources.joined(separator: " / "))")
        }

        lines.append("")
        lines.append("要不要从这里继续？")
        return lines.joined(separator: "\n")
    }

    private static func loadLatestSessionSummaryIfPresent(for ctx: AXProjectContext) -> AXSessionSummaryCapsule? {
        guard FileManager.default.fileExists(atPath: ctx.latestSessionSummaryURL.path),
              let data = try? Data(contentsOf: ctx.latestSessionSummaryURL),
              let summary = try? JSONDecoder().decode(AXSessionSummaryCapsule.self, from: data) else {
            return nil
        }
        return summary
    }

    private static func filteredRecentContext(
        _ recent: AXRecentContext,
        excludingTrailingUserText excludedUserText: String?
    ) -> AXRecentContext {
        let normalizedExcluded = normalizeComparableText(excludedUserText ?? "")
        guard !normalizedExcluded.isEmpty else {
            return recent
        }

        var filtered = recent
        if let last = filtered.messages.last,
           last.role == "user",
           normalizeComparableText(last.content) == normalizedExcluded {
            filtered.messages.removeLast()
        }
        return filtered
    }

    private static func preferredGoal(memory: AXMemory?, sessionSummary: AXSessionSummaryCapsule?) -> String {
        firstNonEmpty([
            memory?.goal,
            sessionSummary?.memorySummary.goal
        ])
    }

    private static func preferredCurrentState(memory: AXMemory?, sessionSummary: AXSessionSummaryCapsule?) -> String {
        firstNonEmpty([
            sessionSummary?.memorySummary.currentState,
            firstNonEmpty(memory?.currentState ?? [])
        ])
    }

    private static func preferredBlocker(memory: AXMemory?, sessionSummary: AXSessionSummaryCapsule?) -> String {
        let blocker = firstNonEmpty([
            sessionSummary?.memorySummary.blocker,
            firstNonEmpty(memory?.openQuestions ?? []),
            firstNonEmpty(memory?.risks ?? [])
        ])
        let trimmed = blocker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return SupervisorBlockerPresentation.label(trimmed)
    }

    private static func preferredNextStep(memory: AXMemory?, sessionSummary: AXSessionSummaryCapsule?) -> String {
        firstNonEmpty([
            sessionSummary?.memorySummary.nextStep,
            firstNonEmpty(memory?.nextSteps ?? [])
        ])
    }

    private static func latestRecentMessage(
        from recent: AXRecentContext,
        role: String,
        fallback: String
    ) -> String {
        for message in recent.messages.reversed() {
            let normalizedRole = message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalizedRole == role else { continue }
            let cleaned = cleanedInline(message.content, max: 180)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return cleanedInline(fallback, max: 180)
    }

    private static func importantDecisionLines(
        rails: SupervisorProjectDecisionRails,
        memory: AXMemory?
    ) -> [String] {
        var merged = dedupeScalars(
            rails.decisionTrack.map(\.statement)
            + (memory?.decisions ?? [])
        )
        if merged.count > 3 {
            merged = Array(merged.prefix(3))
        }
        return merged
    }

    private static func preferredBackgroundLines(rails: SupervisorProjectDecisionRails) -> [String] {
        var statements: [String] = []
        for resolution in rails.resolutions {
            guard let note = resolution.preferredBackgroundNote else { continue }
            let cleaned = cleanedInline(note.statement, max: 180)
            guard !cleaned.isEmpty else { continue }
            statements.append(cleaned)
        }
        let deduped = dedupeScalars(statements)
        if deduped.count > 2 {
            return Array(deduped.prefix(2))
        }
        return deduped
    }

    private static func stageSummary(
        goal: String,
        currentState: String,
        blocker: String,
        nextStep: String,
        latestUser: String,
        latestAssistant: String,
        executionSnapshot: AXRoleExecutionSnapshot,
        automationContinuity: XTAutomationProjectContinuitySnapshot?
    ) -> String {
        if !currentState.isEmpty && !blocker.isEmpty {
            return "\(currentState)；当前卡点是 \(blocker)"
        }
        if !currentState.isEmpty && !nextStep.isEmpty {
            return "\(currentState)；下一步是 \(nextStep)"
        }
        if !currentState.isEmpty {
            return currentState
        }
        if !nextStep.isEmpty && !blocker.isEmpty {
            return "当前待推进 \(nextStep)；但先要处理 \(blocker)"
        }
        if !nextStep.isEmpty {
            return "当前待推进：\(nextStep)"
        }
        if !goal.isEmpty {
            return "围绕目标推进中：\(goal)"
        }
        if let automationContinuity {
            return "自动化停在\(automationContinuitySummaryLine(automationContinuity))"
        }
        if executionSnapshot.hasRecord {
            return "已有最近执行记录，可从最新落点继续。"
        }
        if !latestAssistant.isEmpty {
            return "最近一轮收尾停在助手回复上，可从那里继续。"
        }
        if !latestUser.isEmpty {
            return "最近一轮停在用户要求上，可从那里继续。"
        }
        return "已有可用历史记录，可从最近摘要继续。"
    }

    private static func executionSummaryLine(snapshot: AXRoleExecutionSnapshot) -> String {
        guard snapshot.hasRecord else { return "" }

        let requested = displayModelID(snapshot.requestedModelId)
        let actual = displayModelID(snapshot.actualModelId.isEmpty ? snapshot.requestedModelId : snapshot.actualModelId)
        let reason = humanizedFailureReason(snapshot.effectiveFailureReasonCode, max: 80)
        let retryReason = humanizedFailureReason(snapshot.remoteRetryReasonCode, max: 80)

        switch snapshot.executionPath {
        case "remote_model":
            if snapshot.remoteRetryAttempted {
                let retryFrom = displayModelID(firstNonEmpty([
                    snapshot.remoteRetryFromModelId,
                    snapshot.requestedModelId
                ]))
                let retryTo = displayModelID(firstNonEmpty([
                    snapshot.remoteRetryToModelId,
                    snapshot.actualModelId
                ]))
                let reasonText = retryReason.isEmpty ? "" : "（原因：\(retryReason)）"
                return "远端 \(actual)，期间改试过远端备选 \(retryFrom) -> \(retryTo)\(reasonText)"
            }
            if modelsDiffer(snapshot.requestedModelId, snapshot.actualModelId) && requested != "(none)" {
                return "远端 \(actual)（请求的是 \(requested)）"
            }
            return "远端 \(actual)"
        case "hub_downgraded_to_local":
            let reasonText = reason.isEmpty ? "" : "，原因：\(reason)"
            return "Hub 改派到本地 \(actual)（原远端请求 \(requested)\(reasonText)）"
        case "local_fallback_after_remote_error":
            let reasonText = reason.isEmpty ? "" : "，原因：\(reason)"
            return "本地 \(actual) 兜底（远端首选 \(requested)\(reasonText)）"
        case "local_runtime":
            return "本地 \(actual)"
        case "direct_provider":
            let provider = cleanedInline(snapshot.runtimeProvider, max: 80)
            if provider.isEmpty {
                return actual
            }
            return "\(provider) \(actual)"
        case "remote_error":
            if reason.isEmpty {
                return "远端请求 \(requested) 失败"
            }
            return "远端请求 \(requested) 失败（原因：\(reason)）"
        default:
            return cleanedInline(snapshot.compactSummary, max: 180)
        }
    }

    private static func routeMemorySummaryLine(_ routeMemory: AXProjectModelRouteMemory?) -> String {
        guard let routeMemory else { return "" }

        var parts: [String] = []
        let lastHealthyRemote = cleanedInline(routeMemory.lastHealthyRemoteModelId, max: 120)
        if !lastHealthyRemote.isEmpty {
            parts.append("上次稳定远端是 \(lastHealthyRemote)")
        }
        if routeMemory.consecutiveRemoteFallbackCount > 0 {
            parts.append("近期连续远端 fallback \(routeMemory.consecutiveRemoteFallbackCount) 次")
        }
        let lastActual = cleanedInline(routeMemory.lastActualModelId, max: 120)
        if !lastActual.isEmpty,
           routeMemory.lastExecutionPath != "remote_model" {
            parts.append("最近实际落点是 \(lastActual)")
        }
        let lastReason = humanizedFailureReason(routeMemory.lastFailureReasonCode, max: 80)
        if !lastReason.isEmpty,
           routeMemory.lastExecutionPath != "remote_model" {
            parts.append("最近失败原因是 \(lastReason)")
        }
        return parts.joined(separator: "；")
    }

    private static func latestAutomationContinuity(
        for ctx: AXProjectContext,
        projectID: String
    ) -> XTAutomationProjectContinuitySnapshot? {
        xtAutomationLatestProjectContinuitySnapshot(
            for: ctx,
            projectID: projectID
        )
    }

    private static func automationContinuitySummaryLine(
        _ continuity: XTAutomationProjectContinuitySnapshot?
    ) -> String {
        guard let continuity else { return "" }

        var parts: [String] = []
        if let runID = continuity.runID {
            parts.append("run \(runID)")
        }
        if let effectiveRunID = continuity.effectiveRunID,
           effectiveRunID != continuity.runID {
            parts.append("接续 run \(effectiveRunID)")
        }
        if let runState = continuity.runState {
            parts.append(humanizedAutomationRunState(runState))
        }
        if let attempt = continuity.attempt {
            parts.append("第 \(attempt) 次")
        }
        if let stepLine = automationStepLine(for: continuity) {
            parts.append(stepLine)
        }
        if let verificationLine = automationVerificationLine(for: continuity) {
            parts.append(verificationLine)
        }
        if let blockerLine = automationBlockerLine(for: continuity) {
            parts.append(blockerLine)
        }
        if let retryReasonLine = automationRetryReasonLine(for: continuity) {
            parts.append(retryReasonLine)
        }
        if let recoveryLine = automationRecoveryLine(for: continuity) {
            parts.append(recoveryLine)
        }
        if let retryAfterSeconds = continuity.retryAfterSeconds,
           retryAfterSeconds > 0 {
            parts.append("\(retryAfterSeconds) 秒后可重试")
        }
        return parts.joined(separator: " · ")
    }

    private static func automationRecoveryHandoffLine(
        _ continuity: XTAutomationProjectContinuitySnapshot?
    ) -> String {
        guard let recovery = continuity?.persistedRecoveryAction else { return "" }

        var parts: [String] = [
            "最近恢复\(humanizedAutomationRecoveryAction(recovery.decision.decision))"
        ]
        if let resumeMode = recovery.resumeMode {
            parts.append("resume \(humanizedAutomationResumeMode(resumeMode))")
        }
        let retryStrategy = cleanedInline(recovery.retryStrategy ?? "", max: 120)
        if !retryStrategy.isEmpty {
            parts.append("策略 \(retryStrategy)")
        }
        let retryRunID = cleanedInline(recovery.retryRunID ?? "", max: 120)
        if !retryRunID.isEmpty {
            parts.append("retry run \(retryRunID)")
        } else if let effectiveRunID = continuity?.effectiveRunID,
                  effectiveRunID != continuity?.runID {
            parts.append("接续 run \(effectiveRunID)")
        }
        let holdReason = humanizedFailureReason(recovery.decision.holdReason, max: 80)
        if !holdReason.isEmpty {
            parts.append("hold \(holdReason)")
        }
        return parts.joined(separator: " · ")
    }

    private static func automationContinuitySourceLine(
        _ continuity: XTAutomationProjectContinuitySnapshot?
    ) -> String {
        guard let continuity else { return "" }

        let sourceLabel = humanizedAutomationContinuitySource(continuity.contextSource)
        guard !sourceLabel.isEmpty else { return "" }
        return "\(sourceLabel) 重新水化（仅用于恢复接续，不替代 durable truth）"
    }

    private static func automationStepLine(for continuity: XTAutomationProjectContinuitySnapshot) -> String? {
        let title = firstNonEmpty([
            continuity.currentStepTitle,
            continuity.currentStepID
        ])
        let summary = continuity.currentStepSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stepState = continuity.currentStepState?.displayName ?? ""

        var parts: [String] = []
        if !title.isEmpty {
            parts.append(title)
        }
        if !stepState.isEmpty {
            parts.append(stepState)
        }
        if !summary.isEmpty {
            parts.append(summary)
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func automationVerificationLine(
        for continuity: XTAutomationProjectContinuitySnapshot
    ) -> String? {
        guard let report = continuity.verificationReport else { return nil }

        if !report.required {
            return "无需额外验证"
        }

        var base: String
        if !report.executed {
            base = "验证待执行"
        } else if report.commandCount > 0 {
            if report.passedCommandCount >= report.commandCount {
                base = "验证已通过 \(report.passedCommandCount)/\(report.commandCount)"
            } else {
                base = "验证通过 \(report.passedCommandCount)/\(report.commandCount)"
            }
        } else {
            base = "验证已执行"
        }

        let holdReason = humanizedFailureReason(report.holdReason, max: 80)
        if holdReason.isEmpty {
            return base
        }
        return "\(base)（原因：\(holdReason)）"
    }

    private static func automationBlockerLine(
        for continuity: XTAutomationProjectContinuitySnapshot
    ) -> String? {
        guard let blocker = continuity.blocker else { return nil }
        let summary = cleanedInline(blocker.summary, max: 160)
        guard !summary.isEmpty else { return nil }
        let stage = automationBlockerStageLabel(blocker.stage)
        return stage.isEmpty ? "阻塞：\(summary)" : "\(stage)阻塞：\(summary)"
    }

    private static func automationRetryReasonLine(
        for continuity: XTAutomationProjectContinuitySnapshot
    ) -> String? {
        guard let retryReason = continuity.retryReasonDescriptor else { return nil }

        let summary = cleanedInline(retryReason.summary, max: 160)
        let strategy = cleanedInline(retryReason.strategy, max: 120)
        if !summary.isEmpty, !strategy.isEmpty {
            return "重试原因：\(summary)；策略 \(strategy)"
        }
        if !summary.isEmpty {
            return "重试原因：\(summary)"
        }
        if !strategy.isEmpty {
            return "重试策略：\(strategy)"
        }
        return nil
    }

    private static func automationRecoveryLine(
        for continuity: XTAutomationProjectContinuitySnapshot
    ) -> String? {
        guard let recoveryState = continuity.recoveryState else { return nil }

        var parts: [String] = []
        switch recoveryState.reason {
        case .latestVisibleRecoverable:
            parts.append("恢复可继续")
        case .latestVisibleRetryWait:
            parts.append("恢复等待重试窗口")
        case .latestVisibleRetryBudgetExhausted:
            parts.append("恢复重试额度已用尽")
        case .latestVisibleStableIdentityFailed:
            parts.append("恢复身份校验失败")
        case .latestVisibleStaleRecoverable,
             .latestVisibleActiveRun,
             .latestVisibleCancelled,
             .latestVisibleSuperseded,
             .latestVisibleNotRecoverable,
             .noRecoverableUnsupersededRun:
            return nil
        }

        if !recoveryState.automaticHoldReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(
                "hold \(humanizedFailureReason(recoveryState.automaticHoldReason, max: 80))"
            )
        }
        if let retryAfterRemainingSeconds = recoveryState.retryAfterRemainingSeconds,
           retryAfterRemainingSeconds >= 0 {
            parts.append("剩余 \(retryAfterRemainingSeconds) 秒")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func heartbeatRecoverySummaryLine(
        _ artifact: XTHeartbeatMemoryProjectionArtifact?
    ) -> String {
        guard let artifact else { return "" }

        if let recoveryDecision = artifact.rawPayload.recoveryDecision {
            let summary = cleanedInline(recoveryDecision.summary, max: 160)
            let action = XTMemorySourceTruthPresentation.humanizeToken(recoveryDecision.action.rawValue)
            let reason = humanizedFailureReason(recoveryDecision.reasonCode, max: 80)
            let nextStep = cleanedInline(
                artifact.rawPayload.digestExplainability.systemNextStepText,
                max: 160
            )

            var parts: [String] = []
            if !summary.isEmpty {
                parts.append(summary)
            } else {
                parts.append("heartbeat recovery \(action)")
            }
            if !reason.isEmpty {
                parts.append("原因 \(reason)")
            }
            if !nextStep.isEmpty {
                parts.append("下一步 \(nextStep)")
            }
            return parts.joined(separator: "；")
        }

        if artifact.workingSetProjection.eligible,
           artifact.rawPayload.digestExplainability.visibility == .shown {
            let whatChanged = cleanedInline(
                artifact.rawPayload.digestExplainability.whatChangedText,
                max: 160
            )
            let nextStep = cleanedInline(
                artifact.rawPayload.digestExplainability.systemNextStepText,
                max: 160
            )
            let combined = [whatChanged, nextStep].filter { !$0.isEmpty }
            return combined.joined(separator: "；")
        }

        return ""
    }

    private static func automationBlockerStageLabel(_ stage: XTAutomationBlockerStage) -> String {
        switch stage {
        case .bootstrap:
            return "启动"
        case .action:
            return "执行"
        case .verification:
            return "验证"
        case .policy:
            return "治理"
        case .recovery:
            return "恢复"
        case .runtime:
            return "运行时"
        }
    }

    private static func humanizedAutomationRunState(_ state: XTAutomationRunState) -> String {
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

    private static func humanizedAutomationRecoveryAction(
        _ action: XTAutomationRestartRecoveryAction
    ) -> String {
        switch action {
        case .resume:
            return "继续"
        case .hold:
            return "挂起"
        case .scavenged:
            return "已回收"
        case .suppressed:
            return "抑制"
        }
    }

    private static func humanizedAutomationResumeMode(
        _ mode: XTAutomationRecoveryResumeMode
    ) -> String {
        switch mode {
        case .inPlace:
            return "原地恢复"
        case .retryPackage:
            return "retry package"
        }
    }

    private static func recentConversationLines(latestUser: String, latestAssistant: String) -> [String] {
        var lines: [String] = []
        if !latestUser.isEmpty {
            lines.append("最后一条用户信息：\(quoted(latestUser))")
        }
        if !latestAssistant.isEmpty {
            lines.append("最后一条助手信息：\(quoted(latestAssistant))")
        }
        return lines
    }

    private static func sourceLabels(
        memory: AXMemory?,
        recent: AXRecentContext,
        sessionSummary: AXSessionSummaryCapsule?,
        hasAutomationCheckpoint: Bool,
        hasHeartbeatProjection: Bool,
        executionSnapshot: AXRoleExecutionSnapshot,
        routeMemory: AXProjectModelRouteMemory?,
        hasUIReview: Bool,
        hasDecisionTrack: Bool,
        hasBackgroundPreferenceTrack: Bool
    ) -> [String] {
        var labels: [String] = []
        if memory != nil {
            labels.append("canonical memory")
        }
        if !recent.messages.isEmpty {
            labels.append("recent context")
        }
        if sessionSummary != nil {
            labels.append("latest session summary")
        }
        if hasAutomationCheckpoint {
            labels.append("automation checkpoint")
        }
        if hasHeartbeatProjection {
            labels.append("heartbeat memory projection")
        }
        if hasUIReview {
            labels.append("latest ui review")
        }
        if executionSnapshot.hasRecord {
            labels.append("execution snapshot")
        }
        if routeMemory != nil {
            labels.append("route memory")
        }
        if hasDecisionTrack {
            labels.append("decision track")
        }
        if hasBackgroundPreferenceTrack {
            labels.append("background preference track")
        }
        return labels
    }

    private static func humanizedAutomationContinuitySource(_ raw: String) -> String {
        let normalized = raw
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else { return "" }

        let labels = normalized.map { token -> String in
            switch token {
            case "checkpoint":
                return "本地 checkpoint"
            case "execution_report":
                return "execution report"
            case "retry_package":
                return "retry package"
            default:
                return XTMemorySourceTruthPresentation.humanizeToken(token)
            }
        }

        return labels.joined(separator: " + ")
    }

    private static func dedupeScalars(_ rawValues: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for raw in rawValues {
            let cleaned = cleanedInline(raw, max: 180)
            guard !cleaned.isEmpty else { continue }
            let key = normalizeComparableText(cleaned)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            ordered.append(cleaned)
        }
        return ordered
    }

    private static func firstNonEmpty(_ values: [String?]) -> String {
        for value in values {
            let cleaned = cleanedInline(value ?? "", max: 240)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return ""
    }

    private static func firstNonEmpty(_ values: [String]) -> String {
        for value in values {
            let cleaned = cleanedInline(value, max: 240)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return ""
    }

    private static func cleanedInline(_ raw: String, max: Int) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > max else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: max)
        return String(trimmed[..<end]) + "..."
    }

    private static func normalizeComparableText(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .lowercased()
    }

    private static func modelsDiffer(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedModelKey(lhs)
        let right = normalizedModelKey(rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return false
        }
        return left != right
    }

    private static func normalizedModelKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        if let slash = trimmed.lastIndex(of: "/") {
            let suffix = String(trimmed[trimmed.index(after: slash)...])
            if !suffix.isEmpty {
                return suffix
            }
        }
        return trimmed
    }

    private static func displayModelID(_ raw: String) -> String {
        let cleaned = cleanedInline(raw, max: 120)
        return cleaned.isEmpty ? "(none)" : cleaned
    }

    private static func humanizedFailureReason(_ raw: String, max: Int) -> String {
        let cleaned = cleanedInline(raw, max: max * 2)
        guard !cleaned.isEmpty else { return "" }

        let display = XTRouteTruthPresentation.denyCodeText(cleaned)
            ?? XTRouteTruthPresentation.routeReasonDisplayText(cleaned)
            ?? cleaned
        return cleanedInline(display, max: max)
    }

    private static func quoted(_ raw: String) -> String {
        "“\(cleanedInline(raw, max: 160))”"
    }
}
