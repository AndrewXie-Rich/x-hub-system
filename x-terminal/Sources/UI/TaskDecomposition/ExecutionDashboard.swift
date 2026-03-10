import SwiftUI

/// 执行监控面板 - 实时监控任务执行状态
struct ExecutionDashboard: View {
    @ObservedObject var monitor: ExecutionMonitor
    @State private var selectedTask: UUID?
    @State private var showTaskDetail = false
    @State private var autoRefresh = true
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // 顶部统计栏
            statisticsHeader

            Divider()

            // 主内容区域
            HSplitView {
                // 左侧：任务列表
                taskListSection
                    .frame(minWidth: 300, idealWidth: 400)

                // 右侧：详情和图表
                VStack(spacing: 0) {
                    if let taskId = selectedTask,
                       let state = monitor.taskStates[taskId] {
                        taskDetailSection(state)
                    } else {
                        emptyDetailView
                    }
                }
                .frame(minWidth: 400)
            }

            Divider()

            // 底部控制栏
            controlBar
        }
        .onAppear {
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - 统计头部

    private var statisticsHeader: some View {
        let report = monitor.generateReport()

        return HStack(spacing: 24) {
            // 总任务数
            statCard(
                title: "总任务",
                value: "\(report.totalTasks)",
                icon: "list.bullet",
                color: .blue
            )

            Divider()
                .frame(height: 40)

            // 进行中
            statCard(
                title: "进行中",
                value: "\(report.inProgressTasks)",
                icon: "arrow.clockwise",
                color: .purple
            )

            Divider()
                .frame(height: 40)

            // 已完成
            statCard(
                title: "已完成",
                value: "\(report.completedTasks)",
                icon: "checkmark.circle.fill",
                color: .green
            )

            Divider()
                .frame(height: 40)

            // 失败
            statCard(
                title: "失败",
                value: "\(report.failedTasks)",
                icon: "xmark.circle.fill",
                color: .red
            )

            Divider()
                .frame(height: 40)

            // 平均进度
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.orange)
                    Text("平均进度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text("\(Int(report.averageProgress * 100))%")
                        .font(.title3)
                        .fontWeight(.semibold)

                    ProgressView(value: report.averageProgress)
                        .frame(width: 80)
                }
            }

            Spacer()

            // 预计完成时间
            if let completion = report.estimatedCompletion {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("预计完成")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(completion, style: .relative)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - 任务列表

    private var taskListSection: some View {
        VStack(spacing: 0) {
            // 列表头部
            HStack {
                Text("执行中的任务")
                    .font(.headline)

                Spacer()

                Text("\(monitor.taskStates.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 任务列表
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(monitor.taskStates.values.sorted(by: { $0.startedAt > $1.startedAt })), id: \.task.id) { state in
                        taskRow(state)
                            .background(selectedTask == state.task.id ? Color.accentColor.opacity(0.1) : Color.clear)
                            .onTapGesture {
                                selectedTask = state.task.id
                            }

                        Divider()
                    }
                }
            }
        }
    }

    private func taskRow(_ state: TaskExecutionState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 任务描述
            HStack {
                Image(systemName: state.task.type.icon)
                    .foregroundColor(Color(state.task.type.color))

                Text(state.task.description)
                    .font(.body)
                    .lineLimit(2)

                Spacer()

                // 状态图标
                Image(systemName: state.currentStatus.icon)
                    .foregroundColor(Color(state.currentStatus.color))
            }

            // 进度条
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(Int(state.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(formatElapsedTime(state.startedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: state.progress)
                    .tint(progressColor(state.progress))
            }

            // 错误提示
            if !state.errors.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)

                    Text("\(state.errors.count) 个错误")
                        .font(.caption)
                        .foregroundColor(.red)

                    if state.attempts > 1 {
                        Text("• 第 \(state.attempts) 次尝试")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - 任务详情

    private func taskDetailSection(_ state: TaskExecutionState) -> some View {
        VStack(spacing: 0) {
            // 详情头部
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.task.description)
                        .font(.headline)

                    HStack(spacing: 12) {
                        Label(state.task.type.rawValue, systemImage: state.task.type.icon)
                            .font(.caption)
                            .foregroundColor(Color(state.task.type.color))

                        Label(state.task.complexity.rawValue, systemImage: "gauge")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(state.currentStatus.rawValue, systemImage: state.currentStatus.icon)
                            .font(.caption)
                            .foregroundColor(Color(state.currentStatus.color))
                    }
                }

                Spacer()

                Button {
                    showTaskDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 进度详情
                    progressSection(state)

                    Divider()

                    // 时间信息
                    timeSection(state)

                    Divider()

                    // 执行日志
                    logsSection(state)

                    // 错误信息
                    if !state.errors.isEmpty {
                        Divider()
                        errorsSection(state)
                    }
                }
                .padding(16)
            }
        }
    }

    private func progressSection(_ state: TaskExecutionState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("执行进度")
                .font(.headline)

            // 大进度条
            VStack(spacing: 8) {
                HStack {
                    Text("\(Int(state.progress * 100))%")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(progressColor(state.progress))

                    Spacer()

                    if state.progress < 1.0 {
                        Text("预计剩余: \(estimateRemainingTime(state))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: state.progress)
                    .scaleEffect(y: 2)
                    .tint(progressColor(state.progress))
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func timeSection(_ state: TaskExecutionState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("时间信息")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                timeCard(
                    title: "开始时间",
                    value: formatDate(state.startedAt),
                    icon: "play.circle"
                )

                timeCard(
                    title: "已用时间",
                    value: formatElapsedTime(state.startedAt),
                    icon: "clock"
                )

                timeCard(
                    title: "预计时长",
                    value: formatDuration(state.task.estimatedEffort),
                    icon: "hourglass"
                )

                timeCard(
                    title: "最后更新",
                    value: formatRelativeTime(state.lastUpdateAt),
                    icon: "arrow.clockwise"
                )
            }
        }
    }

    private func timeCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.accentColor)

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

    private func logsSection(_ state: TaskExecutionState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("执行日志")
                    .font(.headline)

                Spacer()

                Text("\(state.logs.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.logs.reversed(), id: \.self) { log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
            }
            .frame(maxHeight: 200)
        }
    }

    private func errorsSection(_ state: TaskExecutionState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)

                Text("错误信息")
                    .font(.headline)

                Spacer()

                Text("\(state.errors.count) 个错误")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            ForEach(state.errors) { error in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(formatDate(error.timestamp))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if error.recoverable {
                            Text("可恢复")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        } else {
                            Text("不可恢复")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                        }
                    }

                    Text(error.message)
                        .font(.body)
                        .foregroundColor(.red)

                    if let code = error.code {
                        Text("错误代码: \(code)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - 空详情视图

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("选择一个任务查看详情")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 控制栏

    private var controlBar: some View {
        HStack {
            // 自动刷新开关
            Toggle("自动刷新", isOn: $autoRefresh)
                .onChange(of: autoRefresh) { enabled in
                    if enabled {
                        startAutoRefresh()
                    } else {
                        stopAutoRefresh()
                    }
                }

            Spacer()

            // 手动刷新按钮
            Button {
                // 刷新数据
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            // 导出报告
            Button {
                exportReport()
            } label: {
                Label("导出报告", systemImage: "square.and.arrow.up")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 辅助方法

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            // 触发视图更新
            Task { @MainActor [monitor] in
                monitor.objectWillChange.send()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func exportReport() {
        let report = monitor.generateReport()
        print(report.description)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatElapsedTime(_ startDate: Date) -> String {
        let elapsed = Date().timeIntervalSince(startDate)
        let hours = Int(elapsed / 3600)
        let minutes = Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(elapsed.truncatingRemainder(dividingBy: 60))

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
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

    private func estimateRemainingTime(_ state: TaskExecutionState) -> String {
        let elapsed = Date().timeIntervalSince(state.startedAt)
        let estimated = state.task.estimatedEffort
        let remaining = max(0, estimated - elapsed)
        return formatDuration(remaining)
    }

    private func progressColor(_ progress: Double) -> Color {
        if progress < 0.3 {
            return .red
        } else if progress < 0.7 {
            return .orange
        } else {
            return .green
        }
    }
}
