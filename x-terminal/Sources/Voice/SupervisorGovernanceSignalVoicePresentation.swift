import Foundation

struct SupervisorGovernanceSignalVoicePresentation: Equatable {
    var trigger: SupervisorVoiceJobTrigger
    var headlineText: String
    var detailText: String
    var metadataText: String
    var actionText: String?
    var fingerprint: String
}

enum SupervisorGovernanceSignalVoicePresentationMapper {
    static func map(
        overview: SupervisorSignalCenterOverviewPresentation?
    ) -> SupervisorGovernanceSignalVoicePresentation? {
        guard let overview,
              overview.priority != .stable else {
            return nil
        }

        return SupervisorGovernanceSignalVoicePresentation(
            trigger: trigger(for: overview),
            headlineText: overview.headlineText,
            detailText: overview.detailText,
            metadataText: overview.metadataText,
            actionText: trimmedNonEmpty(overview.focusAction?.label),
            fingerprint: overview.signalFingerprint
        )
    }

    private static func trigger(
        for overview: SupervisorSignalCenterOverviewPresentation
    ) -> SupervisorVoiceJobTrigger {
        if let focusAction = overview.focusAction {
            switch focusAction.action {
            case .scrollToBoard(let anchorID):
                if anchorID == SupervisorFocusPresentation.pendingHubGrantBoardAnchorID ||
                    anchorID == SupervisorFocusPresentation.pendingSupervisorSkillApprovalBoardAnchorID {
                    return .authorization
                }
            }
        }

        switch overview.priority {
        case .immediate, .attention:
            return .blocked
        case .watch, .stable:
            return .completed
        }
    }

    private static func trimmedNonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
