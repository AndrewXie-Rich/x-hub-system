import SwiftUI

enum XTProjectTranscriptObservationPanelStyle: Equatable {
    case inline
    case elevated
}

struct XTProjectTranscriptObservationInput: Identifiable {
    var projectId: String
    var projectName: String
    var context: AXProjectContext
    var session: ChatSessionModel

    var id: String { projectId }
}

struct XTProjectTranscriptObservationPanel: View {
    let input: XTProjectTranscriptObservationInput
    let style: XTProjectTranscriptObservationPanelStyle
    let loadLimit: Int
    let showsEmptyState: Bool

    @ObservedObject private var session: ChatSessionModel

    init(
        input: XTProjectTranscriptObservationInput,
        style: XTProjectTranscriptObservationPanelStyle = .elevated,
        loadLimit: Int = 120,
        showsEmptyState: Bool = false
    ) {
        self.input = input
        self.style = style
        self.loadLimit = loadLimit
        self.showsEmptyState = showsEmptyState
        _session = ObservedObject(wrappedValue: input.session)
    }

    var body: some View {
        let projection = XTProjectTranscriptProjection.build(
            projectId: input.projectId,
            projectName: input.projectName,
            messages: session.messages,
            pendingToolCallCount: session.pendingToolCalls.count,
            isSending: session.isSending,
            lastError: session.lastError,
            maxRecentLines: 8
        )

        Group {
            if projection.hasUsefulContent {
                content(projection: projection)
            } else if showsEmptyState {
                emptyContent
            }
        }
        .onAppear {
            session.ensureLoaded(ctx: input.context, limit: loadLimit)
        }
    }

    private func content(projection: XTProjectTranscriptProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(projection: projection)

            Text(boundaryText(for: projection))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                if projection.pendingToolCallCount > 0 {
                    observationLine(
                        title: "工具审批",
                        text: "\(projection.pendingToolCallCount) 个 pending tool call",
                        tone: .warning
                    )
                }
                if !projection.lastError.isEmpty {
                    observationLine(
                        title: "错误",
                        text: projection.lastError,
                        tone: .danger
                    )
                }
                if let latestDispatchId = projection.latestDispatchId,
                   !latestDispatchId.isEmpty {
                    let status = projection.latestDispatchStatus ?? "unknown"
                    observationLine(
                        title: "Dispatch",
                        text: "\(latestDispatchId) · \(status)",
                        tone: .primary
                    )
                }
                if let latestSupervisorDispatch = projection.latestSupervisorDispatch {
                    observationLine(
                        title: "Supervisor",
                        text: latestSupervisorDispatch.content,
                        tone: .primary
                    )
                }
                if let latestCoderReply = projection.latestCoderReply {
                    observationLine(
                        title: "Coder",
                        text: latestCoderReply.content,
                        tone: .success
                    )
                }
                if let latestReviewerNote = projection.latestReviewerNote {
                    observationLine(
                        title: "Reviewer",
                        text: latestReviewerNote.content,
                        tone: .warning
                    )
                }
            }

            let recent = recentRoleLines(from: projection)
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近角色线")
                        .font(.caption2.weight(.semibold))
                    ForEach(recent, id: \.messageId) { line in
                        Text("\(roleDisplayName(line.role)): \(capped(line.content, maxChars: 150))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("项目角色对话")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(input.projectName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("当前还没有观察到 Supervisor 派发、Coder 回复或 Reviewer 备注。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
        .overlay(panelBorder)
    }

    private func header(projection: XTProjectTranscriptProjection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("项目角色对话")
                .font(.caption.weight(.semibold))
            Text(input.projectName)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(statusText(projection.status))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(statusColor(projection.status))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(statusColor(projection.status).opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func observationLine(
        title: String,
        text: String,
        tone: XTProjectTranscriptObservationTone
    ) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color(for: tone))
                .frame(width: 72, alignment: .leading)
            Text(capped(text, maxChars: 220))
                .font(.caption2)
                .foregroundStyle(tone == .primary ? .primary : .secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func boundaryText(for projection: XTProjectTranscriptProjection) -> String {
        if projection.source == "hub_role_turn_metadata_projection" {
            return "Hub role-turn metadata 投影；XT 本地 sender 和文本前缀只作为 fallback。"
        }
        return "XT 本地运行时投影；Hub 仍管理 Memory、Skills、grant、model route、quota、kill-switch 和 audit。"
    }

    private func recentRoleLines(
        from projection: XTProjectTranscriptProjection
    ) -> [XTProjectTranscriptLine] {
        var seen = Set<String>()
        let latestIds = [
            projection.latestSupervisorDispatch?.messageId,
            projection.latestCoderReply?.messageId,
            projection.latestReviewerNote?.messageId
        ]
        latestIds.compactMap { $0 }.forEach { seen.insert($0) }
        return Array(projection.recentLines
            .filter { !seen.contains($0.messageId) }
            .suffix(4))
    }

    private var panelPadding: CGFloat {
        switch style {
        case .inline:
            return 0
        case .elevated:
            return 12
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        switch style {
        case .inline:
            EmptyView()
        case .elevated:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private var panelBorder: some View {
        switch style {
        case .inline:
            EmptyView()
        case .elevated:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "awaiting_authorization":
            return "等待授权"
        case "failed":
            return "失败"
        case "running":
            return "执行中"
        case "latest_coder_reply_observed":
            return "看到 Coder 回复"
        case "dispatch_observed":
            return "看到派发"
        default:
            return "已观察"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "awaiting_authorization":
            return .orange
        case "failed":
            return .red
        case "running":
            return .yellow
        case "latest_coder_reply_observed":
            return .green
        default:
            return .secondary
        }
    }

    private func roleDisplayName(_ role: String) -> String {
        switch role {
        case "supervisor":
            return "Supervisor"
        case "coder":
            return "Coder"
        case "reviewer":
            return "Reviewer"
        case "tool":
            return "Tool"
        case "user":
            return "User"
        default:
            return role
        }
    }

    private func color(for tone: XTProjectTranscriptObservationTone) -> Color {
        switch tone {
        case .primary:
            return .primary
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }

    private func capped(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<idx]) + "..."
    }
}

private enum XTProjectTranscriptObservationTone: Equatable {
    case primary
    case success
    case warning
    case danger
}
