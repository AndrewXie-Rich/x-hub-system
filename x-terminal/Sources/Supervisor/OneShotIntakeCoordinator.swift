import Foundation

enum OneShotSplitProfile: String, Codable, Equatable, CaseIterable {
    case auto
    case conservative
    case balanced
    case aggressive
}

enum OneShotTokenBudgetClass: String, Codable, Equatable, CaseIterable {
    case tight
    case standard
    case priorityDelivery = "priority_delivery"
}

enum OneShotDeliveryMode: String, Codable, Equatable, CaseIterable {
    case specFirst = "spec_first"
    case implementationFirst = "implementation_first"
    case releaseFirst = "release_first"
}

enum OneShotHumanAuthorizationType: String, Codable, Equatable, CaseIterable {
    case payment
    case externalSideEffect = "external_side_effect"
    case connectorBinding = "connector_binding"
    case secretBinding = "secret_binding"
    case scopeExpansion = "scope_expansion"
}

struct SupervisorOneShotIntakeRequest: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let requestID: String
    let userGoal: String
    let contextRefs: [String]
    let preferredSplitProfile: OneShotSplitProfile
    let participationMode: DeliveryParticipationMode
    let innovationLevel: SupervisorInnovationLevel
    let tokenBudgetClass: OneShotTokenBudgetClass
    let deliveryMode: OneShotDeliveryMode
    let allowAutoLaunch: Bool
    let requiresHumanAuthorizationTypes: [OneShotHumanAuthorizationType]
    let auditRef: String

    static let frozenFieldOrder = [
        "schema_version",
        "project_id",
        "request_id",
        "user_goal",
        "context_refs",
        "preferred_split_profile",
        "participation_mode",
        "innovation_level",
        "token_budget_class",
        "delivery_mode",
        "allow_auto_launch",
        "requires_human_authorization_types",
        "audit_ref"
    ]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case requestID = "request_id"
        case userGoal = "user_goal"
        case contextRefs = "context_refs"
        case preferredSplitProfile = "preferred_split_profile"
        case participationMode = "participation_mode"
        case innovationLevel = "innovation_level"
        case tokenBudgetClass = "token_budget_class"
        case deliveryMode = "delivery_mode"
        case allowAutoLaunch = "allow_auto_launch"
        case requiresHumanAuthorizationTypes = "requires_human_authorization_types"
        case auditRef = "audit_ref"
    }

    var projectUUID: UUID {
        UUID(uuidString: projectID) ?? UUID(uuidString: oneShotDeterministicUUIDString(seed: projectID))!
    }

    var requestUUID: UUID {
        UUID(uuidString: requestID) ?? UUID(uuidString: oneShotDeterministicUUIDString(seed: requestID))!
    }
}

struct OneShotNormalizationIssue: Codable, Equatable, Identifiable {
    let code: String
    let detail: String
    let blocking: Bool

    var id: String { "\(code):\(detail)" }
}

struct OneShotIntakeSubmission: Equatable {
    let projectID: String?
    let requestID: String?
    let userGoal: String
    let documents: [SupervisorIntakeSourceDocument]
    let contextRefs: [String]
    let preferredSplitProfile: OneShotSplitProfile?
    let participationMode: DeliveryParticipationMode?
    let innovationLevel: SupervisorInnovationLevel?
    let tokenBudgetClass: OneShotTokenBudgetClass?
    let deliveryMode: OneShotDeliveryMode?
    let allowAutoLaunch: Bool?
    let requiresHumanAuthorizationTypes: [OneShotHumanAuthorizationType]
    let auditRef: String?
    let now: Date

    init(
        projectID: String? = nil,
        requestID: String? = nil,
        userGoal: String,
        documents: [SupervisorIntakeSourceDocument] = [],
        contextRefs: [String] = [],
        preferredSplitProfile: OneShotSplitProfile? = nil,
        participationMode: DeliveryParticipationMode? = nil,
        innovationLevel: SupervisorInnovationLevel? = nil,
        tokenBudgetClass: OneShotTokenBudgetClass? = nil,
        deliveryMode: OneShotDeliveryMode? = nil,
        allowAutoLaunch: Bool? = nil,
        requiresHumanAuthorizationTypes: [OneShotHumanAuthorizationType] = [],
        auditRef: String? = nil,
        now: Date = Date()
    ) {
        self.projectID = projectID
        self.requestID = requestID
        self.userGoal = userGoal
        self.documents = documents
        self.contextRefs = contextRefs
        self.preferredSplitProfile = preferredSplitProfile
        self.participationMode = participationMode
        self.innovationLevel = innovationLevel
        self.tokenBudgetClass = tokenBudgetClass
        self.deliveryMode = deliveryMode
        self.allowAutoLaunch = allowAutoLaunch
        self.requiresHumanAuthorizationTypes = requiresHumanAuthorizationTypes
        self.auditRef = auditRef
        self.now = now
    }
}

