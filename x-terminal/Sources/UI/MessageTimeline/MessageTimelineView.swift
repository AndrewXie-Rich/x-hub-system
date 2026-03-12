import SwiftUI

/// 现代化的消息时间线视图，替代原来的 TranscriptTextView
struct MessageTimelineView: View {
    let ctx: AXProjectContext
    @ObservedObject var session: ChatSessionModel
    var bottomPadding: CGFloat = 24
    @Namespace private var bottomID

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(session.messages) { message in
                        MessageCard(message: message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    // 加载指示器
                    if session.isSending {
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
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .onChange(of: session.isSending) { sending in
                if sending {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: session.messages.last?.content ?? "") { _ in
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

/// Tool Result 视图
struct ToolResultView: View {
    let message: AXChatMessage
    @State private var toolResult: ToolResult?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 头部
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: resultIcon)
                        .foregroundColor(resultColor)
                        .font(.system(size: 14))

                    Text(resultTitle)
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

            // 详情
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let result = toolResult {
                        // 状态
                        HStack(spacing: 6) {
                            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.ok ? .green : .red)
                                .font(.caption)
                            Text(result.ok ? "Success" : "Failed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        // 输出
                        ScrollView {
                            Text(result.output)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                    } else {
                        // 原始内容
                        Text(message.content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 22)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(resultBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(resultBorderColor, lineWidth: 1)
        )
        .onAppear {
            toolResult = ToolResultParser.parse(message.content)
        }
    }

    private var resultIcon: String {
        if let result = toolResult {
            return result.ok ? "checkmark.circle" : "xmark.circle"
        }
        return "info.circle"
    }

    private var resultColor: Color {
        if let result = toolResult {
            return result.ok ? .green : .red
        }
        return .secondary
    }

    private var resultTitle: String {
        if let result = toolResult {
            return result.tool.rawValue
        }
        return "Tool Result"
    }

    private var resultBackground: Color {
        if let result = toolResult {
            return result.ok ? Color.green.opacity(0.05) : Color.red.opacity(0.05)
        }
        return Color.secondary.opacity(0.05)
    }

    private var resultBorderColor: Color {
        if let result = toolResult {
            return result.ok ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
        }
        return Color.secondary.opacity(0.2)
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

            Text("Thinking...")
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
