import Foundation

enum PromptCompilationStatus: String, Codable, Equatable {
    case ready
    case rejected
}

enum PromptLintSeverity: String, Codable, Equatable {
    case warning
    case error
}

struct PromptLintIssue: Identifiable, Codable, Equatable {
    var id: UUID
    var laneId: String
    var severity: PromptLintSeverity
    var code: String
    var message: String

    init(
        id: UUID = UUID(),
        laneId: String,
        severity: PromptLintSeverity,
        code: String,
        message: String
    ) {
        self.id = id
        self.laneId = laneId
        self.severity = severity
        self.code = code
        self.message = message
    }
}

struct PromptLintResult: Codable, Equatable {
    var issues: [PromptLintIssue]

    var hasBlockingErrors: Bool {
        issues.contains { $0.severity == .error }
    }

    var blockingIssues: [PromptLintIssue] {
        issues.filter { $0.severity == .error }
    }
}

enum LaneVerificationMethod: String, Codable, Equatable {
    case targetedChecksAndDiffReview = "targeted_checks_and_diff_review"
    case preflightAndSmoke = "preflight_and_smoke"
    case artifactConsistencyReview = "artifact_consistency_review"

    var promptLabel: String {
        switch self {
        case .targetedChecksAndDiffReview:
            return "targeted checks + diff review"
        case .preflightAndSmoke:
            return "preflight + smoke checks"
        case .artifactConsistencyReview:
            return "artifact consistency review"
        }
    }
}

enum LaneVerificationRetryPolicy: String, Codable, Equatable {
    case boundedRetryThenHold = "bounded_retry_then_hold"
    case singleRetryThenEscalate = "single_retry_then_escalate"
    case noAutoRetry = "no_auto_retry"

    var promptLabel: String {
        switch self {
        case .boundedRetryThenHold:
            return "bounded retry, then hold"
        case .singleRetryThenEscalate:
            return "single retry, then escalate"
        case .noAutoRetry:
            return "no automatic retry"
        }
    }
}

enum LaneVerificationHoldPolicy: String, Codable, Equatable {
    case holdOnMismatch = "hold_on_mismatch"
    case holdUntilEvidence = "hold_until_evidence"
    case advisoryOnly = "advisory_only"

    var promptLabel: String {
        switch self {
        case .holdOnMismatch:
            return "hold on verification mismatch"
        case .holdUntilEvidence:
            return "hold until required evidence is attached"
        case .advisoryOnly:
            return "advisory only"
        }
    }
}

struct LaneVerificationContract: Codable, Equatable {
    var expectedState: String
    var verifyMethod: LaneVerificationMethod
    var retryPolicy: LaneVerificationRetryPolicy
    var holdPolicy: LaneVerificationHoldPolicy
    var evidenceRequired: [String]
    var verificationChecklist: [String]

    init(
        expectedState: String,
        verifyMethod: LaneVerificationMethod,
        retryPolicy: LaneVerificationRetryPolicy,
        holdPolicy: LaneVerificationHoldPolicy,
        evidenceRequired: [String],
        verificationChecklist: [String]
    ) {
        self.expectedState = expectedState
        self.verifyMethod = verifyMethod
        self.retryPolicy = retryPolicy
        self.holdPolicy = holdPolicy
        self.evidenceRequired = evidenceRequired
        self.verificationChecklist = verificationChecklist
    }
}

/// 每条 lane 的执行提示词合同（Prompt Contract）
struct PromptContract: Identifiable, Codable, Equatable {
    var laneId: String
    var goal: String
    var boundaries: [String]
    var inputs: [String]
    var outputs: [String]
    var dodChecklist: [String]
    var riskBoundaries: [String]
    var prohibitions: [String]
    var rollbackPoints: [String]
    var refusalSemantics: [String]
    var verificationContract: LaneVerificationContract?
    var compiledPrompt: String
    var tokenBudget: Int

    var id: String { laneId }

    init(
        laneId: String,
        goal: String,
        boundaries: [String],
        inputs: [String],
        outputs: [String],
        dodChecklist: [String],
        riskBoundaries: [String],
        prohibitions: [String] = [],
        rollbackPoints: [String],
        refusalSemantics: [String],
        verificationContract: LaneVerificationContract? = nil,
        compiledPrompt: String,
        tokenBudget: Int
    ) {
        self.laneId = laneId
        self.goal = goal
        self.boundaries = boundaries
        self.inputs = inputs
        self.outputs = outputs
        self.dodChecklist = dodChecklist
        self.riskBoundaries = riskBoundaries
        self.prohibitions = prohibitions
        self.rollbackPoints = rollbackPoints
        self.refusalSemantics = refusalSemantics
        self.verificationContract = verificationContract
        self.compiledPrompt = compiledPrompt
        self.tokenBudget = tokenBudget
    }
}

struct PromptCompilationResult: Codable, Equatable {
    var splitPlanId: UUID
    var expectedLaneCount: Int
    var contracts: [PromptContract]
    var lintResult: PromptLintResult
    var status: PromptCompilationStatus
    var compiledAt: Date

    var coverage: Double {
        guard expectedLaneCount > 0 else { return 1.0 }
        return min(1.0, Double(contracts.count) / Double(expectedLaneCount))
    }

    var lanePromptCoverageComplete: Bool {
        expectedLaneCount > 0 && contracts.count == expectedLaneCount
    }

    var canLaunch: Bool {
        lanePromptCoverageComplete && !lintResult.hasBlockingErrors && status == .ready
    }
}
