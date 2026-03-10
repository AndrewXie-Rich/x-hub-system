import SwiftUI
import UniformTypeIdentifiers

/// 消息时间线的性能优化版本
/// 使用虚拟滚动和消息分页来处理大量消息
struct OptimizedMessageTimelineView: View {
    let ctx: AXProjectContext
    @ObservedObject var session: ChatSessionModel

    @State private var visibleRange: Range<Int> = 0..<50
    @State private var isLoadingMore = false
    @Namespace private var bottomID

    private let pageSize = 50
    private let bufferSize = 10 // 预加载缓冲区

    private var visibleMessages: [AXChatMessage] {
        let start = max(0, visibleRange.lowerBound)
        let end = min(session.messages.count, visibleRange.upperBound)
        return Array(session.messages[start..<end])
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    // 加载更多按钮（顶部）
                    if visibleRange.lowerBound > 0 {
                        LoadMoreButton(isLoading: isLoadingMore) {
                            loadPreviousMessages()
                        }
                    }

                    // 可见消息
                    ForEach(visibleMessages) { message in
                        MessageCard(message: message)
                            .id(message.id)
                            .onAppear {
                                checkIfNeedLoadMore(message: message)
                            }
                    }

                    // 加载指示器
                    if session.isSending {
                        ThinkingIndicator()
                    }

                    // 底部锚点
                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .padding(20)
                .padding(.bottom, 120)
            }
            .onChange(of: session.messages.count) { newCount in
                // 新消息到达，扩展可见范围
                if newCount > visibleRange.upperBound {
                    visibleRange = visibleRange.lowerBound..<newCount
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // 初始化可见范围（显示最后 50 条）
            let total = session.messages.count
            visibleRange = max(0, total - pageSize)..<total
        }
    }

    private func loadPreviousMessages() {
        guard !isLoadingMore else { return }

        isLoadingMore = true

        // 模拟异步加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let newStart = max(0, visibleRange.lowerBound - pageSize)
            visibleRange = newStart..<visibleRange.upperBound
            isLoadingMore = false
        }
    }

    private func checkIfNeedLoadMore(message: AXChatMessage) {
        // 如果滚动到接近顶部，自动加载更多
        guard let index = session.messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }

        if index < visibleRange.lowerBound + bufferSize && visibleRange.lowerBound > 0 {
            loadPreviousMessages()
        }
    }
}

/// 加载更多按钮
struct LoadMoreButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                } else {
                    Image(systemName: "arrow.up.circle")
                    Text("Load previous messages")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

/// 消息统计视图
struct MessageStatsView: View {
    let messages: [AXChatMessage]

    private var stats: MessageStats {
        calculateStats()
    }

    var body: some View {
        HStack(spacing: 20) {
            StatItem(
                icon: "bubble.left.and.bubble.right",
                label: "Total",
                value: "\(stats.total)"
            )

            StatItem(
                icon: "person",
                label: "User",
                value: "\(stats.userCount)",
                color: .blue
            )

            StatItem(
                icon: "sparkles",
                label: "Assistant",
                value: "\(stats.assistantCount)",
                color: .purple
            )

            StatItem(
                icon: "wrench",
                label: "Tools",
                value: "\(stats.toolCount)",
                color: .secondary
            )
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private func calculateStats() -> MessageStats {
        var userCount = 0
        var assistantCount = 0
        var toolCount = 0

        for message in messages {
            switch message.role {
            case .user:
                userCount += 1
            case .assistant:
                assistantCount += 1
            case .tool:
                toolCount += 1
            }
        }

        return MessageStats(
            total: messages.count,
            userCount: userCount,
            assistantCount: assistantCount,
            toolCount: toolCount
        )
    }
}

struct MessageStats {
    let total: Int
    let userCount: Int
    let assistantCount: Int
    let toolCount: Int
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 16))

            Text(value)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 消息导出功能
struct MessageExporter {

    enum ExportFormat {
        case markdown
        case json
        case plainText
    }