struct OneShotIntakeNormalizationResult: Codable, Equatable {
    let schemaVersion: String
    let request: SupervisorOneShotIntakeRequest
    let issues: [OneShotNormalizationIssue]
    let accepted: Bool
    let freezeDecision: ProjectIntakeFreezeDecision
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case request
        case issues
        case accepted
        case freezeDecision = "freeze_decision"
        case auditRef = "audit_ref"
    }
}

struct XTW326OneShotIntakeEvidence: Codable, Equatable {
    let schemaVersion: String
    let normalization: OneShotIntakeNormalizationResult
    let fieldFreeze: OneShotFieldFreeze
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case normalization
        case fieldFreeze = "field_freeze"
        case sourceRefs = "source_refs"
    }
}

@MainActor
final class OneShotIntakeCoordinator {
    private let intakeEngine = SupervisorIntakeAcceptanceEngine()

    func normalize(_ submission: OneShotIntakeSubmission) -> OneShotIntakeNormalizationResult {
        let normalizedProjectID = submission.projectID.flatMap(normalizeUUIDLike) ?? oneShotDeterministicUUIDString(seed: "project|\(submission.userGoal)|\(submission.contextRefs.joined(separator: "|"))")
        let normalizedRequestID = submission.requestID.flatMap(normalizeUUIDLike) ?? oneShotDeterministicUUIDString(seed: "request|\(normalizedProjectID)|\(submission.userGoal)")
        let documents = resolvedDocuments(for: submission, projectID: normalizedProjectID)
        let workflow = intakeEngine.buildProjectIntakeWorkflow(
            projectID: UUID(uuidString: normalizedProjectID) ?? UUID(uuidString: oneShotDeterministicUUIDString(seed: normalizedProjectID))!,
            documents: documents,
            splitProposal: nil,
            now: submission.now
        )

        var issues = workflow.extractorEvidence.issues.map {
            OneShotNormalizationIssue(code: $0.code, detail: $0.detail, blocking: $0.blocking)
        }

        if workflow.freezeGate.decision == .failClosed {
            issues.append(
                OneShotNormalizationIssue(
                    code: workflow.freezeGate.denyCode,
                    detail: "project intake freeze gate failed closed",
                    blocking: true
                )
            )
        }

        let resolvedGoal = resolvedUserGoal(submission: submission, manifestGoal: workflow.manifest.projectGoal)
        if resolvedGoal == "goal_missing_requires_replan" {
            issues.append(
                OneShotNormalizationIssue(
                    code: "user_goal_missing",
                    detail: "one-shot intake requires a non-empty goal or manifest goal",
                    blocking: true
                )
            )
        }

        let inferredAuthorization = inferAuthorizationTypes(
            explicit: submission.requiresHumanAuthorizationTypes,
            userGoal: resolvedGoal,
            documents: documents,
            workflow: workflow
        )
        let resolvedParticipationMode = submission.participationMode ?? workflow.manifest.touchPolicy
        let resolvedInnovationLevel = submission.innovationLevel ?? workflow.manifest.innovationLevel
        let resolvedBudgetClass = submission.tokenBudgetClass ?? mapBudgetTier(workflow.manifest.budgetPolicy.tokenBudgetTier)
        let resolvedDeliveryMode = submission.deliveryMode ?? mapDeliveryMode(workflow.manifest.acceptanceMode)
        let resolvedProfile = resolvedSplitProfile(
            requested: submission.preferredSplitProfile,
            participationMode: resolvedParticipationMode,
            innovationLevel: resolvedInnovationLevel,
            budgetClass: resolvedBudgetClass,
            authorizationTypes: inferredAuthorization,
            manifestRisk: workflow.manifest.riskLevel
        )

        let requestedAutoLaunch = submission.allowAutoLaunch ?? false
        let blockingIssuesPresent = issues.contains(where: \ .blocking)
        let allowAutoLaunch = requestedAutoLaunch
            && inferredAuthorization.isEmpty
            && !blockingIssuesPresent
            && resolvedParticipationMode != .criticalTouch
            && workflow.freezeGate.decision == .pass

        if requestedAutoLaunch && !allowAutoLaunch {
            issues.append(
                OneShotNormalizationIssue(
                    code: "auto_launch_downgraded_fail_closed",
                    detail: "auto launch requested but blocked by authorization or freeze gate",
                    blocking: false
                )
            )
        }

        let request = SupervisorOneShotIntakeRequest(
            schemaVersion: "xt.supervisor_one_shot_intake_request.v1",
            projectID: normalizedProjectID,
            requestID: normalizedRequestID,
            userGoal: resolvedGoal,
            contextRefs: oneShotOrderedUniqueStrings(submission.contextRefs + documents.map(\ .ref) + workflow.manifest.sourceBundleRefs),
            preferredSplitProfile: resolvedProfile,
            participationMode: resolvedParticipationMode,
            innovationLevel: resolvedInnovationLevel,
            tokenBudgetClass: resolvedBudgetClass,
            deliveryMode: resolvedDeliveryMode,
            allowAutoLaunch: allowAutoLaunch,
            requiresHumanAuthorizationTypes: inferredAuthorization,
            auditRef: submission.auditRef ?? workflow.auditRef
        )

        return OneShotIntakeNormalizationResult(
            schemaVersion: "xt.one_shot_intake_normalization_result.v1",
            request: request,
            issues: issues,
            accepted: !blockingIssuesPresent && workflow.freezeGate.decision == .pass,
            freezeDecision: workflow.freezeGate.decision,
            auditRef: request.auditRef
        )
    }

