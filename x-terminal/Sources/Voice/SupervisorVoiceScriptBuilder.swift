import Foundation

enum SupervisorVoiceScriptBuilder {
    static func blockedHeartbeatScript(
        blockerCount: Int,
        projectName: String,
        blockerSummary: String,
        progressLine: String?,
        blockerStreak: Int,
        nextStepLine: String?
    ) -> [String] {
        var script = [
            "先说最重要的。当前有 \(max(1, blockerCount)) 个阻塞项目。",
            "\(spokenProjectName(projectName)) 现在卡在：\(inline(blockerSummary, maxChars: 44))。"
        ]
        if let progressLine {
            script.append(progressLine)
        }
        if blockerStreak > 1 {
            script.append("这个阻塞已经连续 \(blockerStreak) 次心跳没有消掉。")
        }
        if let nextStepLine {
            script.append("你现在只需要：\(inline(nextStepLine, maxChars: 40))。")
        }
        return normalizeScript(script, trigger: .blocked)
    }

    static func permissionHeartbeatScript(
        permissionCount: Int,
        projectName: String,
        summary: String,
        progressLine: String?,
        nextStepLine: String?
    ) -> [String] {
        var script = [
            "先说最重要的。当前有 \(max(1, permissionCount)) 个待授权项目。",
            "\(spokenProjectName(projectName)) 现在等你处理：\(inline(summary, maxChars: 44))。"
        ]
        if let progressLine {
            script.append(progressLine)
        }
        if let nextStepLine {
            script.append("你现在只需要：\(inline(nextStepLine, maxChars: 40))。")
        }
        return normalizeScript(script, trigger: .authorization)
    }

    static func governanceRepairHeartbeatScript(
        repairCount: Int,
        projectName: String,
        summary: String,
        progressLine: String?,
        nextStepLine: String?
    ) -> [String] {
        var script = [
            "先说最重要的。当前有 \(max(1, repairCount)) 个项目需要先修治理设置。",
            "\(spokenProjectName(projectName)) 现在被治理边界挡住了：\(inline(summary, maxChars: 48))。"
        ]
        if let progressLine {
            script.append(progressLine)
        }
        if let nextStepLine {
            script.append("你现在只需要：\(inline(nextStepLine, maxChars: 40))。")
        }
        return normalizeScript(script, trigger: .blocked)
    }

    static func recoveryHeartbeatScript(
        trigger: SupervisorVoiceJobTrigger,
        projectName: String,
        summary: String,
        detail: String,
        priorityReason: String?,
        progressLine: String?,
        nextStepLine: String?
    ) -> [String] {
        let trimmedSummary = inline(summary, maxChars: 48)
        let trimmedDetail = inline(detail, maxChars: 56)
        let trimmedReason = inline(priorityReason ?? "", maxChars: 44)

        var script = [
            trigger == .authorization
                ? "先说最重要的。当前有一项恢复授权要先处理。"
                : "先说最重要的。当前有一项恢复跟进要先处理。"
        ]
        if !trimmedSummary.isEmpty {
            script.append(trimmedSummary)
        } else {
            script.append("\(spokenProjectName(projectName)) 当前有一项恢复动作需要先处理。")
        }
        if !trimmedDetail.isEmpty, trimmedDetail != trimmedSummary {
            script.append(trimmedDetail)
        }
        if !trimmedReason.isEmpty {
            script.append("为什么先看它：\(trimmedReason)。")
        }
        if let progressLine {
            script.append(progressLine)
        }
        if let nextStepLine {
            let next = inline(nextStepLine, maxChars: 44)
            if !next.isEmpty {
                script.append("你现在只需要：\(next)。")
            }
        }
        return normalizeScript(script, trigger: trigger)
    }

