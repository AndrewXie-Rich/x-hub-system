import SwiftUI

extension ProjectGovernanceComposerAccentTone {
    static func forExecutionTier(_ tier: AXProjectExecutionTier) -> Self {
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

    static func forSupervisorTier(_ tier: AXProjectSupervisorInterventionTier) -> Self {
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

    static func forReviewPolicy(_ mode: AXProjectReviewPolicyMode) -> Self {
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

    var color: Color {
        switch self {
        case .gray:
            return .gray
        case .blue:
            return .blue
        case .teal:
            return .teal
        case .green:
            return .green
        case .orange:
            return .orange
        }
    }
}
