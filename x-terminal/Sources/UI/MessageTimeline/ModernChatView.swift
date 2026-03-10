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
        ZStack(alignment: .bottom) {
            // 背景
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            // 消息时间线
            MessageTimelineView(ctx: ctx, session: session)

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
                    .padding(.bottom, 140) // 为输入框留空间
                }
            }

            // 底部 Dock 输入框
            VStack {
                Spacer()
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
