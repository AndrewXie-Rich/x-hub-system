import Foundation

enum AXProjectExecutionTier: String, Codable, CaseIterable, Sendable {
    case a0Observe = "a0_observe"
    case a1Plan = "a1_plan"
    case a2RepoAuto = "a2_repo_auto"
    case a3DeliverAuto = "a3_deliver_auto"
    case a4OpenClaw = "a4_openclaw"

    var displayName: String {
        switch self {
        case .a0Observe:
            return "A0 Observe"
        case .a1Plan:
            return "A1 Plan"
        case .a2RepoAuto:
            return "A2 Repo Auto"
        case .a3DeliverAuto:
            return "A3 Deliver Auto"
        case .a4OpenClaw:
            return "A4 OpenClaw"
        }
    }

    var defaultProjectMemoryCeiling: XTMemoryServingProfile {
        switch self {
        case .a0Observe, .a1Plan:
            return .m2PlanReview
        case .a2RepoAuto, .a3DeliverAuto:
            return .m3DeepDive
        case .a4OpenClaw:
            return .m4FullScan
        }
    }

    var defaultSupervisorInterventionTier: AXProjectSupervisorInterventionTier {
        switch self {
        case .a0Observe:
            return .s0SilentAudit
        case .a1Plan:
            return .s1MilestoneReview
        case .a2RepoAuto:
            return .s2PeriodicReview
        case .a3DeliverAuto, .a4OpenClaw:
            return .s3StrategicCoach
        }
    }

    var minimumSafeSupervisorTier: AXProjectSupervisorInterventionTier {
        switch self {
        case .a0Observe, .a1Plan:
            return .s0SilentAudit
        case .a2RepoAuto, .a3DeliverAuto:
            return .s1MilestoneReview
        case .a4OpenClaw:
            return .s2PeriodicReview
        }
    }

    var defaultReviewPolicyMode: AXProjectReviewPolicyMode {
        switch self {
        case .a0Observe:
            return .milestoneOnly
        case .a1Plan:
            return .periodic
        case .a2RepoAuto, .a3DeliverAuto, .a4OpenClaw:
            return .hybrid
        }
    }

    var defaultProgressHeartbeatSeconds: Int {
        switch self {
        case .a0Observe:
            return 1800
        case .a1Plan:
            return 1200
        case .a2RepoAuto:
            return 900
        case .a3DeliverAuto, .a4OpenClaw:
            return 600
        }
    }

    var defaultReviewPulseSeconds: Int {
        switch self {
        case .a0Observe:
            return 0
        case .a1Plan:
            return 3600
        case .a2RepoAuto:
            return 1800
        case .a3DeliverAuto, .a4OpenClaw:
            return 1200
        }
    }

    var defaultBrainstormReviewSeconds: Int {
        switch self {
        case .a0Observe, .a1Plan:
            return 0
        case .a2RepoAuto:
            return 3600
        case .a3DeliverAuto, .a4OpenClaw:
            return 2400
        }
    }

    var defaultEventDrivenReviewEnabled: Bool {
        switch self {
        case .a0Observe, .a1Plan:
            return false
        case .a2RepoAuto, .a3DeliverAuto, .a4OpenClaw:
            return true
        }
    }

    var defaultEventReviewTriggers: [AXProjectReviewTrigger] {
        switch self {
        case .a0Observe:
            return [.manualRequest]
        case .a1Plan:
            return [.preDoneSummary]
        case .a2RepoAuto:
            return [.blockerDetected, .preDoneSummary]
        case .a3DeliverAuto:
            return [.blockerDetected, .planDrift, .preDoneSummary]
        case .a4OpenClaw:
            return [.blockerDetected, .preHighRiskAction, .preDoneSummary]
        }
    }

    var defaultSurfacePreset: AXProjectAutonomyMode {
        switch self {
        case .a0Observe:
            return .manual
        case .a1Plan, .a2RepoAuto, .a3DeliverAuto:
            return .guided
        case .a4OpenClaw:
            return .trustedOpenClawMode
        }
    }

