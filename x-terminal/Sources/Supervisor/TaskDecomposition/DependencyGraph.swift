import Foundation

/// 依赖图 - 管理任务之间的依赖关系
class DependencyGraph {

    // MARK: - 属性

    /// 任务节点
    private var nodes: [UUID: DecomposedTask] = [:]

    /// 依赖边 (from -> [to])
    /// 表示 from 依赖于 to (to 必须先完成)
    private var edges: [UUID: Set<UUID>] = [:]

    /// 反向边 (to -> [from])
    /// 表示 to 被 from 依赖 (完成 to 后可以解锁 from)
    private var reverseEdges: [UUID: Set<UUID>] = [:]

    // MARK: - 初始化

    init() {}

    init(tasks: [DecomposedTask]) {
        for task in tasks {
            addNode(task)
        }
    }

    // MARK: - 节点管理

    /// 添加任务节点
    func addNode(_ task: DecomposedTask) {
        nodes[task.id] = task

        // 初始化边集合
        if edges[task.id] == nil {
            edges[task.id] = Set()
        }
        if reverseEdges[task.id] == nil {
            reverseEdges[task.id] = Set()
        }

        // 添加任务的依赖边
        for dependencyId in task.dependencies {
            addEdge(from: task.id, to: dependencyId)
        }
    }

    /// 移除任务节点
    func removeNode(_ taskId: UUID) {
        nodes.removeValue(forKey: taskId)

        // 移除所有相关的边
        edges.removeValue(forKey: taskId)
        reverseEdges.removeValue(forKey: taskId)

        // 从其他节点的边中移除
        for (id, _) in edges {
            edges[id]?.remove(taskId)
        }
        for (id, _) in reverseEdges {
            reverseEdges[id]?.remove(taskId)
        }
    }

    /// 获取任务
    func getTask(_ taskId: UUID) -> DecomposedTask? {
        return nodes[taskId]
    }

    /// 获取所有任务
    func getAllTasks() -> [DecomposedTask] {
        return Array(nodes.values)
    }

    // MARK: - 边管理

    /// 添加依赖边
    /// - Parameters:
    ///   - from: 依赖者任务 ID
    ///   - to: 被依赖任务 ID (必须先完成)
    func addEdge(from: UUID, to: UUID) {
        edges[from, default: Set()].insert(to)
        reverseEdges[to, default: Set()].insert(from)
    }

    /// 移除依赖边
    func removeEdge(from: UUID, to: UUID) {
        edges[from]?.remove(to)
        reverseEdges[to]?.remove(from)
    }

    /// 获取任务的直接依赖
    func getDependencies(_ taskId: UUID) -> Set<UUID> {
        return edges[taskId] ?? Set()
    }

    /// 获取依赖该任务的任务列表
    func getDependents(_ taskId: UUID) -> Set<UUID> {
        return reverseEdges[taskId] ?? Set()
    }

    /// 获取任务的所有传递依赖
    func getTransitiveDependencies(_ taskId: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var queue = Array(getDependencies(taskId))

        while !queue.isEmpty {
            let current = queue.removeFirst()
            if result.insert(current).inserted {
                queue.append(contentsOf: getDependencies(current))
            }
        }

        return result
    }

    // MARK: - 图分析

    /// 拓扑排序
    /// - Returns: 排序后的任务 ID 列表，如果存在循环则返回 nil
    func topologicalSort() -> [UUID]? {
        var result: [UUID] = []
        var inDegree: [UUID: Int] = [:]

        // 计算入度
        for (taskId, _) in nodes {
            inDegree[taskId] = edges[taskId]?.count ?? 0
        }

        // 找到所有入度为 0 的节点
        var queue = inDegree.filter { $0.value == 0 }.map { $0.key }

        while !queue.isEmpty {
            let current = queue.removeFirst()
            result.append(current)

            // 减少依赖该节点的任务的入度
            for dependent in getDependents(current) {
                inDegree[dependent]! -= 1
                if inDegree[dependent]! == 0 {
                    queue.append(dependent)
                }
            }
        }

        // 如果结果数量不等于节点数量，说明存在循环
        if result.count != nodes.count {
            return nil
        }

        return result
    }

    /// 检测循环依赖
    /// - Returns: 循环路径列表
    func detectCycles() -> [[UUID]] {
        var cycles: [[UUID]] = []
        var visited = Set<UUID>()
        var recursionStack = Set<UUID>()
        var path: [UUID] = []

        func dfs(_ taskId: UUID) {
            visited.insert(taskId)
            recursionStack.insert(taskId)
            path.append(taskId)

            for dependency in getDependencies(taskId) {
                if !visited.contains(dependency) {
                    dfs(dependency)
                } else if recursionStack.contains(dependency) {
                    // 找到循环
                    if let startIndex = path.firstIndex(of: dependency) {
                        let cycle = Array(path[startIndex...])
                        cycles.append(cycle)
                    }
                }
            }

            recursionStack.remove(taskId)
            path.removeLast()
        }

        for (taskId, _) in nodes {
            if !visited.contains(taskId) {
                dfs(taskId)
            }
        }

        return cycles
    }