    private func resolvedDocuments(for submission: OneShotIntakeSubmission, projectID: String) -> [SupervisorIntakeSourceDocument] {
        if !submission.documents.isEmpty {
            return submission.documents
        }

        let riskToken: String = {
            if submission.requiresHumanAuthorizationTypes.contains(.payment) {
                return "high"
            }
            if submission.allowAutoLaunch == true {
                return "medium"
            }
            return "low"
        }()
        let touchPolicy = (submission.participationMode ?? .guidedTouch).rawValue
        let innovationLevel = (submission.innovationLevel ?? .l1).rawValue
        let budgetTier = mapBudgetClassToLegacyTier(submission.tokenBudgetClass ?? .standard)
        let requiresAuthorization = submission.requiresHumanAuthorizationTypes.isEmpty ? "false" : "true"

        return [
            SupervisorIntakeSourceDocument(
                ref: "synthetic://one-shot/\(projectID)",
                kind: .text,
                contents: """
                project_goal: \(submission.userGoal.trimmingCharacters(in: .whitespacesAndNewlines))
                touch_policy: \(touchPolicy)
                innovation_level: \(innovationLevel)
                suggestion_governance: hybrid
                risk_level: \(riskToken)
                requires_user_authorization: \(requiresAuthorization)
                acceptance_mode: release_candidate
                token_budget_tier: \(budgetTier)
                paid_ai_allowed: false

                ## constraints
                - fail closed
                - no lane explosion
                - no cross pool cycle

                ## acceptance_targets
                - normalized_request_ready
                - explain_ready
                - run_state_explicit
                """
            )
        ]
    }

    private func resolvedUserGoal(submission: OneShotIntakeSubmission, manifestGoal: String) -> String {
        let explicitGoal = submission.userGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitGoal.isEmpty {
            return explicitGoal
        }
        let extractedGoal = manifestGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extractedGoal.isEmpty {
            return extractedGoal
        }
        return "goal_missing_requires_replan"
    }

    private func inferAuthorizationTypes(
        explicit: [OneShotHumanAuthorizationType],
        userGoal: String,
        documents: [SupervisorIntakeSourceDocument],
        workflow: ProjectIntakeWorkflowResult
    ) -> [OneShotHumanAuthorizationType] {
        let joined = ([userGoal] + documents.map(\ .contents) + workflow.manifest.constraints + workflow.manifest.outOfScope)
            .joined(separator: "\n")
            .lowercased()
        var inferred = explicit

        if joined.contains("payment") || joined.contains("billing") || joined.contains("charge") {
            inferred.append(.payment)
        }
        if joined.contains("connector") || joined.contains("channel") || joined.contains("integration") {
            inferred.append(.connectorBinding)
        }
        if joined.contains("secret") || joined.contains("credential") || joined.contains("token") || joined.contains("key") {
            inferred.append(.secretBinding)
        }
        if workflow.manifest.requiresUserAuthorization || joined.contains("deploy") || joined.contains("publish") || joined.contains("launch") || joined.contains("external") || joined.contains("side effect") {
            inferred.append(.externalSideEffect)
        }
        if joined.contains("scope expansion") || joined.contains("out_of_scope") || joined.contains("out of scope") {
            inferred.append(.scopeExpansion)
        }

        return oneShotOrderedUniqueAuthorizationTypes(inferred)
    }

