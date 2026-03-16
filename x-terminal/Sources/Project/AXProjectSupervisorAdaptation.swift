import Foundation

enum AXProjectAIStrengthBand: String, Codable, CaseIterable, Sendable {
    case unknown
    case weak
    case developing
    case capable
    case strong
}

extension AXProjectAIStrengthBand: Comparable {
    static func < (lhs: AXProjectAIStrengthBand, rhs: AXProjectAIStrengthBand) -> Bool {
        lhs.sortRank < rhs.sortRank
    }

    private var sortRank: Int {
        switch self {
        case .unknown:
            return 0
        case .weak:
            return 1
        case .developing:
            return 2
        case .capable:
            return 3
        case .strong:
            return 4
        }
    }
}

enum AXProjectSupervisorAdaptationMode: String, Codable, CaseIterable, Sendable {
    case manualOnly = "manual_only"
    case raiseOnly = "raise_only"
    case bidirectional
}

enum AXProjectSupervisorWorkOrderDepth: String, Codable, CaseIterable, Sendable {
    case none
    case brief
    case milestoneContract = "milestone_contract"
    case executionReady = "execution_ready"
    case stepLockedRescue = "step_locked_rescue"
}

extension AXProjectSupervisorWorkOrderDepth: Comparable {
    static func < (lhs: AXProjectSupervisorWorkOrderDepth, rhs: AXProjectSupervisorWorkOrderDepth) -> Bool {
        lhs.sortRank < rhs.sortRank
    }

    private var sortRank: Int {
        switch self {
        case .none:
            return 0
        case .brief:
            return 1
        case .milestoneContract:
            return 2
        case .executionReady:
            return 3
        case .stepLockedRescue:
            return 4
        }
    }
}

struct AXProjectAIStrengthProfile: Equatable, Sendable {
    static let currentSchemaVersion = "xt.project_ai_strength_profile.v1"

    var schemaVersion: String
    var strengthBand: AXProjectAIStrengthBand
    var confidence: Double
    var recommendedSupervisorFloor: AXProjectSupervisorInterventionTier
    var recommendedWorkOrderDepth: AXProjectSupervisorWorkOrderDepth
    var reasons: [String]
    var assessedAtMs: Int64
    var auditRef: String

    init(
        schemaVersion: String = AXProjectAIStrengthProfile.currentSchemaVersion,
        strengthBand: AXProjectAIStrengthBand,
        confidence: Double,
        recommendedSupervisorFloor: AXProjectSupervisorInterventionTier,
        recommendedWorkOrderDepth: AXProjectSupervisorWorkOrderDepth,
        reasons: [String],
        assessedAtMs: Int64 = 0,
        auditRef: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.strengthBand = strengthBand
        self.confidence = min(1, max(0, confidence))
        self.recommendedSupervisorFloor = recommendedSupervisorFloor
        self.recommendedWorkOrderDepth = recommendedWorkOrderDepth
        self.reasons = normalizedReasons(reasons)
        self.assessedAtMs = max(0, assessedAtMs)
        self.auditRef = auditRef
    }
}

struct AXProjectSupervisorAdaptationPolicy: Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_adaptation_policy.v1"

    var schemaVersion: String
    var adaptationMode: AXProjectSupervisorAdaptationMode
    var allowAutoRelax: Bool
    var stabilityWindowMinutes: Int
    var failureStreakRaiseThreshold: Int
    var insufficientEvidenceRaiseThreshold: Int
    var incidentRaiseEnabled: Bool
    var auditRef: String

    init(
        schemaVersion: String = AXProjectSupervisorAdaptationPolicy.currentSchemaVersion,
        adaptationMode: AXProjectSupervisorAdaptationMode,
        allowAutoRelax: Bool,
        stabilityWindowMinutes: Int,
        failureStreakRaiseThreshold: Int,
        insufficientEvidenceRaiseThreshold: Int,
        incidentRaiseEnabled: Bool,
        auditRef: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.adaptationMode = adaptationMode
        self.allowAutoRelax = allowAutoRelax
        self.stabilityWindowMinutes = max(1, stabilityWindowMinutes)
        self.failureStreakRaiseThreshold = max(1, failureStreakRaiseThreshold)
        self.insufficientEvidenceRaiseThreshold = max(1, insufficientEvidenceRaiseThreshold)
        self.incidentRaiseEnabled = incidentRaiseEnabled
        self.auditRef = auditRef
    }

    static let `default` = AXProjectSupervisorAdaptationPolicy(
        adaptationMode: .raiseOnly,
        allowAutoRelax: false,
        stabilityWindowMinutes: 180,
        failureStreakRaiseThreshold: 3,
        insufficientEvidenceRaiseThreshold: 2,
        incidentRaiseEnabled: true
    )
}

struct AXProjectSupervisorAdaptationSnapshot: Equatable, Sendable {
    var configuredSupervisorTier: AXProjectSupervisorInterventionTier
    var baselineRecommendedSupervisorTier: AXProjectSupervisorInterventionTier
    var recommendedSupervisorTier: AXProjectSupervisorInterventionTier
    var effectiveSupervisorTier: AXProjectSupervisorInterventionTier
    var recommendedWorkOrderDepth: AXProjectSupervisorWorkOrderDepth
    var effectiveWorkOrderDepth: AXProjectSupervisorWorkOrderDepth
    var adaptationPolicy: AXProjectSupervisorAdaptationPolicy
    var projectAIStrengthProfile: AXProjectAIStrengthProfile?
    var escalationReasons: [String]
}

extension AXProjectSupervisorInterventionTier {
    var defaultWorkOrderDepth: AXProjectSupervisorWorkOrderDepth {
        switch self {
        case .s0SilentAudit:
            return .none
        case .s1MilestoneReview:
            return .brief
        case .s2PeriodicReview:
            return .milestoneContract
        case .s3StrategicCoach:
            return .executionReady
        case .s4TightSupervision:
            return .stepLockedRescue
        }
    }
}

private func normalizedReasons(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for value in values {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { continue }
        guard seen.insert(normalized).inserted else { continue }
        ordered.append(normalized)
    }
    return ordered
}
