import Foundation

/// 任务模型（用于任务分解）
struct DecomposedTask: Identifiable, Codable, Equatable {
    let id: UUID
    var description: String
    var type: DecomposedTaskType
    var complexity: DecomposedTaskComplexity
    var estimatedEffort: TimeInterval
    var dependencies: Set<UUID>
    var status: DecomposedTaskStatus
    var priority: Int
    var assignedProjectId: UUID?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var failureReason: String?
    var attempts: Int
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        description: String,
        type: DecomposedTaskType = .development,
        complexity: DecomposedTaskComplexity = .moderate,
        estimatedEffort: TimeInterval = 3600,
        dependencies: Set<UUID> = [],
        status: DecomposedTaskStatus = .pending,
        priority: Int = 5,
        assignedProjectId: UUID? = nil,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.description = description
        self.type = type
        self.complexity = complexity
        self.estimatedEffort = estimatedEffort
        self.dependencies = dependencies
        self.status = status
        self.priority = priority
        self.assignedProjectId = assignedProjectId
        self.createdAt = createdAt
        self.attempts = 0
        self.metadata = metadata
    }

    /// 是否准备好执行（所有依赖已完成）
    func isReady(completedTasks: Set<UUID>) -> Bool {
        guard status == .pending || status == .blocked else {
            return false
        }
        return dependencies.isSubset(of: completedTasks)
    }

    /// 是否可以并行执行
    func canRunInParallel(with other: DecomposedTask) -> Bool {
        // 如果有依赖关系，不能并行
        if dependencies.contains(other.id) || other.dependencies.contains(id) {
            return false
        }
        return true
    }

    /// 估算完成时间
    func estimatedCompletionDate(from startDate: Date = Date()) -> Date {
        return startDate.addingTimeInterval(estimatedEffort)
    }
}

/// 任务类型
enum DecomposedTaskType: String, Codable, CaseIterable {
    case development = "Development"
    case testing = "Testing"
    case documentation = "Documentation"
    case research = "Research"
    case bugfix = "Bug Fix"
    case refactoring = "Refactoring"
    case deployment = "Deployment"
    case review = "Code Review"
    case design = "Design"
    case planning = "Planning"

    var icon: String {
        switch self {
        case .development: return "hammer.fill"
        case .testing: return "checkmark.circle.fill"
        case .documentation: return "doc.text.fill"
        case .research: return "magnifyingglass"
        case .bugfix: return "ant.fill"
        case .refactoring: return "arrow.triangle.2.circlepath"
        case .deployment: return "arrow.up.circle.fill"
        case .review: return "eye.fill"
        case .design: return "paintbrush.fill"
        case .planning: return "list.bullet.clipboard.fill"
        }
    }

    var color: String {
        switch self {
        case .development: return "blue"
        case .testing: return "green"
        case .documentation: return "purple"
        case .research: return "orange"
        case .bugfix: return "red"
        case .refactoring: return "yellow"
        case .deployment: return "pink"
        case .review: return "cyan"
        case .design: return "indigo"
        case .planning: return "gray"
        }
    }
}

/// 任务复杂度
enum DecomposedTaskComplexity: String, Codable, CaseIterable, Comparable {
    case trivial = "Trivial"        // < 1 hour
    case simple = "Simple"          // 1-4 hours
    case moderate = "Moderate"      // 4-8 hours
    case complex = "Complex"        // 1-3 days
    case veryComplex = "Very Complex" // > 3 days

    var estimatedHours: TimeInterval {
        switch self {
        case .trivial: return 0.5 * 3600
        case .simple: return 2 * 3600
        case .moderate: return 6 * 3600
        case .complex: return 16 * 3600
        case .veryComplex: return 40 * 3600
        }
    }

    var maxSubtasks: Int {
        switch self {
        case .trivial: return 1
        case .simple: return 2
        case .moderate: return 4
        case .complex: return 8
        case .veryComplex: return 16
        }
    }

