import Foundation

enum SupervisorPortfolioActionabilityKind: String, Codable, Sendable {
    case decisionAssist = "decision_assist"
    case decisionBlocker = "decision_blocker"
    case specGap = "spec_gap"
    case decisionRail = "decision_rail"
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
        case .decisionAssist:
            return "Decision assist"
        case .decisionBlocker:
            return "Decision blocker"
        case .specGap:
            return "Spec gap"
        case .decisionRail:
            return "Decision rail"
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
    var projectsMissingSpec: Int = 0
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
        projectsMissingSpec: 0,
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
        case projectsMissingSpec = "projects_missing_spec"
        case projectsMissingNextStep = "projects_missing_next_step"
        case stalledProjects = "stalled_projects"
        case zombieProjects = "zombie_projects"
        case actionableToday = "actionable_today"
        case recommendedActions = "recommended_actions"
    }

    var statusLine: String {
        "changed_24h=\(projectsChangedLast24h) · decision=\(decisionBlockerProjectsCount) · spec_gap=\(projectsMissingSpec) · missing_next=\(projectsMissingNextStep) · stalled=\(stalledProjects) · zombie=\(zombieProjects) · today=\(actionableToday)"
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
        let specGaps = cards.filter { isSpecGap($0) }
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
            projectsMissingSpec: specGaps.count,
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

        if isDecisionAssist(card) {
            return SupervisorPortfolioActionabilityItem(
                projectId: card.projectId,
                projectName: card.displayName,
                kind: .decisionAssist,
                priority: .now,
                reasonSummary: decisionAssistReason(card),
                recommendedNextAction: recommendedActionForDecisionAssist(card),
                whyItMatters: decisionAssistWhyItMatters(card),
                staleAgeHours: staleAgeHours
            )
        }

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

        if isSpecGap(card) {
            return SupervisorPortfolioActionabilityItem(
                projectId: card.projectId,
                projectName: card.displayName,
                kind: .specGap,
                priority: .now,
                reasonSummary: specGapReason(card),
                recommendedNextAction: recommendedActionForSpecGap(card),
                whyItMatters: "Without a complete formal spec capsule, Supervisor keeps guessing project intent instead of routing against a stable contract.",
                staleAgeHours: staleAgeHours
            )
        }

        if isDecisionRailReview(card) {
            return SupervisorPortfolioActionabilityItem(
                projectId: card.projectId,
                projectName: card.displayName,
                kind: .decisionRail,
                priority: .today,
                reasonSummary: decisionRailReason(card),
                recommendedNextAction: recommendedActionForDecisionRail(card),
                whyItMatters: decisionRailWhyItMatters(card),
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
        case .decisionAssist:
            return 0
        case .decisionBlocker:
            return 1
        case .specGap:
            return 2
        case .missingNextStep:
            return 3
        case .decisionRail:
            return 4
        case .activeFollowUp:
            return 5
        case .stalled:
            return 6
        case .zombie:
            return 7
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
        if card.decisionAssist != nil { return true }
        let fields = [card.topBlocker, card.currentAction, card.nextStep]
        return fields.contains(where: containsDecisionCue)
    }

    private static func isDecisionAssist(_ card: SupervisorPortfolioProjectCard) -> Bool {
        guard card.projectState != .completed else { return false }
        return card.decisionAssist != nil
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

    private static func isSpecGap(_ card: SupervisorPortfolioProjectCard) -> Bool {
        guard card.projectState != .completed else { return false }
        return !card.missingSpecFields.isEmpty
    }

    private static func isDecisionRailReview(_ card: SupervisorPortfolioProjectCard) -> Bool {
        guard card.projectState != .completed else { return false }
        guard card.hasDecisionRailSignal else { return false }
        guard card.projectState == .active || card.projectState == .idle else { return false }
        return true
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
            return "先审查待批事项并记录决定，再让项目继续。"
        }
        return "先解除这个决策阻塞，或选择一个明确的低风险兜底方案。"
    }

    private static func recommendedActionForDecisionAssist(
        _ card: SupervisorPortfolioProjectCard
    ) -> String {
        guard let assist = card.decisionAssist else {
            return recommendedActionForDecisionBlocker(card)
        }

        let option = decisionAssistOption(assist)
        if let timeoutMs = assist.timeoutEscalationAfterMs, timeoutMs > 0 {
            return "检查 \(card.displayName) 的决策辅助：\(option)。如果一直没有决定，\(decisionAssistTimeoutText(timeoutMs)) 后升级处理。"
        }
        if assist.failClosed || assist.requiresUserDecision {
            return "检查 \(card.displayName) 的决策辅助：\(option)，并在继续工作前记录明确决定。"
        }
        if assist.autoAdoptAllowed {
            return "检查 \(card.displayName) 的决策辅助：\(option)。如果策略仍允许，Supervisor 可以在受治理路径上自动采纳。"
        }
        return "检查 \(card.displayName) 的决策辅助：\(option)，然后批准它，或选择另一个明确兜底方案。"
    }

    private static func recommendedActionForSpecGap(
        _ card: SupervisorPortfolioProjectCard
    ) -> String {
        let fieldList = specGapFieldList(card.missingSpecFields)
        guard !fieldList.isEmpty else {
            return "先补齐正式规格卡片，再继续分发工作。"
        }
        return "补齐 \(card.displayName) 的正式规格字段：\(fieldList)。"
    }

    private static func recommendedActionForDecisionRail(
        _ card: SupervisorPortfolioProjectCard
    ) -> String {
        SupervisorDecisionRailMessaging.recommendedNextAction(
            projectName: card.displayName,
            shadowedBackgroundNoteCount: card.shadowedBackgroundNoteCount,
            weakOnlyBackgroundNoteCount: card.weakOnlyBackgroundNoteCount
        )
    }

    private static func specGapReason(_ card: SupervisorPortfolioProjectCard) -> String {
        let fieldList = specGapFieldList(card.missingSpecFields)
        guard !fieldList.isEmpty else {
            return "formal_spec_missing"
        }
        return "formal_spec_missing: \(fieldList)"
    }

    private static func decisionAssistReason(_ card: SupervisorPortfolioProjectCard) -> String {
        guard let assist = card.decisionAssist else {
            return normalizedReason(card.topBlocker)
        }
        return "\(assist.blockerCategory.rawValue) \(assist.governanceMode.rawValue): \(decisionAssistOption(assist))"
    }

    private static func decisionAssistWhyItMatters(_ card: SupervisorPortfolioProjectCard) -> String {
        guard let assist = card.decisionAssist else {
            return "已经有一个明确的默认方案，这个阻塞不该继续悬空，而应进入明确的受治理决策。"
        }
        if assist.failClosed {
            return "Supervisor 已有可复用的默认方案，但在记录明确的受治理决定前，这个阻塞仍保持 fail-closed。"
        }
        switch assist.governanceMode {
        case .proposalOnly:
            return "已经有一个明确的默认方案，这个阻塞可以进入受治理的接受 / 拒绝决策。"
        case .proposalWithTimeoutEscalation:
            return "已经有一个可逆的低风险默认方案，这个阻塞应转成明确决定，而不是继续无限讨论。"
        case .autoAdoptIfPolicyAllows:
            return "已经有一个低风险、可逆的默认方案；如果策略仍允许，它可以在受治理路径上自动采纳。"
        }
    }

    private static func decisionRailReason(_ card: SupervisorPortfolioProjectCard) -> String {
        SupervisorDecisionRailMessaging.reasonSummary(
            shadowedBackgroundNoteCount: card.shadowedBackgroundNoteCount,
            weakOnlyBackgroundNoteCount: card.weakOnlyBackgroundNoteCount
        )
    }

    private static func decisionRailWhyItMatters(_ card: SupervisorPortfolioProjectCard) -> String {
        SupervisorDecisionRailMessaging.whyItMatters(
            shadowedBackgroundNoteCount: card.shadowedBackgroundNoteCount,
            weakOnlyBackgroundNoteCount: card.weakOnlyBackgroundNoteCount
        )
    }

    private static func zombieReason(
        _ card: SupervisorPortfolioProjectCard,
        now: Double
    ) -> String {
        guard let hours = ageHours(for: card, now: now) else {
            return normalizedReason(card.currentAction)
        }
        let days = max(1, hours / 24)
        return "\(days) 天没有实质性的项目集更新。"
    }

    private static func stalledReason(
        _ card: SupervisorPortfolioProjectCard,
        now: Double
    ) -> String {
        guard let hours = ageHours(for: card, now: now) else {
            return normalizedReason(card.currentAction)
        }
        return "\(hours) 小时没有实质性更新。"
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
        if trimmed.isEmpty { return "项目集状态已更新。" }
        if trimmed == "(无)" || trimmed == "(暂无)" {
            return "项目集状态已更新。"
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

    private static func containsDecisionCue(_ text: String) -> Bool {
        let normalized = normalizeToken(text)
        guard !normalized.isEmpty else { return false }

        let phraseCues = [
            "grant_required",
            "review_required",
            "proposal_pending",
            "default_proposal_pending",
            "needs review",
            "needs approval",
            "sign off",
            "policy decision",
            "decision pending",
            "approval pending",
            "pending approval",
            "pending authorization",
            "awaiting approval",
            "awaiting authorization",
            "requires approval",
            "requires review",
        ]
        if phraseCues.contains(where: normalized.contains) {
            return true
        }

        let englishWordPatterns = [
            #"\bdecision\b"#,
            #"\bapprove\b"#,
            #"\bapproval\b"#,
            #"\bauthorization\b"#,
        ]
        if englishWordPatterns.contains(where: { normalized.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }

        let cjkCues = [
            "决策",
            "审批",
            "授权",
            "待确认",
            "拍板",
            "定案",
            "选择",
        ]
        return cjkCues.contains(where: normalized.contains)
    }

    private static func specGapFieldList(_ fields: [SupervisorProjectSpecField]) -> String {
        fields.map(\.summaryToken).joined(separator: " / ")
    }

    private static func decisionAssistOption(_ assist: SupervisorDecisionBlockerAssist) -> String {
        let option = assist.recommendedOption ?? assist.templateCandidates.first ?? assist.blockerCategory.rawValue
        let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? assist.blockerCategory.rawValue : trimmed
    }

    private static func decisionAssistTimeoutText(_ timeoutMs: Int64) -> String {
        let minutes = max(1, Int((Double(timeoutMs) / 60_000.0).rounded(.down)))
        if minutes < 60 { return "\(minutes)m" }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }
}
