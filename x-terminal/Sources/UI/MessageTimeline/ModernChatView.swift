import SwiftUI

/// 新的聊天视图，使用现代化的消息时间线
struct ModernChatView: View {
    let ctx: AXProjectContext
    let memory: AXMemory?
    let config: AXProjectConfig?
    let hubConnected: Bool
    @ObservedObject var session: ChatSessionModel
    @EnvironmentObject private var appModel: AppModel
    @State private var highlightPendingToolApprovalCard: Bool = false
    @State private var highlightedPendingToolApprovalRequestId: String?
    @State private var highlightedSkillActivityRequestId: String?
    @State private var highlightedSkillActivityFocusNonce: Int?

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
                    config: config,
                    session: session,
                    hubConnected: hubConnected,
                    onApproveSkillActivity: { requestID in
                        session.approvePendingTool(requestID: requestID, router: appModel.llmRouter)
                    },
                    onRetrySkillActivity: { item in
                        session.retryProjectSkillActivity(item, router: appModel.llmRouter)
                    },
                    onOpenGovernance: { destination in
                        appModel.requestProjectSettingsFocus(
                            projectId: projectId,
                            destination: destination
                        )
                    },
                    focusedSkillActivityRequestId: highlightedSkillActivityRequestId,
                    focusedSkillActivityNonce: highlightedSkillActivityFocusNonce,
                    bottomPadding: session.pendingToolCalls.isEmpty ? 24 : 160
                )

                // 待审批工具浮动卡片
                if !session.pendingToolCalls.isEmpty {
                    VStack {
                        Spacer()
                        PendingToolApprovalView(
                            session: session,
                            hubConnected: hubConnected,
                            isFocused: highlightPendingToolApprovalCard,
                            focusedRequestId: highlightedPendingToolApprovalRequestId,
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
        .onAppear {
            processProjectFocusRequest()
        }
        .onChange(of: appModel.projectFocusRequest?.nonce) { _ in
            processProjectFocusRequest()
        }
        .onChange(of: session.isSending) { _ in
            if !session.isSending {
                processProjectFocusRequest()
            }
        }
        .onChange(of: session.pendingToolCalls.map(\.id).joined(separator: ",")) { _ in
            if session.pendingToolCalls.isEmpty {
                highlightPendingToolApprovalCard = false
                highlightedPendingToolApprovalRequestId = nil
                highlightedSkillActivityRequestId = nil
                highlightedSkillActivityFocusNonce = nil
            } else if let focusedRequestId = highlightedPendingToolApprovalRequestId,
                      !session.pendingToolCalls.contains(where: { $0.id == focusedRequestId }) {
                highlightedPendingToolApprovalRequestId = nil
                highlightedSkillActivityRequestId = nil
                highlightedSkillActivityFocusNonce = nil
            }
            processProjectFocusRequest()
        }
    }

    private var projectId: String {
        AXProjectRegistryStore.projectId(forRoot: ctx.root)
    }

    private func processProjectFocusRequest() {
        guard let request = appModel.projectFocusRequest,
              request.projectId == projectId else {
            return
        }

        switch request.subject {
        case let .toolApproval(requestId):
            guard !session.pendingToolCalls.isEmpty else { return }
            highlightedSkillActivityFocusNonce = request.nonce

            if let requestId = requestId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !requestId.isEmpty {
                if session.pendingToolCalls.contains(where: { $0.id == requestId }) {
                    highlightPendingToolApprovalCard = true
                    highlightedPendingToolApprovalRequestId = requestId
                    highlightedSkillActivityRequestId = requestId
                    appModel.clearProjectFocusRequest(request)
                    return
                }
                highlightPendingToolApprovalCard = true
                highlightedPendingToolApprovalRequestId = nil
                highlightedSkillActivityRequestId = nil
                appModel.clearProjectFocusRequest(request)
                return
            }

            highlightPendingToolApprovalCard = true
            highlightedPendingToolApprovalRequestId = nil
            highlightedSkillActivityRequestId = nil
            appModel.clearProjectFocusRequest(request)
        case .routeDiagnose:
            guard !session.isSending else { return }
            session.presentProjectRouteDiagnosis(
                ctx: ctx,
                config: config,
                router: appModel.llmRouter
            )
            appModel.clearProjectFocusRequest(request)
        }
    }

    private var projectRuntimeSection: some View {
        let snapshots = AXRoleExecutionSnapshots.latestSnapshots(for: ctx)
        let coderSnapshot = snapshots[.coder] ?? .empty(role: .coder)
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let governancePresentation = ProjectGovernancePresentation(
            resolved: appModel.resolvedProjectGovernance(config: config)
        )
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
        let latestSessionSummary = AXSessionSummaryCapsulePresentation.load(for: ctx)
        let resumeReminder = appModel.resumeReminderPresentation(projectId: projectId)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))

                Text(ctx.displayName())
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

            ProjectGovernanceCompactSummaryView(
                presentation: governancePresentation,
                onExecutionTierTap: { openGovernance(.executionTier) },
                onSupervisorTierTap: { openGovernance(.supervisorTier) },
                onReviewCadenceTap: { openGovernance(.heartbeatReview) },
                onStatusTap: { openGovernance(.overview) },
                onCalloutTap: { openGovernance(.overview) }
            )

            HStack(spacing: 8) {
                Button {
                    session.presentProjectResumeBrief(ctx: ctx)
                } label: {
                    Label("接上次进度", systemImage: "arrow.clockwise.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(session.isSending)
                .help("基于 canonical memory、session summary 与最近执行记录，本地生成项目接续摘要；不会写入主上下文。")

                if let latestSessionSummary {
                    Text(latestSessionSummary.badgeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                        .help(latestSessionSummary.helpText)
                }

                Spacer(minLength: 0)
            }

            if let resumeReminder {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .foregroundColor(.orange)
                        .font(.system(size: 13, weight: .semibold))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("检测到最近交接摘要")
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(resumeReminder.reasonLabel) · \(resumeReminder.relativeText)；如果你要从上次边界继续，可以直接恢复。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button("稍后") {
                        appModel.dismissResumeReminder(projectId: projectId)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button("接上次进度") {
                        appModel.presentResumeBrief(projectId: projectId)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(session.isSending)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.22), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
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

    private func openGovernance(_ destination: XTProjectGovernanceDestination) {
        appModel.requestProjectSettingsFocus(
            projectId: projectId,
            destination: destination
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
