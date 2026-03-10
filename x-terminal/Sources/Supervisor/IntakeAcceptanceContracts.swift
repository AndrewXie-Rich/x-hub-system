import Foundation

enum SupervisorInnovationLevel: String, Codable, Equatable {
    case l0 = "L0"
    case l1 = "L1"
    case l2 = "L2"
    case l3 = "L3"
    case l4 = "L4"

    init?(token: String) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.init(rawValue: normalized)
    }
}

enum SupervisorSuggestionGovernance: String, Codable, Equatable {
    case supervisorOnly = "supervisor_only"
    case hybrid
    case laneOpen = "lane_open"

    init?(token: String) {
        let normalized = normalizedFieldKey(token)
        switch normalized {
        case "supervisor_only": self = .supervisorOnly
        case "hybrid": self = .hybrid
        case "lane_open": self = .laneOpen
        default: return nil
        }
    }
}

enum SupervisorRiskLevel: String, Codable, Equatable {
    case low
    case medium
    case high

    init?(token: String) {
        let normalized = normalizedFieldKey(token)
        switch normalized {
        case "low": self = .low
        case "medium", "med": self = .medium
        case "high", "critical": self = .high
        default: return nil
        }
    }
}

enum SupervisorAcceptanceMode: String, Codable, Equatable {
    case internalBeta = "internal_beta"
    case releaseCandidate = "release_candidate"
    case production

    init?(token: String) {
        let normalized = normalizedFieldKey(token)
        switch normalized {
        case "internal_beta", "beta": self = .internalBeta
        case "release_candidate", "rc": self = .releaseCandidate
        case "production", "prod": self = .production
        default: return nil
        }
    }
}

enum SupervisorBudgetTier: String, Codable, Equatable {
    case tight
    case balanced
    case aggressive

    init?(token: String) {
        let normalized = normalizedFieldKey(token)
        switch normalized {
        case "tight": self = .tight
        case "balanced", "standard": self = .balanced
        case "aggressive", "burst": self = .aggressive
        default: return nil
        }
    }
}

struct SupervisorIntakeSourceDocument: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case markdown
        case spec
        case workOrder = "work_order"
        case text
    }

    let ref: String
    let kind: Kind
    let contents: String

    var id: String { ref }
}

struct ProjectIntakeBudgetPolicy: Codable, Equatable {
    let tokenBudgetTier: SupervisorBudgetTier
    let paidAIAllowed: Bool

    enum CodingKeys: String, CodingKey {
        case tokenBudgetTier = "token_budget_tier"
        case paidAIAllowed = "paid_ai_allowed"
    }
}

struct ProjectIntakePoolPlanEntry: Codable, Equatable, Identifiable {
    let poolID: String
    let poolGoal: String
    let recommendedLaneCount: Int
    let laneSplitReason: String

    var id: String { poolID }

    enum CodingKeys: String, CodingKey {
        case poolID = "pool_id"
        case poolGoal = "pool_goal"
        case recommendedLaneCount = "recommended_lane_count"
        case laneSplitReason = "lane_split_reason"
    }
}

struct ProjectIntakeManifest: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sourceBundleRefs: [String]
    let projectGoal: String
    let inScope: [String]
    let outOfScope: [String]
    let constraints: [String]
    let touchPolicy: DeliveryParticipationMode
    let innovationLevel: SupervisorInnovationLevel
    let suggestionGovernance: SupervisorSuggestionGovernance
    let riskLevel: SupervisorRiskLevel
    let requiresUserAuthorization: Bool
    let acceptanceMode: SupervisorAcceptanceMode
    let budgetPolicy: ProjectIntakeBudgetPolicy
    let poolPlan: [ProjectIntakePoolPlanEntry]
    let acceptanceTargets: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sourceBundleRefs = "source_bundle_refs"
        case projectGoal = "project_goal"
        case inScope = "in_scope"
        case outOfScope = "out_of_scope"
        case constraints
        case touchPolicy = "touch_policy"
        case innovationLevel = "innovation_level"
        case suggestionGovernance = "suggestion_governance"
        case riskLevel = "risk_level"
        case requiresUserAuthorization = "requires_user_authorization"
        case acceptanceMode = "acceptance_mode"
        case budgetPolicy = "budget_policy"
        case poolPlan = "pool_plan"
        case acceptanceTargets = "acceptance_targets"
        case auditRef = "audit_ref"
    }
}

enum ProjectIntakeFreezeDecision: String, Codable, Equatable {
    case pass
    case failClosed = "fail_closed"
}

struct ProjectIntakeFreezeGate: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let intakeManifestRef: String
    let requiredFieldsComplete: Bool
    let scopeConflictDetected: Bool
    let authorizationBoundaryClear: Bool
    let decision: ProjectIntakeFreezeDecision
    let denyCode: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case intakeManifestRef = "intake_manifest_ref"
        case requiredFieldsComplete = "required_fields_complete"
        case scopeConflictDetected = "scope_conflict_detected"
        case authorizationBoundaryClear = "authorization_boundary_clear"
        case decision
        case denyCode = "deny_code"
    }
}

struct ProjectIntakeIssue: Codable, Equatable, Identifiable {
    let code: String
    let field: String
    let detail: String
    let blocking: Bool

    var id: String { "\(field):\(code):\(detail)" }
}

struct ProjectIntakeExtractionEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let sourceBundleRefs: [String]
    let projectGoal: String
    let inScope: [String]
    let outOfScope: [String]
    let constraints: [String]
    let acceptanceTargets: [String]
    let touchPolicy: String?
    let innovationLevel: String?
    let suggestionGovernance: String?
    let riskLevel: String?
    let requiresUserAuthorization: Bool?
    let acceptanceMode: String?
    let budgetTier: String?
    let paidAIAllowed: Bool?
    let requiredFieldsPresent: [String]
    let missingRequiredFields: [String]
    let issues: [ProjectIntakeIssue]
    let requiredFieldCoverage: Double
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case sourceBundleRefs = "source_bundle_refs"
        case projectGoal = "project_goal"
        case inScope = "in_scope"
        case outOfScope = "out_of_scope"
        case constraints
        case acceptanceTargets = "acceptance_targets"
        case touchPolicy = "touch_policy"
        case innovationLevel = "innovation_level"
        case suggestionGovernance = "suggestion_governance"
        case riskLevel = "risk_level"
        case requiresUserAuthorization = "requires_user_authorization"
        case acceptanceMode = "acceptance_mode"
        case budgetTier = "budget_tier"
        case paidAIAllowed = "paid_ai_allowed"
        case requiredFieldsPresent = "required_fields_present"
        case missingRequiredFields = "missing_required_fields"
        case issues
        case requiredFieldCoverage = "required_field_coverage"
        case auditRef = "audit_ref"
    }
}

