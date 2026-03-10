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