    static func voiceReadinessHeartbeatScript(
        kind: VoiceReadinessCheckKind,
        readyForFirstTask: Bool,
        headline: String,
        summary: String,
        progressLine: String?,
        nextStepLine: String?
    ) -> [String] {
        var script: [String]
        if kind == .pairingValidity {
            if readyForFirstTask {
                script = [
                    "先报当前状态。首个任务已经能做，但配对续连还需要确认。",
                    inline(summary, maxChars: 56).isEmpty
                        ? "当前正式异网入口还没有完成验证。"
                        : "\(inline(summary, maxChars: 56))。"
                ]
            } else {
                script = [
                    "先报当前状态。当前配对续连还没恢复。",
                    inline(headline, maxChars: 52).isEmpty
                        ? "当前正式异网入口还没有恢复。"
                        : "当前卡在：\(inline(headline, maxChars: 52))。"
                ]
            }
        } else if readyForFirstTask {
            script = [
                "先报当前状态。语音首个任务已经能做，但还有一项修复别忘了。",
                inline(summary, maxChars: 56).isEmpty
                    ? "当前还有一项语音修复待处理。"
                    : "\(inline(summary, maxChars: 56))。"
            ]
        } else {
            script = [
                "先报当前状态。Supervisor 语音链路现在还是失败闭锁。",
                inline(headline, maxChars: 52).isEmpty
                    ? "当前语音主链还没恢复。"
                    : "当前卡在：\(inline(headline, maxChars: 52))。"
            ]
        }
        if let progressLine {
            script.append(progressLine)
        }
        if let nextStepLine {
            script.append("如果你现在要介入，先 \(inline(nextStepLine, maxChars: 44))。")
        }
        return normalizeScript(script, trigger: readyForFirstTask ? .completed : .blocked)
    }

    static func pendingGrantAnnouncementScript(
        pendingCount: Int,
        projectName: String,
        capabilitySummary: String,
        scopeSummary: String?,
        reasonSummary: String?,
        sourceSummary: String?
    ) -> [String] {
        var script: [String] = []
        if pendingCount > 1 {
            script.append("先说最重要的。当前有 \(max(2, pendingCount)) 笔待处理的 Hub 授权，我先报最紧急的一笔。")
        } else {
            script.append("先说最重要的。现在有一笔新的 Hub 授权待处理。")
        }
        script.append("\(spokenProjectName(projectName)) 现在需要你确认：\(inline(capabilitySummary, maxChars: 40))。")
        if let sourceSummary {
            script.append("这笔是从 \(inline(sourceSummary, maxChars: 36)) 进来的。")
        }
        if let scopeSummary {
            script.append("\(inline(scopeSummary, maxChars: 44))。")
        }
        if let reasonSummary {
            script.append("原因是：\(inline(reasonSummary, maxChars: 40))。")
        }
        script.append("我说完后会继续听。你可以直接说，批准这笔授权，或者，拒绝这笔授权。")
        return normalizeScript(script, trigger: .authorization)
    }

    static func pendingSkillApprovalAnnouncementScript(
        pendingCount: Int,
        authorizationMode: SupervisorPendingSkillAuthorizationMode = .localApproval,
        projectName: String,
        skillSummary: String,
        routingSummary: String?,
        toolSummary: String?,
        reasonSummary: String?
    ) -> [String] {
        var script: [String] = []
        switch authorizationMode {
        case .localApproval:
            if pendingCount > 1 {
                script.append("先说最重要的。当前有 \(max(2, pendingCount)) 条待处理的本地技能调用，我先报最早的一条。")
            } else {
                script.append("先说最重要的。现在有一条新的本地技能调用待你审批。")
            }
            script.append("\(spokenProjectName(projectName)) 现在需要你确认：\(inline(skillSummary, maxChars: 40))。")
        case .hubGrant:
            if pendingCount > 1 {
                script.append("先说最重要的。当前有 \(max(2, pendingCount)) 条待处理的技能授权，我先报最早的一条。")
            } else {
                script.append("先说最重要的。现在有一条新的技能授权待处理。")
            }
            script.append("\(spokenProjectName(projectName)) 现在需要你处理授权：\(inline(skillSummary, maxChars: 40))。")
        case .blocked:
            if pendingCount > 1 {
                script.append("先说最重要的。当前有 \(max(2, pendingCount)) 条待处理的技能治理阻塞，我先报最早的一条。")
            } else {
                script.append("先说最重要的。现在有一条新的技能治理阻塞待处理。")
            }
            script.append("\(spokenProjectName(projectName)) 现在需要你处理治理阻塞：\(inline(skillSummary, maxChars: 40))。")
        }
        if let routingSummary {
            script.append("系统说明：\(inline(routingSummary, maxChars: 96))。")
        }
        if let toolSummary {
            script.append("这次动作会碰到：\(inline(toolSummary, maxChars: 40))。")
        }
        if let reasonSummary {
            script.append("当前卡在：\(inline(reasonSummary, maxChars: 40))。")
        }
        switch authorizationMode {
        case .localApproval:
            script.append("我说完后会继续听。你可以直接说，可以，或者不行。也可以说，批准这个技能调用，或者拒绝这个技能调用。")
        case .hubGrant:
            script.append("我说完后会继续听。这条需要先到 Hub 授权面板处理；如果你现在不想继续，也可以直接说，拒绝这个技能调用。")
        case .blocked:
            script.append("我说完后会继续听。这条需要先按阻塞提示处理；如果你现在不想继续，也可以直接说，拒绝这个技能调用。")
        }
        return normalizeScript(script, trigger: .authorization)
    }

