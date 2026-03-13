import SwiftUI

/// 现代化的消息时间线视图，替代原来的 TranscriptTextView
struct MessageTimelineView: View {
    let ctx: AXProjectContext
    @ObservedObject var session: ChatSessionModel
    let hubConnected: Bool
    let onApproveSkillActivity: (String) -> Void
    let onRetrySkillActivity: (ProjectSkillActivityItem) -> Void
    var bottomPadding: CGFloat = 24
    @Namespace private var bottomID
    @State private var recentSkillActivities: [ProjectSkillActivityItem] = []
    @State private var selectedSkillRecord: ProjectSkillRecordSheetState?

    private let recentSkillActivityLimit = 8

    private var visibleMessages: [AXChatMessage] {
        session.messages.filter { message in
            message.role != .tool
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(visibleMessages) { message in
                        MessageCard(message: message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if !recentSkillActivities.isEmpty {
                        ProjectSkillActivitySection(
                            items: recentSkillActivities,
                            pendingRequestIDs: Set(session.pendingToolCalls.map(\.id)),
                            hubConnected: hubConnected,
                            isBusy: session.isSending,
                            onApprove: onApproveSkillActivity,
                            onReject: { requestID in
                                session.rejectPendingTool(requestID: requestID)
                            },
                            onRetry: onRetrySkillActivity,
                            onViewFullRecord: showFullRecord
                        )
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // 加载指示器
                    if session.shouldShowThinkingIndicator {
                        ThinkingIndicator()
                            .transition(.opacity)
                    }

                    // 底部锚点
                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .padding(20)
                .padding(.bottom, bottomPadding)
            }
            .onChange(of: session.messages.count) { _ in
                refreshRecentSkillActivities()
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .onChange(of: session.isSending) { sending in
                refreshRecentSkillActivities()
                if sending {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: session.messages.last?.content ?? "") { _ in
                refreshRecentSkillActivities()
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
            .onChange(of: session.pendingToolCalls.map(\.id).joined(separator: ",")) { _ in
                refreshRecentSkillActivities()
            }
            .onChange(of: recentSkillActivities.count) { _ in
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
            .onAppear {
                refreshRecentSkillActivities()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedSkillRecord) { record in
            ProjectSkillRecordSheet(record: record)
        }
    }

    private func refreshRecentSkillActivities() {
        recentSkillActivities = ProjectSkillActivityPresentation.loadRecentActivities(
            ctx: ctx,
            limit: recentSkillActivityLimit
        )
    }

    private func showFullRecord(for item: ProjectSkillActivityItem) {
        guard let record = ProjectSkillActivityPresentation.fullRecord(
            ctx: ctx,
            requestID: item.requestID
        ) else {
            return
        }
        selectedSkillRecord = ProjectSkillRecordSheetState(record: record)
    }
}

/// 单个消息卡片
struct MessageCard: View {
    let message: AXChatMessage
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 头像
            MessageAvatar(role: message.role)

            // 消息内容
            VStack(alignment: .leading, spacing: 8) {
                // 消息头部
                HStack(spacing: 8) {
                    Text(roleLabel)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(roleLabelColor)

                    if let tag = message.tag, !tag.isEmpty {
                        Text(tag)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Spacer()

                    Text(timeLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // 悬停时显示操作按钮
                    if isHovered && message.role != .tool {
                        MessageActionButtons(message: message)
                    }
                }

                // 消息内容
                MessageContentView(message: message)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user:
            return "You"
        case .assistant:
            return "Assistant"
        case .tool:
            return "Tool"
        }
    }

    private var roleLabelColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return .purple
        case .tool:
            return .secondary
        }
    }

    private var cardBackground: Color {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.06)
        case .assistant:
            return Color(nsColor: .controlBackgroundColor)
        case .tool:
            return Color.secondary.opacity(0.04)
        }
    }

    private var borderColor: Color {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.15)
        case .assistant:
            return Color.secondary.opacity(0.1)
        case .tool:
            return Color.secondary.opacity(0.08)
        }
    }

    private var timeLabel: String {
        let date = Date(timeIntervalSince1970: message.createdAt)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

/// 消息头像
struct MessageAvatar: View {
    let role: AXChatRole

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarGradient)
                .frame(width: 36, height: 36)

            Image(systemName: iconName)
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .semibold))
        }
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
    }

    private var iconName: String {
        switch role {
        case .user:
            return "person.fill"
        case .assistant:
            return "sparkles"
        case .tool:
            return "wrench.fill"
        }
    }

    private var avatarGradient: LinearGradient {
        switch role {
        case .user:
            return LinearGradient(
                colors: [Color.blue, Color.blue.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .assistant:
            return LinearGradient(
                colors: [Color.purple, Color.pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .tool:
            return LinearGradient(
                colors: [Color.secondary, Color.secondary.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// 消息操作按钮
struct MessageActionButtons: View {
    let message: AXChatMessage

    var body: some View {
        HStack(spacing: 4) {
            Button {
                copyToClipboard(message.content)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// 消息内容视图
struct MessageContentView: View {
    let message: AXChatMessage

    var body: some View {
        switch message.role {
        case .assistant:
            // Assistant 消息：解析并展示结构化内容
            AssistantMessageContent(message: message)

        case .tool:
            // Tool 消息：展示 tool result
            ToolResultView(message: message)

        case .user:
            // User 消息：简单文本
            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProjectSkillActivitySection: View {
    let items: [ProjectSkillActivityItem]
    let pendingRequestIDs: Set<String>
    let hubConnected: Bool
    let isBusy: Bool
    let onApprove: (String) -> Void
    let onReject: (String) -> Void
    let onRetry: (ProjectSkillActivityItem) -> Void
    let onViewFullRecord: (ProjectSkillActivityItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(.secondary)
                Text("Recent Skill Activity")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                Spacer()
                Text("\(items.count)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(items) { item in
                ProjectSkillActivityCard(
                    item: item,
                    isPendingApproval: pendingRequestIDs.contains(item.requestID),
                    hubConnected: hubConnected,
                    isBusy: isBusy,
                    onApprove: {
                        onApprove(item.requestID)
                    },
                    onReject: {
                        onReject(item.requestID)
                    },
                    onRetry: {
                        onRetry(item)
                    },
                    onViewFullRecord: {
                        onViewFullRecord(item)
                    }
                )
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ProjectSkillActivityCard: View {
    let item: ProjectSkillActivityItem
    let isPendingApproval: Bool
    let hubConnected: Bool
    let isBusy: Bool
    let onApprove: () -> Void
    let onReject: () -> Void
    let onRetry: () -> Void
    let onViewFullRecord: () -> Void
    @State private var showDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: ProjectSkillActivityPresentation.iconName(for: item))
                    .foregroundStyle(iconColor)
                    .font(.system(size: 14))

                Text(ProjectSkillActivityPresentation.title(for: item))
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)

                Spacer()

                Text(ProjectSkillActivityPresentation.statusLabel(for: item))
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(iconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(iconColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                if !item.skillID.isEmpty {
                    Text(item.skillID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                }

                Text(ProjectSkillActivityPresentation.toolBadge(for: item))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(ProjectSkillActivityPresentation.body(for: item))
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if ProjectSkillActivityPresentation.isAwaitingApproval(item), isPendingApproval {
                    Button("Approve") {
                        onApprove()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || !hubConnected)
                    .help(hubConnected ? "Approve and run this governed skill dispatch" : "Connect Hub before approving")

                    Button("Reject") {
                        onReject()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    .help("Reject this pending governed skill dispatch without running it")
                }

                if ProjectSkillActivityPresentation.canRetry(item) {
                    Button("Retry") {
                        onRetry()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy || isPendingApproval)
                    .help(isPendingApproval ? "This request is already waiting for approval" : "Replay the last governed dispatch with the same guarded tool arguments")
                }

                Button("View Full Record") {
                    onViewFullRecord()
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                ScrollView {
                    Text(ProjectSkillActivityPresentation.diagnostics(for: item))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(.top, 6)
            }
            .font(.caption)
            .tint(.secondary)
        }
        .padding(12)
        .background(iconColor.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(iconColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var iconColor: Color {
        switch item.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed":
            return .green
        case "failed":
            return .red
        case "blocked":
            return .orange
        case "awaiting_approval":
            return .yellow
        case "resolved":
            return .blue
        default:
            return .secondary
        }
    }

    private var timeLabel: String {
        let date = Date(timeIntervalSince1970: item.createdAt)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

private struct ProjectSkillRecordSheetState: Identifiable {
    let record: ProjectSkillFullRecord

    var id: String { record.id }
}

private struct ProjectSkillRecordSheet: View {
    let record: ProjectSkillRecordSheetState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.record.title)
                        .font(.system(.headline, design: .rounded))
                    HStack(spacing: 8) {
                        Text(record.record.requestID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        ProjectSkillRecordStatusBadge(statusLabel: record.record.latestStatusLabel)
                    }
                }

                Spacer()

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        ProjectSkillActivityPresentation.fullRecordText(record.record),
                        forType: .string
                    )
                }
                .buttonStyle(.bordered)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !record.record.requestMetadata.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "Request Metadata",
                            fields: record.record.requestMetadata
                        )
                    }

                    if !record.record.approvalFields.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "Approval Status",
                            fields: record.record.approvalFields
                        )
                    }

                    if let toolArgs = record.record.toolArgumentsText,
                       !toolArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProjectSkillRecordCodeSection(
                            title: "Tool Arguments",
                            text: toolArgs,
                            initiallyExpanded: true
                        )
                    }

                    if !record.record.resultFields.isEmpty
                        || !(record.record.rawOutputPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !(record.record.rawOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProjectSkillRecordResultSection(record: record.record)
                    }

                    if !record.record.evidenceFields.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "Evidence Refs",
                            fields: record.record.evidenceFields
                        )
                    }

                    if !record.record.approvalHistory.isEmpty {
                        ProjectSkillRecordTimelineSection(
                            title: "Approval History",
                            entries: record.record.approvalHistory
                        )
                    }

                    if !record.record.timeline.isEmpty {
                        ProjectSkillRecordTimelineSection(
                            title: "Event Timeline",
                            entries: record.record.timeline
                        )
                    }

                    if let evidenceJSON = record.record.supervisorEvidenceJSON,
                       !evidenceJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProjectSkillRecordCodeSection(
                            title: "Supervisor Evidence JSON",
                            text: evidenceJSON,
                            initiallyExpanded: false
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
    }
}

struct ProjectSkillRecordStatusBadge: View {
    let statusLabel: String

    var body: some View {
        if !statusLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           statusLabel != "Unknown" {
            Text(statusLabel)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private var color: Color {
        switch statusLabel.lowercased() {
        case "completed":
            return .green
        case "failed":
            return .red
        case "blocked":
            return .orange
        case "awaiting approval":
            return .yellow
        case "resolved":
            return .blue
        default:
            return .secondary
        }
    }
}

struct ProjectSkillRecordFieldSection: View {
    let title: String
    let fields: [ProjectSkillRecordField]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle
            VStack(alignment: .leading, spacing: 8) {
                ForEach(fields) { field in
                    HStack(alignment: .top, spacing: 12) {
                        Text(field.label)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)

                        Text(field.value)
                            .font(.system(.subheadline, design: .default))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    private var sectionTitle: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
            Spacer()
            Text("\(fields.count)")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

struct ProjectSkillRecordCodeSection: View {
    let title: String
    let text: String
    let initiallyExpanded: Bool
    @State private var isExpanded: Bool

    init(title: String, text: String, initiallyExpanded: Bool) {
        self.title = title
        self.text = text
        self.initiallyExpanded = initiallyExpanded
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $isExpanded) {
                ScrollView {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .frame(maxHeight: 220)
            } label: {
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
        .tint(.secondary)
    }
}

private struct ProjectSkillRecordResultSection: View {
    let record: ProjectSkillFullRecord
    @State private var showFullRawOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Result Summary")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                Spacer()
            }

            if !record.resultFields.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(record.resultFields) { field in
                        HStack(alignment: .top, spacing: 12) {
                            Text(field.label)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)

                            Text(field.value)
                                .font(.system(.subheadline, design: .default))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            if let preview = record.rawOutputPreview,
               !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Raw Output Preview")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
            }

            if let rawOutput = record.rawOutput,
               !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("Full Raw Output", isExpanded: $showFullRawOutput) {
                    ScrollView {
                        Text(rawOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .frame(maxHeight: 220)
                }
                .font(.caption)
                .tint(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ProjectSkillRecordTimelineSection: View {
    let title: String
    let entries: [ProjectSkillRecordTimelineEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                Spacer()
                Text("\(entries.count)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(entries) { entry in
                ProjectSkillRecordTimelineCard(entry: entry)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ProjectSkillRecordTimelineCard: View {
    let entry: ProjectSkillRecordTimelineEntry
    @State private var showRawJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.statusLabel)
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                Text(entry.timestamp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text(entry.summary)
                .font(.system(.subheadline, design: .default))
                .fixedSize(horizontal: false, vertical: true)

            if let detail = entry.detail,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("Raw Event JSON", isExpanded: $showRawJSON) {
                ScrollView {
                    Text(entry.rawJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .frame(maxHeight: 180)
            }
            .font(.caption)
            .tint(.secondary)
        }
        .padding(12)
        .background(statusColor.opacity(0.05))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor.opacity(0.14), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch entry.status.lowercased() {
        case "completed":
            return .green
        case "failed":
            return .red
        case "blocked":
            return .orange
        case "awaiting_approval":
            return .yellow
        case "resolved":
            return .blue
        default:
            return .secondary
        }
    }
}

/// Tool Result 视图
struct ToolResultView: View {
    let message: AXChatMessage
    @State private var toolResult: ToolResult?
    @State private var showDiagnostics = false

    var body: some View {
        Group {
            if let result = toolResult, !ToolResultPresentation.shouldShowTimelineCard(for: result) {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: resultIcon)
                            .foregroundColor(resultColor)
                            .font(.system(size: 14))

                        Text(summaryTitle)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)

                        Spacer()

                        if let result = toolResult {
                            Text(result.tool.rawValue)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(summaryBody)
                        .font(.system(.subheadline, design: .default))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                        ScrollView {
                            Text(diagnosticsText)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 220)
                        .padding(.top, 6)
                    }
                    .font(.caption)
                    .tint(.secondary)
                }
                .padding(12)
                .background(resultBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(resultBorderColor, lineWidth: 1)
                )
            }
        }
        .onAppear {
            toolResult = ToolResultParser.parse(message.content)
        }
        .onChange(of: message.content) { newContent in
            toolResult = ToolResultParser.parse(newContent)
        }
    }

    private var resultIcon: String {
        guard let result = toolResult else { return "exclamationmark.triangle.fill" }
        return ToolResultPresentation.iconName(for: result)
    }

    private var resultColor: Color {
        guard let result = toolResult else { return .orange }
        return result.ok ? .green : .orange
    }

    private var summaryTitle: String {
        guard let result = toolResult else { return "Action needs attention" }
        return ToolResultPresentation.title(for: result)
    }

    private var summaryBody: String {
        guard let result = toolResult else {
            return "A tool call returned diagnostics. Open Diagnostics to inspect the raw output."
        }
        return ToolResultPresentation.body(for: result)
    }

    private var diagnosticsText: String {
        if let result = toolResult, !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return result.output
        }
        return message.content
    }

    private var resultBackground: Color {
        guard let result = toolResult else { return Color.orange.opacity(0.06) }
        return result.ok ? Color.green.opacity(0.06) : Color.orange.opacity(0.06)
    }

    private var resultBorderColor: Color {
        guard let result = toolResult else { return Color.orange.opacity(0.24) }
        return result.ok ? Color.green.opacity(0.24) : Color.orange.opacity(0.24)
    }
}

/// Assistant 消息内容（支持 tool calls 展示）
struct AssistantMessageContent: View {
    let message: AXChatMessage
    @State private var parsedContent: ParsedContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let parsed = parsedContent, !parsed.isEmpty {
                // 结构化内容
                ForEach(parsed.parts) { part in
                    ParsedPartView(part: part)
                }
            } else {
                // 纯文本内容
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear {
            parsedContent = ToolCallParser.parse(message.content)
        }
        .onChange(of: message.content) { newContent in
            parsedContent = ToolCallParser.parse(newContent)
        }
    }
}

/// 解析后的部分视图
struct ParsedPartView: View {
    let part: ParsedPart

    var body: some View {
        switch part {
        case .text(let content):
            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .toolCall(let toolCall):
            ToolCallCard(toolCall: toolCall)

        case .thinking(let content):
            ThinkingCard(content: content)
        }
    }
}

/// Tool Call 卡片
struct ToolCallCard: View {
    let toolCall: ToolCall
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 工具头部（可点击折叠）
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: toolIcon)
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14))

                    Text(toolCall.tool.rawValue)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 工具详情（可折叠）
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // 参数
                    if !toolCall.args.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Arguments:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(Array(toolCall.args.keys.sorted()), id: \.self) { key in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(key)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)

                                    Text(formatArgValue(toolCall.args[key]))
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 22)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var toolIcon: String {
        switch toolCall.tool {
        case .read_file:
            return "doc.text"
        case .write_file:
            return "pencil"
        case .list_dir:
            return "folder"
        case .search:
            return "magnifyingglass"
        case .skills_search:
            return "magnifyingglass"
        case .summarize:
            return "text.alignleft"
        case .run_command:
            return "terminal"
        case .git_status, .git_diff, .git_apply_check, .git_apply:
            return "arrow.triangle.branch"
        case .session_list:
            return "list.bullet.rectangle"
        case .session_resume:
            return "play.circle"
        case .session_compact:
            return "archivebox"
        case .agentImportRecord:
            return "checklist"
        case .memory_snapshot:
            return "memorychip"
        case .project_snapshot:
            return "folder.badge.gearshape"
        case .deviceUIObserve:
            return "eye"
        case .deviceUIAct:
            return "hand.tap"
        case .deviceUIStep:
            return "point.3.connected.trianglepath.dotted"
        case .deviceClipboardRead, .deviceClipboardWrite:
            return "list.clipboard"
        case .deviceScreenCapture:
            return "camera.viewfinder"
        case .deviceBrowserControl:
            return "safari"
        case .deviceAppleScript:
            return "apple.logo"
        case .need_network, .bridge_status, .web_fetch, .web_search, .browser_read:
            return "network"
        }
    }

    private func formatArgValue(_ value: JSONValue?) -> String {
        guard let value = value else { return "null" }

        switch value {
        case .string(let s):
            return s.count > 100 ? String(s.prefix(100)) + "..." : s
        case .number(let n):
            return String(n)
        case .bool(let b):
            return String(b)
        case .null:
            return "null"
        case .array(let arr):
            return "[\(arr.count) items]"
        case .object(let obj):
            return "{\(obj.count) keys}"
        }
    }
}

/// Thinking 卡片
struct ThinkingCard: View {
    let content: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "brain")
                        .foregroundColor(.orange)
                    Text("Thinking")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 22)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

/// 思考指示器
struct ThinkingIndicator: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(scale(for: index))
                }
            }

            Text("我在整理回复。")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.08))
        )
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }

    private func scale(for index: Int) -> CGFloat {
        let offset = Double(index) * 0.33
        let normalizedPhase = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 1.0 + sin(normalizedPhase * .pi * 2) * 0.4
    }
}
