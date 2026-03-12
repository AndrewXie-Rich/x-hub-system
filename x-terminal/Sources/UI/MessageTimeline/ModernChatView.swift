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
        return HStack(spacing: 8) {
            Image(systemName: "hammer.circle.fill")
                .foregroundColor(.blue)
                .font(.system(size: 14))

            Text(ctx.projectName())
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("Coder")
                .font(.system(size: 13, weight: .medium))

            Text(projectConfiguredChipText(configuredModelId: configuredModelId))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())

            if let actualChip = projectActualChipText(configuredModelId: configuredModelId, snapshot: coderSnapshot) {
                Text(actualChip)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(projectRouteColor(snapshot: coderSnapshot))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(projectRouteColor(snapshot: coderSnapshot).opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(projectRouteStatusText(snapshot: coderSnapshot))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(projectRouteColor(snapshot: coderSnapshot))
                .lineLimit(1)
                .help(projectRouteTooltip(configuredModelId: configuredModelId, snapshot: coderSnapshot))
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

    private func displayModel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "default hub route" : trimmed
    }

    private func preferredDisplayValue(_ primary: String, fallback: String) -> String {
        let first = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty {
            return first
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func projectConfiguredChipText(configuredModelId: String) -> String {
        "cfg \(shortModelLabel(configuredModelId))"
    }

    private func projectActualChipText(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String? {
        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = preferredDisplayValue(snapshot.actualModelId, fallback: snapshot.requestedModelId)
        guard !actual.isEmpty || snapshot.hasRecord else { return nil }

        if !actual.isEmpty,
           !configured.isEmpty,
           normalizedModelIdentity(actual) == normalizedModelIdentity(configured),
           snapshot.executionPath == "remote_model" {
            return "actual \(shortModelLabel(actual))"
        }

        if !actual.isEmpty {
            return "actual \(shortModelLabel(actual))"
        }
        return "actual pending"
    }

    private func projectRouteStatusText(snapshot: AXRoleExecutionSnapshot) -> String {
        switch snapshot.executionPath {
        case "remote_model", "direct_provider":
            return "remote verified"
        case "hub_downgraded_to_local":
            return "local downgrade"
        case "local_fallback_after_remote_error":
            return "local fallback"
        case "local_runtime":
            return "local only"
        case "remote_error":
            return "remote failed"
        default:
            return "no record"
        }
    }

    private func projectRouteTooltip(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        var lines: [String] = []
        lines.append("configured=\(displayModel(configuredModelId))")
        if !snapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("requested=\(snapshot.requestedModelId)")
        }
        if !snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("last_actual=\(snapshot.actualModelId)")
        }
        if !snapshot.executionPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           snapshot.executionPath != "no_record" {
            lines.append("last_path=\(snapshot.executionPath)")
        }
        if !snapshot.fallbackReasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("reason=\(snapshot.fallbackReasonCode)")
        }
        lines.append("transport=\(HubAIClient.transportMode().rawValue)")
        return lines.joined(separator: "\n")
    }

    private func projectRouteColor(snapshot: AXRoleExecutionSnapshot) -> Color {
        switch snapshot.executionPath {
        case "remote_model", "direct_provider":
            return .green
        case "hub_downgraded_to_local", "local_fallback_after_remote_error":
            return .orange
        case "local_runtime":
            return .yellow
        case "remote_error":
            return .red
        default:
            return .secondary
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