struct ProjectBootstrapLaneBinding: Codable, Equatable, Identifiable {
    let laneID: String
    let goal: String
    let dependsOn: [String]
    let lanePlanRef: String
    let promptPackRef: String

    var id: String { laneID }

    enum CodingKeys: String, CodingKey {
        case laneID = "lane_id"
        case goal
        case dependsOn = "depends_on"
        case lanePlanRef = "lane_plan_ref"
        case promptPackRef = "prompt_pack_ref"
    }
}

struct ProjectBootstrapBinding: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let intakeManifestRef: String
    let touchPolicy: DeliveryParticipationMode
    let poolPlan: [ProjectIntakePoolPlanEntry]
    let laneBindings: [ProjectBootstrapLaneBinding]
    let promptPackRefs: [String]
    let bootstrapReady: Bool
    let issues: [ProjectIntakeIssue]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case intakeManifestRef = "intake_manifest_ref"
        case touchPolicy = "touch_policy"
        case poolPlan = "pool_plan"
        case laneBindings = "lane_bindings"
        case promptPackRefs = "prompt_pack_refs"
        case bootstrapReady = "bootstrap_ready"
        case issues
        case auditRef = "audit_ref"
    }
}

struct ProjectIntakeWorkflowResult: Codable, Equatable {
    let extractorEvidence: ProjectIntakeExtractionEvidence
    let manifest: ProjectIntakeManifest
    let freezeGate: ProjectIntakeFreezeGate
    let bootstrapBinding: ProjectBootstrapBinding
    let status: String
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case extractorEvidence = "extractor_evidence"
        case manifest
        case freezeGate = "freeze_gate"
        case bootstrapBinding = "bootstrap_binding"
        case status
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

enum AcceptanceGateStatus: String, Codable, Equatable {
    case pass = "PASS"
    case candidatePass = "candidate_pass"
    case pending
    case fail = "FAIL"
    case blocked = "BLOCKED"
    case unknown

    init(token: String) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .uppercased()
        switch normalized {
        case "PASS": self = .pass
        case "CANDIDATE_PASS": self = .candidatePass
        case "PENDING": self = .pending
        case "FAIL", "FAILED": self = .fail
        case "BLOCKED": self = .blocked
        default: self = .unknown
        }
    }
}

struct AcceptanceGateReading: Codable, Equatable, Identifiable {
    let gateID: String
    let status: AcceptanceGateStatus

    var id: String { gateID }

    init(gateID: String, status: AcceptanceGateStatus) {
        self.gateID = gateID
        self.status = status
    }

    init?(token: String) {
        let pieces = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return nil }
        let gateID = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gateID.isEmpty else { return nil }
        self.init(gateID: gateID, status: AcceptanceGateStatus(token: pieces[1]))
    }

    enum CodingKeys: String, CodingKey {
        case gateID = "gate_id"
        case status
    }
}

enum AcceptanceRiskSeverity: String, Codable, Equatable {
    case low
    case medium
    case high
    case critical

    init(token: String) {
        let normalized = normalizedFieldKey(token)
        switch normalized {
        case "critical": self = .critical
        case "high": self = .high
        case "medium", "med": self = .medium
        default: self = .low
        }
    }
}

struct AcceptanceRisk: Codable, Equatable, Identifiable {
    let riskID: String
    let severity: AcceptanceRiskSeverity
    let mitigation: String

    var id: String { riskID }

    enum CodingKeys: String, CodingKey {
        case riskID = "risk_id"
        case severity
        case mitigation
    }
}

struct AcceptanceRollbackPoint: Codable, Equatable, Identifiable {
    let component: String
    let rollbackRef: String

    var id: String { "\(component):\(rollbackRef)" }

    enum CodingKeys: String, CodingKey {
        case component
        case rollbackRef = "rollback_ref"
    }
}

enum AcceptanceDeliveryStatus: String, Codable, Equatable {
    case candidate
    case accepted
    case rejected
    case insufficientEvidence = "insufficient_evidence"
}

struct AcceptancePack: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let deliveryStatus: AcceptanceDeliveryStatus
    let completedTasks: [String]
    let gateVector: String
    let riskSummary: [AcceptanceRisk]
    let rollbackPoints: [AcceptanceRollbackPoint]
    let evidenceRefs: [String]
    let userSummaryRef: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case deliveryStatus = "delivery_status"
        case completedTasks = "completed_tasks"
        case gateVector = "gate_vector"
        case riskSummary = "risk_summary"
        case rollbackPoints = "rollback_points"
        case evidenceRefs = "evidence_refs"
        case userSummaryRef = "user_summary_ref"
        case auditRef = "audit_ref"
    }
}

enum AcceptanceValidationIssueSeverity: String, Codable, Equatable {
    case warning
    case blocking
}

struct AcceptanceValidationIssue: Codable, Equatable, Identifiable {
    let code: String
    let message: String
    let severity: AcceptanceValidationIssueSeverity

    var id: String { "\(severity.rawValue):\(code):\(message)" }
}

struct AcceptanceValidationReport: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let pass: Bool
    let completenessRatio: Double
    let issues: [AcceptanceValidationIssue]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case pass
        case completenessRatio = "completeness_ratio"
        case issues
        case auditRef = "audit_ref"
    }
}

