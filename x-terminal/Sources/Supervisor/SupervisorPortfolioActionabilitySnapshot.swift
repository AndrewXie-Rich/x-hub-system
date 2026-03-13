import Foundation

enum SupervisorPortfolioActionabilityKind: String, Codable, Sendable {
    case decisionBlocker = "decision_blocker"
    case missingNextStep = "missing_next_step"
    case stalled
    case zombie
    case activeFollowUp = "active_follow_up"
}

enum SupervisorPortfolioActionabilityPriority: String, Codable, Sendable {
    case now
    case today
}

struct SupervisorPortfolioActionabilityItem: Identifiable, Equatable, Codable, Sendable {
    var projectId: String
    var projectName: String
    var kind: SupervisorPortfolioActionabilityKind
    var priority: SupervisorPortfolioActionabilityPriority
    var reasonSummary: String
    var recommendedNextAction: String
    var whyItMatters: String
    var staleAgeHours: Int?

    var id: String { "\(projectId):\(kind.rawValue)" }

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case projectName = "project_name"
        case kind
        case priority
        case reasonSummary = "reason_summary"
        case recommendedNextAction = "recommended_next_action"
        case whyItMatters = "why_it_matters"
        case staleAgeHours = "stale_age_hours"
    }

    var kindLabel: String {
        switch kind {
        case .decisionBlocker:
            return "Decision blocker"
        case .missingNextStep:
            return "Missing next"
        case .stalled:
            return "Stalled"
        case .zombie:
            return "Zombie"
        case .activeFollowUp:
            return "Action today"
        }
    }
}

struct SupervisorPortfolioActionabilitySnapshot: Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_portfolio_actionability_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var projectsChangedLast24h: Int
    var decisionBlockerProjectsCount: Int
    var projectsMissingNextStep: Int
    var stalledProjects: Int
    var zombieProjects: Int
    var actionableToday: Int
    var recommendedActions: [SupervisorPortfolioActionabilityItem]

    static let empty = SupervisorPortfolioActionabilitySnapshot(
        schemaVersion: schemaVersion,
        updatedAtMs: 0,
        projectsChangedLast24h: 0,
        decisionBlockerProjectsCount: 0,
        projectsMissingNextStep: 0,
        stalledProjects: 0,
        zombieProjects: 0,
        actionableToday: 0,
        recommendedActions: []
    )

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case projectsChangedLast24h = "projects_changed_last_24h"
        case decisionBlockerProjectsCount = "decision_blocker_projects_count"
        case projectsMissingNextStep = "projects_missing_next_step"
        case stalledProjects = "stalled_projects"
        case zombieProjects = "zombie_projects"
        case actionableToday = "actionable_today"
        case recommendedActions = "recommended_actions"
    }

    var statusLine: String {
        "changed_24h=\(projectsChangedLast24h) · decision=\(decisionBlockerProjectsCount) · missing_next=\(projectsMissingNextStep) · stalled=\(stalledProjects) · zombie=\(zombieProjects) · today=\(actionableToday)"
    }
}

enum SupervisorPortfolioActionabilitySnapshotBuilder {
    private static let changedWindowHours = 24.0
    private static let stalledAfterHours = 24.0
    private static let zombieAfterHours = 24.0 * 7.0

    private struct RankedRecommendationItem {
        var item: SupervisorPortfolioActionabilityItem
        var projectState: SupervisorPortfolioProjectState
        var criticalQueuePriority: Bool
    }

    static func build(
        from snapshot: SupervisorPortfolioSnapshot,
        now: Double? = nil
    ) -> SupervisorPortfolioActionabilitySnapshot {
        let referenceNow: Double
        if let now, now > 0 {
            referenceNow = now
        } else if snapshot.updatedAt > 0 {
            referenceNow = snapshot.updatedAt
        } else {
            referenceNow = Date().timeIntervalSince1970
        }
        return build(from: snapshot.projects, now: referenceNow)
    }

    static func build(
        from cards: [SupervisorPortfolioProjectCard],
        now: Double
    ) -> SupervisorPortfolioActionabilitySnapshot {
        let changedProjects = cards.filter { changedWithinLast24Hours($0, now: now) }
        let decisionBlockers = cards.filter { isDecisionBlocker($0) }
        let missingNext = cards.filter { isMissingNextStep($0) }
        let stalled = cards.filter { isStalled($0, now: now) }
        let zombie = cards.filter { isZombie($0, now: now) }

        let recommendedActions = cards.compactMap { card -> RankedRecommendationItem? in
            guard let item = recommendationItem(for: card, now: now) else { return nil }
            return RankedRecommendationItem(
                item: item,
                projectState: card.projectState,
                criticalQueuePriority: card.projectState == .blocked || card.projectState == .awaitingAuthorization
            )
        }
        .sorted(by: compareRecommendationItems)
        .map(\.item)

        let actionableToday = Set(
            recommendedActions
                .filter { $0.priority == .now || $0.priority == .today }
                .map(\.projectId)
        ).count

        return SupervisorPortfolioActionabilitySnapshot(
            schemaVersion: SupervisorPortfolioActionabilitySnapshot.schemaVersion,
            updatedAtMs: max(0, Int64((now * 1000.0).rounded())),
            projectsChangedLast24h: changedProjects.count,
            decisionBlockerProjectsCount: decisionBlockers.count,
            projectsMissingNextStep: missingNext.count,
            stalledProjects: stalled.count,
            zombieProjects: zombie.count,
            actionableToday: actionableToday,
            recommendedActions: recommendedActions
        )
    }

