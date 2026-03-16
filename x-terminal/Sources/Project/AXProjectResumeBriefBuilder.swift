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
        let stageLine = stageSummary(
            goal: goal,
            currentState: currentState,
            blocker: blocker,
            nextStep: nextStep,
            latestUser: latestUser,
            latestAssistant: latestAssistant,
            executionSnapshot: executionSnapshot
        )

        let hasMeaningfulContent =
            !goal.isEmpty ||
            !currentState.isEmpty ||
            !blocker.isEmpty ||
            !nextStep.isEmpty ||
            latestUIReview != nil ||
            !latestUser.isEmpty ||
            !latestAssistant.isEmpty ||
            executionSnapshot.hasRecord ||
            routeMemory != nil ||
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
        firstNonEmpty([
            sessionSummary?.memorySummary.blocker,
            firstNonEmpty(memory?.openQuestions ?? []),
            firstNonEmpty(memory?.risks ?? [])
        ])
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
        executionSnapshot: AXRoleExecutionSnapshot
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
        let reason = cleanedInline(snapshot.fallbackReasonCode, max: 80)
        let retryReason = cleanedInline(snapshot.remoteRetryReasonCode, max: 80)

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
        let lastReason = cleanedInline(routeMemory.lastFailureReasonCode, max: 80)
        if !lastReason.isEmpty,
           routeMemory.lastExecutionPath != "remote_model" {
            parts.append("最近失败原因是 \(lastReason)")
        }
        return parts.joined(separator: "；")
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

    private static func quoted(_ raw: String) -> String {
        "“\(cleanedInline(raw, max: 160))”"
    }
}
