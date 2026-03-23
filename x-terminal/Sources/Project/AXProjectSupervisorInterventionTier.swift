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

    var oneLineSummary: String {
        switch self {
        case .s0SilentAudit:
            return "只看 heartbeat 和硬性审计，不主动插建议。"
        case .s1MilestoneReview:
            return "只在 blocker、pre-done、关键里程碑时 review，平时不打扰。"
        case .s2PeriodicReview:
            return "按固定节奏做 pulse review，必要时在 safe point 给建议。"
        case .s3StrategicCoach:
            return "定时加事件驱动 review，发现更好路径时默认可以要求 replan。"
        case .s4TightSupervision:
            return "高频 review、强确认和更细粒度救援，接近旁路带教。"
        }
    }

    var behaviorHighlights: [String] {
        switch self {
        case .s0SilentAudit:
            return [
                "只读 heartbeat / audit",
                "默认 observe only",
                "只在 kill-switch / 越界时出手"
            ]
        case .s1MilestoneReview:
            return [
                "里程碑 review",
                "safe point 给建议",
                "brief 级 work order"
            ]
        case .s2PeriodicReview:
            return [
                "定时 pulse review",
                "suggest at safe point",
                "milestone contract depth"
            ]
        case .s3StrategicCoach:
            return [
                "周期 + 事件驱动",
                "replan at safe point",
                "execution ready depth"
            ]
        case .s4TightSupervision:
            return [
                "高频 review",
                "step-locked rescue",
                "强 ack / 强纠偏"
            ]
        }
    }

    var typicalUseCases: [String] {
        switch self {
        case .s0SilentAudit:
            return [
                "A0 / A1 观察型项目",
                "用户强主控场景"
            ]
        case .s1MilestoneReview:
            return [
                "A1 计划型项目",
                "低频监督"
            ]
        case .s2PeriodicReview:
            return [
                "A2 Repo Auto",
                "需要定期纠偏的项目"
            ]
        case .s3StrategicCoach:
            return [
                "A3 Deliver Auto",
                "A4 旁路战略监督"
            ]
        case .s4TightSupervision:
            return [
                "高风险交付",
                "连续失误或需要手把手纠偏"
            ]
        }
    }

    var defaultAckSummary: String {
        defaultAckRequired ? "Required" : "Optional"
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
