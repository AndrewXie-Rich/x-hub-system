//
//  ProjectDetailView.swift
//  XTerminal
//
//  项目详情视图
//

import SwiftUI

/// 项目详情视图
struct ProjectDetailView: View {
    @ObservedObject var project: ProjectModel
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            titleBar

            Divider()

            // 内容区域
            ScrollView {
                VStack(spacing: 20) {
                    // 基本信息
                    basicInfoSection

                    Divider()

                    // 状态和进度
                    statusSection

                    Divider()

                    // 模型和配置
                    modelSection

                    Divider()

                    // 成本和预算
                    costSection

                    Divider()

                    // 协作信息
                    collaborationSection

                    Divider()

                    // 时间线
                    timelineSection

                    Divider()

                    // 危险操作
                    dangerZoneSection
                }
                .padding(20)
            }

            Divider()

            // 底部按钮
            bottomBar
        }
        .frame(width: 700, height: 800)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "确认删除项目",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                deleteProject()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除项目 \"\(project.name)\" 将无法恢复。确定要继续吗？")
        }
    }

    // MARK: - Subviews

    private var titleBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // 状态指示器
                Circle()
                    .fill(project.statusColor)
                    .frame(width: 12, height: 12)

                Text(project.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }

            ProjectGovernanceBadge(presentation: governancePresentation, compact: true)
        }
        .padding()
    }

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基本信息")
                .font(.headline)

            InfoRow(label: "项目 ID", value: project.id.uuidString)
            InfoRow(label: "任务描述", value: project.taskDescription)
            InfoRow(label: "创建时间", value: formatDate(project.createdAt))
            InfoRow(label: "最后活动", value: project.lastActivityTime)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("状态和进度")
                .font(.headline)

            // 状态卡片
            HStack(spacing: 16) {
                StatusCard(
                    icon: project.primaryStatusIcon,
                    label: "状态",
                    value: project.status.text,
                    color: project.statusColor
                )

                StatusCard(
                    icon: "message",
                    label: "消息",
                    value: "\(project.messageCount)",
                    color: .blue
                )

                if project.pendingApprovals > 0 {
                    StatusCard(
                        icon: "bolt",
                        label: "待授权",
                        value: "\(project.pendingApprovals)",
                        color: .orange
                    )
                }
            }

            // 优先级
            HStack {
                Text("优先级")
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<10, id: \.self) { index in
                        Circle()
                            .fill(index < project.priority ? Color.blue : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模型和治理")
                .font(.headline)

            InfoRow(label: "当前模型", value: project.currentModel.displayName)
            InfoRow(label: "模型 ID", value: project.currentModel.id)
            InfoRow(label: "Execution", value: project.executionTier.displayName)
            InfoRow(label: "Supervisor", value: project.supervisorInterventionTier.displayName)
            InfoRow(label: "Review", value: project.reviewPolicyMode.displayName)
            InfoRow(
                label: "Cadence",
                value: "heartbeat \(governanceDurationLabel(project.progressHeartbeatSeconds)) · pulse \(governanceDurationLabel(project.reviewPulseSeconds)) · brainstorm \(governanceDurationLabel(project.brainstormReviewSeconds))"
            )
            InfoRow(
                label: "Guidance",
                value: "\(project.supervisorInterventionTier.defaultInterventionMode.displayName) · \(project.supervisorInterventionTier.defaultAckRequired ? "ack required" : "ack optional")"
            )

            ProjectGovernanceInspector(presentation: governancePresentation)
        }
    }

    private var costSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("成本和预算")
                .font(.headline)

            // 成本统计
            HStack(spacing: 16) {
                CostCard(
                    label: "总成本",
                    value: String(format: "$%.2f", project.costTracker.totalCost),
                    color: .green
                )

                CostCard(
                    label: "总 Tokens",
                    value: formatNumber(project.costTracker.totalTokens),
                    color: .blue
                )
            }

            // 预算信息
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("每日预算")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f", project.budget.daily))
                        .foregroundColor(.primary)
                }

                ProgressView(value: project.budget.used, total: project.budget.daily)
                    .tint(project.budget.used > project.budget.daily ? .red : .green)

                HStack {
                    Text("已使用")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f / $%.2f", project.budget.used, project.budget.daily))
                        .font(.caption)
                        .foregroundColor(project.budget.used > project.budget.daily ? .red : .secondary)
                }
            }
        }
    }

    private var collaborationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("协作信息")
                .font(.headline)

            if !project.dependencies.isEmpty {
                InfoRow(label: "依赖项目", value: "\(project.dependencies.count) 个")
            }

            if !project.dependents.isEmpty {
                InfoRow(label: "被依赖", value: "\(project.dependents.count) 个项目")
            }

            if !project.sharedKnowledge.isEmpty {
                InfoRow(label: "共享知识", value: "\(project.sharedKnowledge.count) 条")
            }

            if !project.collaboratingProjects.isEmpty {
                InfoRow(label: "协作项目", value: "\(project.collaboratingProjects.count) 个")
            }

            if project.dependencies.isEmpty && project.dependents.isEmpty &&
               project.sharedKnowledge.isEmpty && project.collaboratingProjects.isEmpty {
                Text("暂无协作信息")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("时间线")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TimelineItem(
                    icon: "plus.circle",
                    label: "创建",
                    time: formatDate(project.createdAt),
                    color: .blue
                )

                if let startTime = project.startTime {
                    TimelineItem(
                        icon: "play.circle",
                        label: "开始",
                        time: formatDate(startTime),
                        color: .green
                    )
                }

                if let pauseTime = project.pauseTime {
                    TimelineItem(
                        icon: "pause.circle",
                        label: "暂停",
                        time: formatDate(pauseTime),
                        color: .orange
                    )
                }

                if let resumeTime = project.resumeTime {
                    TimelineItem(
                        icon: "play.circle",
                        label: "恢复",
                        time: formatDate(resumeTime),
                        color: .green
                    )
                }

                if let completionTime = project.completionTime {
                    TimelineItem(
                        icon: "checkmark.circle",
                        label: "完成",
                        time: formatDate(completionTime),
                        color: .green
                    )
                }

                if let archiveTime = project.archiveTime {
                    TimelineItem(
                        icon: "archivebox",
                        label: "归档",
                        time: formatDate(archiveTime),
                        color: .secondary
                    )
                }
            }
        }
    }

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("危险操作")
                .font(.headline)
                .foregroundColor(.red)

            Button(action: { showDeleteConfirmation = true }) {
                HStack {
                    Image(systemName: "trash")
                    Text("删除项目")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // 快速操作按钮
            if project.status == .pending {
                Button("开始项目") {
                    startProject()
                }
                .buttonStyle(.borderedProminent)
            } else if project.status == .running {
                Button("暂停项目") {
                    pauseProject()
                }
                .buttonStyle(.bordered)
            } else if project.status == .paused {
                Button("恢复项目") {
                    resumeProject()
                }
                .buttonStyle(.borderedProminent)
            } else if project.status == .completed {
                Button("归档项目") {
                    archiveProject()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
    }

    // MARK: - Helper Views

    private func InfoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func startProject() {
        Task {
            await appModel.startMultiProject(project.id)
        }
    }

    private func pauseProject() {
        Task {
            await appModel.pauseMultiProject(project.id)
        }
    }

    private func resumeProject() {
        Task {
            await appModel.resumeMultiProject(project.id)
        }
    }

    private func archiveProject() {
        Task {
            await appModel.multiProjectManager.archiveProject(project.id)
        }
    }

    private func deleteProject() {
        Task {
            await appModel.deleteMultiProject(project.id)
            dismiss()
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private var governancePresentation: ProjectGovernancePresentation {
        ProjectGovernancePresentation(
            executionTier: project.executionTier,
            supervisorInterventionTier: project.supervisorInterventionTier,
            reviewPolicyMode: project.reviewPolicyMode,
            progressHeartbeatSeconds: project.progressHeartbeatSeconds,
            reviewPulseSeconds: project.reviewPulseSeconds,
            brainstormReviewSeconds: project.brainstormReviewSeconds,
            eventDrivenReviewEnabled: project.eventDrivenReviewEnabled,
            compatSource: "multi_project_detail"
        )
    }
}

/// 状态卡片
struct StatusCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 24))

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

/// 成本卡片
struct CostCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

/// 时间线项目
struct TimelineItem: View {
    let icon: String
    let label: String
    let time: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 16))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Text(time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ProjectDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let project = ProjectModel(
            name: "重构前端代码",
            taskDescription: "重构整个前端 UI 系统，使用 SwiftUI 替代 UIKit",
            modelName: "claude-opus-4.6",
            autonomyLevel: .auto
        )
        project.status = .running
        project.messageCount = 42
        project.pendingApprovals = 2
        project.priority = 7

        return ProjectDetailView(project: project)
            .environmentObject(AppModel())
    }
}
#endif