    var baseCapabilityBundle: AXProjectCapabilityBundle {
        switch self {
        case .a0Observe:
            return .observeOnly
        case .a1Plan:
            return AXProjectCapabilityBundle(
                allowJobPlanAuto: true,
                allowRepoWrite: false,
                allowRepoBuild: false,
                allowRepoTest: false,
                allowGitApply: false,
                allowBrowserRuntime: false,
                allowDeviceTools: false,
                allowConnectorActions: false,
                allowExtensions: false,
                allowAutoLocalApproval: false
            )
        case .a2RepoAuto, .a3DeliverAuto:
            return AXProjectCapabilityBundle(
                allowJobPlanAuto: true,
                allowRepoWrite: true,
                allowRepoBuild: true,
                allowRepoTest: true,
                allowGitApply: true,
                allowBrowserRuntime: false,
                allowDeviceTools: false,
                allowConnectorActions: false,
                allowExtensions: false,
                allowAutoLocalApproval: false
            )
        case .a4OpenClaw:
            return AXProjectCapabilityBundle(
                allowJobPlanAuto: true,
                allowRepoWrite: true,
                allowRepoBuild: true,
                allowRepoTest: true,
                allowGitApply: true,
                allowBrowserRuntime: true,
                allowDeviceTools: true,
                allowConnectorActions: true,
                allowExtensions: true,
                allowAutoLocalApproval: true
            )
        }
    }

    var defaultExecutionBudget: AXProjectExecutionBudget {
        switch self {
        case .a0Observe:
            return AXProjectExecutionBudget(
                maxContinuousRunMinutes: 10,
                maxToolCallsPerRun: 0,
                maxRetryDepth: 0,
                maxCostUSDSoft: 1,
                preDoneReviewRequired: false,
                doneRequiresEvidence: false
            )
        case .a1Plan:
            return AXProjectExecutionBudget(
                maxContinuousRunMinutes: 20,
                maxToolCallsPerRun: 8,
                maxRetryDepth: 1,
                maxCostUSDSoft: 3,
                preDoneReviewRequired: true,
                doneRequiresEvidence: false
            )
        case .a2RepoAuto:
            return AXProjectExecutionBudget(
                maxContinuousRunMinutes: 45,
                maxToolCallsPerRun: 24,
                maxRetryDepth: 2,
                maxCostUSDSoft: 8,
                preDoneReviewRequired: true,
                doneRequiresEvidence: true
            )
        case .a3DeliverAuto:
            return AXProjectExecutionBudget(
                maxContinuousRunMinutes: 90,
                maxToolCallsPerRun: 48,
                maxRetryDepth: 3,
                maxCostUSDSoft: 15,
                preDoneReviewRequired: true,
                doneRequiresEvidence: true
            )
        case .a4OpenClaw:
            return AXProjectExecutionBudget(
                maxContinuousRunMinutes: 120,
                maxToolCallsPerRun: 80,
                maxRetryDepth: 3,
                maxCostUSDSoft: 25,
                preDoneReviewRequired: true,
                doneRequiresEvidence: true
            )
        }
    }

    static func fromLegacyAutonomyMode(_ mode: AXProjectAutonomyMode) -> AXProjectExecutionTier {
        switch mode {
        case .manual:
            return .a0Observe
        case .guided:
            return .a1Plan
        case .trustedOpenClawMode:
            return .a4OpenClaw
        }
    }

    static func fromLegacyAutonomyLevel(_ level: AutonomyLevel) -> AXProjectExecutionTier {
        switch level {
        case .manual:
            return .a0Observe
        case .assisted:
            return .a1Plan
        case .semiAuto:
            return .a2RepoAuto
        case .auto:
            return .a3DeliverAuto
        case .fullAuto:
            return .a4OpenClaw
        }
    }
}

extension AXProjectExecutionTier: Comparable {
    static func < (lhs: AXProjectExecutionTier, rhs: AXProjectExecutionTier) -> Bool {
        lhs.sortRank < rhs.sortRank
    }

    private var sortRank: Int {
        switch self {
        case .a0Observe:
            return 0
        case .a1Plan:
            return 1
        case .a2RepoAuto:
            return 2
        case .a3DeliverAuto:
            return 3
        case .a4OpenClaw:
            return 4
        }
    }
}
