//
//  SupervisorStatusBar.swift
//  XTerminal
//
//

import SwiftUI

/// Supervisor 状态栏
/// 显示在窗口顶部，提供 Supervisor 状态和项目统计信息
struct SupervisorStatusBar: View {
    @ObservedObject var supervisor: SupervisorModel
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var supervisorManager = SupervisorManager.shared

    var body: some View {
        HStack(spacing: 16) {
            // 左侧: Supervisor 信息
            supervisorInfo

            Spacer()

            // 右侧: 项目统计
            projectStatistics

            // 快速操作按钮
            quickActions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.secondary.opacity(0.2)),
            alignment: .bottom
        )
    }

    // MARK: - Subviews

    private var supervisorInfo: some View {
        let snapshot = supervisorExecutionSnapshot
        let tooltip = ExecutionRoutePresentation.tooltip(
            configuredModelId: configuredSupervisorModelId,
            snapshot: snapshot
        )
        let statusColor = supervisorStatusColor(snapshot: snapshot)
        let pendingMemoryFollowUpQuestion = supervisorManager.supervisorPendingMemoryFactFollowUpQuestion
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.purple)
                .font(.system(size: 14))

            Text("Supervisor · \(ExecutionRoutePresentation.activeModelLabel(configuredModelId: configuredSupervisorModelId, snapshot: snapshot))")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .help(tooltip)

            Text(supervisorStatusText(snapshot: snapshot))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
                .help(tooltip)

            if !supervisor.memorySize.isEmpty && supervisor.memorySize != "0GB" {
                Label(supervisor.memorySize, systemImage: "internaldrive")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if !pendingMemoryFollowUpQuestion.isEmpty {
                Label("待补背景", systemImage: "text.bubble.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                    .help(pendingMemoryFollowUpQuestion)
            }
        }
    }

    private var configuredSupervisorModelId: String {
        let configured = appModel.settingsStore.settings.assignment(for: .supervisor).model?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured
    }

    private var supervisorExecutionSnapshot: AXRoleExecutionSnapshot {
        ExecutionRoutePresentation.supervisorSnapshot(from: supervisorManager)
    }

    private func supervisorStatusText(snapshot: AXRoleExecutionSnapshot) -> String {
        if snapshot.executionPath == "no_record" && !appModel.hubInteractive {
            return "Hub 关闭"
        }
        return ExecutionRoutePresentation.statusText(snapshot: snapshot)
    }

    private func supervisorStatusColor(snapshot: AXRoleExecutionSnapshot) -> Color {
        if snapshot.executionPath == "no_record" && !appModel.hubInteractive {
            return .red
        }
        return ExecutionRoutePresentation.statusColor(snapshot: snapshot)
    }

    private var projectStatistics: some View {
        HStack(spacing: 12) {
            StatusBadge(
                icon: "chart.bar",
                label: "活跃",
                count: supervisor.activeProjects.count,
                total: supervisor.totalProjectsCount,
                color: .blue
            )

            if supervisor.pendingApprovals > 0 {
                StatusBadge(
                    icon: "bolt",
                    label: "待授权",
                    count: supervisor.pendingApprovals,
                    color: .orange
                )
            }

            if supervisor.needsAttention > 0 {
                StatusBadge(
                    icon: "exclamationmark.triangle",
                    label: "需关注",
                    count: supervisor.needsAttention,
                    color: .red
                )
            }

            StatusBadge(
                icon: "checkmark.circle",
                label: "完成",
                count: supervisor.completedProjects.count,
                color: .green
            )
        }
        .font(.system(size: 11))
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button(action: {
                supervisorManager.requestSupervisorWindow(reason: "status_bar")
            }) {
                Image(systemName: "message.circle.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .help("打开 Supervisor 窗口 (⌘⇧S)")
        }
    }
}

/// 状态徽章
struct StatusBadge: View {
    let icon: String
    var label: String? = nil
    var count: Int
    var total: Int? = nil
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)

            if let total = total {
                Text("\(count)/\(total)")
                    .foregroundColor(.primary)
            } else {
                Text("\(count)")
                    .foregroundColor(.primary)
            }
        }
        .help(label ?? "")
    }
}

// MARK: - Preview

#if DEBUG
struct SupervisorStatusBar_Previews: PreviewProvider {
    static var previews: some View {
        SupervisorStatusBar(supervisor: SupervisorModel.preview)
            .environmentObject(AppModel())
            .frame(height: 40)
    }
}
#endif
