//
//  SupervisorStatusBar.swift
//  XTerminal
//
//  Created by Claude on 2026-02-27.
//

import SwiftUI

/// Supervisor 状态栏
/// 显示在窗口顶部，提供 Supervisor 状态和项目统计信息
struct SupervisorStatusBar: View {
    @ObservedObject var supervisor: SupervisorModel
    @State private var showSupervisorChat = false

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
        .sheet(isPresented: $showSupervisorChat) {
            SupervisorChatWindow(supervisor: supervisor)
        }
    }

    // MARK: - Subviews

    private var supervisorInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.purple)
                .font(.system(size: 14))

            Text("Supervisor")
                .font(.system(size: 13, weight: .medium))

            Text("(\(supervisor.modelName))")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // 在线状态
            HStack(spacing: 4) {
                Circle()
                    .fill(supervisor.isOnline ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(supervisor.isOnline ? "在线" : "离线")
                    .font(.system(size: 11))
                    .foregroundColor(supervisor.isOnline ? .green : .red)
            }

            // 记忆大小
            if !supervisor.memorySize.isEmpty && supervisor.memorySize != "0GB" {
                Label(supervisor.memorySize, systemImage: "internaldrive")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
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
            Button(action: { showSupervisorChat.toggle() }) {
                Image(systemName: "message.circle.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .help("与 Supervisor 对话 (⌘⇧S)")
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
            .frame(height: 40)
    }
}
#endif