    static func export(messages: [AXChatMessage], format: ExportFormat) -> String {
        switch format {
        case .markdown:
            return exportAsMarkdown(messages)
        case .json:
            return exportAsJSON(messages)
        case .plainText:
            return exportAsPlainText(messages)
        }
    }

    private static func exportAsMarkdown(_ messages: [AXChatMessage]) -> String {
        var output = "# Chat History\n\n"
        output += "Exported: \(Date().formatted())\n\n"
        output += "---\n\n"

        for message in messages {
            let role = message.role.rawValue.capitalized
            let timestamp = Date(timeIntervalSince1970: message.createdAt).formatted()

            output += "## \(role)\n"
            output += "*\(timestamp)*\n\n"
            output += message.content
            output += "\n\n---\n\n"
        }

        return output
    }

    private static func exportAsJSON(_ messages: [AXChatMessage]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(messages),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return json
    }

    private static func exportAsPlainText(_ messages: [AXChatMessage]) -> String {
        var output = "Chat History\n"
        output += "Exported: \(Date().formatted())\n"
        output += String(repeating: "=", count: 50) + "\n\n"

        for message in messages {
            let role = message.role.rawValue.uppercased()
            let timestamp = Date(timeIntervalSince1970: message.createdAt).formatted()

            output += "[\(role)] \(timestamp)\n"
            output += message.content
            output += "\n\n" + String(repeating: "-", count: 50) + "\n\n"
        }

        return output
    }
}

/// 消息导出按钮
struct MessageExportButton: View {
    let messages: [AXChatMessage]
    @State private var showExportSheet = false
    @State private var selectedFormat: MessageExporter.ExportFormat = .markdown

    var body: some View {
        Button {
            showExportSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                Text("Export")
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(
                messages: messages,
                selectedFormat: $selectedFormat,
                onExport: { format in
                    exportMessages(format: format)
                }
            )
        }
    }

    private func exportMessages(format: MessageExporter.ExportFormat) {
        let content = MessageExporter.export(messages: messages, format: format)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "chat_history.\(fileExtension(for: format))"
        panel.allowedContentTypes = [contentType(for: format)]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func fileExtension(for format: MessageExporter.ExportFormat) -> String {
        switch format {
        case .markdown: return "md"
        case .json: return "json"
        case .plainText: return "txt"
        }
    }

    private func contentType(for format: MessageExporter.ExportFormat) -> UTType {
        switch format {
        case .markdown: return .plainText
        case .json: return .json
        case .plainText: return .plainText
        }
    }
}

struct ExportSheet: View {
    let messages: [AXChatMessage]
    @Binding var selectedFormat: MessageExporter.ExportFormat
    let onExport: (MessageExporter.ExportFormat) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Chat History")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Format")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Format", selection: $selectedFormat) {
                    Text("Markdown").tag(MessageExporter.ExportFormat.markdown)
                    Text("JSON").tag(MessageExporter.ExportFormat.json)
                    Text("Plain Text").tag(MessageExporter.ExportFormat.plainText)
                }
                .pickerStyle(.radioGroup)
            }

            Divider()

            HStack {
                Text("\(messages.count) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Export") {
                    onExport(selectedFormat)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

/// 消息缓存管理器
actor MessageCacheManager {
    private var cache: [String: CachedMessage] = [:]
    private let maxCacheSize = 1000

    struct CachedMessage {
        let message: AXChatMessage
        let renderedView: Any? // 预渲染的视图
        let timestamp: Date
    }

    func cache(_ message: AXChatMessage) {
        // 如果缓存已满，删除最旧的
        if cache.count >= maxCacheSize {
            let oldest = cache.min { $0.value.timestamp < $1.value.timestamp }
            if let key = oldest?.key {
                cache.removeValue(forKey: key)
            }
        }

        cache[message.id] = CachedMessage(
            message: message,
            renderedView: nil,
            timestamp: Date()
        )
    }

    func get(_ id: String) -> AXChatMessage? {
        cache[id]?.message
    }

    func clear() {
        cache.removeAll()
    }

    func clearOld(olderThan interval: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-interval)
        cache = cache.filter { $0.value.timestamp > cutoff }
    }
}
