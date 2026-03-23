import Foundation

struct SupervisorPortfolioBadgePresentation: Equatable, Identifiable {
    var id: String
    var title: String
    var count: Int
    var tone: SupervisorHeaderControlTone
}

struct SupervisorPortfolioActionabilityRowPresentation: Equatable, Identifiable {
    var id: String
    var projectName: String
    var kindLabel: String
    var recommendedNextAction: String
    var whyText: String
    var tone: SupervisorHeaderControlTone
}

struct SupervisorPortfolioCriticalQueueRowPresentation: Equatable, Identifiable {
    var id: String
    var text: String
    var tone: SupervisorHeaderControlTone
}

struct SupervisorPortfolioTodayQueuePresentation: Equatable {
    var title: String
    var priorityHint: String?
    var statusLine: String
    var rows: [SupervisorPortfolioActionabilityRowPresentation]
}

struct SupervisorPortfolioCloseOutQueuePresentation: Equatable {
    var title: String
    var priorityHint: String?
    var statusLine: String
    var rows: [SupervisorPortfolioActionabilityRowPresentation]
}

struct SupervisorPortfolioCriticalQueuePresentation: Equatable {
    var title: String
    var rows: [SupervisorPortfolioCriticalQueueRowPresentation]
}

struct SupervisorPortfolioOverviewPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var statusLine: String
    var countBadges: [SupervisorPortfolioBadgePresentation]
    var metricBadgeRows: [[SupervisorPortfolioBadgePresentation]]
    var projectNotificationLine: String?
    var infrastructureStatusLine: String?
    var infrastructureTransitionLine: String?
    var emptyStateText: String?
    var todayQueue: SupervisorPortfolioTodayQueuePresentation?
    var closeOutQueue: SupervisorPortfolioCloseOutQueuePresentation?
    var criticalQueue: SupervisorPortfolioCriticalQueuePresentation?
}

enum SupervisorPortfolioOverviewPresentationMapper {
    private struct CloseOutQueueItem {
        var card: SupervisorPortfolioProjectCard
        var signal: SupervisorMemoryCompactionSignal
    }

    static func map(
        snapshot: SupervisorPortfolioSnapshot,
        actionability: SupervisorPortfolioActionabilitySnapshot,
        projectNotificationStatusLine: String?,
        hasProjectNotificationActivity: Bool,
        infrastructureStatusLine: String,
        infrastructureTransitionLine: String,
        maxTodayQueueItems: Int = 4,
        maxCloseOutQueueItems: Int = 3,
        maxCriticalQueueItems: Int = 3
    ) -> SupervisorPortfolioOverviewPresentation {
        let todayQueueItems = Array(actionability.recommendedActions.prefix(maxTodayQueueItems))
        let closeOutItems = Array(closeOutQueueItems(snapshot.projects).prefix(maxCloseOutQueueItems))
        let criticalQueueItems = Array(snapshot.criticalQueue.prefix(maxCriticalQueueItems))
        var metricBadgeRows: [[SupervisorPortfolioBadgePresentation]] = [
            [
                badge(title: "24h变更", count: actionability.projectsChangedLast24h, tone: .accent),
                badge(title: "决策阻塞", count: actionability.decisionBlockerProjectsCount, tone: .danger),
                badge(title: "规格缺口", count: actionability.projectsMissingSpec, tone: .warning),
                badge(title: "缺下一步", count: actionability.projectsMissingNextStep, tone: .warning),
            ],
            [
                badge(title: "决策护栏", count: decisionRailSignalCount(snapshot.projects), tone: .warning),
                badge(title: "停滞", count: actionability.stalledProjects, tone: .warning),
                badge(title: "休眠", count: actionability.zombieProjects, tone: .neutral),
                badge(title: "今日动作", count: actionability.actionableToday, tone: .accent),
            ]
        ]
        let compactionBadges = memoryCompactionMetricBadges(snapshot.projects)
        if !compactionBadges.isEmpty {
            metricBadgeRows.append(compactionBadges)
        }

        return SupervisorPortfolioOverviewPresentation(
            iconName: snapshot.projects.isEmpty ? "square.stack.3d.up" : "square.stack.3d.up.fill",
            iconTone: snapshot.projects.isEmpty ? .neutral : .accent,
            title: "项目总览",
            statusLine: statusLine(snapshot),
            countBadges: [
                badge(title: "进行中", count: snapshot.counts.active, tone: .accent),
                badge(title: "阻塞", count: snapshot.counts.blocked, tone: .warning),
                badge(title: "待授权", count: snapshot.counts.awaitingAuthorization, tone: .danger),
                badge(title: "完成", count: snapshot.counts.completed, tone: .success),
            ],
            metricBadgeRows: metricBadgeRows,
            projectNotificationLine: hasProjectNotificationActivity
                ? nonEmpty(projectNotificationStatusLine)
                : nil,
            infrastructureStatusLine: nonEmpty(infrastructureStatusLine).map { "基础设施 · \($0)" },
            infrastructureTransitionLine: nonEmpty(infrastructureTransitionLine).map { "最近切换 · \($0)" },
            emptyStateText: snapshot.projects.isEmpty
                ? "当前还没有可展示的受辖项目。项目进入 registry 并产生状态摘要后，这里会显示当前动作、阻塞和下一步。"
                : nil,
            todayQueue: todayQueueItems.isEmpty
                ? nil
                : SupervisorPortfolioTodayQueuePresentation(
                    title: "今天优先处理",
                    priorityHint: priorityHint(todayQueueItems),
                    statusLine: todayQueueStatusLine(actionability),
                    rows: todayQueueItems.map(actionabilityRow)
                ),
            closeOutQueue: closeOutItems.isEmpty
                ? nil
                : SupervisorPortfolioCloseOutQueuePresentation(
                    title: "完成态收口",
                    priorityHint: closeOutQueuePriorityHint(closeOutItems),
                    statusLine: closeOutQueueStatusLine(closeOutItems),
                    rows: closeOutItems.map(closeOutQueueRow)
                ),
            criticalQueue: criticalQueueItems.isEmpty
                ? nil
                : SupervisorPortfolioCriticalQueuePresentation(
                    title: "高优先队列",
                    rows: criticalQueueItems.map(criticalQueueRow)
                )
        )
    }

