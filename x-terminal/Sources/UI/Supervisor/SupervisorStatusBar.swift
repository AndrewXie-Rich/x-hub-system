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
            SupervisorChatWindow()
                .environmentObject(appModel)
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

            Text("(\(supervisorRouteLabel))")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .help(supervisorRouteTooltip)

            HStack(spacing: 4) {
                Circle()
                    .fill(supervisorAvailability.color)
                    .frame(width: 8, height: 8)

                Text(supervisorAvailability.label)
                    .font(.system(size: 11))
                    .foregroundColor(supervisorAvailability.color)
            }

            if !supervisor.memorySize.isEmpty && supervisor.memorySize != "0GB" {
                Label(supervisor.memorySize, systemImage: "internaldrive")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var configuredSupervisorModelId: String {
        let configured = appModel.settingsStore.settings.assignment(for: .supervisor).model?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured
    }

    private var lastActualSupervisorModelId: String {
        supervisorManager.lastSupervisorActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var supervisorRouteLabel: String {
        let configured = configuredSupervisorModelId
        let actual = lastActualSupervisorModelId

        if !actual.isEmpty, !configured.isEmpty, normalizedModelIdentity(actual) != normalizedModelIdentity(configured) {
            return "cfg \(shortModelLabel(configured)) / actual \(shortModelLabel(actual))"
        }
        if !actual.isEmpty {
            return shortModelLabel(actual)
        }
        if !configured.isEmpty {
            return shortModelLabel(configured)
        }
        return "default hub route"
    }

    private var supervisorRouteTooltip: String {
        let configured = configuredSupervisorModelId
        let actual = lastActualSupervisorModelId
        let mode = supervisorManager.lastSupervisorReplyExecutionMode.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("configured=\(configured.isEmpty ? "default_hub_route" : configured)")
        if !actual.isEmpty {
            lines.append("last_actual=\(actual)")
        }
        if !mode.isEmpty {
            lines.append("last_mode=\(mode)")
        }
        lines.append("transport=\(HubAIClient.transportMode().rawValue)")
        return lines.joined(separator: "\n")
    }

    private var supervisorAvailability: (label: String, color: Color) {
        if appModel.hubInteractive {
            return ("Hub 可达", .green)
        }

        switch supervisorManager.lastSupervisorReplyExecutionMode {
        case "local_direct_reply", "local_direct_action", "local_preflight", "local_fallback_after_remote_error":
            return ("本地可用", .orange)
        default:
            return ("Hub 未连通", .red)
        }
    }

    private func shortModelLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "default hub route" }
        if trimmed.count <= 30 {
            return trimmed
        }
        if let slash = trimmed.lastIndex(of: "/") {
            let suffix = trimmed[trimmed.index(after: slash)...]
            if suffix.count <= 30 {
                return String(suffix)
            }
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 30)
        return String(trimmed[..<end]) + "..."
    }

    private func normalizedModelIdentity(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
            .environmentObject(AppModel())
            .frame(height: 40)
    }
}
#endif
