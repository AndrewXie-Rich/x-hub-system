import Foundation

struct SupervisorPortfolioUIReviewActivityPresentation: Equatable, Identifiable {
    var id: String
    var projectId: String
    var projectName: String
    var statusLine: String
    var summaryLine: String
    var detailLine: String?
    var updatedText: String
    var screenshotFileURL: URL?
    var tone: SupervisorHeaderControlTone
}

enum SupervisorPortfolioUIReviewActivityPresentationMapper {
    static func map(
        projectId: String,
        projectName: String,
        review: XTUIReviewPresentation,
        now: Date = Date()
    ) -> SupervisorPortfolioUIReviewActivityPresentation {
        SupervisorPortfolioUIReviewActivityPresentation(
            id: "ui-review:\(projectId)",
            projectId: projectId,
            projectName: projectName,
            statusLine: "\(review.verdictLabel) · \(review.evidenceLabel)",
            summaryLine: review.issueSummary,
            detailLine: detailLine(for: review),
            updatedText: review.relativeUpdatedText(now: now),
            screenshotFileURL: review.screenshotFileURL,
            tone: tone(for: review)
        )
    }

    private static func detailLine(
        for review: XTUIReviewPresentation
    ) -> String? {
        var parts: [String] = []

        if let trend = review.trend {
            parts.append(trend.headline)
        }

        if let comparison = review.comparison {
            if !comparison.addedIssueLabels.isEmpty {
                parts.append("新增 \(comparison.addedIssueLabels.count) 项")
            }
            if !comparison.resolvedIssueLabels.isEmpty {
                parts.append("解决 \(comparison.resolvedIssueLabels.count) 项")
            }
        }

        if parts.isEmpty {
            let summary = review.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let issueSummary = review.issueSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty, summary != issueSummary {
                parts.append(summary)
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func tone(
        for review: XTUIReviewPresentation
    ) -> SupervisorHeaderControlTone {
        switch review.verdict {
        case .ready:
            return .success
        case .attentionNeeded:
            return .warning
        case .insufficientEvidence:
            return .danger
        }
    }
}
