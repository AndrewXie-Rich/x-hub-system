import Foundation

/// 任务分配器 - 负责将任务智能分配给项目
@MainActor
class TaskAssigner {

    // MARK: - 属性

    weak var supervisor: SupervisorModel?
    private let laneAllocator = LaneAllocator()
    private(set) var lastLaneAllocationResult: LaneAllocationResult?

    // MARK: - 初始化

    init(supervisor: SupervisorModel? = nil) {
        self.supervisor = supervisor
    }

    // MARK: - 公共方法

    /// 智能分配任务
    /// - Parameter tasks: 要分配的任务列表
    /// - Returns: 任务 ID 到项目的映射
    func smartAssign(_ tasks: [DecomposedTask]) async -> [UUID: ProjectModel] {
        guard let supervisor else {
            return [:]
        }

        let syntheticLanes = tasks.enumerated().map { makeSyntheticLane(task: $0.element, index: $0.offset + 1) }
        let allocation = laneAllocator.allocate(
            lanes: syntheticLanes,
            projects: supervisor.activeProjects
        )
        lastLaneAllocationResult = allocation

        return Dictionary(uniqueKeysWithValues: allocation.assignments.map { ($0.task.id, $0.project) })
    }

    /// 分配已落盘 lane（XT-W2-12）
    /// - Parameter lanes: 来自 ProjectMaterializer 的落盘结果
    /// - Returns: 分配结果（含 explain 字段）
    func allocateMaterializedLanes(_ lanes: [MaterializedLane]) async -> LaneAllocationResult {
        let projects = supervisor?.activeProjects ?? []
        let result = laneAllocator.allocate(lanes: lanes, projects: projects)
        lastLaneAllocationResult = result
        return result
    }

    /// 分配单个任务到指定项目
    /// - Parameters:
    ///   - task: 任务
    ///   - project: 项目
    /// - Returns: 更新后的任务
    @discardableResult
    func assignTask(_ task: DecomposedTask, to project: ProjectModel) async -> DecomposedTask {
        var updatedTask = task
        updatedTask.assignedProjectId = project.id
        updatedTask.status = .assigned

        // 更新项目的任务队列
        project.taskQueue.removeAll { $0.id == task.id }
        project.taskQueue.append(updatedTask)

        // 记录分配日志
        logAssignment(task: updatedTask, project: project)
        return updatedTask
    }

    /// 重新分配任务
    /// - Parameter taskId: 任务 ID
    func reassignTask(_ taskId: UUID) async {
        guard let supervisor = supervisor else { return }

        // 查找任务
        var task: DecomposedTask?
        var currentProject: ProjectModel?

        for project in supervisor.activeProjects {
            if let foundTask = project.taskQueue.first(where: { $0.id == taskId }) {
                task = foundTask
                currentProject = project
                break
            }
        }

        guard var task = task, let currentProject = currentProject else {
            return
        }

        // 从当前项目移除
        currentProject.taskQueue.removeAll { $0.id == taskId }

        // 重置任务状态
        task.status = .pending
        task.assignedProjectId = nil
        task.attempts += 1

        // 重新分配
        let assignments = await smartAssign([task])
        if let newProject = assignments[task.id] {
            _ = await assignTask(task, to: newProject)
        }
    }

    /// 评估项目对任务的能力
    /// - Parameters:
    ///   - project: 项目
    ///   - task: 任务
    /// - Returns: 能力评分 (0-1)
    func evaluateCapability(_ project: ProjectModel, for task: DecomposedTask) -> Double {
        var score = 0.0

        // 1. 模型能力评分 (40%)
        let modelScore = evaluateModelCapability(project.currentModel.name, for: task)
        score += modelScore * 0.4

        // 2. 自主性级别评分 (20%)
        let governanceScore = evaluateAutonomyLevel(project, for: task)
        score += governanceScore * 0.2

        // 3. 历史表现评分 (20%)
        let performanceScore = evaluateHistoricalPerformance(project, for: task)
        score += performanceScore * 0.2

        // 4. 任务类型匹配度 (20%)
        let typeScore = evaluateDecomposedTaskTypeMatch(project, for: task)
        score += typeScore * 0.2

        return min(1.0, max(0.0, score))
    }

    // MARK: - 私有方法

    /// 评估分配
    private func evaluateAssignment(task: DecomposedTask, project: ProjectModel) async -> AssignmentScore {
        let capabilityScore = evaluateCapability(project, for: task)
        let loadScore = evaluateLoadScore(project)
        let costScore = evaluateCostScore(project, task: task)

        // 综合评分
        let totalScore = capabilityScore * 0.5 + loadScore * 0.3 + costScore * 0.2

        return AssignmentScore(
            project: project,
            task: task,
            capabilityScore: capabilityScore,
            loadScore: loadScore,
            costScore: costScore,
            totalScore: totalScore
        )
    }

    /// 评估模型能力
    private func evaluateModelCapability(_ modelName: String, for task: DecomposedTask) -> Double {
        // 简化版本：根据模型名称评估
        let normalized = modelName.lowercased()

        if normalized.contains("opus") {
            return 1.0 // 最强模型
        } else if normalized.contains("sonnet") {
            return 0.8 // 中等模型
        } else if normalized.contains("haiku") {
            return 0.6 // 快速模型
        }

        return 0.7 // 默认评分
    }

