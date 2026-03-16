import Foundation

extension AXProjectExecutionTier {
    var schedulingAutonomyScore: Double {
        switch self {
        case .a0Observe:
            return 0.15
        case .a1Plan:
            return 0.35
        case .a2RepoAuto:
            return 0.58
        case .a3DeliverAuto:
            return 0.82
        case .a4OpenClaw:
            return 1.0
        }
    }

    var schedulingParallelCapacity: Int {
        switch self {
        case .a0Observe:
            return 1
        case .a1Plan:
            return 2
        case .a2RepoAuto:
            return 3
        case .a3DeliverAuto:
            return 4
        case .a4OpenClaw:
            return 5
        }
    }

    var schedulingDurationMultiplier: Double {
        switch self {
        case .a0Observe:
            return 0.95
        case .a1Plan:
            return 0.85
        case .a2RepoAuto:
            return 0.75
        case .a3DeliverAuto:
            return 0.65
        case .a4OpenClaw:
            return 0.55
        }
    }
}

extension AXProjectSupervisorInterventionTier {
    var schedulingRiskSupportScore: Double {
        switch self {
        case .s0SilentAudit:
            return 0.05
        case .s1MilestoneReview:
            return 0.20
        case .s2PeriodicReview:
            return 0.45
        case .s3StrategicCoach:
            return 0.72
        case .s4TightSupervision:
            return 0.90
        }
    }

    var schedulingCapacityPenalty: Int {
        switch self {
        case .s4TightSupervision:
            return 1
        case .s0SilentAudit, .s1MilestoneReview, .s2PeriodicReview, .s3StrategicCoach:
            return 0
        }
    }
}

extension ProjectModel {
    var governanceSchedulingAutonomyScore: Double {
        executionTier.schedulingAutonomyScore
    }

    var governanceSchedulingRiskSupportScore: Double {
        supervisorInterventionTier.schedulingRiskSupportScore
    }

    var governanceParallelCapacity: Int {
        max(1, executionTier.schedulingParallelCapacity - supervisorInterventionTier.schedulingCapacityPenalty)
    }

    var governancePrefersExclusiveScheduling: Bool {
        executionTier == .a4OpenClaw || supervisorInterventionTier == .s4TightSupervision
    }
}

func xtSuggestedExecutionTier(for riskTier: LaneRiskTier) -> AXProjectExecutionTier {
    switch riskTier {
    case .critical:
        return .a4OpenClaw
    case .high:
        return .a3DeliverAuto
    case .medium:
        return .a2RepoAuto
    case .low:
        return .a1Plan
    }
}

func xtSuggestedSupervisorTier(for riskTier: LaneRiskTier) -> AXProjectSupervisorInterventionTier {
    switch riskTier {
    case .critical:
        return .s4TightSupervision
    case .high:
        return .s3StrategicCoach
    case .medium:
        return .s2PeriodicReview
    case .low:
        return .s1MilestoneReview
    }
}
