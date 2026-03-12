import Foundation

enum SupervisorPortfolioProjectState: String, Codable, Sendable {
    case active
    case blocked
    case awaitingAuthorization = "awaiting_authorization"
    case completed
    case idle
}

enum SupervisorPortfolioMemoryFreshness: String, Codable, Sendable {
    case fresh
    case ttlCached = "ttl_cached"
    case stale
}

enum SupervisorProjectActionSeverity: String, Codable, Sendable {
    case silentLog = "silent_log"
    case badgeOnly = "badge_only"
    case briefCard = "brief_card"
    case interruptNow = "interrupt_now"
    case authorizationRequired = "authorization_required"
}

enum SupervisorProjectActionEventType: String, Codable, Sendable {
    case created
    case progressed
    case blocked
    case awaitingAuthorization = "awaiting_authorization"
    case completed
    case archived
}

enum SupervisorProjectActionEventKind: Sendable {
    case created
    case updated
    case removed
}

struct SupervisorPortfolioProjectCard: Identifiable, Equatable, Codable, Sendable {
    var projectId: String
    var displayName: String
    var projectState: SupervisorPortfolioProjectState
    var runtimeState: String
    var currentAction: String
    var topBlocker: String
    var nextStep: String
    var memoryFreshness: SupervisorPortfolioMemoryFreshness
    var updatedAt: Double
    var recentMessageCount: Int

    var id: String { projectId }
}

struct SupervisorPortfolioProjectCounts: Equatable, Codable, Sendable {
    var active: Int
    var blocked: Int
    var awaitingAuthorization: Int
    var completed: Int
    var idle: Int

    static let zero = SupervisorPortfolioProjectCounts(
        active: 0,
        blocked: 0,
        awaitingAuthorization: 0,
        completed: 0,
        idle: 0
    )
}

struct SupervisorPortfolioCriticalQueueItem: Identifiable, Equatable, Codable, Sendable {
    var projectId: String
    var projectName: String
    var reason: String
    var severity: SupervisorProjectActionSeverity
    var nextAction: String

    var id: String { projectId + ":" + reason }
}

struct SupervisorPortfolioSnapshot: Equatable, Codable, Sendable {
    var updatedAt: Double
    var counts: SupervisorPortfolioProjectCounts
    var criticalQueue: [SupervisorPortfolioCriticalQueueItem]
    var projects: [SupervisorPortfolioProjectCard]

    static let empty = SupervisorPortfolioSnapshot(
        updatedAt: 0,
        counts: .zero,
        criticalQueue: [],
        projects: []
    )

    var statusLine: String {
        "projects=\(projects.count) · active=\(counts.active) · blocked=\(counts.blocked) · auth=\(counts.awaitingAuthorization) · completed=\(counts.completed)"
    }

    func actionabilitySnapshot(now: Double? = nil) -> SupervisorPortfolioActionabilitySnapshot {
        SupervisorPortfolioActionabilitySnapshotBuilder.build(from: self, now: now)
    }
}

struct SupervisorProjectActionEvent: Identifiable, Equatable, Codable, Sendable {
    var eventId: String
    var projectId: String
    var projectName: String
    var eventType: SupervisorProjectActionEventType
    var severity: SupervisorProjectActionSeverity
    var actionTitle: String
    var actionSummary: String
    var whyItMatters: String
    var nextAction: String
    var occurredAt: Double

    var id: String { eventId }
}

enum SupervisorPortfolioSnapshotBuilder {
    static func projectState(
        from digest: SupervisorManager.SupervisorMemoryProjectDigest
    ) -> SupervisorPortfolioProjectState {
        SupervisorProjectCapsuleBuilder.projectState(from: digest)
    }

