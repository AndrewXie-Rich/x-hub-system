import Foundation

enum SupervisorHeartbeatPriority: Int, Equatable {
    case immediate = 0
    case attention = 1
    case watch = 2
    case stable = 3

    var label: String {
        switch self {
        case .immediate:
            return "立即处理"
        case .attention:
            return "优先关注"
        case .watch:
            return "继续观察"
        case .stable:
            return "最近汇报"
        }
    }

    var tone: SupervisorHeaderControlTone {
        switch self {
        case .immediate:
            return .warning
        case .attention:
            return .accent
        case .watch:
            return .success
        case .stable:
            return .neutral
        }
    }

    var actionStyle: SupervisorHeartbeatActionStyle {
        switch self {
        case .immediate, .attention:
            return .prominent
        case .watch, .stable:
            return .standard
        }
    }

    var belongsToAttentionSection: Bool {
        switch self {
        case .immediate, .attention:
            return true
        case .watch, .stable:
            return false
        }
    }
}

enum SupervisorHeartbeatActionStyle: Equatable {
    case standard
    case prominent
}

enum SupervisorHeartbeatAction: Equatable {
    case openFocus(String)
}

struct SupervisorHeartbeatActionDescriptor: Equatable, Identifiable {
    var action: SupervisorHeartbeatAction
    var label: String
    var style: SupervisorHeartbeatActionStyle
    var tone: SupervisorHeaderControlTone
    var isEnabled: Bool

    var id: String {
        switch action {
        case .openFocus(let rawURL):
            return "openFocus|\(rawURL)|\(label)|\(style)|\(tone)|\(isEnabled)"
        }
    }
}

struct SupervisorHeartbeatEntryPresentation: Equatable, Identifiable {
    var id: String
    var timeText: String
    var changeText: String
    var changeTone: SupervisorHeaderControlTone
    var reasonText: String
    var priority: SupervisorHeartbeatPriority
    var priorityText: String
    var priorityTone: SupervisorHeaderControlTone
    var headlineText: String
    var headlineTone: SupervisorHeaderControlTone
    var detailLines: [String]
    var contentText: String
    var focusAction: SupervisorHeartbeatActionDescriptor?
}

struct SupervisorHeartbeatOverviewPresentation: Equatable {
    var priority: SupervisorHeartbeatPriority
    var priorityText: String
    var priorityTone: SupervisorHeaderControlTone
    var headlineText: String
    var detailText: String
    var metadataText: String
    var focusAction: SupervisorHeartbeatActionDescriptor?
}

struct SupervisorHeartbeatFeedPresentation: Equatable {
    var title: String
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var emptyStateText: String
    var overview: SupervisorHeartbeatOverviewPresentation?
    var entries: [SupervisorHeartbeatEntryPresentation]

    var isEmpty: Bool {
        entries.isEmpty
    }
}

enum SupervisorHeartbeatPresentation {
    private enum FocusKind: Equatable {
        case governance
        case routeDiagnose
        case authorization
        case skillRecord
        case project
        case supervisor
        case settings
        case other
    }

    private struct FocusDescriptor: Equatable {
        var kind: FocusKind
        var actionLabel: String
    }

    private struct EntrySummary: Equatable {
        var priority: SupervisorHeartbeatPriority
        var headlineText: String
        var headlineTone: SupervisorHeaderControlTone
        var detailLines: [String]
    }

