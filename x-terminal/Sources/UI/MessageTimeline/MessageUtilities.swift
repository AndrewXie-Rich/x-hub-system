import SwiftUI

/// 键盘快捷键管理器
struct MessageKeyboardShortcuts: View {
    let onSearch: () -> Void
    let onFilter: () -> Void
    let onExport: () -> Void
    let onScrollToTop: () -> Void
    let onScrollToBottom: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        EmptyView()
            .keyboardShortcut("f", modifiers: [.command]) // 搜索
            .onAppear {
                // 注册快捷键
            }
    }
}

/// 消息主题管理器
enum MessageTheme {
    case light
    case dark
    case auto

    var userMessageBackground: Color {
        switch self {
        case .light:
            return Color.blue.opacity(0.08)
        case .dark:
            return Color.blue.opacity(0.15)
        case .auto:
            return Color.blue.opacity(0.06)
        }
    }

    var assistantMessageBackground: Color {
        switch self {
        case .light:
            return Color(nsColor: .controlBackgroundColor)
        case .dark:
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        case .auto:
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    var toolMessageBackground: Color {
        switch self {
        case .light:
            return Color.secondary.opacity(0.05)
        case .dark:
            return Color.secondary.opacity(0.1)
        case .auto:
            return Color.secondary.opacity(0.04)
        }
    }
}

/// 消息可访问性增强
struct AccessibleMessageCard: View {
    let message: AXChatMessage

    var body: some View {
        MessageCard(message: message)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        let role = message.role.rawValue.capitalized
        let time = Date(timeIntervalSince1970: message.createdAt).formatted(date: .omitted, time: .shortened)
        return "\(role) message at \(time)"
    }

    private var accessibilityHint: String {
        "Double tap to select, triple tap to copy"
    }
}

/// 消息手势管理器
struct MessageGestureHandler: ViewModifier {
    let message: AXChatMessage
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onLongPress: () -> Void

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                onTap()
            }
            .onTapGesture(count: 2) {
                onDoubleTap()
            }
            .onLongPressGesture {
                onLongPress()
            }
    }
}

extension View {
    func messageGestures(
        message: AXChatMessage,
        onTap: @escaping () -> Void = {},
        onDoubleTap: @escaping () -> Void = {},
        onLongPress: @escaping () -> Void = {}
    ) -> some View {
        modifier(MessageGestureHandler(
            message: message,
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            onLongPress: onLongPress
        ))
    }
}

/// 消息动画预设
enum MessageAnimation {
    static let cardAppear = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let cardDisappear = Animation.easeOut(duration: 0.2)
    static let toolCallExpand = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let scrollToBottom = Animation.easeOut(duration: 0.3)
    static let thinkingDots = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: false)
}

/// 消息布局配置
struct MessageLayoutConfig {
    var cardPadding: CGFloat = 16
    var cardSpacing: CGFloat = 16
    var cardCornerRadius: CGFloat = 12
    var avatarSize: CGFloat = 36
    var maxCardWidth: CGFloat = 800
    var minInputHeight: CGFloat = 44
    var maxInputHeight: CGFloat = 200

    static let compact = MessageLayoutConfig(
        cardPadding: 12,
        cardSpacing: 12,
        cardCornerRadius: 10,
        avatarSize: 32,
        maxCardWidth: .infinity,
        minInputHeight: 40,
        maxInputHeight: 150
    )

    static let standard = MessageLayoutConfig()

    static let spacious = MessageLayoutConfig(
        cardPadding: 20,
        cardSpacing: 20,
        cardCornerRadius: 14,
        avatarSize: 40,
        maxCardWidth: 900,
        minInputHeight: 48,
        maxInputHeight: 250
    )
}

/// 消息调试视图
struct MessageDebugView: View {
    let message: AXChatMessage
    @State private var showDebugInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MessageCard(message: message)

            if showDebugInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug Info")
                        .font(.caption)
                        .fontWeight(.bold)

                    Text("ID: \(message.id)")
                        .font(.system(.caption2, design: .monospaced))

                    Text("Role: \(message.role.rawValue)")
                        .font(.system(.caption2, design: .monospaced))

                    Text("Created: \(Date(timeIntervalSince1970: message.createdAt).formatted())")
                        .font(.system(.caption2, design: .monospaced))

                    Text("Content Length: \(message.content.count) chars")
                        .font(.system(.caption2, design: .monospaced))

                    if let tag = message.tag {
                        Text("Tag: \(tag)")
                            .font(.system(.caption2, design: .monospaced))
                    }
                }
                .padding(8)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(6)
                .transition(.opacity)
            }
        }
        .onTapGesture(count: 3) {
            withAnimation {
                showDebugInfo.toggle()
            }
        }
    }
}

/// 消息性能监控
class MessagePerformanceMonitor: ObservableObject {
    @Published var renderTime: TimeInterval = 0
    @Published var messageCount: Int = 0
    @Published var averageRenderTime: TimeInterval = 0

    private var renderTimes: [TimeInterval] = []

    func recordRender(duration: TimeInterval) {
        renderTime = duration
        renderTimes.append(duration)

        if renderTimes.count > 100 {
            renderTimes.removeFirst()
        }

        averageRenderTime = renderTimes.reduce(0, +) / Double(renderTimes.count)
    }

    func reset() {
        renderTimes.removeAll()
        renderTime = 0
        averageRenderTime = 0
    }
}

/// 性能监控视图
struct PerformanceOverlay: View {
    @ObservedObject var monitor: MessagePerformanceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Performance")
                .font(.caption)
                .fontWeight(.bold)

            Text("Last Render: \(String(format: "%.2f", monitor.renderTime * 1000))ms")
                .font(.system(.caption2, design: .monospaced))

            Text("Avg Render: \(String(format: "%.2f", monitor.averageRenderTime * 1000))ms")
                .font(.system(.caption2, design: .monospaced))

            Text("Messages: \(monitor.messageCount)")
                .font(.system(.caption2, design: .monospaced))
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .foregroundColor(.white)
        .cornerRadius(6)
    }
}

/// 消息预加载管理器
actor MessagePreloader {
    private var preloadedMessages: Set<String> = []

    func shouldPreload(_ messageId: String) -> Bool {
        !preloadedMessages.contains(messageId)
    }

    func markPreloaded(_ messageId: String) {
        preloadedMessages.insert(messageId)
    }

    func clear() {
        preloadedMessages.removeAll()
    }
}

/// 消息批量操作
struct MessageBatchOperations {
    @MainActor
    static func deleteMessages(_ messages: [AXChatMessage], from session: ChatSessionModel) {
        let idsToDelete = Set(messages.map { $0.id })
        session.messages.removeAll { idsToDelete.contains($0.id) }
    }

    static func copyMessages(_ messages: [AXChatMessage]) {
        let text = messages.map { message in
            let role = message.role.rawValue.capitalized
            let timestamp = Date(timeIntervalSince1970: message.createdAt).formatted()
            return "[\(role)] \(timestamp)\n\(message.content)"
        }.joined(separator: "\n\n---\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func filterMessages(_ messages: [AXChatMessage], by role: AXChatRole) -> [AXChatMessage] {
        messages.filter { $0.role == role }
    }

    static func searchMessages(_ messages: [AXChatMessage], query: String) -> [AXChatMessage] {
        let lowercasedQuery = query.lowercased()
        return messages.filter { $0.content.lowercased().contains(lowercasedQuery) }
    }
}
