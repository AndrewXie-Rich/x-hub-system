import Foundation

enum SupervisorOfficialSkillsChannelActionSupport {
    static func primaryBlocker(
        from blockerSummaries: [AXOfficialSkillBlockerSummaryItem]
    ) -> AXOfficialSkillBlockerSummaryItem? {
        XTOfficialSkillsBlockerActionSupport.rankedBlockers(blockerSummaries).first
    }

    static func readinessAction(
        statusLine: String,
        transitionLine: String,
        detailLine: String,
        blockerSummaries: [AXOfficialSkillBlockerSummaryItem] = []
    ) -> (label: String, url: String)? {
        if let blocker = primaryBlocker(from: blockerSummaries),
           let action = XTOfficialSkillsBlockerActionSupport.action(for: blocker) {
            return (
                label: action.label,
                url: action.url
            )
        }

        let normalizedStatus = normalizedScalar(statusLine)
        let normalizedTransition = normalizedScalar(transitionLine)
        let normalizedDetail = normalizedScalar(detailLine)
        let hasExplicitBlockers = normalizedDetail.localizedCaseInsensitiveContains("Top blockers:")
        let title = hasExplicitBlockers
            ? "查看官方技能阻塞项"
            : "查看官方技能通道"
        let detail = firstMeaningfulScalar([
            normalizedDetail,
            normalizedTransition,
            normalizedStatus
        ])

        guard let url = XTDeepLinkURLBuilder.hubSetupURL(
            sectionId: "verify_readiness",
            title: title,
            detail: detail,
            refreshAction: .recheckOfficialSkills,
            refreshReason: "official_skills_channel"
        ) else {
            return nil
        }

        return (
            label: hasExplicitBlockers ? "查看阻塞项" : "打开就绪检查",
            url: url.absoluteString
        )
    }

    private static func firstMeaningfulScalar(_ values: [String]) -> String {
        values.first { !normalizedScalar($0).isEmpty } ?? ""
    }

    private static func normalizedScalar(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
