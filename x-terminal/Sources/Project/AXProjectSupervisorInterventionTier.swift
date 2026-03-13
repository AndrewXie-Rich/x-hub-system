import Foundation

enum AXProjectSupervisorInterventionTier: String, Codable, CaseIterable, Sendable {
    case s0SilentAudit = "s0_silent_audit"
    case s1MilestoneReview = "s1_milestone_review"
    case s2PeriodicReview = "s2_periodic_review"
    case s3StrategicCoach = "s3_strategic_coach"
    case s4TightSupervision = "s4_tight_supervision"

    var displayName: String {
        switch self {
        case .s0SilentAudit:
            return "S0 Silent Audit"
        case .s1MilestoneReview:
            return "S1 Milestone Review"
        case .s2PeriodicReview:
            return "S2 Periodic Review"
        case .s3StrategicCoach:
            return "S3 Strategic Coach"
        case .s4TightSupervision:
            return "S4 Tight Supervision"
        }
    }

    var defaultReviewMemoryCeiling: XTMemoryServingProfile {
        switch self {
        case .s0SilentAudit, .s1MilestoneReview:
            return .m2PlanReview
        case .s2PeriodicReview:
            return .m3DeepDive
        case .s3StrategicCoach, .s4TightSupervision:
            return .m4FullScan
        }
    }

    var defaultInterventionMode: SupervisorGuidanceInterventionMode {
        switch self {
        case .s0SilentAudit:
            return .observeOnly
        case .s1MilestoneReview, .s2PeriodicReview:
            return .suggestNextSafePoint
        case .s3StrategicCoach, .s4TightSupervision:
            return .replanNextSafePoint
        }
    }

    var defaultAckRequired: Bool {
        switch self {
        case .s0SilentAudit:
            return false
        case .s1MilestoneReview, .s2PeriodicReview, .s3StrategicCoach, .s4TightSupervision:
            return true
        }
    }
}

extension AXProjectSupervisorInterventionTier: Comparable {
    static func < (
        lhs: AXProjectSupervisorInterventionTier,
        rhs: AXProjectSupervisorInterventionTier
    ) -> Bool {
        lhs.sortRank < rhs.sortRank
    }

    private var sortRank: Int {
        switch self {
        case .s0SilentAudit:
            return 0
        case .s1MilestoneReview:
            return 1
        case .s2PeriodicReview:
            return 2
        case .s3StrategicCoach:
            return 3
        case .s4TightSupervision:
            return 4
        }
    }
}
