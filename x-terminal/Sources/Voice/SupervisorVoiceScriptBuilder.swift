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
            script.append("先说最重要的。当前有 \(max(2, pendingCount)) 笔待处理的 Hub grant，我先报最紧急的一笔。")
        } else {
            script.append("先说最重要的。现在有一笔新的 Hub grant 待处理。")
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
        script.append("我说完后会继续听。你可以直接说，批准这个 grant，或者，拒绝这个 grant。")
        return normalizeScript(script, trigger: .authorization)
    }

    static func stableHeartbeatScript(
        projectCount: Int,
        queueCount: Int,
        leadProjectName: String,
        progressLine: String?,
        nextStepLine: String?
    ) -> [String] {
        var script = [
            "先报当前状态。现在有 \(max(1, projectCount)) 个项目在跑，没有新的阻塞。"
        ]
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
}