struct AcceptanceAggregationInput: Codable, Equatable {
    let projectID: String
    let completedTasks: [String]
    let gateReadings: [AcceptanceGateReading]
    let riskSummary: [AcceptanceRisk]
    let rollbackPoints: [AcceptanceRollbackPoint]
    let evidenceRefs: [String]
    let userSummaryRef: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case completedTasks = "completed_tasks"
        case gateReadings = "gate_readings"
        case riskSummary = "risk_summary"
        case rollbackPoints = "rollback_points"
        case evidenceRefs = "evidence_refs"
        case userSummaryRef = "user_summary_ref"
        case auditRef = "audit_ref"
    }
}

struct AcceptanceAggregationEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let completedTasks: [String]
    let gateVector: String
    let riskCount: Int
    let rollbackPointCount: Int
    let evidenceRefCount: Int
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case completedTasks = "completed_tasks"
        case gateVector = "gate_vector"
        case riskCount = "risk_count"
        case rollbackPointCount = "rollback_point_count"
        case evidenceRefCount = "evidence_ref_count"
        case auditRef = "audit_ref"
    }
}

struct AcceptanceDeliveryPackage: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let userSummaryRef: String
    let userSummary: String
    let nextStepSuggestion: String
    let notificationAttempt: DeliveryNotificationAttempt
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case userSummaryRef = "user_summary_ref"
        case userSummary = "user_summary"
        case nextStepSuggestion = "next_step_suggestion"
        case notificationAttempt = "notification_attempt"
        case auditRef = "audit_ref"
    }
}

struct AcceptanceWorkflowResult: Codable, Equatable {
    let aggregationEvidence: AcceptanceAggregationEvidence
    let acceptancePack: AcceptancePack
    let validationReport: AcceptanceValidationReport
    let deliveryPackage: AcceptanceDeliveryPackage
    let status: String
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case aggregationEvidence = "aggregation_evidence"
        case acceptancePack = "acceptance_pack"
        case validationReport = "validation_report"
        case deliveryPackage = "delivery_package"
        case status
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

private struct ProjectIntakeExtractionResult {
    let projectGoal: String
    let inScope: [String]
    let outOfScope: [String]
    let constraints: [String]
    let acceptanceTargets: [String]
    let touchPolicy: DeliveryParticipationMode?
    let innovationLevel: SupervisorInnovationLevel?
    let suggestionGovernance: SupervisorSuggestionGovernance?
    let riskLevel: SupervisorRiskLevel?
    let requiresUserAuthorization: Bool?
    let acceptanceMode: SupervisorAcceptanceMode?
    let budgetTier: SupervisorBudgetTier?
    let paidAIAllowed: Bool?
    let issues: [ProjectIntakeIssue]
    let requiredFieldsPresent: [String]
    let missingRequiredFields: [String]
    let requiredFieldCoverage: Double
}

final class ProjectIntakeExtractor {
    private let requiredFields = [
        "project_goal",
        "in_scope",
        "out_of_scope",
        "constraints",
        "acceptance_targets",
        "touch_policy",
        "risk_level",
        "requires_user_authorization",
        "acceptance_mode"
    ]

    func extract(projectID: String, documents: [SupervisorIntakeSourceDocument], auditRef: String) -> ProjectIntakeExtractionEvidence {
        let result = extractResult(documents: documents)
        return ProjectIntakeExtractionEvidence(
            schemaVersion: "xt.project_intake_extractor_evidence.v1",
            projectID: projectID,
            sourceBundleRefs: documents.map(\.ref),
            projectGoal: result.projectGoal,
            inScope: result.inScope,
            outOfScope: result.outOfScope,
            constraints: result.constraints,
            acceptanceTargets: result.acceptanceTargets,
            touchPolicy: result.touchPolicy?.rawValue,
            innovationLevel: result.innovationLevel?.rawValue,
            suggestionGovernance: result.suggestionGovernance?.rawValue,
            riskLevel: result.riskLevel?.rawValue,
            requiresUserAuthorization: result.requiresUserAuthorization,
            acceptanceMode: result.acceptanceMode?.rawValue,
            budgetTier: result.budgetTier?.rawValue,
            paidAIAllowed: result.paidAIAllowed,
            requiredFieldsPresent: result.requiredFieldsPresent,
            missingRequiredFields: result.missingRequiredFields,
            issues: result.issues,
            requiredFieldCoverage: result.requiredFieldCoverage,
            auditRef: auditRef
        )
    }

