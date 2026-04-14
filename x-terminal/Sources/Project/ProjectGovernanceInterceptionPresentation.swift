import Foundation

struct ProjectGovernanceInterceptionPresentation: Equatable, Sendable {
    var item: ProjectSkillActivityItem
    var blockedSummary: String?
    var policyReason: String?
    var governanceReason: String
    var governanceTruthLine: String?
    var repairHint: XTGuardrailRepairHint?

    var repairActionSummary: String? {
        guard let repairHint else { return nil }
        return "\(repairHint.buttonTitle)：\(repairHint.helpText)"
    }

    var shouldShowGovernanceReason: Bool {
        let summary = blockedSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reason = governanceReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty || summary != reason
    }

    var repairFocusContext: XTSectionFocusContext? {
        guard repairHint != nil else { return nil }

        let detail = repairEvidenceLines.joined(separator: "\n")
        return XTSectionFocusContext(
            title: "治理拦截修复",
            detail: detail.isEmpty ? nil : detail
        )
    }

    var repairInlineMessage: String? {
        guard let focusContext = repairFocusContext else { return nil }
        guard let detail = focusContext.detail, !detail.isEmpty else {
            return focusContext.title
        }
        if detail.contains("\n") {
            return "\(focusContext.title)\n\(detail)"
        }
        return "\(focusContext.title) · \(detail)"
    }

    private var repairEvidenceLines: [String] {
        let summary = blockedSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let truth = governanceTruthLine?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reason = governanceReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let policy = policyReason?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let repairAction = repairActionSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var parts: [String] = []
        if !summary.isEmpty {
            parts.append("最近一次拦截：\(summary)")
        } else if !reason.isEmpty {
            parts.append("最近一次拦截：\(reason)")
        }
        if !reason.isEmpty {
            parts.append("governance_reason=\(reason)")
        }
        if !truth.isEmpty {
            parts.append("governance_truth=\(truth)")
        }
        if !policy.isEmpty {
            parts.append("policy_reason=\(policy)")
        }
        if !repairAction.isEmpty {
            parts.append("repair_action=\(repairAction)")
        }
        return parts
    }

    static func latest(
        from items: [ProjectSkillActivityItem]
    ) -> ProjectGovernanceInterceptionPresentation? {
        items
            .compactMap(Self.make)
            .sorted { lhs, rhs in
                if lhs.item.createdAt != rhs.item.createdAt {
                    return lhs.item.createdAt > rhs.item.createdAt
                }
                return lhs.item.requestID > rhs.item.requestID
            }
            .first
    }

    static func make(
        from item: ProjectSkillActivityItem
    ) -> ProjectGovernanceInterceptionPresentation? {
        let normalizedStatus = item.status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedStatus == "blocked" || normalizedStatus == "failed" else {
            return nil
        }
        guard let governanceReason = ProjectSkillActivityPresentation.governanceReason(for: item) else {
            return nil
        }

        return ProjectGovernanceInterceptionPresentation(
            item: item,
            blockedSummary: ProjectSkillActivityPresentation.blockedSummary(for: item),
            policyReason: ProjectSkillActivityPresentation.policyReason(for: item),
            governanceReason: governanceReason,
            governanceTruthLine: ProjectSkillActivityPresentation.displayGovernanceTruthLine(for: item),
            repairHint: XTGuardrailMessagePresentation.repairHint(
                denyCode: item.denyCode,
                policySource: item.policySource,
                policyReason: item.policyReason
            )
        )
    }
}
