//
//  ProjectsGridView.swift
//  XTerminal
//
//

import SwiftUI

/// 项目网格视图
/// 以网格形式展示所有项目
struct ProjectsGridView: View {
    @ObservedObject var projectsManager: MultiProjectManager
    @State private var selectedProject: ProjectModel?
    @State private var showProjectDetail = false

    let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 300), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(projectsManager.projects) { project in
                    ProjectCard(project: project)
                        .onTapGesture {
                            selectedProject = project
                            showProjectDetail = true
                        }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showProjectDetail) {
            if let project = selectedProject {
                ProjectDetailView(project: project)
            }
        }
    }
}

/// 项目卡片
struct ProjectCard: View {
    @ObservedObject var project: ProjectModel
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶部: 状态和标题
            header

            // 任务描述
            taskInfo

            Divider()

            // 模型信息
            modelInfo

            // 状态信息
            statusInfo
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(project.statusColor.opacity(0.3), lineWidth: 2)
        )
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            // 状态指示器
            Circle()
                .fill(project.statusColor)
                .frame(width: 12, height: 12)

            Text(project.name)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            // 更多菜单
            Menu {
                Button("打开") { project.open() }

                if project.status == .running {
                    Button("暂停") { project.pause() }
                } else if project.status == .paused {
                    Button("恢复") { project.resume() }
                }

                Button("设置") { project.showSettings() }

                Divider()

                if project.status == .completed {
                    Button("归档") { project.archive() }
                }

                Button("删除", role: .destructive) { project.delete() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var taskInfo: some View {
        HStack(spacing: 4) {
            Image(systemName: project.taskIcon)
                .foregroundColor(.secondary)
                .font(.caption)

            Text(project.taskDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    private var modelInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .foregroundColor(.purple)
                    .font(.caption)

                Text(project.currentModel.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }

            ModelCapabilityStrip(model: project.currentModel, limit: 4, compact: true)
        }
    }

    private var statusInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 主要状态
            HStack(spacing: 6) {
                Image(systemName: project.primaryStatusIcon)
                    .foregroundColor(project.primaryStatusColor)
                    .font(.caption)

                Text(project.primaryStatusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(project.primaryStatusColor)
            }

            // 消息数量
            HStack(spacing: 6) {
                Image(systemName: "message")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Text("\(project.messageCount) 条消息")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 最后活动时间
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Text(project.lastActivityTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 成本信息
            if project.costTracker.totalCost > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Text("$\(String(format: "%.2f", project.costTracker.totalCost))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let latestSessionSummary {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Text(latestSessionSummary.badgeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .help(latestSessionSummary.helpText)
            }

            if let registeredProjectId {
                Button("接上次进度") {
                    appModel.presentResumeBrief(projectId: registeredProjectId)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var registeredProjectId: String? {
        let projectId = project.registeredProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return projectId.isEmpty ? nil : projectId
    }

    private var latestSessionSummary: AXSessionSummaryCapsulePresentation? {
        guard let rootPath = project.registeredProjectRootPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            return nil
        }
        let ctx = AXProjectContext(root: URL(fileURLWithPath: rootPath, isDirectory: true))
        return AXSessionSummaryCapsulePresentation.load(for: ctx)
    }
}

// MARK: - Preview

#if DEBUG
struct ProjectsGridView_Previews: PreviewProvider {
    static var previews: some View {
        ProjectsGridView(projectsManager: MultiProjectManager.preview)
            .environmentObject(AppModel())
    }
}

extension MultiProjectManager {
    static var preview: MultiProjectManager {
        let supervisor = SupervisorModel.preview
        let manager = MultiProjectManager(supervisor: supervisor)

        // 添加示例项目
        Task {
            _ = await manager.createProject(ProjectConfig(
                name: "Project A",
                taskDescription: "重构前端代码",
                taskIcon: "doc.text",
                modelName: "claude-opus-4.6",
                isLocalModel: false,
                executionTier: .a3DeliverAuto,
                autoStart: true
            ))

            _ = await manager.createProject(ProjectConfig(
                name: "Project B",
                taskDescription: "修复登录 Bug",
                taskIcon: "ladybug",
                modelName: "llama-3-70b-local",
                isLocalModel: true,
                executionTier: .a1Plan,
                autoStart: false
            ))

            _ = await manager.createProject(ProjectConfig(
                name: "Project C",
                taskDescription: "写 API 文档",
                taskIcon: "doc.richtext",
                modelName: "llama-3-8b-local",
                isLocalModel: true,
                executionTier: .a2RepoAuto,
                autoStart: false
            ))
        }

        return manager
    }
}
#endif