    private func extractResult(documents: [SupervisorIntakeSourceDocument]) -> ProjectIntakeExtractionResult {
        let parsedDocuments = documents.map(ParsedIntakeDocument.init)

        let goalResult = resolveScalar(
            documents: parsedDocuments,
            aliases: ["project_goal", "goal", "objective", "target", "目标", "项目目标"],
            field: "project_goal"
        )
        let inScope = resolveList(
            documents: parsedDocuments,
            aliases: ["in_scope", "scope", "included_scope", "范围", "在范围内", "scope_in"]
        )
        let outOfScope = resolveList(
            documents: parsedDocuments,
            aliases: ["out_of_scope", "excluded_scope", "non_goals", "不在范围", "out scope", "scope_out"]
        )
        let constraints = resolveList(
            documents: parsedDocuments,
            aliases: ["constraints", "constraint", "red_lines", "redline", "约束", "红线"]
        )
        let acceptanceTargets = resolveList(
            documents: parsedDocuments,
            aliases: ["acceptance_targets", "acceptance", "验收", "验收目标", "definition_of_done"]
        )
        let touchPolicyResult = resolveScalar(
            documents: parsedDocuments,
            aliases: ["touch_policy", "participation_mode", "user_participation", "介入等级", "用户介入等级"],
            field: "touch_policy"
        )
        let innovationLevelResult = resolveScalar(
            documents: parsedDocuments,
            aliases: ["innovation_level", "innovation", "创新等级"],
            field: "innovation_level"
        )
        let suggestionGovernanceResult = resolveScalar(
            documents: parsedDocuments,
            aliases: ["suggestion_governance", "governance", "建议治理"],
            field: "suggestion_governance"
        )
        let riskLevelResult = resolveScalar(
            documents: parsedDocuments,
            aliases: ["risk_level", "risk", "风险", "风险等级"],
            field: "risk_level"
        )
        let authorizationResult = resolveScalar(
            documents: parsedDocuments,
            aliases: ["requires_user_authorization", "user_authorization", "authorization", "授权", "需要用户授权"],
            field: "requires_user_authorization"
        )
        let acceptanceModeResult = resolveScalar(
            documents: parsedDocuments,
            aliases: ["acceptance_mode", "delivery_mode", "验收模式"],
            field: "acceptance_mode"
        )
        let budgetTierResult = resolveScalar(
            documents: parsedDocuments,
            aliases: ["token_budget_tier", "budget_tier", "token_budget", "预算档位"],
            field: "token_budget_tier"
        )
        let paidAIResult = resolveScalar(
            documents: parsedDocuments,
            aliases: ["paid_ai_allowed", "allow_paid_ai", "paid_ai", "允许付费模型"],
            field: "paid_ai_allowed"
        )

        let touchPolicy = touchPolicyResult.value.map(DeliveryParticipationMode.init(policyToken:))
        let innovationLevel = innovationLevelResult.value.flatMap(SupervisorInnovationLevel.init(token:))
        let suggestionGovernance = suggestionGovernanceResult.value.flatMap(SupervisorSuggestionGovernance.init(token:))
        let riskLevel = riskLevelResult.value.flatMap(SupervisorRiskLevel.init(token:)) ?? inferRiskLevel(from: constraints + acceptanceTargets)
        let requiresUserAuthorization = authorizationResult.value.flatMap(parseBool)
        let acceptanceMode = acceptanceModeResult.value.flatMap(SupervisorAcceptanceMode.init(token:))
        let budgetTier = budgetTierResult.value.flatMap(SupervisorBudgetTier.init(token:))
        let paidAIAllowed = paidAIResult.value.flatMap(parseBool)

        var issues = goalResult.issues
        issues.append(contentsOf: touchPolicyResult.issues)
        issues.append(contentsOf: innovationLevelResult.issues)
        issues.append(contentsOf: suggestionGovernanceResult.issues)
        issues.append(contentsOf: riskLevelResult.issues)
        issues.append(contentsOf: authorizationResult.issues)
        issues.append(contentsOf: acceptanceModeResult.issues)
        issues.append(contentsOf: budgetTierResult.issues)
        issues.append(contentsOf: paidAIResult.issues)

        let scopeOverlap = Set(inScope).intersection(Set(outOfScope)).sorted()
        if !scopeOverlap.isEmpty {
            issues.append(
                ProjectIntakeIssue(
                    code: "scope_conflict_overlap",
                    field: "scope",
                    detail: scopeOverlap.joined(separator: ","),
                    blocking: true
                )
            )
        }

        let presentFieldMap: [String: Bool] = [
            "project_goal": !goalResult.value.orEmpty.isEmpty,
            "in_scope": !inScope.isEmpty,
            "out_of_scope": !outOfScope.isEmpty,
            "constraints": !constraints.isEmpty,
            "acceptance_targets": !acceptanceTargets.isEmpty,
            "touch_policy": touchPolicy != nil,
            "risk_level": riskLevel != nil,
            "requires_user_authorization": requiresUserAuthorization != nil,
            "acceptance_mode": acceptanceMode != nil
        ]

        let requiredFieldsPresent = requiredFields.filter { presentFieldMap[$0] == true }
        let missingRequiredFields = requiredFields.filter { presentFieldMap[$0] != true }
        let requiredFieldCoverage = requiredFields.isEmpty
            ? 1.0
            : Double(requiredFieldsPresent.count) / Double(requiredFields.count)

        return ProjectIntakeExtractionResult(
            projectGoal: goalResult.value.orEmpty,
            inScope: inScope,
            outOfScope: outOfScope,
            constraints: constraints,
            acceptanceTargets: acceptanceTargets,
            touchPolicy: touchPolicy,
            innovationLevel: innovationLevel,
            suggestionGovernance: suggestionGovernance,
            riskLevel: riskLevel,
            requiresUserAuthorization: requiresUserAuthorization,
            acceptanceMode: acceptanceMode,
            budgetTier: budgetTier,
            paidAIAllowed: paidAIAllowed,
            issues: orderedUniqueIssues(issues),
            requiredFieldsPresent: requiredFieldsPresent,
            missingRequiredFields: missingRequiredFields,
            requiredFieldCoverage: requiredFieldCoverage
        )
    }

