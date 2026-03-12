import Foundation

enum SupervisorTaskRole: String, Codable, CaseIterable, Sendable {
    case planner
    case coder
    case reviewer
    case doc
    case ops

    var canonicalTaskTags: [String] {
        switch self {
        case .planner:
            return ["scope_freeze", "spec_capsule", "decision_blocker"]
        case .coder:
            return ["codegen", "refactor", "runtime_fix"]
        case .reviewer:
            return ["review", "regression", "gate_review"]
        case .doc:
            return ["docs", "release_notes", "spec_freeze_writeup"]
        case .ops:
            return ["runbook", "rollout", "runtime_probe", "operator_action"]
        }
    }

    var preferredConfigRoles: [AXRole] {
        switch self {
        case .planner:
            return [.advisor, .supervisor]
        case .coder:
            return [.coder, .refine, .coarse]
        case .reviewer:
            return [.reviewer, .advisor]
        case .doc:
            return [.refine, .advisor, .reviewer]
        case .ops:
            return [.supervisor, .advisor, .reviewer]
        }
    }
}

enum SupervisorTaskRisk: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical

    var requiresHubPolicy: Bool {
        switch self {
        case .high, .critical:
            return true
        case .low, .medium:
            return false
        }
    }
}

enum SupervisorTaskSideEffect: String, Codable, CaseIterable, Sendable {
    case none
    case localMutation = "local_mutation"
    case externalRead = "external_read"
    case externalWrite = "external_write"
    case irreversible

    var minimumGrantPolicy: SupervisorRouteGrantPolicy {
        switch self {
        case .none:
            return .lowRiskOK
        case .localMutation, .externalRead:
            return .projectPolicyRequired
        case .externalWrite, .irreversible:
            return .hubPolicyRequired
        }
    }

    var hasOperationalSideEffect: Bool {
        self != .none
    }
}

enum SupervisorPreferredModelClass: String, Codable, CaseIterable, Sendable {
    case localReasoner = "local_reasoner"
    case paidPlanner = "paid_planner"
    case paidGeneral = "paid_general"
    case paidCoder = "paid_coder"
    case localCodegen = "local_codegen"
    case paidReviewer = "paid_reviewer"
    case paidWriter = "paid_writer"
    case localWriter = "local_writer"
    case paidOps = "paid_ops"
}

enum SupervisorRouteGrantPolicy: String, Codable, CaseIterable, Sendable {
    case lowRiskOK = "low_risk_ok"
    case projectPolicyRequired = "project_policy_required"
    case hubPolicyRequired = "hub_policy_required"

    private var severity: Int {
        switch self {
        case .lowRiskOK:
            return 0
        case .projectPolicyRequired:
            return 1
        case .hubPolicyRequired:
            return 2
        }
    }

    static func max(_ lhs: SupervisorRouteGrantPolicy, _ rhs: SupervisorRouteGrantPolicy) -> SupervisorRouteGrantPolicy {
        lhs.severity >= rhs.severity ? lhs : rhs
    }
}

struct SupervisorModelRouteExplainability: Codable, Equatable, Sendable {
    var whyRole: String
    var whyPreferredModelClasses: String
    var whyHubStillDecides: String
    var matchedSignals: [String]
    var classifierReasons: [String]

    var isEmpty: Bool {
        whyRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || whyPreferredModelClasses.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || whyHubStillDecides.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SupervisorModelRouteDecision: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_model_route_decision.v1"

    var schemaVersion: String
    var projectID: String
    var role: SupervisorTaskRole
    var taskTags: [String]
    var risk: SupervisorTaskRisk
    var sideEffect: SupervisorTaskSideEffect
    var codeExecution: Bool
    var preferredModelClasses: [SupervisorPreferredModelClass]
    var fallbackOrder: [SupervisorPreferredModelClass]
    var grantPolicy: SupervisorRouteGrantPolicy
    var hubPolicyRequired: Bool
    var matchedRouteTags: [String]
    var projectModelHints: [String]
    var explainability: SupervisorModelRouteExplainability

    init(
        schemaVersion: String = SupervisorModelRouteDecision.currentSchemaVersion,
        projectID: String,
        role: SupervisorTaskRole,
        taskTags: [String],
        risk: SupervisorTaskRisk,
        sideEffect: SupervisorTaskSideEffect,
        codeExecution: Bool,
        preferredModelClasses: [SupervisorPreferredModelClass],
        fallbackOrder: [SupervisorPreferredModelClass],
        grantPolicy: SupervisorRouteGrantPolicy,
        hubPolicyRequired: Bool,
        matchedRouteTags: [String],
        projectModelHints: [String],
        explainability: SupervisorModelRouteExplainability
    ) {
        self.schemaVersion = schemaVersion
        self.projectID = projectID
        self.role = role
        self.taskTags = taskTags
        self.risk = risk
        self.sideEffect = sideEffect
        self.codeExecution = codeExecution
        self.preferredModelClasses = preferredModelClasses
        self.fallbackOrder = fallbackOrder
        self.grantPolicy = grantPolicy
        self.hubPolicyRequired = hubPolicyRequired
        self.matchedRouteTags = matchedRouteTags
        self.projectModelHints = projectModelHints
        self.explainability = explainability
    }
}
