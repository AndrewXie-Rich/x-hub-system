import Foundation

enum XTProjectGovernanceDestination: String, CaseIterable, Codable, Sendable {
    case overview = "project_governance"
    case uiReview = "ui_review"
    case executionTier = "execution_tier"
    case supervisorTier = "supervisor_tier"
    case heartbeatReview = "review_cadence"

    static let editorCases: [XTProjectGovernanceDestination] = [
        .executionTier,
        .supervisorTier,
        .heartbeatReview
    ]

    static func parse(_ raw: String?) -> XTProjectGovernanceDestination? {
        guard let raw else { return nil }
        let token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !token.isEmpty else { return nil }

        switch token {
        case overview.rawValue, "overview":
            return .overview
        case uiReview.rawValue, "uireview", "ui_review_workspace", "review_workspace":
            return .uiReview
        case executionTier.rawValue, "execution", "a_tier", "atier":
            return .executionTier
        case supervisorTier.rawValue, "supervision", "supervisor", "s_tier", "stier":
            return .supervisorTier
        case heartbeatReview.rawValue, "heartbeat_review", "heartbeat", "review", "cadence":
            return .heartbeatReview
        default:
            return nil
        }
    }

    var displayTitle: String {
        switch self {
        case .overview:
            return "Project Governance"
        case .uiReview:
            return "UI Review"
        case .executionTier:
            return "Execution Tier"
        case .supervisorTier:
            return "Supervisor Tier"
        case .heartbeatReview:
            return "Heartbeat & Review"
        }
    }

    var focusContext: XTSectionFocusContext {
        switch self {
        case .overview:
            return XTSectionFocusContext(
                title: "Project Governance",
                detail: "Current governance status"
            )
        case .uiReview:
            return XTSectionFocusContext(
                title: "Latest UI Review",
                detail: "Project UI review workspace"
            )
        case .executionTier:
            return XTSectionFocusContext(
                title: "Project Governance",
                detail: "Execution Tier"
            )
        case .supervisorTier:
            return XTSectionFocusContext(
                title: "Project Governance",
                detail: "Supervisor Tier"
            )
        case .heartbeatReview:
            return XTSectionFocusContext(
                title: "Project Governance",
                detail: "Heartbeat & Review"
            )
        }
    }
}

enum XTProjectSettingsSectionID {
    static let projectGovernance = XTProjectGovernanceDestination.overview.rawValue
    static let uiReview = XTProjectGovernanceDestination.uiReview.rawValue
    static let executionTier = XTProjectGovernanceDestination.executionTier.rawValue
    static let supervisorTier = XTProjectGovernanceDestination.supervisorTier.rawValue
    static let reviewCadence = XTProjectGovernanceDestination.heartbeatReview.rawValue
}

struct XTProjectSettingsFocusRequest: Equatable {
    var nonce: Int
    var projectId: String
    var destination: XTProjectGovernanceDestination
    var context: XTSectionFocusContext?

    var sectionId: String { destination.rawValue }
}