    private func inferRiskLevel(from entries: [String]) -> SupervisorRiskLevel? {
        let joined = entries.joined(separator: " ").lowercased()
        if joined.contains("production") || joined.contains("security") || joined.contains("deploy") || joined.contains("grant") {
            return .high
        }
        if joined.contains("release candidate") || joined.contains("migration") || joined.contains("rollback") {
            return .medium
        }
        return nil
    }
}

final class IntakeConflictArbiter {
    func freezeGate(
        projectID: String,
        extraction: ProjectIntakeExtractionEvidence,
        manifestRef: String
    ) -> ProjectIntakeFreezeGate {
        let scopeConflictDetected = extraction.issues.contains { $0.code == "scope_conflict_overlap" }
        let requiredFieldsComplete = extraction.missingRequiredFields.isEmpty
        let authorizationBoundaryClear: Bool = {
            guard let requiresAuth = extraction.requiresUserAuthorization else { return false }
            if extraction.riskLevel == SupervisorRiskLevel.high.rawValue {
                return requiresAuth == true || requiresAuth == false
            }
            return true
        }()

        let decision: ProjectIntakeFreezeDecision
        let denyCode: String
        if !requiredFieldsComplete {
            decision = .failClosed
            denyCode = "intake_missing_required_field"
        } else if scopeConflictDetected {
            decision = .failClosed
            denyCode = "scope_conflict"
        } else if !authorizationBoundaryClear {
            decision = .failClosed
            denyCode = "authorization_boundary_unclear"
        } else {
            decision = .pass
            denyCode = "none"
        }

        return ProjectIntakeFreezeGate(
            schemaVersion: "xt.intake_freeze_gate.v1",
            projectID: projectID,
            intakeManifestRef: manifestRef,
            requiredFieldsComplete: requiredFieldsComplete,
            scopeConflictDetected: scopeConflictDetected,
            authorizationBoundaryClear: authorizationBoundaryClear,
            decision: decision,
            denyCode: denyCode
        )
    }
}

final class ProjectIntakeManifestBuilder {
    func build(
        extraction: ProjectIntakeExtractionEvidence,
        projectID: String,
        splitProposal: SplitProposal?,
        auditRef: String
    ) -> ProjectIntakeManifest {
        let poolPlan = buildPoolPlan(goal: extraction.projectGoal, proposal: splitProposal)
        return ProjectIntakeManifest(
            schemaVersion: "xt.project_intake_manifest.v1",
            projectID: projectID,
            sourceBundleRefs: extraction.sourceBundleRefs,
            projectGoal: extraction.projectGoal,
            inScope: extraction.inScope,
            outOfScope: extraction.outOfScope,
            constraints: extraction.constraints,
            touchPolicy: DeliveryParticipationMode(policyToken: extraction.touchPolicy ?? DeliveryParticipationMode.guidedTouch.rawValue),
            innovationLevel: SupervisorInnovationLevel(token: extraction.innovationLevel ?? SupervisorInnovationLevel.l1.rawValue) ?? .l1,
            suggestionGovernance: SupervisorSuggestionGovernance(token: extraction.suggestionGovernance ?? SupervisorSuggestionGovernance.hybrid.rawValue) ?? .hybrid,
            riskLevel: SupervisorRiskLevel(token: extraction.riskLevel ?? SupervisorRiskLevel.medium.rawValue) ?? .medium,
            requiresUserAuthorization: extraction.requiresUserAuthorization ?? true,
            acceptanceMode: SupervisorAcceptanceMode(token: extraction.acceptanceMode ?? SupervisorAcceptanceMode.internalBeta.rawValue) ?? .internalBeta,
            budgetPolicy: ProjectIntakeBudgetPolicy(
                tokenBudgetTier: SupervisorBudgetTier(token: extraction.budgetTier ?? SupervisorBudgetTier.balanced.rawValue) ?? .balanced,
                paidAIAllowed: extraction.paidAIAllowed ?? false
            ),
            poolPlan: poolPlan,
            acceptanceTargets: extraction.acceptanceTargets,
            auditRef: auditRef
        )
    }

    private func buildPoolPlan(goal: String, proposal: SplitProposal?) -> [ProjectIntakePoolPlanEntry] {
        guard let proposal else {
            return [
                ProjectIntakePoolPlanEntry(
                    poolID: "supervisor-main",
                    poolGoal: goal,
                    recommendedLaneCount: 1,
                    laneSplitReason: "intake_bootstrap_placeholder_until_split_plan_ready"
                )
            ]
        }

        let isolatedCount = proposal.lanes.filter(\ .createChildProject).count
        let sharedCount = proposal.lanes.count - isolatedCount
        var entries: [ProjectIntakePoolPlanEntry] = []

        if sharedCount > 0 {
            entries.append(
                ProjectIntakePoolPlanEntry(
                    poolID: "supervisor-main",
                    poolGoal: goal,
                    recommendedLaneCount: sharedCount,
                    laneSplitReason: sharedCount == proposal.lanes.count
                        ? "single_pool_shared_execution_plan"
                        : "shared_scope_lanes_remain_in_primary_pool"
                )
            )
        }

        if isolatedCount > 0 {
            entries.append(
                ProjectIntakePoolPlanEntry(
                    poolID: "isolated-side-effects",
                    poolGoal: "Isolate high-risk or side-effecting lanes",
                    recommendedLaneCount: isolatedCount,
                    laneSplitReason: "child_project_lanes_require_isolated_workspace"
                )
            )
        }

        return entries.isEmpty
            ? [
                ProjectIntakePoolPlanEntry(
                    poolID: "supervisor-main",
                    poolGoal: goal,
                    recommendedLaneCount: 1,
                    laneSplitReason: "fallback_single_pool"
                )
            ]
            : entries
    }
}

@MainActor
final class ProjectBootstrapBinder {
    private let promptFactory = PromptFactory()