    static func badge(
        title: String,
        count: Int,
        tone: SupervisorHeaderControlTone
    ) -> SupervisorPortfolioBadgePresentation {
        SupervisorPortfolioBadgePresentation(
            id: "\(title)|\(count)|\(tone.rawValue)",
            title: title,
            count: count,
            tone: tone
        )
    }

    static func actionabilityRow(
        _ item: SupervisorPortfolioActionabilityItem
    ) -> SupervisorPortfolioActionabilityRowPresentation {
        SupervisorPortfolioActionabilityRowPresentation(
            id: item.id,
            projectName: item.projectName,
            kindLabel: actionabilityLabel(item.kind),
            recommendedNextAction: item.recommendedNextAction,
            whyText: "原因：\(item.whyItMatters)",
            tone: actionabilityTone(item.kind)
        )
    }

    static func criticalQueueRow(
        _ item: SupervisorPortfolioCriticalQueueItem
    ) -> SupervisorPortfolioCriticalQueueRowPresentation {
        SupervisorPortfolioCriticalQueueRowPresentation(
            id: item.id,
            text: "\(item.projectName)：\(item.reason)。下一步：\(item.nextAction)",
            tone: criticalQueueTone(item.severity)
        )
    }

    static func actionabilityTone(
        _ kind: SupervisorPortfolioActionabilityKind
    ) -> SupervisorHeaderControlTone {
        switch kind {
        case .decisionAssist:
            return .warning
        case .decisionBlocker:
            return .danger
        case .specGap, .decisionRail, .missingNextStep, .stalled:
            return .warning
        case .zombie:
            return .neutral
        case .activeFollowUp:
            return .accent
        }
    }

    static func criticalQueueTone(
        _ severity: SupervisorProjectActionSeverity
    ) -> SupervisorHeaderControlTone {
        switch severity {
        case .silentLog:
            return .neutral
        case .badgeOnly:
            return .accent
        case .briefCard:
            return .warning
        case .interruptNow, .authorizationRequired:
            return .danger
        }
    }

    static func priorityHint(
        _ items: [SupervisorPortfolioActionabilityItem]
    ) -> String? {
        let names = Array(items.prefix(2)).map(\.projectName)
        guard !names.isEmpty else { return nil }
        return "建议优先处理：\(names.joined(separator: "、"))"
    }

    static func actionabilityLabel(
        _ kind: SupervisorPortfolioActionabilityKind
    ) -> String {
        switch kind {
        case .decisionAssist:
            return "决策建议"
        case .decisionBlocker:
            return "决策阻塞"
        case .specGap:
            return "规格缺口"
        case .decisionRail:
            return "决策护栏"
        case .missingNextStep:
            return "缺下一步"
        case .stalled:
            return "停滞"
        case .zombie:
            return "休眠"
        case .activeFollowUp:
            return "今日动作"
        }
    }

    private static func closeOutQueueItems(
        _ cards: [SupervisorPortfolioProjectCard]
    ) -> [CloseOutQueueItem] {
        cards.compactMap { card -> CloseOutQueueItem? in
            guard card.projectState == .completed,
                  let signal = card.memoryCompactionSignal else {
                return nil
            }
            return CloseOutQueueItem(card: card, signal: signal)
        }
        .sorted { lhs, rhs in
            if lhs.signal.archiveCandidate != rhs.signal.archiveCandidate {
                return lhs.signal.archiveCandidate && !rhs.signal.archiveCandidate
            }
            if lhs.card.updatedAt != rhs.card.updatedAt {
                return lhs.card.updatedAt > rhs.card.updatedAt
            }
            return lhs.card.displayName.localizedCaseInsensitiveCompare(rhs.card.displayName) == .orderedAscending
        }
    }