    private static func recommendationItem(
        for card: SupervisorPortfolioProjectCard,
        now: Double
    ) -> SupervisorPortfolioActionabilityItem? {
        guard card.projectState != .completed else { return nil }

        let staleAgeHours = ageHours(for: card, now: now)

        if isDecisionBlocker(card) {
            let reason = firstNonEmpty(
                normalizedReason(card.topBlocker),
                fallback: normalizedReason(card.currentAction)
            )
            return SupervisorPortfolioActionabilityItem(
                projectId: card.projectId,
                projectName: card.displayName,
                kind: .decisionBlocker,
                priority: .now,
                reasonSummary: reason,
                recommendedNextAction: recommendedActionForDecisionBlocker(card),
                whyItMatters: card.projectState == .awaitingAuthorization
                    ? "This project is waiting on a governed approval before it can continue."
                    : "This blocker is decision-shaped, so the portfolio cannot route a safe next move until it is resolved.",
                staleAgeHours: staleAgeHours
            )
        }

        if isMissingNextStep(card) {
            return SupervisorPortfolioActionabilityItem(
                projectId: card.projectId,
                projectName: card.displayName,
                kind: .missingNextStep,
                priority: .now,
                reasonSummary: normalizedReason(card.currentAction),
                recommendedNextAction: "Define one concrete next step for \(card.displayName) before routing more work.",
                whyItMatters: "Without a concrete next step, the dashboard cannot answer what should happen today.",
                staleAgeHours: staleAgeHours
            )
        }

        if isZombie(card, now: now) {
            return SupervisorPortfolioActionabilityItem(
                projectId: card.projectId,
                projectName: card.displayName,
                kind: .zombie,
                priority: .today,
                reasonSummary: zombieReason(card, now: now),
                recommendedNextAction: hasConcreteNextStep(card.nextStep)
                    ? card.nextStep
                    : "Decide whether to archive or explicitly reactivate \(card.displayName).",
                whyItMatters: "Long-idle projects hide the real queue until they are archived or given an explicit recovery plan.",
                staleAgeHours: staleAgeHours
            )
        }

        if isStalled(card, now: now) {
            return SupervisorPortfolioActionabilityItem(
                projectId: card.projectId,
                projectName: card.displayName,
                kind: .stalled,
                priority: .today,
                reasonSummary: stalledReason(card, now: now),
                recommendedNextAction: hasConcreteNextStep(card.nextStep)
                    ? card.nextStep
                    : "Re-establish an owner and next checkpoint for \(card.displayName).",
                whyItMatters: "The project has gone quiet long enough that it is likely slipping without an explicit follow-up.",
                staleAgeHours: staleAgeHours
            )
        }

        guard hasConcreteNextStep(card.nextStep) else { return nil }
        return SupervisorPortfolioActionabilityItem(
            projectId: card.projectId,
            projectName: card.displayName,
            kind: .activeFollowUp,
            priority: .today,
            reasonSummary: normalizedReason(card.currentAction),
            recommendedNextAction: card.nextStep,
            whyItMatters: "Recent portfolio state already produced a concrete next move, so the homepage can answer what to handle today.",
            staleAgeHours: staleAgeHours
        )
    }

    private static func compareRecommendationItems(
        _ lhs: RankedRecommendationItem,
        _ rhs: RankedRecommendationItem
    ) -> Bool {
        let priorityDelta = priorityScore(lhs.item.priority) - priorityScore(rhs.item.priority)
        if priorityDelta != 0 { return priorityDelta < 0 }
        let stateDelta = projectStateScore(lhs.projectState) - projectStateScore(rhs.projectState)
        if stateDelta != 0 { return stateDelta < 0 }
        let criticalDelta = criticalQueueScore(lhs.criticalQueuePriority) - criticalQueueScore(rhs.criticalQueuePriority)
        if criticalDelta != 0 { return criticalDelta < 0 }
        let kindDelta = kindScore(lhs.item.kind) - kindScore(rhs.item.kind)
        if kindDelta != 0 { return kindDelta < 0 }

        let leftAge = lhs.item.staleAgeHours ?? -1
        let rightAge = rhs.item.staleAgeHours ?? -1
        if leftAge != rightAge { return leftAge > rightAge }
        return lhs.item.projectName.localizedCaseInsensitiveCompare(rhs.item.projectName) == .orderedAscending
    }