    func bind(
        manifest: ProjectIntakeManifest,
        freezeGate: ProjectIntakeFreezeGate,
        splitProposal: SplitProposal?,
        auditRef: String
    ) -> ProjectBootstrapBinding {
        var issues: [ProjectIntakeIssue] = []

        guard freezeGate.decision == .pass else {
            issues.append(
                ProjectIntakeIssue(
                    code: "intake_freeze_gate_blocked",
                    field: "freeze_gate",
                    detail: freezeGate.denyCode,
                    blocking: true
                )
            )
            return ProjectBootstrapBinding(
                schemaVersion: "xt.project_bootstrap_binding.v1",
                projectID: manifest.projectID,
                intakeManifestRef: "build/reports/xt_w3_21_project_intake_manifest.v1.json",
                touchPolicy: manifest.touchPolicy,
                poolPlan: manifest.poolPlan,
                laneBindings: [],
                promptPackRefs: [],
                bootstrapReady: false,
                issues: issues,
                auditRef: auditRef
            )
        }

        guard let splitProposal else {
            issues.append(
                ProjectIntakeIssue(
                    code: "lane_plan_missing",
                    field: "split_proposal",
                    detail: "pool/lane bootstrap requires split proposal",
                    blocking: true
                )
            )
            return ProjectBootstrapBinding(
                schemaVersion: "xt.project_bootstrap_binding.v1",
                projectID: manifest.projectID,
                intakeManifestRef: "build/reports/xt_w3_21_project_intake_manifest.v1.json",
                touchPolicy: manifest.touchPolicy,
                poolPlan: manifest.poolPlan,
                laneBindings: [],
                promptPackRefs: [],
                bootstrapReady: false,
                issues: issues,
                auditRef: auditRef
            )
        }

        let compilation = promptFactory.compileContracts(for: splitProposal, globalContext: manifest.projectGoal)
        if compilation.status == .rejected {
            issues.append(
                ProjectIntakeIssue(
                    code: "prompt_pack_rejected",
                    field: "prompt_pack_refs",
                    detail: compilation.lintResult.issues.map(\ .code).joined(separator: ","),
                    blocking: true
                )
            )
        }

        let promptRefByLaneID = Dictionary(uniqueKeysWithValues: splitProposal.lanes.map {
            ($0.laneId, "prompt://split-plan/\(splitProposal.splitPlanId.uuidString.lowercased())/lane/\($0.laneId)")
        })
        let laneBindings = splitProposal.lanes.map { lane in
            ProjectBootstrapLaneBinding(
                laneID: lane.laneId,
                goal: lane.goal,
                dependsOn: lane.dependsOn,
                lanePlanRef: "lane://split-plan/\(splitProposal.splitPlanId.uuidString.lowercased())/lane/\(lane.laneId)",
                promptPackRef: promptRefByLaneID[lane.laneId] ?? "prompt://missing/\(lane.laneId)"
            )
        }
        let promptPackRefs = orderedUnique(laneBindings.map(\ .promptPackRef))

        return ProjectBootstrapBinding(
            schemaVersion: "xt.project_bootstrap_binding.v1",
            projectID: manifest.projectID,
            intakeManifestRef: "build/reports/xt_w3_21_project_intake_manifest.v1.json",
            touchPolicy: manifest.touchPolicy,
            poolPlan: manifest.poolPlan,
            laneBindings: laneBindings,
            promptPackRefs: promptPackRefs,
            bootstrapReady: issues.filter(\ .blocking).isEmpty,
            issues: issues,
            auditRef: auditRef
        )
    }
}

final class AcceptanceEvidenceAggregator {
    func aggregate(_ input: AcceptanceAggregationInput) -> (AcceptanceAggregationEvidence, AcceptancePack) {
        let gateVector = input.gateReadings
            .map { "\($0.gateID):\($0.status.rawValue)" }
            .joined(separator: ",")
        let evidence = AcceptanceAggregationEvidence(
            schemaVersion: "xt.acceptance_aggregation_evidence.v1",
            projectID: input.projectID,
            completedTasks: orderedUnique(input.completedTasks),
            gateVector: gateVector,
            riskCount: input.riskSummary.count,
            rollbackPointCount: input.rollbackPoints.count,
            evidenceRefCount: input.evidenceRefs.count,
            auditRef: input.auditRef
        )
        let pack = AcceptancePack(
            schemaVersion: "xt.acceptance_pack.v1",
            projectID: input.projectID,
            deliveryStatus: .candidate,
            completedTasks: orderedUnique(input.completedTasks),
            gateVector: gateVector,
            riskSummary: input.riskSummary,
            rollbackPoints: input.rollbackPoints,
            evidenceRefs: orderedUnique(input.evidenceRefs),
            userSummaryRef: input.userSummaryRef,
            auditRef: input.auditRef
        )
        return (evidence, pack)
    }
}

final class AcceptanceLinkValidator {
    func validate(_ pack: AcceptancePack) -> AcceptanceValidationReport {
        var issues: [AcceptanceValidationIssue] = []
        let completenessChecks: [Bool] = [
            !pack.completedTasks.isEmpty,
            !pack.gateVector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !pack.evidenceRefs.isEmpty && pack.evidenceRefs.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            !pack.rollbackPoints.isEmpty && pack.rollbackPoints.allSatisfy { !$0.rollbackRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            !pack.userSummaryRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ]

        if pack.completedTasks.isEmpty {
            issues.append(
                AcceptanceValidationIssue(
                    code: "missing_completed_tasks",
                    message: "Acceptance pack requires completed task refs.",
                    severity: .blocking
                )
            )
        }
        if pack.gateVector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                AcceptanceValidationIssue(
                    code: "missing_gate_vector",
                    message: "Acceptance pack requires a gate vector.",
                    severity: .blocking
                )
            )
        }
        if pack.evidenceRefs.isEmpty {
            issues.append(
                AcceptanceValidationIssue(
                    code: "missing_evidence_refs",
                    message: "Acceptance pack requires evidence refs.",
                    severity: .blocking
                )
            )
        }
        if pack.rollbackPoints.isEmpty {
            issues.append(
                AcceptanceValidationIssue(
                    code: "missing_rollback_points",
                    message: "Acceptance pack requires rollback points.",
                    severity: .blocking
                )
            )
        }
        if pack.userSummaryRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                AcceptanceValidationIssue(
                    code: "missing_user_summary_ref",
                    message: "Acceptance pack requires a user summary ref.",
                    severity: .blocking
                )
            )
        }

        let completenessRatio = Double(completenessChecks.filter { $0 }.count) / Double(completenessChecks.count)
        return AcceptanceValidationReport(
            schemaVersion: "xt.acceptance_validation_report.v1",
            projectID: pack.projectID,
            pass: !issues.contains { $0.severity == .blocking },
            completenessRatio: completenessRatio,
            issues: issues,
            auditRef: pack.auditRef
        )
    }
}

final class AcceptanceDecisionCompiler {
    func compile(pack: AcceptancePack, validation: AcceptanceValidationReport) -> AcceptancePack {
        let gateStatuses = pack.gateVector
            .split(separator: ",")
            .compactMap { AcceptanceGateReading(token: String($0)) }
            .map(\ .status)
        let deliveryStatus: AcceptanceDeliveryStatus
        if validation.pass == false {
            deliveryStatus = .insufficientEvidence
        } else if gateStatuses.contains(.fail) || gateStatuses.contains(.blocked) {
            deliveryStatus = .rejected
        } else if !gateStatuses.isEmpty && gateStatuses.allSatisfy({ $0 == .pass }) {
            deliveryStatus = .accepted
        } else {
            deliveryStatus = .candidate
        }

        return AcceptancePack(
            schemaVersion: pack.schemaVersion,
            projectID: pack.projectID,
            deliveryStatus: deliveryStatus,
            completedTasks: pack.completedTasks,
            gateVector: pack.gateVector,
            riskSummary: pack.riskSummary,
            rollbackPoints: pack.rollbackPoints,
            evidenceRefs: pack.evidenceRefs,
            userSummaryRef: pack.userSummaryRef,
            auditRef: pack.auditRef
        )
    }
}

