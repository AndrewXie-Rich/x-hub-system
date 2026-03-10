import Foundation

/// 任务分解器 - 负责将复杂任务拆解为子任务
@MainActor
class TaskDecomposer {

    // MARK: - 属性

    private let analyzer = TaskAnalyzer()
    private let splitProposalEngine = SplitProposalEngine()

    // MARK: - 公共方法

    /// 分析并分解任务
    /// - Parameter description: 任务描述
    /// - Returns: 分解后的任务列表和依赖图
    func analyzeAndDecompose(_ description: String) async -> DecompositionResult {
        // 1. 分析任务
        let analysis = await analyzer.analyze(description)

        // 2. 创建根任务
        let rootTask = DecomposedTask(
            description: description,
            type: analysis.type,
            complexity: analysis.complexity,
            estimatedEffort: analysis.estimatedEffort,
            priority: 5
        )

        // 3. 判断是否需要拆解
        if !analysis.needsDecomposition {
            return DecompositionResult(
                rootTask: rootTask,
                subtasks: [],
                allTasks: [rootTask],
                dependencyGraph: DependencyGraph(tasks: [rootTask]),
                analysis: analysis
            )
        }

        // 4. 拆解任务
        let subtasks = await decomposeTask(rootTask, analysis: analysis)

        // 5. 构建依赖图
        let allTasks = [rootTask] + subtasks
        let graph = buildDependencyGraph(allTasks, analysis: analysis)

        return DecompositionResult(
            rootTask: rootTask,
            subtasks: subtasks,
            allTasks: allTasks,
            dependencyGraph: graph,
            analysis: analysis
        )
    }

    /// 分析任务并生成可审阅拆分提案
    /// - Parameters:
    ///   - description: 用户任务描述
    ///   - rootProjectId: 根项目 ID
    ///   - planVersion: 提案版本号
    /// - Returns: 拆分提案结果（含校验）
    func analyzeAndBuildSplitProposal(
        _ description: String,
        rootProjectId: UUID = UUID(),
        planVersion: Int = 1
    ) async -> SplitProposalBuildResult {
        let decomposition = await analyzeAndDecompose(description)
        return buildSplitProposal(
            from: decomposition,
            rootProjectId: rootProjectId,
            planVersion: planVersion
        )
    }

    /// 基于分解结果构造拆分提案
    func buildSplitProposal(
        from decomposition: DecompositionResult,
        rootProjectId: UUID,
        planVersion: Int = 1
    ) -> SplitProposalBuildResult {
        splitProposalEngine.buildProposal(
            from: decomposition,
            rootProjectId: rootProjectId,
            planVersion: planVersion
        )
    }

    /// 拆解任务
    /// - Parameters:
    ///   - task: 要拆解的任务
    ///   - analysis: 任务分析结果
    /// - Returns: 子任务列表
    func decomposeTask(_ task: DecomposedTask, analysis: TaskAnalysis) async -> [DecomposedTask] {
        var subtasks: [DecomposedTask] = []

        // 如果有建议的子任务，使用它们
        if !analysis.suggestedSubtasks.isEmpty {
            subtasks = createSubtasksFromSuggestions(
                analysis.suggestedSubtasks,
                parentTask: task,
                analysis: analysis
            )
        } else {
            // 否则使用通用拆解策略
            subtasks = createGenericSubtasks(task, analysis: analysis)
        }

        // 调整子任务的优先级和复杂度
        subtasks = adjustSubtaskProperties(subtasks, parentTask: task)

        return subtasks
    }

    /// 构建依赖图
    /// - Parameters:
    ///   - tasks: 任务列表
    ///   - analysis: 任务分析结果
    /// - Returns: 依赖图
    func buildDependencyGraph(_ tasks: [DecomposedTask], analysis: TaskAnalysis) -> DependencyGraph {
        let graph = DependencyGraph()

        // 添加所有任务节点
        for task in tasks {
            graph.addNode(task)
        }

        // 根据任务类型和描述推断依赖关系
        inferDependencies(tasks: tasks, graph: graph, analysis: analysis)

        return graph
    }

    // MARK: - 私有方法

    /// 从建议创建子任务
    private func createSubtasksFromSuggestions(
        _ suggestions: [String],
        parentTask: DecomposedTask,
        analysis: TaskAnalysis
    ) -> [DecomposedTask] {
        var subtasks: [DecomposedTask] = []

        for (index, suggestion) in suggestions.enumerated() {
            let subtaskType = inferSubtaskType(suggestion, parentType: parentTask.type)
            let subtaskComplexity = estimateSubtaskComplexity(
                suggestion,
                parentComplexity: parentTask.complexity,
                totalSubtasks: suggestions.count
            )

            let subtask = DecomposedTask(
                description: suggestion,
                type: subtaskType,
                complexity: subtaskComplexity,
                estimatedEffort: subtaskComplexity.estimatedHours,
                priority: parentTask.priority,
                metadata: [
                    "parent_task_id": parentTask.id.uuidString,
                    "subtask_index": "\(index)",
                    "total_subtasks": "\(suggestions.count)"
                ]
            )

            subtasks.append(subtask)
        }

        return subtasks
    }

