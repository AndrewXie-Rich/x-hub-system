import SwiftUI

/// 任务分解视图 - 用于输入任务并查看分解结果
struct TaskDecompositionView: View {
    @ObservedObject var orchestrator: SupervisorOrchestrator
    @Environment(\.dismiss) private var dismiss

    @State private var taskDescription: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var decompositionResult: DecompositionResult?
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            titleBar

            Divider()

            // 主内容
            ScrollView {
                VStack(spacing: 24) {
                    // 输入区域
                    inputSection

                    // 分解结果
                    if let result = decompositionResult {
                        resultSection(result)
                    }
                }
                .padding(24)
            }

            Divider()

            // 底部操作栏
            bottomBar
        }
        .frame(width: 900, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 标题栏

    private var titleBar: some View {
        HStack {
            Image(systemName: "scissors")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("任务自动分解")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - 输入区域

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("任务描述", systemImage: "text.alignleft")
                    .font(.headline)

                Spacer()

                Text("\(taskDescription.count) 字符")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $taskDescription)
                .font(.body)
                .frame(minHeight: 120, maxHeight: 200)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            // 提示信息
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)

                Text("详细描述任务可以获得更准确的分解结果。包括任务目标、约束条件、技术要求等。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(8)

            // 分解按钮
            Button {
                Task {
                    await analyzeTask()
                }
            } label: {
                HStack {
                    if isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }

                    Text(isAnalyzing ? "分析中..." : "分析并分解任务")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)
        }
    }

    // MARK: - 结果区域

    private func resultSection(_ result: DecompositionResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // 分析摘要
            analysisSummary(result.analysis)

            Divider()

            // 子任务列表
            if result.hasSubtasks {
                subtasksList(result)

                Divider()

                // 依赖关系图
                dependencyGraphSection(result)

                Divider()

                // 执行计划
                executionPlanSection(result)
            } else {
                noSubtasksMessage
            }
        }
    }

    // MARK: - 分析摘要

    private func analysisSummary(_ analysis: TaskAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("分析结果", systemImage: "chart.bar.doc.horizontal")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                summaryCard(
                    title: "任务类型",
                    value: analysis.type.rawValue,
                    icon: analysis.type.icon,
                    color: Color(analysis.type.color)
                )

                summaryCard(
                    title: "复杂度",
                    value: analysis.complexity.rawValue,
                    icon: "gauge.medium",
                    color: complexityColor(analysis.complexity)
                )

                summaryCard(
                    title: "风险等级",
                    value: analysis.riskLevel.rawValue,
                    icon: "exclamationmark.triangle",
                    color: Color(analysis.riskLevel.color)
                )

                summaryCard(
                    title: "预计工作量",
                    value: formatDuration(analysis.estimatedEffort),
                    icon: "clock",
                    color: .blue
                )

                summaryCard(
                    title: "所需技能",
                    value: "\(analysis.requiredSkills.count) 项",
                    icon: "star",
                    color: .purple
                )

                summaryCard(
                    title: "关键词",
                    value: "\(analysis.keywords.count) 个",
                    icon: "tag",
                    color: .orange
                )
            }

            // 所需技能详情
            if !analysis.requiredSkills.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("所需技能:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(analysis.requiredSkills, id: \.self) { skill in
                            Text(skill)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundColor(.accentColor)
                                .cornerRadius(12)
                        }
                    }
                }
            }
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 子任务列表

    private func subtasksList(_ result: DecompositionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("子任务列表", systemImage: "list.bullet")
                    .font(.headline)

                Spacer()

                Text("\(result.subtasks.count) 个子任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(result.subtasks.enumerated()), id: \.element.id) { index, task in
                subtaskCard(task, index: index + 1)
            }
        }
    }

    private func subtaskCard(_ task: DecomposedTask, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 序号
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 32, height: 32)

                Text("\(index)")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                // 任务描述
                Text(task.description)
                    .font(.body)

                // 任务属性
                HStack(spacing: 12) {
                    taskAttribute(icon: task.type.icon, text: task.type.rawValue, color: Color(task.type.color))
                    taskAttribute(icon: "gauge", text: task.complexity.rawValue, color: complexityColor(task.complexity))
                    taskAttribute(icon: "clock", text: formatDuration(task.estimatedEffort), color: .blue)
                    taskAttribute(icon: "flag", text: "优先级 \(task.priority)", color: .orange)
                }

                // 依赖关系
                if !task.dependencies.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("依赖 \(task.dependencies.count) 个任务")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func taskAttribute(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 依赖关系图

    private func dependencyGraphSection(_ result: DecompositionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("依赖关系", systemImage: "arrow.triangle.branch")
                .font(.headline)

            let stats = result.dependencyGraph.getStatistics()

            HStack(spacing: 16) {
                statItem(label: "任务数", value: "\(stats.taskCount)")
                statItem(label: "依赖关系", value: "\(stats.edgeCount)")
                statItem(label: "最大层级", value: "\(stats.maxLevel)")
                statItem(label: "关键路径", value: "\(stats.criticalPathLength)")

                if stats.hasCycles {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("检测到循环依赖")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            // 简化的依赖关系可视化
            if stats.edgeCount > 0 {
                dependencyVisualization(result.dependencyGraph)
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
    }

    private func dependencyVisualization(_ graph: DependencyGraph) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let levels = graph.calculateLevels()
            let maxLevel = levels.values.max() ?? 0

            ForEach(0...maxLevel, id: \.self) { level in
                let tasksAtLevel = levels.filter { $0.value == level }.map { $0.key }

                if !tasksAtLevel.isEmpty {
                    HStack(spacing: 8) {
                        Text("Level \(level)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)

                        FlowLayout(spacing: 8) {
                            ForEach(tasksAtLevel, id: \.self) { taskId in
                                if let task = graph.getTask(taskId) {
                                    Text(task.description.prefix(20))
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - 执行计划

    private func executionPlanSection(_ result: DecompositionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("执行计划", systemImage: "calendar.badge.clock")
                .font(.headline)

            let parallelGroups = result.parallelGroups

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("可并行执行的任务组:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(parallelGroups.count) 个阶段")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(parallelGroups.enumerated()), id: \.offset) { index, group in
                    HStack(alignment: .top, spacing: 12) {
                        Text("阶段 \(index + 1)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                            .frame(width: 60, alignment: .leading)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(group.count) 个任务可并行执行")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            FlowLayout(spacing: 6) {
                                ForEach(group, id: \.self) { taskId in
                                    if let task = result.allTasks.first(where: { $0.id == taskId }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: task.type.icon)
                                                .font(.caption2)

                                            Text(task.description.prefix(15))
                                                .font(.caption2)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }

                // 总预计时间
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.blue)

                    Text("总预计工作量:")
                        .font(.subheadline)

                    Text(formatDuration(result.totalEstimatedEffort))
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    if parallelGroups.count > 1 {
                        Text("(可并行执行)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - 无子任务消息

    private var noSubtasksMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("任务无需拆分")
                .font(.headline)

            Text("该任务复杂度较低，可以直接执行，无需拆分为子任务。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - 底部操作栏

    private var bottomBar: some View {
        HStack {
            Button("清除") {
                taskDescription = ""
                decompositionResult = nil
            }
            .disabled(taskDescription.isEmpty && decompositionResult == nil)

            Spacer()

            if decompositionResult != nil {
                Button("导出结果") {
                    exportResult()
                }

                Button("开始执行") {
                    Task {
                        await executeDecomposedTasks()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Button("关闭") {
                dismiss()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - 辅助方法

    private func analyzeTask() async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let result = await orchestrator.handleNewTask(taskDescription)
        decompositionResult = result
    }

    private func executeDecomposedTasks() async {
        // 实现执行逻辑
        dismiss()
    }

    private func exportResult() {
        // 实现导出逻辑
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func complexityColor(_ complexity: DecomposedTaskComplexity) -> Color {
        switch complexity {
        case .trivial: return .green
        case .simple: return .blue
        case .moderate: return .orange
        case .complex: return .red
        case .veryComplex: return .purple
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