final class DeliveryPackageEmitter {
    private let notifier = DeliveryNotifier()

    func emit(pack: AcceptancePack, participationMode: DeliveryParticipationMode, now: Date = Date()) -> AcceptanceDeliveryPackage {
        let statusLine = "delivery_status=\(pack.deliveryStatus.rawValue)"
        let taskLine = "completed_tasks=\(pack.completedTasks.joined(separator: ", "))"
        let gateLine = "gate_vector=\(pack.gateVector)"
        let riskLine = pack.riskSummary.isEmpty
            ? "risk_summary=none"
            : "risk_summary=\(pack.riskSummary.map { "\($0.severity.rawValue):\($0.mitigation)" }.joined(separator: " | "))"
        let rollbackLine = pack.rollbackPoints.isEmpty
            ? "rollback_points=none"
            : "rollback_points=\(pack.rollbackPoints.map { "\($0.component)->\($0.rollbackRef)" }.joined(separator: " | "))"
        let evidenceLine = pack.evidenceRefs.isEmpty
            ? "evidence_refs=none"
            : "evidence_refs=\(pack.evidenceRefs.joined(separator: " | "))"

        let nextStepSuggestion: String = {
            switch pack.deliveryStatus {
            case .accepted:
                return "promote delivery summary to user-visible closure and archive rollback anchors"
            case .candidate:
                return "hold at candidate and finish remaining gate promotion before user closure"
            case .rejected:
                return "rollback to latest stable anchor and reopen missing gates"
            case .insufficientEvidence:
                return "collect missing evidence refs and rollback anchors before retry"
            }
        }()

        let payload = DeliveryNotificationPayload(
            taskID: pack.projectID,
            eventKind: .completion,
            deliverySummary: [statusLine, taskLine, gateLine].joined(separator: "\n"),
            riskSummary: pack.riskSummary.map { "\($0.severity.rawValue): \($0.mitigation)" },
            evidenceRefs: pack.evidenceRefs,
            rollbackPoint: pack.rollbackPoints.first?.rollbackRef ?? "",
            nextStepSuggestion: nextStepSuggestion
        )
        let attempt = notifier.prepareNotification(mode: participationMode, payload: payload, now: now)

        let summary = [
            statusLine,
            taskLine,
            gateLine,
            riskLine,
            rollbackLine,
            evidenceLine,
            "next_step=\(nextStepSuggestion)"
        ].joined(separator: "\n")

        return AcceptanceDeliveryPackage(
            schemaVersion: "xt.delivery_package_emitter.v1",
            projectID: pack.projectID,
            userSummaryRef: pack.userSummaryRef,
            userSummary: summary,
            nextStepSuggestion: nextStepSuggestion,
            notificationAttempt: attempt,
            auditRef: pack.auditRef
        )
    }
}

@MainActor
final class SupervisorIntakeAcceptanceEngine {
    private let extractor = ProjectIntakeExtractor()
    private let arbiter = IntakeConflictArbiter()
    private let manifestBuilder = ProjectIntakeManifestBuilder()
    private let bootstrapBinder = ProjectBootstrapBinder()
    private let aggregator = AcceptanceEvidenceAggregator()
    private let validator = AcceptanceLinkValidator()
    private let compiler = AcceptanceDecisionCompiler()
    private let emitter = DeliveryPackageEmitter()

    func buildProjectIntakeWorkflow(
        projectID: UUID = UUID(),
        documents: [SupervisorIntakeSourceDocument],
        splitProposal: SplitProposal?,
        now: Date = Date()
    ) -> ProjectIntakeWorkflowResult {
        let projectToken = projectID.uuidString.lowercased()
        let auditRef = makeAuditRef(prefix: "audit-intake", projectID: projectToken, now: now)
        let extraction = extractor.extract(projectID: projectToken, documents: documents, auditRef: auditRef)
        let manifest = manifestBuilder.build(extraction: extraction, projectID: projectToken, splitProposal: splitProposal, auditRef: auditRef)
        let freezeGate = arbiter.freezeGate(
            projectID: projectToken,
            extraction: extraction,
            manifestRef: "build/reports/xt_w3_21_project_intake_manifest.v1.json"
        )
        let bootstrap = bootstrapBinder.bind(
            manifest: manifest,
            freezeGate: freezeGate,
            splitProposal: splitProposal,
            auditRef: auditRef
        )
        let minimalGaps = orderedUnique(
            extraction.missingRequiredFields
                + extraction.issues.filter(\ .blocking).map(\ .code)
                + bootstrap.issues.filter(\ .blocking).map(\ .code)
        )
        let status: String = {
            if freezeGate.decision == .pass && bootstrap.bootstrapReady {
                return "intake_frozen_and_bootstrap_ready"
            }
            return "fail_closed_needs_user_decision"
        }()

        return ProjectIntakeWorkflowResult(
            extractorEvidence: extraction,
            manifest: manifest,
            freezeGate: freezeGate,
            bootstrapBinding: bootstrap,
            status: status,
            minimalGaps: minimalGaps,
            auditRef: auditRef
        )
    }

    func buildAcceptanceWorkflow(
        input: AcceptanceAggregationInput,
        participationMode: DeliveryParticipationMode,
        now: Date = Date()
    ) -> AcceptanceWorkflowResult {
        let (aggregationEvidence, draftPack) = aggregator.aggregate(input)
        let validation = validator.validate(draftPack)
        let compiledPack = compiler.compile(pack: draftPack, validation: validation)
        let deliveryPackage = emitter.emit(pack: compiledPack, participationMode: participationMode, now: now)
        let minimalGaps = validation.issues
            .filter { $0.severity == .blocking }
            .map(\ .code)
        let status = "acceptance_\(compiledPack.deliveryStatus.rawValue)"

        return AcceptanceWorkflowResult(
            aggregationEvidence: aggregationEvidence,
            acceptancePack: compiledPack,
            validationReport: validation,
            deliveryPackage: deliveryPackage,
            status: status,
            minimalGaps: minimalGaps,
            auditRef: input.auditRef
        )
    }
}

