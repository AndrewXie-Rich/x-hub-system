import Foundation

struct SupervisorPrimarySignalPresentation: Equatable {
    static let cockpitActionID = "focus_primary_signal"

    var badgeText: String
    var badgeTone: SupervisorHeaderControlTone
    var eyebrowText: String
    var headlineText: String
    var detailText: String
    var metadataText: String
    var focusAction: SupervisorSignalCenterOverviewActionDescriptor?

    var cockpitAction: PrimaryActionRailAction? {
        guard let focusAction else { return nil }

        return PrimaryActionRailAction(
            id: Self.cockpitActionID,
            title: focusAction.label,
            subtitle: detailText,
            systemImage: cockpitSystemImage,
            style: badgeTone == .danger ? .diagnostic : .secondary
        )
    }

    private var cockpitSystemImage: String {
        switch badgeTone {
        case .danger:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "shield.lefthalf.filled"
        case .accent:
            return "bolt.horizontal.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .neutral:
            return "scope"
        }
    }
}

enum SupervisorPrimarySignalPresentationMapper {
    static func map(
        overview: SupervisorSignalCenterOverviewPresentation?
    ) -> SupervisorPrimarySignalPresentation? {
        guard let overview,
              overview.priority != .stable else {
            return nil
        }

        return SupervisorPrimarySignalPresentation(
            badgeText: overview.priorityText,
            badgeTone: overview.priorityTone,
            eyebrowText: "当前主信号",
            headlineText: overview.headlineText,
            detailText: overview.detailText,
            metadataText: overview.metadataText,
            focusAction: overview.focusAction
        )
    }
}