    /// 计算关键路径
    /// - Returns: 关键路径上的任务 ID 列表
    func criticalPath() -> [UUID] {
        guard let sorted = topologicalSort() else {
            return []
        }

        var earliestStart: [UUID: TimeInterval] = [:]
        var latestStart: [UUID: TimeInterval] = [:]

        // 计算最早开始时间
        for taskId in sorted {
            guard nodes[taskId] != nil else { continue }
            let task = nodes[taskId]!

            var maxDependencyTime: TimeInterval = 0
            for dependencyId in getDependencies(taskId) {
                if let depTask = nodes[dependencyId],
                   let depStart = earliestStart[dependencyId] {
                    maxDependencyTime = max(maxDependencyTime, depStart + depTask.estimatedEffort)
                }
            }
            earliestStart[taskId] = maxDependencyTime
        }

        // 计算最晚开始时间
        let totalTime = sorted.compactMap { taskId -> TimeInterval? in
            guard let task = nodes[taskId],
                  let start = earliestStart[taskId] else { return nil }
            return start + task.estimatedEffort
        }.max() ?? 0

        for taskId in sorted.reversed() {
            guard let task = nodes[taskId] else { continue }

            let dependents = getDependents(taskId)
            if dependents.isEmpty {
                latestStart[taskId] = totalTime - task.estimatedEffort
            } else {
                var minDependentTime = totalTime
                for dependentId in dependents {
                    if let depLatest = latestStart[dependentId] {
                        minDependentTime = min(minDependentTime, depLatest)
                    }
                }
                latestStart[taskId] = minDependentTime - task.estimatedEffort
            }
        }

        // 找出关键路径（最早开始时间 == 最晚开始时间）
        let criticalTasks = sorted.filter { taskId in
            guard let earliest = earliestStart[taskId],
                  let latest = latestStart[taskId] else { return false }
            return abs(earliest - latest) < 0.01 // 浮点数比较
        }

        return criticalTasks
    }

    /// 识别可并行执行的任务组
    /// - Returns: 可并行执行的任务组列表
    func parallelGroups() -> [[UUID]] {
        guard let sorted = topologicalSort() else {
            return []
        }

        var groups: [[UUID]] = []
        var completed = Set<UUID>()

        while completed.count < nodes.count {
            // 找出所有依赖已完成的任务
            var currentGroup: [UUID] = []

            for taskId in sorted {
                if completed.contains(taskId) {
                    continue
                }

                let dependencies = getDependencies(taskId)
                if dependencies.isSubset(of: completed) {
                    currentGroup.append(taskId)
                }
            }

            if currentGroup.isEmpty {
                break // 防止死循环
            }

            groups.append(currentGroup)
            completed.formUnion(currentGroup)
        }

        return groups
    }

    /// 获取准备好执行的任务
    /// - Parameter completedTasks: 已完成的任务 ID 集合
    /// - Returns: 准备好执行的任务列表
    func getReadyTasks(completedTasks: Set<UUID>) -> [DecomposedTask] {
        return nodes.values.filter { task in
            task.status == .pending && task.dependencies.isSubset(of: completedTasks)
        }
    }

    /// 计算任务的层级
    /// - Returns: 任务 ID 到层级的映射
    func calculateLevels() -> [UUID: Int] {
        guard let sorted = topologicalSort() else {
            return [:]
        }

        var levels: [UUID: Int] = [:]

        for taskId in sorted {
            let dependencies = getDependencies(taskId)
            if dependencies.isEmpty {
                levels[taskId] = 0
            } else {
                let maxDependencyLevel = dependencies.compactMap { levels[$0] }.max() ?? 0
                levels[taskId] = maxDependencyLevel + 1
            }
        }

        return levels
    }

    // MARK: - 统计信息

    /// 获取图的统计信息
    func getStatistics() -> GraphStatistics {
        let taskCount = nodes.count
        let edgeCount = edges.values.reduce(0) { $0 + $1.count }
        let cycles = detectCycles()
        let hasCycles = !cycles.isEmpty
        let criticalPathTasks = criticalPath()
        let levels = calculateLevels()
        let maxLevel = levels.values.max() ?? 0

        return GraphStatistics(
            taskCount: taskCount,
            edgeCount: edgeCount,
            hasCycles: hasCycles,
            cycleCount: cycles.count,
            criticalPathLength: criticalPathTasks.count,
            maxLevel: maxLevel
        )
    }

    // MARK: - 可视化支持

    /// 导出为 DOT 格式（用于 Graphviz）
    func exportToDOT() -> String {
        var dot = "digraph DependencyGraph {\n"
        dot += "  rankdir=LR;\n"
        dot += "  node [shape=box];\n\n"

        // 添加节点
        for (taskId, task) in nodes {
            let label = task.description.prefix(30)
            let color = colorForStatus(task.status)
            dot += "  \"\(taskId)\" [label=\"\(label)\", fillcolor=\"\(color)\", style=filled];\n"
        }

        dot += "\n"

        // 添加边
        for (from, tos) in edges {
            for to in tos {
                dot += "  \"\(from)\" -> \"\(to)\";\n"
            }
        }

        dot += "}\n"
        return dot
    }

    private func colorForStatus(_ status: DecomposedTaskStatus) -> String {
        switch status {
        case .pending: return "lightgray"
        case .ready: return "lightblue"
        case .assigned: return "lightcyan"
        case .inProgress: return "lightyellow"
        case .completed: return "lightgreen"
        case .failed: return "lightcoral"
        case .blocked: return "orange"
        case .cancelled: return "gray"
        }
    }
}

// MARK: - 辅助结构

/// 图统计信息
struct GraphStatistics {
    let taskCount: Int
    let edgeCount: Int
    let hasCycles: Bool
    let cycleCount: Int
    let criticalPathLength: Int
    let maxLevel: Int

    var averageDependencies: Double {
        guard taskCount > 0 else { return 0 }
        return Double(edgeCount) / Double(taskCount)
    }
}