    static func map(
        entries: [SupervisorManager.HeartbeatFeedEntry],
        limit: Int = 4,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> SupervisorHeartbeatFeedPresentation {
        let unsortedEntries = entries.enumerated().map { index, entry in
            let focusDescriptor = focusDescriptor(for: entry.focusActionURL)
            let summary = summarize(entry: entry, focusDescriptor: focusDescriptor)
            return (
                index: index,
                entry: SupervisorHeartbeatEntryPresentation(
                    id: entry.id,
                    timeText: timeText(
                        entry.createdAt,
                        timeZone: timeZone,
                        locale: locale
                    ),
                    changeText: entry.changed ? "有变化" : "无重大变化",
                    changeTone: entry.changed ? .success : .neutral,
                    reasonText: reasonText(for: entry.reason),
                    priority: summary.priority,
                    priorityText: summary.priority.label,
                    priorityTone: summary.priority.tone,
                    headlineText: summary.headlineText,
                    headlineTone: summary.headlineTone,
                    detailLines: summary.detailLines,
                    contentText: entry.content,
                    focusAction: nonEmpty(entry.focusActionURL).map {
                        SupervisorHeartbeatActionDescriptor(
                            action: .openFocus($0),
                            label: focusDescriptor.actionLabel,
                            style: summary.priority.actionStyle,
                            tone: summary.headlineTone,
                            isEnabled: true
                        )
                    }
                )
            )
        }

        let mappedEntries = unsortedEntries.sorted { lhs, rhs in
            if lhs.entry.priority.rawValue != rhs.entry.priority.rawValue {
                return lhs.entry.priority.rawValue < rhs.entry.priority.rawValue
            }
            return lhs.index < rhs.index
        }
        .map { $0.entry }

        let visibleEntries = Array(mappedEntries.prefix(limit))

        let overview = visibleEntries.first.map {
            overviewPresentation(
                topEntry: $0,
                totalCount: visibleEntries.count
            )
        }

        return SupervisorHeartbeatFeedPresentation(
            title: "Supervisor 心跳",
            iconName: "heart.fill",
            iconTone: overview?.priorityTone ?? .danger,
            emptyStateText: "当前还没有 heartbeat。收到新的主动汇报后，心脏会跳两下，并在这里保留最近记录。",
            overview: overview,
            entries: visibleEntries
        )
    }

    static func highestPriority(
        entries: [SupervisorManager.HeartbeatFeedEntry]
    ) -> SupervisorHeartbeatPriority? {
        entries.reduce(nil) { current, entry in
            let focusDescriptor = focusDescriptor(for: entry.focusActionURL)
            let priority = summarize(entry: entry, focusDescriptor: focusDescriptor).priority
            guard let current else { return priority }
            return priority.rawValue < current.rawValue ? priority : current
        }
    }

    private static func summarize(
        entry: SupervisorManager.HeartbeatFeedEntry,
        focusDescriptor: FocusDescriptor
    ) -> EntrySummary {
        let sections = sectionLines(from: entry.content)
        let governanceLines = sections["治理修复"] ?? []
        let voiceReadinessLines = sections["语音就绪"] ?? []
        let permissionLines = sections["权限申请"] ?? []
        let queueLines = sections["排队态势"] ?? []
        let progressLines = sections["主动推进"] ?? []
        let topBoardLines = sections["重点看板"] ?? []
        let nextStepLines = sections["Coder 下一步建议"] ?? []

        let routeLines = nextStepLines.filter {
            $0.contains("模型路由") || $0.contains("/route diagnose")
        }
        let blockerLines = topBoardLines.filter {
            $0.contains("🚧") || $0.contains("阻塞")
        }

        if focusDescriptor.kind == .governance || !governanceLines.isEmpty {
            return EntrySummary(
                priority: .immediate,
                headlineText: "治理修复",
                headlineTone: .warning,
                detailLines: prioritizedLines(governanceLines, fallback: nextStepLines)
            )
        }

        if focusDescriptor.kind == .authorization || !permissionLines.isEmpty {
            return EntrySummary(
                priority: .immediate,
                headlineText: "授权待处理",
                headlineTone: .warning,
                detailLines: prioritizedLines(permissionLines, fallback: nextStepLines)
            )
        }

        if !voiceReadinessLines.isEmpty {
            let advisoryOnly = voiceReadinessLines.contains { $0.contains("first task ready") }
            return EntrySummary(
                priority: advisoryOnly ? .watch : .attention,
                headlineText: advisoryOnly ? "语音仍有待修复项" : "语音链路待修复",
                headlineTone: advisoryOnly ? .accent : .warning,
                detailLines: prioritizedLines(voiceReadinessLines, fallback: nextStepLines)
            )
        }

        if focusDescriptor.kind == .routeDiagnose || !routeLines.isEmpty {
            return EntrySummary(
                priority: .attention,
                headlineText: "模型路由诊断",
                headlineTone: .accent,
                detailLines: prioritizedLines(routeLines, fallback: topBoardLines)
            )
        }

        if !blockerLines.isEmpty {
            return EntrySummary(
                priority: .attention,
                headlineText: "项目阻塞",
                headlineTone: .danger,
                detailLines: prioritizedLines(blockerLines, fallback: nextStepLines)
            )
        }

        if let firstProgress = firstMeaningfulLine(progressLines) {
            return EntrySummary(
                priority: .watch,
                headlineText: "已主动推进",
                headlineTone: .success,
                detailLines: prioritizedLines([firstProgress], fallback: nextStepLines)
            )
        }

        if !queueLines.isEmpty {
            return EntrySummary(
                priority: .watch,
                headlineText: "排队关注",
                headlineTone: .accent,
                detailLines: prioritizedLines(queueLines, fallback: nextStepLines)
            )
        }

        return EntrySummary(
            priority: .stable,
            headlineText: "状态稳定",
            headlineTone: entry.changed ? .success : .neutral,
            detailLines: prioritizedLines(topBoardLines, fallback: nextStepLines)
        )
    }

    private static func overviewPresentation(
        topEntry: SupervisorHeartbeatEntryPresentation,
        totalCount: Int
    ) -> SupervisorHeartbeatOverviewPresentation {
        let detailText = firstMeaningfulLine(topEntry.detailLines)
            ?? firstMeaningfulLine(topEntry.contentText)
            ?? topEntry.headlineText
        let remainingCount = max(0, totalCount - 1)
        var metadataParts = [topEntry.reasonText, topEntry.timeText]
        if remainingCount > 0 {
            metadataParts.append("另有 \(remainingCount) 条更新")
        }

        return SupervisorHeartbeatOverviewPresentation(
            priority: topEntry.priority,
            priorityText: topEntry.priorityText,
            priorityTone: topEntry.priorityTone,
            headlineText: topEntry.headlineText,
            detailText: detailText,
            metadataText: metadataParts.joined(separator: " · "),
            focusAction: topEntry.focusAction
        )
    }

    private static func focusDescriptor(for rawURL: String?) -> FocusDescriptor {
        let trimmed = nonEmpty(rawURL) ?? ""
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let route = XTDeepLinkParser.parse(url) else {
            return FocusDescriptor(kind: .other, actionLabel: "打开相关视图")
        }

        switch route {
        case .supervisor:
            return FocusDescriptor(kind: .supervisor, actionLabel: "打开 Supervisor")
        case .hubSetup:
            return FocusDescriptor(kind: .settings, actionLabel: "打开 Hub 设置")
        case .settings, .supervisorSettings:
            return FocusDescriptor(kind: .settings, actionLabel: "打开设置")
        case .resume:
            return FocusDescriptor(kind: .project, actionLabel: "打开项目")
        case .project(let projectRoute):
            if projectRoute.governanceDestination != nil {
                return FocusDescriptor(kind: .governance, actionLabel: "打开治理设置")
            }
            switch projectRoute.focusTarget {
            case .routeDiagnose:
                return FocusDescriptor(kind: .routeDiagnose, actionLabel: "打开路由诊断")
            case .grant, .approval, .toolApproval:
                return FocusDescriptor(kind: .authorization, actionLabel: "打开授权处理")
            case .skillRecord:
                return FocusDescriptor(kind: .skillRecord, actionLabel: "打开技能记录")
            case nil:
                break
            }
            if projectRoute.openTarget == .supervisor {
                return FocusDescriptor(kind: .supervisor, actionLabel: "打开 Supervisor")
            }
            return FocusDescriptor(kind: .project, actionLabel: "打开项目")
        }
    }

    private static func sectionLines(from content: String) -> [String: [String]] {
        let sectionTitles: Set<String> = [
            "主动推进",
            "重点看板",
            "排队态势",
            "权限申请",
            "治理修复",
            "语音就绪",
            "Lane 健康巡检",
            "Coder 下一步建议"
        ]

        var sections: [String: [String]] = [:]
        var currentSection: String?

        for rawLine in content.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if sectionTitles.contains(trimmed.replacingOccurrences(of: "：", with: "")) {
                currentSection = trimmed.replacingOccurrences(of: "：", with: "")
                continue
            }

            guard let currentSection else { continue }
            let normalized = normalizedLine(trimmed)
            guard !normalized.isEmpty, normalized != "（无）", normalized != "（本轮无需介入）", normalized != "（暂无）", normalized != "（无异常 lane）" else {
                continue
            }
            sections[currentSection, default: []].append(normalized)
        }

        return sections
    }