    static func < (lhs: DecomposedTaskComplexity, rhs: DecomposedTaskComplexity) -> Bool {
        let order: [DecomposedTaskComplexity] = [.trivial, .simple, .moderate, .complex, .veryComplex]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// 任务状态
enum DecomposedTaskStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case ready = "Ready"
    case assigned = "Assigned"
    case inProgress = "In Progress"
    case completed = "Completed"
    case failed = "Failed"
    case blocked = "Blocked"
    case cancelled = "Cancelled"

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .ready: return "checkmark.circle"
        case .assigned: return "person.circle"
        case .inProgress: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .blocked: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .pending: return "gray"
        case .ready: return "blue"
        case .assigned: return "cyan"
        case .inProgress: return "purple"
        case .completed: return "green"
        case .failed: return "red"
        case .blocked: return "orange"
        case .cancelled: return "gray"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

/// 任务分析结果
struct TaskAnalysis {
    let originalDescription: String
    let keywords: [String]
    let verbs: [String]
    let objects: [String]
    let constraints: [String]
    let type: DecomposedTaskType
    let complexity: DecomposedTaskComplexity
    let estimatedEffort: TimeInterval
    let requiredSkills: [String]
    let riskLevel: RiskLevel
    let suggestedSubtasks: [String]
    let potentialDependencies: [String]

    /// 是否需要拆解
    var needsDecomposition: Bool {
        return complexity >= .complex || suggestedSubtasks.count > 1
    }
}

/// 风险等级
enum RiskLevel: String, Codable, CaseIterable, Comparable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        let order: [RiskLevel] = [.low, .medium, .high, .critical]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// 拆分泳道风险等级
enum SplitRiskTier: String, Codable, CaseIterable, Comparable {
    case low
    case medium
    case high
    case critical

    init(from riskLevel: RiskLevel) {
        switch riskLevel {
        case .low:
            self = .low
        case .medium:
            self = .medium
        case .high:
            self = .high
        case .critical:
            self = .critical
        }
    }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    static func < (lhs: SplitRiskTier, rhs: SplitRiskTier) -> Bool {
        let order: [SplitRiskTier] = [.low, .medium, .high, .critical]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// 拆分泳道预算档位
enum SplitBudgetClass: String, Codable, CaseIterable, Comparable {
    case compact
    case standard
    case premium
    case burst

    var tokenBudget: Int {
        switch self {
        case .compact:
            return 2_000
        case .standard:
            return 4_000
        case .premium:
            return 8_000
        case .burst:
            return 12_000
        }
    }

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .premium: return "Premium"
        case .burst: return "Burst"
        }
    }

    static func < (lhs: SplitBudgetClass, rhs: SplitBudgetClass) -> Bool {
        let order: [SplitBudgetClass] = [.compact, .standard, .premium, .burst]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// 拆分落盘模式（hard = create_child_project）
enum SplitMaterializationMode: String, Codable, CaseIterable {
    case hard
    case soft

    var createChildProject: Bool {
        self == .hard
    }
}

/// 单个泳道拆分提案
struct SplitLaneProposal: Identifiable, Codable, Equatable {
    var laneId: String
    var goal: String
    var dependsOn: [String]
    var riskTier: SplitRiskTier
    var budgetClass: SplitBudgetClass
    var createChildProject: Bool
    var expectedArtifacts: [String]
    var dodChecklist: [String]
    var verificationContract: LaneVerificationContract? = nil
    var estimatedEffortMs: Int
    var tokenBudget: Int
    var sourceTaskId: UUID?
    var notes: [String]

    var id: String { laneId }

    var materializationMode: SplitMaterializationMode {
        createChildProject ? .hard : .soft
    }

    var isHighRisk: Bool {
        riskTier >= .high
    }
}

/// 多泳道拆分提案（可审阅/确认/覆盖）
struct SplitProposal: Identifiable, Codable, Equatable {
    var splitPlanId: UUID
    var rootProjectId: UUID
    var planVersion: Int
    var complexityScore: Double
    var lanes: [SplitLaneProposal]
    var recommendedConcurrency: Int
    var tokenBudgetTotal: Int
    var estimatedWallTimeMs: Int
    var sourceTaskDescription: String
    var createdAt: Date

    var id: UUID { splitPlanId }
}

enum SplitProposalIssueSeverity: String, Codable, Equatable {
    case warning
    case blocking
}

struct SplitProposalValidationIssue: Identifiable, Codable, Equatable {
    var id: UUID
    var code: String
    var message: String
    var severity: SplitProposalIssueSeverity
    var laneId: String?

    init(
        id: UUID = UUID(),
        code: String,
        message: String,
        severity: SplitProposalIssueSeverity,
        laneId: String? = nil
    ) {
        self.id = id
        self.code = code
        self.message = message
        self.severity = severity
        self.laneId = laneId
    }
}

struct SplitProposalValidationResult: Codable, Equatable {
    var issues: [SplitProposalValidationIssue]

    var hasBlockingIssues: Bool {
        issues.contains { $0.severity == .blocking }
    }

    var blockingIssues: [SplitProposalValidationIssue] {
        issues.filter { $0.severity == .blocking }
    }
}

enum SplitProposalFlowState: String, Codable, Equatable {
    case idle
    case proposing
    case proposed
    case overridden
    case confirmed
    case rejected
    case blocked
}

/// Split proposal 状态机契约（供 UI/编排/AI-XT-2 对齐同一套流转规则）
extension SplitProposalFlowState {
    static let stateMachineVersion = "xterminal.split_flow_state_machine.v1"

    private static let transitionTable: [SplitProposalFlowState: Set<SplitProposalFlowState>] = [
        .idle: [.proposing],
        .proposing: [.proposed, .blocked],
        .proposed: [.overridden, .confirmed, .rejected, .blocked, .idle],
        .overridden: [.overridden, .proposed, .confirmed, .rejected, .blocked, .idle],
        .confirmed: [.idle],
        .rejected: [.idle],
        .blocked: [.blocked, .proposed, .overridden, .confirmed, .rejected, .idle]
    ]

    static func allowedTransitions(from state: SplitProposalFlowState) -> Set<SplitProposalFlowState> {
        transitionTable[state] ?? []
    }

    func canTransition(to next: SplitProposalFlowState) -> Bool {
        Self.allowedTransitions(from: self).contains(next)
    }
}

enum SplitAuditEventType: String, Codable, Equatable {
    case splitProposed = "supervisor.split.proposed"
    case splitConfirmed = "supervisor.split.confirmed"
    case splitOverridden = "supervisor.split.overridden"
    case splitRejected = "supervisor.split.rejected"
    case promptCompiled = "supervisor.prompt.compiled"
    case promptRejected = "supervisor.prompt.rejected"
}

struct SplitAuditEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var eventType: SplitAuditEventType
    var splitPlanId: UUID
    var at: Date
    var detail: String
    var payload: [String: String]

    init(
        id: UUID = UUID(),
        eventType: SplitAuditEventType,
        splitPlanId: UUID,
        at: Date = Date(),
        detail: String,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.eventType = eventType
        self.splitPlanId = splitPlanId
        self.at = at
        self.detail = detail
        self.payload = payload
    }
}

/// 用户对 lane 的局部覆盖
struct SplitLaneOverride: Identifiable, Codable, Equatable {
    var id: UUID
    var laneId: String
    var createChildProject: Bool?
    var budgetClass: SplitBudgetClass?
    var riskTier: SplitRiskTier?
    var dodChecklist: [String]?
    var note: String?
    var confirmHighRiskHardToSoft: Bool?

    init(
        id: UUID = UUID(),
        laneId: String,
        createChildProject: Bool? = nil,
        budgetClass: SplitBudgetClass? = nil,
        riskTier: SplitRiskTier? = nil,
        dodChecklist: [String]? = nil,
        note: String? = nil,
        confirmHighRiskHardToSoft: Bool? = nil
    ) {
        self.id = id
        self.laneId = laneId
        self.createChildProject = createChildProject
        self.budgetClass = budgetClass
        self.riskTier = riskTier
        self.dodChecklist = dodChecklist
        self.note = note
        self.confirmHighRiskHardToSoft = confirmHighRiskHardToSoft
    }
}

/// 覆盖回放所需的 lane 快照（用于“可回放”与差异说明）
struct SplitLaneSnapshot: Codable, Equatable {
    var laneId: String
    var createChildProject: Bool
    var riskTier: SplitRiskTier
    var budgetClass: SplitBudgetClass
    var tokenBudget: Int
    var dodChecklist: [String]
}

/// 单次 override 的机读记录（用于重放和确定性校验）
struct SplitLaneOverrideRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var laneId: String
    var reason: String
    var override: SplitLaneOverride
    var before: SplitLaneSnapshot
    var after: SplitLaneSnapshot
    var appliedAt: Date
    var issueCodes: [String]
}

/// 任务执行状态
struct TaskExecutionState {
    var task: DecomposedTask
    let projectId: UUID
    let startedAt: Date
    var lastUpdateAt: Date
    var progress: Double
    var currentStatus: DecomposedTaskStatus
    var attempts: Int
    var errors: [DecomposedTaskError]
    var logs: [String]

    mutating func updateProgress(_ newProgress: Double) {
        progress = min(1.0, max(0.0, newProgress))
        lastUpdateAt = Date()
    }

    mutating func recordError(_ error: DecomposedTaskError) {
        errors.append(error)
        attempts += 1
        lastUpdateAt = Date()
    }

    mutating func addLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        logs.append("[\(timestamp)] \(message)")
        lastUpdateAt = Date()
    }
}

/// 任务错误
struct DecomposedTaskError: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let message: String
    let code: String?
    let recoverable: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        message: String,
        code: String? = nil,
        recoverable: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.code = code
        self.recoverable = recoverable
    }
}