    private static func closeOutQueueRow(
        _ item: CloseOutQueueItem
    ) -> SupervisorPortfolioActionabilityRowPresentation {
        SupervisorPortfolioActionabilityRowPresentation(
            id: "close-out:\(item.card.projectId)",
            projectName: item.card.displayName,
            kindLabel: item.signal.archiveCandidate ? "归档候选" : "记忆收口",
            recommendedNextAction: closeOutQueueNextAction(item.card, signal: item.signal),
            whyText: "原因：\(closeOutQueueWhyText(item.signal))",
            tone: item.signal.archiveCandidate ? .warning : .accent
        )
    }

    static func decisionRailSignalCount(
        _ cards: [SupervisorPortfolioProjectCard]
    ) -> Int {
        cards.filter(\.hasDecisionRailSignal).count
    }

    static func memoryCompactionSignalCount(
        _ cards: [SupervisorPortfolioProjectCard]
    ) -> Int {
        cards.filter(\.hasMemoryCompactionSignal).count
    }

    static func archiveCandidateCount(
        _ cards: [SupervisorPortfolioProjectCard]
    ) -> Int {
        cards.filter { $0.memoryCompactionSignal?.archiveCandidate == true }.count
    }

    static func memoryCompactionMetricBadges(
        _ cards: [SupervisorPortfolioProjectCard]
    ) -> [SupervisorPortfolioBadgePresentation] {
        let compactionCount = memoryCompactionSignalCount(cards)
        let archiveCount = archiveCandidateCount(cards)
        var badges: [SupervisorPortfolioBadgePresentation] = []
        if compactionCount > 0 {
            badges.append(
                badge(title: "记忆收口", count: compactionCount, tone: .accent)
            )
        }
        if archiveCount > 0 {
            badges.append(
                badge(title: "归档候选", count: archiveCount, tone: .warning)
            )
        }
        return badges
    }

    private static func statusLine(_ snapshot: SupervisorPortfolioSnapshot) -> String {
        "\(snapshot.projects.count) 个项目 · \(snapshot.counts.active) 个进行中 · \(snapshot.counts.blocked) 个阻塞 · \(snapshot.counts.awaitingAuthorization) 个待授权 · \(snapshot.counts.completed) 个已完成"
    }

    private static func todayQueueStatusLine(
        _ actionability: SupervisorPortfolioActionabilitySnapshot
    ) -> String {
        "\(actionability.actionableToday) 个项目建议今天处理 · 决策阻塞 \(actionability.decisionBlockerProjectsCount) 个 · 规格缺口 \(actionability.projectsMissingSpec) 个"
    }

    private static func closeOutQueuePriorityHint(
        _ items: [CloseOutQueueItem]
    ) -> String? {
        let names = Array(items.prefix(2)).map(\.card.displayName)
        guard !names.isEmpty else { return nil }
        return "建议先确认：\(names.joined(separator: "、"))"
    }

    private static func closeOutQueueStatusLine(
        _ items: [CloseOutQueueItem]
    ) -> String {
        let archiveCount = items.filter(\.signal.archiveCandidate).count
        let rollupCount = max(0, items.count - archiveCount)
        return "\(items.count) 个完成态项目待确认 · 归档候选 \(archiveCount) 个 · 已收口 \(rollupCount) 个"
    }

    private static func closeOutQueueNextAction(
        _ card: SupervisorPortfolioProjectCard,
        signal: SupervisorMemoryCompactionSignal
    ) -> String {
        if signal.archiveCandidate {
            if let nextStep = normalizedCloseOutStep(card.nextStep),
               looksLikeCloseOutStep(nextStep),
               nextStep.contains("归档") {
                return nextStep
            }
            return "审阅收口证据并确认归档；如无新增范围，归档该项目。"
        }
        if let nextStep = normalizedCloseOutStep(card.nextStep),
           looksLikeCloseOutStep(nextStep) {
            return nextStep
        }
        return "审阅收口摘要，确认是否归档或保留少量关键跟踪项。"
    }

    private static func closeOutQueueWhyText(
        _ signal: SupervisorMemoryCompactionSignal
    ) -> String {
        if signal.archiveCandidate {
            return "该项目已完成并进入归档候选状态，需要确认收口证据后再退出活跃视图。"
        }
        return "该项目已完成且关键记忆已收口，需要确认是否归档或继续保留少量关键跟踪项。"
    }

    private static func normalizedCloseOutStep(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        let placeholders = [
            "(暂无)",
            "(无)",
            "(none)",
            "继续当前任务",
            "continue current task",
        ]
        return placeholders.contains(lowered) ? nil : trimmed
    }

    private static func looksLikeCloseOutStep(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return [
            "archive",
            "archived",
            "close out",
            "close-out",
            "closeout",
            "rollup",
            "compaction",
            "收口",
            "归档",
            "结项",
        ].contains { lowered.contains($0) }
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