    private static func prioritizedLines(
        _ primary: [String],
        fallback: [String],
        limit: Int = 2
    ) -> [String] {
        let primaryLines = primary.compactMap(firstMeaningfulLine).uniqued()
        let fallbackLines = fallback.compactMap(firstMeaningfulLine).uniqued()
        let combined = (primaryLines + fallbackLines).uniqued()
        return Array(combined.prefix(max(1, limit)))
    }

    private static func firstMeaningfulLine(_ raw: String) -> String? {
        let normalized = normalizedLine(raw)
        return normalized.isEmpty ? nil : normalized
    }

    private static func firstMeaningfulLine(_ lines: [String]) -> String? {
        lines.compactMap(firstMeaningfulLine).first
    }

    private static func normalizedLine(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[•\-]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"（打开：.*?）$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func timeText(
        _ timestamp: Double,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static func reasonText(for rawReason: String) -> String {
        switch normalizedReasonCode(rawReason) {
        case "timer", "periodic_check":
            return "定时巡检"
        case "project_created":
            return "新项目"
        case "project_updated":
            return "项目更新"
        case "project_removed":
            return "项目移除"
        case "incident_handled":
            return "事件处理"
        case "lane_health_changed":
            return "Lane 变化"
        case "guidance_ack_follow_up":
            return "指导跟进"
        case "event":
            return "事件触发"
        default:
            return normalizedReasonCode(rawReason)
                .replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func normalizedReasonCode(_ rawReason: String) -> String {
        rawReason
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