    static func projectState(from entry: AXProjectEntry) -> SupervisorPortfolioProjectState {
        let currentAction = normalizedNonPlaceholder(
            entry.currentStateSummary,
            fallback: normalizedNonPlaceholder(entry.statusDigest, fallback: "")
        )
        let blocker = normalizedNonPlaceholder(entry.blockerSummary, fallback: "")
        let nextStep = normalizedNonPlaceholder(entry.nextStepSummary, fallback: "继续当前任务")
        return projectState(
            runtimeState: currentAction,
            currentAction: currentAction,
            blocker: blocker,
            nextStep: nextStep
        )
    }

    static func build(
        from digests: [SupervisorManager.SupervisorMemoryProjectDigest],
        now: Double = Date().timeIntervalSince1970
    ) -> SupervisorPortfolioSnapshot {
        let cards = digests.map { makeCard(from: $0, now: now) }.sorted(by: compareCards)
        let counts = cards.reduce(into: SupervisorPortfolioProjectCounts.zero) { partial, card in
            switch card.projectState {
            case .active:
                partial.active += 1
            case .blocked:
                partial.blocked += 1
            case .awaitingAuthorization:
                partial.awaitingAuthorization += 1
            case .completed:
                partial.completed += 1
            case .idle:
                partial.idle += 1
            }
        }

        let criticalQueue = cards.compactMap { card -> SupervisorPortfolioCriticalQueueItem? in
            switch card.projectState {
            case .awaitingAuthorization:
                return SupervisorPortfolioCriticalQueueItem(
                    projectId: card.projectId,
                    projectName: card.displayName,
                    reason: "authorization_required",
                    severity: .authorizationRequired,
                    nextAction: card.nextStep
                )
            case .blocked:
                return SupervisorPortfolioCriticalQueueItem(
                    projectId: card.projectId,
                    projectName: card.displayName,
                    reason: card.topBlocker,
                    severity: .briefCard,
                    nextAction: card.nextStep
                )
            default:
                return nil
            }
        }

        return SupervisorPortfolioSnapshot(
            updatedAt: now,
            counts: counts,
            criticalQueue: criticalQueue,
            projects: cards
        )
    }

    static func makeActionEvent(
        from entry: AXProjectEntry,
        kind: SupervisorProjectActionEventKind,
        now: Double = Date().timeIntervalSince1970
    ) -> SupervisorProjectActionEvent {
        let current = normalizedNonPlaceholder(entry.currentStateSummary, fallback: "")
        let blocker = normalizedNonPlaceholder(entry.blockerSummary, fallback: "")
        let nextStep = normalizedNonPlaceholder(entry.nextStepSummary, fallback: "继续当前任务")
        let digest = normalizedNonPlaceholder(entry.statusDigest, fallback: "")
        let currentAction = !current.isEmpty ? current : (!digest.isEmpty ? digest : "项目状态已更新")

        let eventType: SupervisorProjectActionEventType
        let severity: SupervisorProjectActionSeverity
        let actionTitle: String
        let actionSummary: String
        let whyItMatters: String

        switch kind {
        case .created:
            eventType = .created
            severity = .badgeOnly
            actionTitle = "新增项目：\(entry.displayName)"
            actionSummary = "项目已进入 Supervisor 管辖范围。"
            whyItMatters = "Supervisor 需要把该项目纳入 portfolio 与调度视图。"
        case .removed:
            eventType = .archived
            severity = .briefCard
            actionTitle = "项目移除：\(entry.displayName)"
            actionSummary = "项目已从当前 portfolio 中移除。"
            whyItMatters = "Supervisor 需要更新项目总览与优先级。"
        case .updated:
            if looksLikeAuthorization(currentAction + " " + blocker + " " + nextStep) {
                eventType = .awaitingAuthorization
                severity = .authorizationRequired
                actionTitle = "项目待授权：\(entry.displayName)"
                actionSummary = capped(blocker.isEmpty ? currentAction : blocker, maxChars: 88)
                whyItMatters = "该项目正等待授权，未处理前不会继续推进。"
            } else if !blocker.isEmpty {
                eventType = .blocked
                severity = .briefCard
                actionTitle = "项目阻塞：\(entry.displayName)"
                actionSummary = capped(blocker, maxChars: 88)
                whyItMatters = "该项目当前存在明确 blocker，需要优先解阻或改道。"
            } else if looksLikeCompleted(currentAction + " " + digest) {
                eventType = .completed
                severity = .badgeOnly
                actionTitle = "项目完成：\(entry.displayName)"
                actionSummary = capped(currentAction, maxChars: 88)
                whyItMatters = "该项目可从 active 关注区移出。"
            } else {
                eventType = .progressed
                severity = .silentLog
                actionTitle = "项目推进：\(entry.displayName)"
                actionSummary = capped(currentAction, maxChars: 88)
                whyItMatters = "Supervisor 需要掌握最新 current action，但无需中断。"
            }
        }

        return SupervisorProjectActionEvent(
            eventId: "spf_evt_\(normalizedToken(entry.projectId))_\(Int(now * 1000))",
            projectId: entry.projectId,
            projectName: entry.displayName,
            eventType: eventType,
            severity: severity,
            actionTitle: actionTitle,
            actionSummary: actionSummary,
            whyItMatters: whyItMatters,
            nextAction: nextStep,
            occurredAt: now
        )
    }