    private func resolvedSplitProfile(
        requested: OneShotSplitProfile?,
        participationMode: DeliveryParticipationMode,
        innovationLevel: SupervisorInnovationLevel,
        budgetClass: OneShotTokenBudgetClass,
        authorizationTypes: [OneShotHumanAuthorizationType],
        manifestRisk: SupervisorRiskLevel
    ) -> OneShotSplitProfile {
        guard let requested else {
            return inferSplitProfile(
                participationMode: participationMode,
                innovationLevel: innovationLevel,
                budgetClass: budgetClass,
                authorizationTypes: authorizationTypes,
                manifestRisk: manifestRisk
            )
        }
        guard requested == .auto else { return requested }
        return inferSplitProfile(
            participationMode: participationMode,
            innovationLevel: innovationLevel,
            budgetClass: budgetClass,
            authorizationTypes: authorizationTypes,
            manifestRisk: manifestRisk
        )
    }

    private func inferSplitProfile(
        participationMode: DeliveryParticipationMode,
        innovationLevel: SupervisorInnovationLevel,
        budgetClass: OneShotTokenBudgetClass,
        authorizationTypes: [OneShotHumanAuthorizationType],
        manifestRisk: SupervisorRiskLevel
    ) -> OneShotSplitProfile {
        if !authorizationTypes.isEmpty || manifestRisk == .high || budgetClass == .tight || participationMode == .criticalTouch {
            return .conservative
        }
        if innovationLevel == .l4 || innovationLevel == .l3 || budgetClass == .priorityDelivery {
            return .aggressive
        }
        return .balanced
    }

    private func mapBudgetTier(_ tier: SupervisorBudgetTier) -> OneShotTokenBudgetClass {
        switch tier {
        case .tight:
            return .tight
        case .balanced:
            return .standard
        case .aggressive:
            return .priorityDelivery
        }
    }

    private func mapBudgetClassToLegacyTier(_ budgetClass: OneShotTokenBudgetClass) -> String {
        switch budgetClass {
        case .tight:
            return "tight"
        case .standard:
            return "balanced"
        case .priorityDelivery:
            return "aggressive"
        }
    }

    private func mapDeliveryMode(_ acceptanceMode: SupervisorAcceptanceMode) -> OneShotDeliveryMode {
        switch acceptanceMode {
        case .internalBeta:
            return .implementationFirst
        case .releaseCandidate, .production:
            return .releaseFirst
        }
    }

    private func normalizeUUIDLike(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = UUID(uuidString: trimmed.lowercased()) {
            return parsed.uuidString.lowercased()
        }
        return oneShotDeterministicUUIDString(seed: trimmed)
    }
}

func oneShotOrderedUniqueStrings(_ values: [String]) -> [String] {
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

func oneShotOrderedUniqueAuthorizationTypes(_ values: [OneShotHumanAuthorizationType]) -> [OneShotHumanAuthorizationType] {
    var seen: Set<String> = []
    var ordered: [OneShotHumanAuthorizationType] = []
    for value in values {
        if seen.insert(value.rawValue).inserted {
            ordered.append(value)
        }
    }
    return ordered
}

func oneShotDeterministicUUIDString(seed: String) -> String {
    func fnv1a64(_ text: String, seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    let upper = fnv1a64(seed, seed: 14_695_981_039_346_656_037)
    let lower = fnv1a64(String(seed.reversed()), seed: 10_995_116_282_11)

    let part1 = UInt32(truncatingIfNeeded: upper >> 32)
    let part2 = UInt16(truncatingIfNeeded: upper >> 16)
    let rawPart3 = UInt16(truncatingIfNeeded: upper)
    let rawPart4 = UInt16(truncatingIfNeeded: lower >> 48)
    let part3 = (rawPart3 & 0x0fff) | 0x5000
    let part4 = (rawPart4 & 0x3fff) | 0x8000
    let part5 = UInt64(truncatingIfNeeded: lower) & 0x0000_ffff_ffff_ffff

    let uuid = String(format: "%08x-%04x-%04x-%04x-%012llx", part1, part2, part3, part4, part5)
    return UUID(uuidString: uuid)?.uuidString.lowercased() ?? "00000000-0000-5000-8000-000000000000"
}

func oneShotMakeAuditRef(prefix: String, projectID: String, now: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
    let token = formatter.string(from: now)
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
    return "\(prefix)-\(projectID.prefix(8))-\(token)"
}