    static func stableHeartbeatScript(
        activeProjectCount: Int,
        managedProjectCount: Int,
        queueCount: Int,
        leadProjectName: String,
        progressLine: String?,
        nextStepLine: String?
    ) -> [String] {
        var script: [String] = []
        if activeProjectCount > 0 {
            script.append("先报当前状态。现在有 \(activeProjectCount) 个项目在跑，没有新的阻塞。")
        } else if managedProjectCount > 0 {
            script.append("先报当前状态。当前没有项目在跑，也没有新的阻塞。")
            script.append("我这边接管了 \(managedProjectCount) 个项目，先按优先级盯下一步。")
        } else {
            script.append("先报当前状态。当前还没有项目在跑，也没有新的阻塞。")
        }
        if queueCount > 0 {
            script.append("\(queueCount) 个项目还在排队，我先盯着 \(spokenProjectName(leadProjectName))。")
        } else if progressLine == nil {
            script.append("主线先继续稳定推进。")
        }
        if let progressLine {
            script.append(progressLine)
        }
        if let nextStepLine {
            script.append("如果你现在要介入，先 \(inline(nextStepLine, maxChars: 40))。")
        }
        return normalizeScript(script, trigger: .completed)
    }

    static func routeDiagnoseHeartbeatScript(
        projectName: String,
        routeReason: String?,
        failureAction: String?,
        routeHint: String?,
        followUpLine: String?,
        progressLine: String?,
        nextStepLine: String?
    ) -> [String] {
        let trimmedReason = inline(routeReason ?? "", maxChars: 32)
        let trimmedAction = inline(failureAction ?? "", maxChars: 40)
        let trimmedHint = inline(routeHint ?? "", maxChars: 52)
        let trimmedFollowUp = inline(followUpLine ?? "", maxChars: 52)

        var script = [
            "先报当前状态。现在没有新的阻塞，但模型路由值得先看一下。"
        ]
        if !trimmedReason.isEmpty {
            script.append("\(spokenProjectName(projectName)) 最近最常见的路由问题是：\(trimmedReason)。")
        } else {
            script.append("\(spokenProjectName(projectName)) 最近 route repair 还在反复失败。")
        }
        if !trimmedAction.isEmpty {
            script.append("最近一次失败停在：\(trimmedAction)。")
        }
        if !trimmedHint.isEmpty {
            script.append("方向上更像：\(trimmedHint)。")
        }
        if !trimmedFollowUp.isEmpty {
            script.append("\(trimmedFollowUp)。")
        }
        if let progressLine {
            script.append(progressLine)
        }
        if let nextStepLine {
            let normalizedNextStep = nextStepLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedNextStep.contains("/route diagnose")
                || normalizedNextStep.localizedCaseInsensitiveContains("route diagnose") {
                script.append("如果你现在要介入，先看 route diagnose。")
            } else {
                script.append("如果你现在要介入，先 \(inline(normalizedNextStep, maxChars: 40))。")
            }
        } else {
            script.append("如果你现在要介入，先看 route diagnose。")
        }
        return normalizeScript(script, trigger: .completed)
    }