    /// 评估自主性级别
    private func evaluateAutonomyLevel(_ project: ProjectModel, for task: DecomposedTask) -> Double {
        let executionScore = project.governanceSchedulingAutonomyScore
        let supervisionScore = project.governanceSchedulingRiskSupportScore
        let needsStrongerGovernance = task.complexity >= .complex
            || task.type == .deployment
            || task.type == .refactoring

        let supervisionWeight = needsStrongerGovernance ? 0.20 : 0.10
        let score = executionScore * 0.85 + supervisionScore * supervisionWeight
        return max(0.45, min(1.0, score))
    }

    /// 评估历史表现
    private func evaluateHistoricalPerformance(_ project: ProjectModel, for task: DecomposedTask) -> Double {
        // 基于项目的任务队列完成情况
        let completedTasks = project.taskQueue.filter { $0.status == .completed }.count
        let failedTasks = project.taskQueue.filter { $0.status == .failed }.count
        let totalTasks = completedTasks + failedTasks

        guard totalTasks > 0 else {
            return 0.7 // 新项目默认评分
        }

        let successRate = Double(completedTasks) / Double(totalTasks)
        return successRate
    }

    /// 评估任务类型匹配度
    private func evaluateDecomposedTaskTypeMatch(_ project: ProjectModel, for task: DecomposedTask) -> Double {
        // 简化实现：所有项目都能处理所有类型的任务
        // 可以根据项目历史任务类型进行优化
        return 0.8
    }

    /// 评估负载评分
    private func evaluateLoadScore(_ project: ProjectModel) -> Double {
        let currentTasks = project.taskQueue.filter { $0.status == .inProgress }.count
        let maxConcurrentTasks = 3 // 假设每个项目最多同时处理 3 个任务

        let loadRatio = Double(currentTasks) / Double(maxConcurrentTasks)
        return 1.0 - loadRatio // 负载越低，评分越高
    }

    /// 评估成本评分
    private func evaluateCostScore(_ project: ProjectModel, task: DecomposedTask) -> Double {
        let dailyBudget = project.budget.daily
        let currentCost = project.costTracker.totalCost
        let remainingBudget = dailyBudget - currentCost

        // 估算任务成本（简化版本）
        let estimatedCost = task.estimatedEffort / 3600.0 * 0.1 // 假设每小时 $0.1

        if estimatedCost > remainingBudget {
            return 0.0 // 预算不足
        }

        let budgetUtilization = currentCost / dailyBudget
        return 1.0 - budgetUtilization // 预算使用率越低，评分越高
    }

    /// 负载均衡
    private func balanceLoad(
        _ assignments: [UUID: ProjectModel],
        projectLoads: [UUID: Double]
    ) -> [UUID: ProjectModel] {
        // 简化实现：返回原始分配
        // 实际应用中可以实现更复杂的负载均衡算法
        return assignments
    }

    private func makeSyntheticLane(task: DecomposedTask, index: Int) -> MaterializedLane {
        let laneID = task.metadata["lane_id"] ?? "lane-\(index)"
        let riskTier = LaneRiskTier(rawValue: task.metadata["risk_tier"] ?? "") ?? inferRiskTier(task)
        let budgetClass = LaneBudgetClass(rawValue: task.metadata["budget_class"] ?? "") ?? inferBudgetClass(task)
        let createChild = task.metadata["create_child_project"] == "1"
        let dependsOn = task.metadata["depends_on"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        let plan = SupervisorLanePlan(
            laneID: laneID,
            goal: task.description,
            dependsOn: dependsOn,
            riskTier: riskTier,
            budgetClass: budgetClass,
            createChildProject: createChild,
            expectedArtifacts: [],
            dodChecklist: [],
            source: .inferred,
            metadata: task.metadata,
            task: task
        )

        return MaterializedLane(
            plan: plan,
            mode: createChild ? .hardSplit : .softSplit,
            task: task,
            targetProject: nil,
            lineageOperations: [],
            decisionReasons: ["synthetic_lane"],
            explain: "synthetic lane for smartAssign"
        )
    }

    private func inferRiskTier(_ task: DecomposedTask) -> LaneRiskTier {
        if task.complexity >= .complex {
            return .high
        }
        if task.complexity == .moderate {
            return .medium
        }
        return .low
    }

    private func inferBudgetClass(_ task: DecomposedTask) -> LaneBudgetClass {
        if task.complexity >= .complex {
            return .premium
        }
        if task.complexity == .trivial || task.complexity == .simple {
            return .economy
        }
        return .balanced
    }

    /// 记录分配日志
    private func logAssignment(task: DecomposedTask, project: ProjectModel) {
        let message = """
        任务分配:
        - 任务: \(task.description)
        - 项目: \(project.name)
        - 类型: \(task.type.rawValue)
        - 复杂度: \(task.complexity.rawValue)
        - 预计工作量: \(String(format: "%.1f", task.estimatedEffort / 3600.0)) 小时
        """
        print(message)
    }
}

// MARK: - 辅助结构

/// 分配评分
struct AssignmentScore {
    let project: ProjectModel
    let task: DecomposedTask
    let capabilityScore: Double
    let loadScore: Double
    let costScore: Double
    let totalScore: Double
}