    private static func priorityScore(_ priority: SupervisorPortfolioActionabilityPriority) -> Int {
        switch priority {
        case .now:
            return 0
        case .today:
            return 1
        }
    }

    private static func kindScore(_ kind: SupervisorPortfolioActionabilityKind) -> Int {
        switch kind {
        case .decisionBlocker:
            return 0
        case .missingNextStep:
            return 1
        case .activeFollowUp:
            return 2
        case .stalled:
            return 3
        case .zombie:
            return 4
        }
    }

    private static func projectStateScore(_ state: SupervisorPortfolioProjectState) -> Int {
        switch state {
        case .blocked:
            return 0
        case .awaitingAuthorization:
            return 1
        case .active:
            return 2
        case .idle:
            return 3
        case .completed:
            return 4
        }
    }

    private static func criticalQueueScore(_ criticalQueuePriority: Bool) -> Int {
        criticalQueuePriority ? 0 : 1
    }

    private static func changedWithinLast24Hours(
        _ card: SupervisorPortfolioProjectCard,
        now: Double
    ) -> Bool {
        guard card.updatedAt > 0 else { return false }
        return max(0, now - card.updatedAt) <= changedWindowHours * 3_600.0
    }

    private static func isDecisionBlocker(_ card: SupervisorPortfolioProjectCard) -> Bool {
        guard card.projectState != .completed else { return false }
        if card.projectState == .awaitingAuthorization { return true }
        let merged = [card.topBlocker, card.currentAction, card.nextStep].joined(separator: " ").lowercased()
        let decisionTokens = [
            "decision",
            "approve",
            "approval",
            "authorization",
            "grant_required",
            "review_required",
            "needs review",
            "needs approval",
            "sign off",
            "policy decision",
            "决策",
            "审批",
            "授权",
            "确认",
            "拍板",
            "定案",
            "选择",
        ]
        return decisionTokens.contains { merged.contains($0) }
    }

    private static func isMissingNextStep(_ card: SupervisorPortfolioProjectCard) -> Bool {
        guard card.projectState != .completed else { return false }
        let next = normalizeToken(card.nextStep)
        let placeholders = [
            "",
            "继续当前任务",
            "continue current task",
            "keep monitoring",
            "monitor current task",
            "same as current",
            "待补充",
            "unknown",
            "n/a",
        ]
        return placeholders.contains(next)
    }

    private static func isStalled(
        _ card: SupervisorPortfolioProjectCard,
        now: Double
    ) -> Bool {
        guard card.projectState != .completed else { return false }
        guard !isZombie(card, now: now) else { return false }
        guard let ageHours = ageHours(for: card, now: now) else { return false }
        return Double(ageHours) >= stalledAfterHours
    }

    private static func isZombie(
        _ card: SupervisorPortfolioProjectCard,
        now: Double
    ) -> Bool {
        guard card.projectState != .completed else { return false }
        guard let ageHours = ageHours(for: card, now: now) else { return false }
        return Double(ageHours) >= zombieAfterHours
    }

    private static func ageHours(
        for card: SupervisorPortfolioProjectCard,
        now: Double
    ) -> Int? {
        guard card.updatedAt > 0 else { return nil }
        let age = max(0, now - card.updatedAt)
        return Int((age / 3_600.0).rounded(.down))
    }

    private static func recommendedActionForDecisionBlocker(
        _ card: SupervisorPortfolioProjectCard
    ) -> String {
        if hasConcreteNextStep(card.nextStep) {
            return card.nextStep
        }
        if card.projectState == .awaitingAuthorization {
            return "Review the pending approval and record a decision before asking the project to continue."
        }
        return "Resolve the decision blocker or choose an explicit lower-risk fallback."
    }

    private static func zombieReason(
        _ card: SupervisorPortfolioProjectCard,
        now: Double
    ) -> String {
        guard let hours = ageHours(for: card, now: now) else {
            return normalizedReason(card.currentAction)
        }
        let days = max(1, hours / 24)
        return "\(days)d without a meaningful portfolio update."
    }

    private static func stalledReason(
        _ card: SupervisorPortfolioProjectCard,
        now: Double
    ) -> String {
        guard let hours = ageHours(for: card, now: now) else {
            return normalizedReason(card.currentAction)
        }
        return "\(hours)h since the last meaningful update."
    }

    private static func hasConcreteNextStep(_ nextStep: String) -> Bool {
        let normalized = normalizeToken(nextStep)
        guard !normalized.isEmpty else { return false }
        let placeholders = [
            "继续当前任务",
            "continue current task",
            "keep monitoring",
            "monitor current task",
            "same as current",
            "待补充",
            "unknown",
            "n/a",
        ]
        return !placeholders.contains(normalized)
    }

    private static func normalizedReason(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Portfolio state updated." }
        if trimmed == "(无)" || trimmed == "(暂无)" {
            return "Portfolio state updated."
        }
        guard trimmed.count > 96 else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 96)
        return String(trimmed[..<end]) + "..."
    }

    private static func firstNonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func normalizeToken(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