    /// 创建通用子任务
    private func createGenericSubtasks(_ task: DecomposedTask, analysis: TaskAnalysis) -> [DecomposedTask] {
        var subtasks: [DecomposedTask] = []

        // 根据复杂度决定拆分数量
        let subtaskCount = min(task.complexity.maxSubtasks, 4)

        switch task.type {
        case .development:
            subtasks = createDevelopmentSubtasks(task, count: subtaskCount)

        case .testing:
            subtasks = createTestingSubtasks(task, count: subtaskCount)

        case .bugfix:
            subtasks = createBugfixSubtasks(task)

        case .refactoring:
            subtasks = createRefactoringSubtasks(task, count: subtaskCount)

        case .documentation:
            subtasks = createDocumentationSubtasks(task, count: subtaskCount)

        default:
            // 通用拆分
            subtasks = createDefaultSubtasks(task, count: subtaskCount)
        }

        return subtasks
    }

    /// 创建开发类子任务
    private func createDevelopmentSubtasks(_ task: DecomposedTask, count: Int) -> [DecomposedTask] {
        var subtasks: [DecomposedTask] = []

        if count >= 2 {
            subtasks.append(DecomposedTask(
                description: "设计和规划: \(task.description)",
                type: .design,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.2,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "design"]
            ))

            subtasks.append(DecomposedTask(
                description: "实现核心功能: \(task.description)",
                type: .development,
                complexity: .moderate,
                estimatedEffort: task.estimatedEffort * 0.5,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "implementation"]
            ))
        }

        if count >= 3 {
            subtasks.append(DecomposedTask(
                description: "编写测试: \(task.description)",
                type: .testing,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.2,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "testing"]
            ))
        }

        if count >= 4 {
            subtasks.append(DecomposedTask(
                description: "文档和代码审查: \(task.description)",
                type: .documentation,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.1,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "documentation"]
            ))
        }

        return subtasks
    }

    /// 创建测试类子任务
    private func createTestingSubtasks(_ task: DecomposedTask, count: Int) -> [DecomposedTask] {
        return [
            DecomposedTask(
                description: "编写测试用例: \(task.description)",
                type: .testing,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.3,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "test_cases"]
            ),
            DecomposedTask(
                description: "执行测试: \(task.description)",
                type: .testing,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.4,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "execution"]
            ),
            DecomposedTask(
                description: "分析结果和修复: \(task.description)",
                type: .bugfix,
                complexity: .moderate,
                estimatedEffort: task.estimatedEffort * 0.3,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "analysis"]
            )
        ]
    }

    /// 创建 Bug 修复类子任务
    private func createBugfixSubtasks(_ task: DecomposedTask) -> [DecomposedTask] {
        return [
            DecomposedTask(
                description: "重现和定位问题: \(task.description)",
                type: .research,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.3,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "reproduce"]
            ),
            DecomposedTask(
                description: "实现修复: \(task.description)",
                type: .bugfix,
                complexity: .moderate,
                estimatedEffort: task.estimatedEffort * 0.5,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "fix"]
            ),
            DecomposedTask(
                description: "验证修复: \(task.description)",
                type: .testing,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.2,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "verify"]
            )
        ]
    }

    /// 创建重构类子任务
    private func createRefactoringSubtasks(_ task: DecomposedTask, count: Int) -> [DecomposedTask] {
        return [
            DecomposedTask(
                description: "分析现有代码: \(task.description)",
                type: .research,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.25,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "analysis"]
            ),
            DecomposedTask(
                description: "设计重构方案: \(task.description)",
                type: .design,
                complexity: .moderate,
                estimatedEffort: task.estimatedEffort * 0.25,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "design"]
            ),
            DecomposedTask(
                description: "实施重构: \(task.description)",
                type: .refactoring,
                complexity: .moderate,
                estimatedEffort: task.estimatedEffort * 0.4,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "refactor"]
            ),
            DecomposedTask(
                description: "验证功能完整性: \(task.description)",
                type: .testing,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.1,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "phase": "verify"]
            )
        ]
    }

    /// 创建文档类子任务
    private func createDocumentationSubtasks(_ task: DecomposedTask, count: Int) -> [DecomposedTask] {
        return [
            DecomposedTask(
                description: "编写技术文档: \(task.description)",
                type: .documentation,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.6,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "doc_type": "technical"]
            ),
            DecomposedTask(
                description: "编写用户文档: \(task.description)",
                type: .documentation,
                complexity: .simple,
                estimatedEffort: task.estimatedEffort * 0.4,
                priority: task.priority,
                metadata: ["parent_task_id": task.id.uuidString, "doc_type": "user"]
            )
        ]
    }

    /// 创建默认子任务
    private func createDefaultSubtasks(_ task: DecomposedTask, count: Int) -> [DecomposedTask] {
        var subtasks: [DecomposedTask] = []
        let effortPerSubtask = task.estimatedEffort / Double(count)

        for i in 0..<count {
            subtasks.append(DecomposedTask(
                description: "子任务 \(i + 1): \(task.description)",
                type: task.type,
                complexity: .simple,
                estimatedEffort: effortPerSubtask,
                priority: task.priority,
                metadata: [
                    "parent_task_id": task.id.uuidString,
                    "subtask_index": "\(i)",
                    "total_subtasks": "\(count)"
                ]
            ))
        }

        return subtasks
    }

    /// 推断子任务类型
    private func inferSubtaskType(_ description: String, parentType: DecomposedTaskType) -> DecomposedTaskType {
        let normalized = description.lowercased()

        if normalized.contains("设计") || normalized.contains("design") {
            return .design
        }
        if normalized.contains("测试") || normalized.contains("test") {
            return .testing
        }
        if normalized.contains("文档") || normalized.contains("document") {
            return .documentation
        }
        if normalized.contains("修复") || normalized.contains("fix") {
            return .bugfix
        }
        if normalized.contains("重构") || normalized.contains("refactor") {
            return .refactoring
        }
        if normalized.contains("研究") || normalized.contains("research") || normalized.contains("分析") {
            return .research
        }

        return parentType
    }

    /// 估算子任务复杂度
    private func estimateSubtaskComplexity(
        _ description: String,
        parentComplexity: DecomposedTaskComplexity,
        totalSubtasks: Int
    ) -> DecomposedTaskComplexity {
        // 子任务通常比父任务简单
        switch parentComplexity {
        case .veryComplex:
            return totalSubtasks > 4 ? .moderate : .complex
        case .complex:
            return totalSubtasks > 3 ? .simple : .moderate
        case .moderate:
            return .simple
        case .simple:
            return .trivial
        case .trivial:
            return .trivial
        }
    }

    /// 调整子任务属性
    private func adjustSubtaskProperties(_ subtasks: [DecomposedTask], parentTask: DecomposedTask) -> [DecomposedTask] {
        return subtasks.enumerated().map { index, task in
            var adjusted = task

            // 调整优先级（早期任务优先级更高）
            adjusted.priority = parentTask.priority + (subtasks.count - index)

            return adjusted
        }
    }

    /// 推断依赖关系
    private func inferDependencies(tasks: [DecomposedTask], graph: DependencyGraph, analysis: TaskAnalysis) {
        // 按照 metadata 中的 phase 排序
        let phaseOrder = ["design", "implementation", "testing", "documentation", "verify"]

        for i in 0..<tasks.count {
            for j in (i + 1)..<tasks.count {
                let task1 = tasks[i]
                let task2 = tasks[j]

                // 检查是否有明确的阶段依赖
                if let phase1 = task1.metadata["phase"],
                   let phase2 = task2.metadata["phase"],
                   let index1 = phaseOrder.firstIndex(of: phase1),
                   let index2 = phaseOrder.firstIndex(of: phase2) {

                    if index1 < index2 {
                        // task2 依赖于 task1
                        var updatedTask2 = task2
                        updatedTask2.dependencies.insert(task1.id)
                        graph.addEdge(from: task2.id, to: task1.id)
                    }
                }

                // 基于任务类型的隐式依赖
                if shouldDependOn(task2, on: task1) {
                    var updatedTask2 = task2
                    updatedTask2.dependencies.insert(task1.id)
                    graph.addEdge(from: task2.id, to: task1.id)
                }
            }
        }
    }

    /// 判断任务是否应该依赖另一个任务
    private func shouldDependOn(_ task: DecomposedTask, on dependency: DecomposedTask) -> Bool {
        // 测试依赖于开发
        if task.type == .testing && dependency.type == .development {
            return true
        }

        // 文档依赖于开发
        if task.type == .documentation && dependency.type == .development {
            return true
        }

        // 部署依赖于测试
        if task.type == .deployment && dependency.type == .testing {
            return true
        }

        // 代码审查依赖于开发
        if task.type == .review && dependency.type == .development {
            return true
        }

        return false
    }
}

// MARK: - 辅助结构

/// 任务分解结果
struct DecompositionResult {
    let rootTask: DecomposedTask
    let subtasks: [DecomposedTask]
    let allTasks: [DecomposedTask]
    let dependencyGraph: DependencyGraph
    let analysis: TaskAnalysis

    var hasSubtasks: Bool {
        return !subtasks.isEmpty
    }

    var totalEstimatedEffort: TimeInterval {
        return allTasks.reduce(0) { $0 + $1.estimatedEffort }
    }

    var executionOrder: [UUID]? {
        return dependencyGraph.topologicalSort()
    }

    var parallelGroups: [[UUID]] {
        return dependencyGraph.parallelGroups()
    }
}
