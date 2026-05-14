//
//  SupervisorStatusBar.swift
//  XTerminal
//
//

import Combine
import SwiftUI

/// Supervisor 状态栏
/// 显示在窗口顶部，按需激活 Supervisor，避免启动期立刻拉起完整后台服务。
struct SupervisorStatusBar: View {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore
    @StateObject private var runtime = SupervisorStatusBarRuntime()

    var body: some View {
        Group {
            if let supervisorManager = runtime.supervisorManager {
                SupervisorStatusBarActiveView(
                    supervisorManager: supervisorManager,
                    configuredSupervisorModelId: configuredSupervisorModelId
                )
            } else {
                SupervisorStatusBarColdStartView(
                    configuredSupervisorModelId: configuredSupervisorModelId,
                    hubInteractive: hubInteractive,
                    onOpenSupervisor: {
                        let manager = runtime.activate(with: appModel)
                        manager.requestSupervisorWindow(reason: "status_bar")
                    }
                )
            }
        }
    }

    private var configuredSupervisorModelId: String {
        let configured = appModel.settingsStore.settings.assignment(for: .supervisor).model?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured
    }

    private var hubInteractive: Bool {
        hubConnectionStore.snapshot.interactive
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("SupervisorStatusBar requires xtAppModelReference")
        }
        return appModelReference
    }
}

@MainActor
private final class SupervisorStatusBarRuntime: ObservableObject {
    @Published fileprivate var supervisorManager: SupervisorManager?

    private var cancellables = Set<AnyCancellable>()

    init() {
        supervisorManager = SupervisorManager.sharedIfInitialized
        NotificationCenter.default.publisher(for: SupervisorManager.didInitializeNotification)
            .compactMap { $0.object as? SupervisorManager }
            .sink { [weak self] manager in
                self?.supervisorManager = manager
            }
            .store(in: &cancellables)
    }

    func activate(with appModel: AppModel) -> SupervisorManager {
        let manager = SupervisorManager.shared
        manager.attachAppModelIfNeeded(appModel)
        supervisorManager = manager
        return manager
    }
}

private struct SupervisorStatusBarColdStartView: View {
    let configuredSupervisorModelId: String
    let hubInteractive: Bool
    let onOpenSupervisor: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                    .font(.system(size: 14))

                Text("Supervisor · \(configuredSupervisorLabel)")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(hubInteractive ? "按需加载" : "Hub 关闭")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(hubInteractive ? .secondary : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((hubInteractive ? Color.secondary : Color.red).opacity(0.12))
                    .clipShape(Capsule())
                    .help("启动期不自动拉起 Supervisor 后台轮询；打开 Supervisor 窗口后再接管。")
            }

            Spacer()

            Button(action: onOpenSupervisor) {
                Image(systemName: "message.circle.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .help("打开 Supervisor 窗口 (⌘⇧S)")
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

    private var configuredSupervisorLabel: String {
        ExecutionRoutePresentation.configuredModelLabel(
            configuredModelId: configuredSupervisorModelId,
            snapshot: AXRoleExecutionSnapshot.empty(role: .supervisor)
        )
    }
}

/// Supervisor 状态栏完整视图
/// 仅在 Supervisor 已经初始化后显示完整状态，避免应用启动时立刻拉起后台服务。
private struct SupervisorStatusBarActiveView: View {
    let supervisorManager: SupervisorManager
    let configuredSupervisorModelId: String
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore
    @EnvironmentObject private var globalHomeStore: XTGlobalHomeStore
    @StateObject private var statusStore = XTSupervisorStatusBarStore()

    var body: some View {
        HStack(spacing: 16) {
            supervisorInfo

            Spacer()

            projectStatistics

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
        .onAppear {
            statusStore.bind(to: supervisorManager)
        }
        .onChange(of: supervisorIdentity) { _ in
            statusStore.bind(to: supervisorManager)
        }
    }

    // MARK: - Subviews

    private var supervisorInfo: some View {
        let snapshot = statusSnapshot.executionSnapshot
        let tooltip = ExecutionRoutePresentation.tooltip(
            configuredModelId: configuredSupervisorModelId,
            snapshot: snapshot,
            paidAccessSnapshot: globalHomeStore.snapshot.remotePaidAccessSnapshot
        )
        let statusColor = supervisorStatusColor(snapshot: snapshot)
        let detailBadge = ExecutionRoutePresentation.detailBadge(
            configuredModelId: configuredSupervisorModelId,
            snapshot: snapshot
        )
        let interpretationBadge = ExecutionRoutePresentation.interpretationBadge(
            configuredModelId: configuredSupervisorModelId,
            snapshot: snapshot
        )
        let pendingMemoryFollowUpQuestion = statusSnapshot.pendingMemoryFollowUpQuestion

        return HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.purple)
                .font(.system(size: 14))

            Text("Supervisor · \(ExecutionRoutePresentation.configuredModelLabel(configuredModelId: configuredSupervisorModelId, snapshot: snapshot))")
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

            if let detailBadge {
                Text(detailBadge.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(detailBadge.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(detailBadge.color.opacity(0.12))
                    .clipShape(Capsule())
                    .lineLimit(1)
                    .help(tooltip)
            }

            if let interpretationBadge {
                Text(interpretationBadge.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(interpretationBadge.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(interpretationBadge.color.opacity(0.12))
                    .clipShape(Capsule())
                    .lineLimit(1)
                    .help(tooltip)
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

    private var supervisorIdentity: ObjectIdentifier {
        ObjectIdentifier(supervisorManager)
    }

    private func supervisorStatusText(snapshot: AXRoleExecutionSnapshot) -> String {
        if snapshot.executionPath == "no_record" && !hubInteractive {
            return "Hub 关闭"
        }
        return ExecutionRoutePresentation.statusText(snapshot: snapshot)
    }

    private func supervisorStatusColor(snapshot: AXRoleExecutionSnapshot) -> Color {
        if snapshot.executionPath == "no_record" && !hubInteractive {
            return .red
        }
        return ExecutionRoutePresentation.statusColor(snapshot: snapshot)
    }

    private var projectStatistics: some View {
        HStack(spacing: 12) {
            StatusBadge(
                icon: "chart.bar",
                label: "活跃",
                count: statusSnapshot.activeProjectCount,
                total: statusSnapshot.totalProjectCount,
                color: .blue
            )

            if statusSnapshot.pendingWorkCount > 0 {
                StatusBadge(
                    icon: "bolt",
                    label: "待处理",
                    count: statusSnapshot.pendingWorkCount,
                    color: .orange
                )
            }

            if statusSnapshot.blockedProjectCount > 0 {
                StatusBadge(
                    icon: "exclamationmark.triangle",
                    label: "阻塞",
                    count: statusSnapshot.blockedProjectCount,
                    color: .red
                )
            }

            StatusBadge(
                icon: "checkmark.circle",
                label: "完成",
                count: statusSnapshot.completedProjectCount,
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

    private var statusSnapshot: XTSupervisorStatusBarSnapshot {
        statusStore.snapshot
    }

    private var hubInteractive: Bool {
        hubConnectionStore.snapshot.interactive
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
        let appModel = AppModel()
        SupervisorStatusBar()
            .environment(\.xtAppModelReference, appModel)
            .environmentObject(appModel.hubConnectionStore)
            .environmentObject(appModel.globalHomeStore)
            .frame(height: 40)
    }
}
#endif
