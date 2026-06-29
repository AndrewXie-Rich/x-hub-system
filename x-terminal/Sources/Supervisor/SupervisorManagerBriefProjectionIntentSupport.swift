import Foundation

extension SupervisorManager {
    func looksLikeSupervisorCasualConversationPrompt(_ normalized: String) -> Bool {
        guard normalizedContainsAny(
            normalized,
            [
                "你最近",
                "你今天",
                "你现在",
                "你还好吗",
                "你好吗",
                "感觉如何",
                "感觉怎么样",
                "你感觉如何",
                "你感觉怎么样",
                "你觉得如何",
                "你觉得怎么样",
                "体验如何",
                "体验怎么样",
                "心情如何",
                "心情怎么样",
                "聊聊天",
                "聊聊",
                "说说话",
                "在这套系统里",
                "在这个系统里",
                "这个系统里",
                "你在这里",
                "你在这套系统"
            ]
        ) else {
            return false
        }

        return !normalizedContainsAny(
            normalized,
            [
                "项目",
                "状态",
                "进度",
                "进展",
                "卡点",
                "阻塞",
                "下一步",
                "优先级",
                "汇报",
                "简报",
                "brief",
                "summary",
                "blocker",
                "priority",
                "nextstep"
            ]
        )
    }

    func shouldBypassSupervisorBriefRouting(_ normalized: String) -> Bool {
        guard !normalized.isEmpty else { return false }
        if looksLikeSupervisorCasualConversationPrompt(normalized) {
            return true
        }

        if normalizedContainsAny(
            normalized,
            [
                "不用当成项目回答",
                "不要当成项目回答",
                "别当成项目回答",
                "不用当成项目",
                "不要当成项目",
                "别当成项目",
                "不是项目问题",
                "notaprojectanswer",
                "notprojectspecific",
                "donttreatitasaproject"
            ]
        ) {
            return true
        }

        let systemMetaSubjects = [
            "这套系统",
            "这个系统",
            "系统本身",
            "整个系统",
            "xhub",
            "x hub",
            "xhubsystem",
            "xterminal",
            "x terminal",
            "supervisor",
            "记忆系统",
            "治理协议",
            "review policy",
            "heartbeat",
            "safe point",
            "上下文",
            "人格",
            "persona",
            "协议",
            "架构",
            "内核"
        ]
        let metaDiscussionSignals = [
            "建议",
            "你觉得",
            "怎么看",
            "详细说说",
            "详细讲讲",
            "说说",
            "聊聊",
            "brainstorm",
            "评估",
            "分析",
            "review",
            "复盘",
            "方案",
            "设计",
            "改进",
            "优化",
            "优先做什么",
            "先做哪个",
            "哪里不通",
            "怎么做更好"
        ]
        return normalizedContainsAny(normalized, systemMetaSubjects)
            && normalizedContainsAny(normalized, metaDiscussionSignals)
    }

    func isNaturalSupervisorBriefRequest(
        _ normalized: String,
        projectSelectionSource: String?
    ) -> Bool {
        let strongSignals = [
            "汇报",
            "简报",
            "brief",
            "summary",
            "状态",
            "进度",
            "进展",
            "卡点",
            "卡在哪",
            "阻塞",
            "下一步",
            "先做哪个",
            "优先级",
            "priority"
        ]
        if normalizedContainsAny(normalized, strongSignals) {
            return true
        }

        let softSignals = [
            "怎么样",
            "如何了",
            "到哪了"
        ]
        guard normalizedContainsAny(normalized, softSignals) else { return false }

        if projectSelectionSource == "explicit_user_mention" || projectSelectionSource == "current_task" {
            return true
        }

        return normalizedContainsAny(
            normalized,
            [
                "项目",
                "这个项目",
                "当前项目",
                "当前任务",
                "这个任务",
                "workflow",
                "release",
                "staging"
            ]
        )
    }

    func shouldUseSupervisorBriefProjectionForStatusQuery(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { return false }
        let normalized = normalizedLookupKey(trimmed)
        guard !normalized.isEmpty else { return false }
        guard !shouldBypassSupervisorBriefRouting(normalized) else { return false }
        let tokens = [
            "进度",
            "状态",
            "卡点",
            "阻塞",
            "下一步",
            "授权",
            "grant",
            "status",
            "progress",
            "blocker",
            "brief",
            "summary",
            "nextstep",
            "next",
            "进展",
            "优先",
            "优先级",
            "先做哪个",
            "priority"
        ]
        return tokens.contains(where: { normalized.contains(normalizedLookupKey($0)) })
    }

    func supervisorBriefProjectionVoiceQueryTrigger(_ text: String) -> String {
        let normalized = normalizedLookupKey(text)
        if normalized.contains("授权") || normalized.contains("grant") {
            return "awaiting_authorization"
        }
        if normalized.contains("卡点") || normalized.contains("阻塞") || normalized.contains("blocker") {
            return "blocked"
        }
        if normalized.contains("下一步") || normalized.contains("建议") || normalized.contains("nextstep") {
            return "critical_path_changed"
        }
        return "daily_digest"
    }
}
