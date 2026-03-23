import Foundation

enum ProjectGovernanceComposerAccentTone: Equatable, Sendable {
    case gray
    case blue
    case teal
    case green
    case orange
}

struct ProjectGovernanceDestinationCardPresentation: Equatable, Sendable {
    let destination: XTProjectGovernanceDestination
    let heading: String
    let title: String
    let summary: String
    let accentTone: ProjectGovernanceComposerAccentTone
    let isSelected: Bool
}

struct ProjectGovernanceComposerPresentation: Equatable, Sendable {
    let cards: [ProjectGovernanceDestinationCardPresentation]

    init(
        executionTier: AXProjectExecutionTier,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier,
        reviewPolicyMode: AXProjectReviewPolicyMode,
        governancePresentation: ProjectGovernancePresentation,
        selectedDestination: XTProjectGovernanceDestination
    ) {
        cards = XTProjectGovernanceDestination.editorCases.map { destination in
            switch destination {
            case .executionTier:
                return ProjectGovernanceDestinationCardPresentation(
                    destination: destination,
                    heading: destination.displayTitle,
                    title: executionTier.displayName,
                    summary: executionTier.oneLineSummary,
                    accentTone: Self.executionAccentTone(for: executionTier),
                    isSelected: selectedDestination == destination
                )
            case .supervisorTier:
                return ProjectGovernanceDestinationCardPresentation(
                    destination: destination,
                    heading: destination.displayTitle,
                    title: supervisorInterventionTier.displayName,
                    summary: supervisorInterventionTier.oneLineSummary,
                    accentTone: Self.supervisorAccentTone(for: supervisorInterventionTier),
                    isSelected: selectedDestination == destination
                )
            case .heartbeatReview:
                return ProjectGovernanceDestinationCardPresentation(
                    destination: destination,
                    heading: destination.displayTitle,
                    title: reviewPolicyMode.displayName,
                    summary: governancePresentation.reviewCadenceText,
                    accentTone: Self.reviewAccentTone(for: reviewPolicyMode),
                    isSelected: selectedDestination == destination
                )
            case .overview:
                return ProjectGovernanceDestinationCardPresentation(
                    destination: destination,
                    heading: destination.displayTitle,
                    title: destination.displayTitle,
                    summary: governancePresentation.homeStatusMessage,
                    accentTone: .blue,
                    isSelected: selectedDestination == destination
                )
            case .uiReview:
                return ProjectGovernanceDestinationCardPresentation(
                    destination: destination,
                    heading: destination.displayTitle,
                    title: destination.displayTitle,
                    summary: "Latest UI review workspace",
                    accentTone: .teal,
                    isSelected: selectedDestination == destination
                )
            }
        }
    }

    private static func executionAccentTone(
        for tier: AXProjectExecutionTier
    ) -> ProjectGovernanceComposerAccentTone {
        switch tier {
        case .a0Observe:
            return .gray
        case .a1Plan:
            return .blue
        case .a2RepoAuto:
            return .teal
        case .a3DeliverAuto:
            return .green
        case .a4OpenClaw:
            return .orange
        }
    }

    private static func supervisorAccentTone(
        for tier: AXProjectSupervisorInterventionTier
    ) -> ProjectGovernanceComposerAccentTone {
        switch tier {
        case .s0SilentAudit:
            return .gray
        case .s1MilestoneReview:
            return .blue
        case .s2PeriodicReview:
            return .teal
        case .s3StrategicCoach:
            return .green
        case .s4TightSupervision:
            return .orange
        }
    }

    private static func reviewAccentTone(
        for mode: AXProjectReviewPolicyMode
    ) -> ProjectGovernanceComposerAccentTone {
        switch mode {
        case .off:
            return .gray
        case .milestoneOnly:
            return .blue
        case .periodic:
            return .teal
        case .hybrid:
            return .green
        case .aggressive:
            return .orange
        }
    }
}