    private static func makeCard(
        from digest: SupervisorManager.SupervisorMemoryProjectDigest,
        now: Double
    ) -> SupervisorPortfolioProjectCard {
        let capsule = SupervisorProjectCapsuleBuilder.build(from: digest, now: now)
        return SupervisorProjectCapsuleBuilder.card(from: capsule, recentMessageCount: digest.recentMessageCount)
    }

    private static func compareCards(_ lhs: SupervisorPortfolioProjectCard, _ rhs: SupervisorPortfolioProjectCard) -> Bool {
        let lp = priority(for: lhs.projectState)
        let rp = priority(for: rhs.projectState)
        if lp != rp { return lp < rp }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func priority(for state: SupervisorPortfolioProjectState) -> Int {
        switch state {
        case .awaitingAuthorization:
            return 0
        case .blocked:
            return 1
        case .active:
            return 2
        case .completed:
            return 3
        case .idle:
            return 4
        }
    }

    private static func projectState(
        runtimeState: String,
        currentAction: String,
        blocker: String,
        nextStep: String
    ) -> SupervisorPortfolioProjectState {
        let merged = [runtimeState, currentAction, blocker, nextStep].joined(separator: " ").lowercased()
        if looksLikeAuthorization(merged) {
            return .awaitingAuthorization
        }
        if !blocker.isEmpty {
            return .blocked
        }
        if looksLikeCompleted(merged) {
            return .completed
        }
        if looksLikeIdle(merged) {
            return .idle
        }
        return .active
    }

    private static func memoryFreshness(updatedAt: Double, now: Double) -> SupervisorPortfolioMemoryFreshness {
        guard updatedAt > 0 else { return .stale }
        let age = max(0, now - updatedAt)
        if age <= 300 { return .fresh }
        if age <= 1_800 { return .ttlCached }
        return .stale
    }

    private static func looksLikeAuthorization(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return [
            "grant_required",
            "awaiting_authorization",
            "authorization",
            "授权",
            "批准",
            "approve",
            "pending grant",
            "grant_pending",
        ].contains { lowered.contains($0) }
    }

    private static func looksLikeCompleted(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return [
            "已完成",
            "完成",
            "completed",
            "finished",
            "done",
        ].contains { lowered.contains($0) }
    }

    private static func looksLikeIdle(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return [
            "暂停",
            "待命",
            "waiting",
            "paused",
            "idle",
            "排队中",
        ].contains { lowered.contains($0) }
    }

    private static func normalizedNonPlaceholder(_ value: String?, fallback: String) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if trimmed == "(无)" || trimmed == "(暂无)" || trimmed == "(none)" {
            return fallback
        }
        return trimmed
    }

    private static func capped(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let index = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<index]) + "…"
    }

    private static func normalizedToken(_ value: String) -> String {
        let lowered = value.lowercased()
        return lowered.replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
    }
}
