import Foundation

extension SupervisorManager {
    func heartbeatPortfolioCard(
        for project: AXProjectEntry,
        cachedCards: [String: SupervisorPortfolioProjectCard],
        now: Double
    ) -> SupervisorPortfolioProjectCard {
        if var card = cachedCards[project.projectId] {
            if card.prioritySnapshot == nil {
                card.prioritySnapshot = SupervisorPortfolioSnapshotBuilder.card(
                    from: project,
                    now: now
                ).prioritySnapshot
            }
            return card
        }
        return SupervisorPortfolioSnapshotBuilder.card(from: project, now: now)
    }

    func heartbeatPortfolioTokenLines(
        card: SupervisorPortfolioProjectCard
    ) -> [String] {
        guard let priority = card.prioritySnapshot else { return [] }
        return [
            "portfolio_priority_band=\(priority.priorityBand.rawValue)",
            "portfolio_priority_score=\(priority.priorityScore)",
            "portfolio_priority_why=\(capped(SupervisorPortfolioSnapshotBuilder.priorityWhyText(for: card), maxChars: 220))"
        ]
    }

    func heartbeatPortfolioPriorityReasonLine(
        card: SupervisorPortfolioProjectCard?,
        lead: String
    ) -> String? {
        guard let card,
              let priority = card.prioritySnapshot else {
            return nil
        }
        return "\(lead)：\(capped(SupervisorPortfolioSnapshotBuilder.priorityWhyText(for: card), maxChars: 96))（优先级：\(priority.priorityBand.displayName) · score=\(priority.priorityScore)）"
    }

    func heartbeatPortfolioBandRank(
        _ band: SupervisorPortfolioPriorityBand?
    ) -> Int {
        switch band {
        case .critical:
            return 0
        case .high:
            return 1
        case .normal:
            return 2
        case .low:
            return 3
        case nil:
            return 4
        }
    }
}