    static func governanceSignalHeartbeatScript(
        signal: SupervisorGovernanceSignalVoicePresentation,
        progressLine: String?,
        nextStepLine: String?
    ) -> [String] {
        let headline = inline(signal.headlineText, maxChars: 40)
        let detail = inline(signal.detailText, maxChars: 56)
        let metadata = inline(signal.metadataText, maxChars: 96)
        let action = inline(signal.actionText ?? "", maxChars: 32)

        var script: [String] = []
        if !headline.isEmpty {
            script.append(headline)
        }

        if !detail.isEmpty {
            script.append(detail)
        } else {
            switch signal.trigger {
            case .authorization:
                script.append("当前有一项待确认的治理动作")
            case .blocked:
                script.append("当前有一项治理风险需要先处理")
            case .completed, .userQueryReply:
                script.append("当前有一项新的治理信号值得先看")
            }
        }

        if !metadata.isEmpty, metadata != detail {
            script.append(metadata)
        }
        if let progressLine {
            script.append(progressLine)
        }
        if !action.isEmpty {
            switch signal.trigger {
            case .authorization, .blocked:
                script.append("你现在只需要：\(action)")
            case .completed, .userQueryReply:
                script.append("如果你现在要介入，先\(action)")
            }
        } else if let nextStepLine {
            let next = inline(nextStepLine, maxChars: 40)
            if !next.isEmpty {
                switch signal.trigger {
                case .authorization, .blocked:
                    script.append("你现在只需要：\(next)")
                case .completed, .userQueryReply:
                    script.append("如果你现在要介入，先\(next)")
                }
            }
        }
        return normalizeScript(script, trigger: signal.trigger)
    }

    static func projectionScript(
        ttsScript: [String],
        trigger: SupervisorVoiceJobTrigger
    ) -> [String] {
        normalizeScript(ttsScript, trigger: trigger)
    }

    static func projectionFallbackScript(
        topline: String,
        blocker: String,
        pendingGrantCount: Int,
        nextBestAction: String,
        summary: String
    ) -> [String] {
        var script: [String] = []
        let trimmedTopline = inline(topline, maxChars: 80)
        let trimmedSummary = inline(summary, maxChars: 80)
        if !trimmedTopline.isEmpty {
            script.append(trimmedTopline)
        } else if !trimmedSummary.isEmpty {
            script.append(trimmedSummary)
        }
        let trimmedBlocker = inline(blocker, maxChars: 48)
        if !trimmedBlocker.isEmpty {
            script.append("当前阻塞是：\(trimmedBlocker)。")
        }
        if pendingGrantCount > 0 {
            script.append("当前有 \(pendingGrantCount) 个待授权项。")
        }
        let trimmedNext = inline(nextBestAction, maxChars: 48)
        if !trimmedNext.isEmpty {
            script.append("你现在只需要：\(trimmedNext)。")
        }
        return normalizeScript(script, trigger: pendingGrantCount > 0 ? .authorization : .blocked)
    }

    static func conciseReplyScript(from text: String) -> [String] {
        let sanitized = text
            .replacingOccurrences(of: "```", with: " ")
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "•", with: "")
                    .replacingOccurrences(of: "📊", with: "")
                    .replacingOccurrences(of: "🚧", with: "")
                    .replacingOccurrences(of: "🎯", with: "")
                    .replacingOccurrences(of: "✅", with: "")
                    .replacingOccurrences(of: "❌", with: "")
                    .replacingOccurrences(of: "⚠️", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty &&
                !line.hasPrefix("[") &&
                !line.hasPrefix("```")
            }

        guard !sanitized.isEmpty else { return [] }