@MainActor
extension SupervisorOrchestrator {
    func buildProjectIntakeWorkflow(
        projectID: UUID = UUID(),
        documents: [SupervisorIntakeSourceDocument],
        splitProposal: SplitProposal? = nil,
        now: Date = Date()
    ) -> ProjectIntakeWorkflowResult {
        SupervisorIntakeAcceptanceEngine().buildProjectIntakeWorkflow(
            projectID: projectID,
            documents: documents,
            splitProposal: splitProposal,
            now: now
        )
    }

    func buildAcceptanceWorkflow(
        input: AcceptanceAggregationInput,
        participationMode: DeliveryParticipationMode,
        now: Date = Date()
    ) -> AcceptanceWorkflowResult {
        SupervisorIntakeAcceptanceEngine().buildAcceptanceWorkflow(
            input: input,
            participationMode: participationMode,
            now: now
        )
    }
}

private struct ParsedIntakeDocument {
    let ref: String
    let scalarFields: [String: [String]]
    let listFields: [String: [String]]

    init(document: SupervisorIntakeSourceDocument) {
        ref = document.ref
        var scalars: [String: [String]] = [:]
        var lists: [String: [String]] = [:]

        for line in document.contents.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            if let pair = parseKeyValueLine(trimmedLine) {
                let key = normalizedFieldKey(pair.key)
                let values = parseLooseList(pair.value)
                if values.count <= 1 {
                    scalars[key, default: []].append(pair.value.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                lists[key, default: []].append(contentsOf: values)
            }
        }

        let sections = parseMarkdownSections(document.contents)
        for (key, values) in sections {
            if values.count == 1 && !values[0].contains(",") {
                scalars[key, default: []].append(values[0])
            }
            lists[key, default: []].append(contentsOf: values)
        }

        scalarFields = scalars.mapValues(orderedUnique)
        listFields = lists.mapValues(orderedUnique)
    }
}

private struct ResolvedScalarResult {
    let value: String?
    let issues: [ProjectIntakeIssue]
}

private func resolveScalar(
    documents: [ParsedIntakeDocument],
    aliases: [String],
    field: String
) -> ResolvedScalarResult {
    let aliasSet = Set(aliases.map(normalizedFieldKey))
    var values: [(String, String)] = []
    for document in documents {
        for (key, entries) in document.scalarFields where aliasSet.contains(key) {
            values.append(contentsOf: entries.map { (document.ref, $0) })
        }
        if values.isEmpty {
            for (key, entries) in document.listFields where aliasSet.contains(key) {
                if let first = entries.first {
                    values.append((document.ref, first))
                }
            }
        }
    }
    let normalizedDistinct = orderedUnique(values.map { $0.1 }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    if normalizedDistinct.count > 1 {
        return ResolvedScalarResult(
            value: normalizedDistinct.first,
            issues: [
                ProjectIntakeIssue(
                    code: "scalar_conflict",
                    field: field,
                    detail: normalizedDistinct.joined(separator: " | "),
                    blocking: true
                )
            ]
        )
    }
    return ResolvedScalarResult(value: normalizedDistinct.first, issues: [])
}

private func resolveList(documents: [ParsedIntakeDocument], aliases: [String]) -> [String] {
    let aliasSet = Set(aliases.map(normalizedFieldKey))
    var values: [String] = []
    for document in documents {
        for (key, entries) in document.listFields where aliasSet.contains(key) {
            values.append(contentsOf: entries)
        }
    }
    return orderedUnique(values)
}

private func parseMarkdownSections(_ text: String) -> [String: [String]] {
    var result: [String: [String]] = [:]
    var currentSection: String?

    for line in text.components(separatedBy: .newlines) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLine.hasPrefix("#") {
            let heading = trimmedLine.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            currentSection = normalizedFieldKey(heading)
            continue
        }

        guard let currentSection, !trimmedLine.isEmpty else { continue }
        if isMarkdownListLine(trimmedLine) {
            result[currentSection, default: []].append(stripMarkdownListPrefix(trimmedLine))
        } else if result[currentSection, default: []].isEmpty {
            result[currentSection, default: []].append(trimmedLine)
        }
    }

    return result.mapValues(orderedUnique)
}

private func parseKeyValueLine(_ line: String) -> (key: String, value: String)? {
    guard let range = line.range(of: ":") else { return nil }
    let rawKey = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    let rawValue = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawKey.isEmpty, !rawValue.isEmpty else { return nil }
    let key = rawKey.hasPrefix("-") ? String(rawKey.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) : rawKey
    return (key, rawValue)
}

private func parseLooseList(_ raw: String) -> [String] {
    let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    let normalized = trimmed.replacingOccurrences(of: "\"", with: "")
    let separators = CharacterSet(charactersIn: ",|")
    return orderedUnique(
        normalized
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    )
}

private func parseBool(_ raw: String) -> Bool? {
    switch normalizedFieldKey(raw) {
    case "true", "yes", "y", "1": return true
    case "false", "no", "n", "0": return false
    default: return nil
    }
}

private func isMarkdownListLine(_ line: String) -> Bool {
    guard let first = line.first else { return false }
    if first == "-" || first == "*" { return true }
    return line.range(of: #"^\d+[\.)]\s+"#, options: .regularExpression) != nil
}

private func stripMarkdownListPrefix(_ line: String) -> String {
    if let range = line.range(of: #"^(-|\*|\d+[\.)])\s+"#, options: .regularExpression) {
        return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedFieldKey(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "/", with: "_")
}

private func orderedUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        if seen.insert(trimmed).inserted {
            ordered.append(trimmed)
        }
    }
    return ordered
}

private func orderedUniqueIssues(_ values: [ProjectIntakeIssue]) -> [ProjectIntakeIssue] {
    var seen: Set<String> = []
    var ordered: [ProjectIntakeIssue] = []
    for value in values {
        if seen.insert(value.id).inserted {
            ordered.append(value)
        }
    }
    return ordered
}

private func makeAuditRef(prefix: String, projectID: String, now: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
    let token = formatter.string(from: now)
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
    return "\(prefix)-\(projectID.prefix(8))-\(token)"
}

private extension Optional where Wrapped == String {
    var orEmpty: String {
        self ?? ""
    }
}
