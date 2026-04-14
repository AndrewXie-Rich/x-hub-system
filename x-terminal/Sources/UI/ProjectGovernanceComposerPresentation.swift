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
                    heading: destination.localizedDisplayTitle,
                    title: executionTier.localizedDisplayLabel,
                    summary: executionTier.oneLineSummary,
                    accentTone: .forExecutionTier(executionTier),
                    isSelected: selectedDestination == destination
                )
            case .supervisorTier:
                return ProjectGovernanceDestinationCardPresentation(
                    destination: destination,
                    heading: destination.localizedDisplayTitle,
                    title: supervisorInterventionTier.localizedDisplayLabel,
                    summary: supervisorInterventionTier.oneLineSummary,
                    accentTone: .forSupervisorTier(supervisorInterventionTier),
                    isSelected: selectedDestination == destination
                )
            case .heartbeatReview:
                return ProjectGovernanceDestinationCardPresentation(
                    destination: destination,
                    heading: destination.localizedDisplayTitle,
                    title: reviewPolicyMode.localizedDisplayName,
                    summary: governancePresentation.reviewCadenceText,
                    accentTone: .forReviewPolicy(reviewPolicyMode),
                    isSelected: selectedDestination == destination
                )
            case .overview:
                return ProjectGovernanceDestinationCardPresentation(
                    destination: destination,
                    heading: destination.localizedDisplayTitle,
                    title: destination.localizedDisplayTitle,
                    summary: governancePresentation.homeStatusMessage,
                    accentTone: .blue,
                    isSelected: selectedDestination == destination
                )
            case .uiReview:
                return ProjectGovernanceDestinationCardPresentation(
                    destination: destination,
                    heading: destination.localizedDisplayTitle,
                    title: destination.localizedDisplayTitle,
                    summary: "最近一次 UI 审查工作区",
                    accentTone: .teal,
                    isSelected: selectedDestination == destination
                )
            }
        }
    }
}
