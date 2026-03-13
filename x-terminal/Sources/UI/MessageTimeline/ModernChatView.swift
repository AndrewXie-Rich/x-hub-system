import SwiftUI

/// 新的聊天视图，使用现代化的消息时间线
struct ModernChatView: View {
    let ctx: AXProjectContext
    let memory: AXMemory?
    let config: AXProjectConfig?
    let hubConnected: Bool
    @ObservedObject var session: ChatSessionModel
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            projectRuntimeSection

            Divider()

            ZStack(alignment: .bottom) {
                // 背景
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()

                // 消息时间线
                MessageTimelineView(
                    ctx: ctx,
                    session: session,
                    bottomPadding: session.pendingToolCalls.isEmpty ? 24 : 160
                )

                // 待审批工具浮动卡片
                if !session.pendingToolCalls.isEmpty {
                    VStack {
                        Spacer()
                        PendingToolApprovalView(
                            session: session,
                            hubConnected: hubConnected,
                            onApprove: {
                                session.approvePendingTools(router: appModel.llmRouter)
                            },
                            onReject: {
                                session.rejectPendingTools()
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                DockInputView(
                    ctx: ctx,
                    memory: memory,
                    config: config,
                    hubConnected: hubConnected,
                    session: session
                )
                .environmentObject(appModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            session.ensureLoaded(ctx: ctx, limit: 200)
        }
        .onChange(of: ctx.root.path) { _ in
            session.ensureLoaded(ctx: ctx, limit: 200)
        }
    }

    private var projectRuntimeSection: some View {
        let snapshots = AXRoleExecutionSnapshots.latestSnapshots(for: ctx)
        let coderSnapshot = snapshots[.coder] ?? .empty(role: .coder)
        let configuredModelId = AXRoleExecutionSnapshots.configuredModelId(
            for: .coder,
            projectConfig: config,
            settings: appModel.settingsStore.settings
        )
        let tooltip = ExecutionRoutePresentation.tooltip(
            configuredModelId: configuredModelId,
            snapshot: coderSnapshot
        )
        let statusColor = ExecutionRoutePresentation.statusColor(snapshot: coderSnapshot)

        return HStack(spacing: 8) {
            Image(systemName: "hammer.circle.fill")
                .foregroundColor(.blue)
                .font(.system(size: 14))

            Text(ctx.projectName())
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("Coder (\(ExecutionRoutePresentation.activeModelLabel(configuredModelId: configuredModelId, snapshot: coderSnapshot)))")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .help(tooltip)

            Text(ExecutionRoutePresentation.statusText(snapshot: coderSnapshot))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
                .help(tooltip)
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

}

/// 预览
#if DEBUG
struct ModernChatView_Previews: PreviewProvider {
    static var previews: some View {
        let ctx = AXProjectContext(
            root: URL(fileURLWithPath: "/tmp/test")
        )
        let session = ChatSessionModel()

        // 添加示例消息
        session.messages = [
            AXChatMessage(role: .user, content: "Hello, can you help me with this code?", createdAt: Date().timeIntervalSince1970 - 300),
            AXChatMessage(role: .assistant, tag: "claude-3.5", content: "Of course! I'd be happy to help. What would you like to know?", createdAt: Date().timeIntervalSince1970 - 280),
            AXChatMessage(role: .user, content: "Can you read the main.swift file?", createdAt: Date().timeIntervalSince1970 - 200),
            AXChatMessage(role: .assistant, tag: "claude-3.5", content: "I'll read that file for you.", createdAt: Date().timeIntervalSince1970 - 180),
        ]

        return ModernChatView(
            ctx: ctx,
            memory: nil,
            config: nil,
            hubConnected: true,
            session: session
        )
        .environmentObject(AppModel())
        .frame(width: 1000, height: 700)
    }
}
#endif