        var script: [String] = []
        for line in sanitized {
            let spoken = normalizedReplyLine(line)
            guard !spoken.isEmpty else { continue }
            script.append(spoken)
            if script.count == 2 { break }
        }
        return normalizeScript(script, trigger: .userQueryReply)
    }

    static func previewScript(
        locale: VoiceSupportedLocale,
        timbre: VoiceTimbrePreset,
        speedLabel: String,
        resolvedOutput: VoicePlaybackSource,
        selectedVoicePackTitle: String?
    ) -> [String] {
        let outputLabel = localizedOutputLabel(
            locale: locale,
            resolvedOutput: resolvedOutput,
            selectedVoicePackTitle: selectedVoicePackTitle
        )

        switch locale {
        case .englishUS:
            return normalizeScript(
                [
                    "Supervisor here. The build is green, one lane still has a blocker, and I am ready to move the next step forward.",
                    "Current output is \(outputLabel), tuned \(localizedTimbreLabel(timbre, locale: locale)) at \(speedLabel). If this sounds right, keep it for live updates."
                ],
                trigger: .userQueryReply
            )
        case .chineseMainland:
            return normalizeScript(
                [
                    "这里是 Supervisor。当前构建已通过，还有一个泳道阻塞，我准备继续推进下一步。",
                    "当前输出是\(outputLabel)，风格偏\(localizedTimbreLabel(timbre, locale: locale))，语速 \(speedLabel)。如果这段听起来自然，就继续用它做实时播报。"
                ],
                trigger: .userQueryReply
            )
        }
    }

    static func normalizeScript(
        _ lines: [String],
        trigger: SupervisorVoiceJobTrigger
    ) -> [String] {
        lines.enumerated().compactMap { index, raw in
            normalizedLine(raw, index: index, trigger: trigger)
        }
    }

    private static func normalizedReplyLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return inline(trimmed, maxChars: 88)
    }

    private static func normalizedLine(
        _ text: String,
        index: Int,
        trigger: SupervisorVoiceJobTrigger
    ) -> String? {
        var cleaned = text
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if cleaned.hasPrefix("Supervisor 更新。") {
            cleaned = cleaned.replacingOccurrences(of: "Supervisor 更新。", with: index == 0 ? "先说最重要的。" : "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.hasPrefix("建议下一步：") {
            let suffix = cleaned.replacingOccurrences(of: "建议下一步：", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned = suffix.isEmpty ? "" : "你现在只需要：\(suffix)"
        } else if cleaned.hasPrefix("当前关注：") {
            let suffix = cleaned.replacingOccurrences(of: "当前关注：", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned = suffix.isEmpty ? "" : "我先盯着 \(suffix)"
        }
        guard !cleaned.isEmpty else { return nil }

        if index == 0,
           trigger == .completed,
           !cleaned.hasPrefix("先报当前状态。") &&
           !cleaned.hasPrefix("先说最重要的。") &&
           !cleaned.hasPrefix("Supervisor Hub 简报。") {
            cleaned = "先报当前状态。\(cleaned)"
        }
        if index == 0,
           (trigger == .blocked || trigger == .authorization),
           !cleaned.hasPrefix("先说最重要的。") &&
           !cleaned.hasPrefix("Supervisor Hub 简报。") &&
           !cleaned.hasPrefix("当前项目背景记忆还没喂够") {
            cleaned = "先说最重要的。\(cleaned)"
        }

        return ensureSentenceEnding(inline(cleaned, maxChars: 96))
    }

    private static func spokenProjectName(_ text: String) -> String {
        let cleaned = inline(text, maxChars: 32)
        return cleaned.isEmpty ? "当前项目" : cleaned
    }

    private static func inline(_ text: String, maxChars: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        if collapsed.count <= maxChars {
            return collapsed
        }
        let index = collapsed.index(collapsed.startIndex, offsetBy: max(1, maxChars))
        return String(collapsed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ensureSentenceEnding(_ text: String) -> String {
        guard let last = text.last else { return text }
        if "。！？!?…".contains(last) {
            return text
        }
        return text + "。"
    }

    private static func localizedOutputLabel(
        locale: VoiceSupportedLocale,
        resolvedOutput: VoicePlaybackSource,
        selectedVoicePackTitle: String?
    ) -> String {
        switch resolvedOutput {
        case .hubVoicePack:
            if let selectedVoicePackTitle,
               !selectedVoicePackTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                switch locale {
                case .englishUS:
                    return "Hub voice pack \(selectedVoicePackTitle)"
                case .chineseMainland:
                    return "Hub 音包 \(selectedVoicePackTitle)"
                }
            }
            switch locale {
            case .englishUS:
                return "Hub voice pack"
            case .chineseMainland:
                return "Hub 音包"
            }
        case .systemSpeech:
            switch locale {
            case .englishUS:
                return "system speech"
            case .chineseMainland:
                return "系统语音"
            }
        }
    }

    private static func localizedTimbreLabel(
        _ timbre: VoiceTimbrePreset,
        locale: VoiceSupportedLocale
    ) -> String {
        switch locale {
        case .englishUS:
            switch timbre {
            case .neutral:
                return "neutral"
            case .warm:
                return "warm"
            case .clear:
                return "clear"
            case .bright:
                return "bright"
            case .calm:
                return "calm"
            }
        case .chineseMainland:
            switch timbre {
            case .neutral:
                return "中性"
            case .warm:
                return "温暖"
            case .clear:
                return "清晰"
            case .bright:
                return "明亮"
            case .calm:
                return "沉稳"
            }
        }
    }
}
