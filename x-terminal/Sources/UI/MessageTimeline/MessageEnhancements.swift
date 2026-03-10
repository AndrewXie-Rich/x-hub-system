import SwiftUI

/// 消息上下文菜单
struct MessageContextMenu: View {
    let message: AXChatMessage
    let onCopy: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    let onRegenerate: (() -> Void)?

    var body: some View {
        Group {
            // 复制
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            // 回复
            Button {
                onReply()
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }

            Divider()

            // 重新生成（仅 Assistant 消息）
            if message.role == .assistant, let regenerate = onRegenerate {
                Button {
                    regenerate()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }

                Divider()
            }

            // 删除
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// 消息引用预览
struct MessageReplyPreview: View {
    let replyTo: AXChatMessage
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 8) {
                // 左侧竖线
                Rectangle()
                    .fill(replyColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    // 回复对象
                    Text(replyToLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(replyColor)

                    // 消息预览
                    Text(replyTo.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var replyToLabel: String {
        switch replyTo.role {
        case .user:
            return "Replying to You"
        case .assistant:
            return "Replying to Assistant"
        case .tool:
            return "Replying to Tool"
        }
    }

    private var replyColor: Color {
        switch replyTo.role {
        case .user:
            return .blue
        case .assistant:
            return .purple
        case .tool:
            return .secondary
        }
    }
}

/// 消息反应（Emoji）
struct MessageReactions: View {
    let reactions: [String: Int] // emoji -> count
    let onReact: (String) -> Void
    let onShowAll: () -> Void

    private let maxVisible = 5

    var body: some View {
        HStack(spacing: 6) {
            // 显示前几个反应
            ForEach(Array(reactions.keys.prefix(maxVisible)), id: \.self) { emoji in
                ReactionBubble(
                    emoji: emoji,
                    count: reactions[emoji] ?? 0,
                    onTap: {
                        onReact(emoji)
                    }
                )
            }

            // 更多按钮
            if reactions.count > maxVisible {
                Button {
                    onShowAll()
                } label: {
                    Text("+\(reactions.count - maxVisible)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            // 添加反应按钮
            Button {
                // 显示 emoji 选择器
            } label: {
                Image(systemName: "face.smiling")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 单个反应气泡
struct ReactionBubble: View {
    let emoji: String
    let count: Int
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.caption)

                if count > 1 {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isPressed ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isPressed ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2)) {
                        isPressed = false
                    }
                }
        )
    }
}

/// 代码块视图（带语法高亮）
struct CodeBlockView: View {
    let code: String
    let language: String

    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    copyCode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied" : "Copy")
                    }
                    .font(.caption)
                    .foregroundColor(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))

            Divider()

            // 代码内容
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxHeight: 400)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

/// Markdown 渲染视图（简化版）
struct SimpleMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdown(), id: \.id) { block in
                renderBlock(block)
            }
        }
    }

    private func parseMarkdown() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        var currentCodeBlock: [String] = []
        var inCodeBlock = false
        var codeLanguage = ""

        for line in lines {
            let lineStr = String(line)

            // 代码块
            if lineStr.hasPrefix("```") {
                if inCodeBlock {
                    // 结束代码块
                    blocks.append(MarkdownBlock(
                        type: .code(language: codeLanguage),
                        content: currentCodeBlock.joined(separator: "\n")
                    ))
                    currentCodeBlock = []
                    inCodeBlock = false
                    codeLanguage = ""
                } else {
                    // 开始代码块
                    inCodeBlock = true
                    codeLanguage = String(lineStr.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if inCodeBlock {
                currentCodeBlock.append(lineStr)
                continue
            }

            // 标题
            if lineStr.hasPrefix("#") {
                let level = lineStr.prefix(while: { $0 == "#" }).count
                let text = lineStr.dropFirst(level).trimmingCharacters(in: .whitespaces)
                blocks.append(MarkdownBlock(type: .heading(level: level), content: text))
                continue
            }

            // 普通文本
            if !lineStr.isEmpty {
                blocks.append(MarkdownBlock(type: .text, content: lineStr))
            }
        }

        return blocks
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block.type {
        case .text:
            Text(block.content)
                .font(.body)
                .textSelection(.enabled)

        case .heading(let level):
            Text(block.content)
                .font(headingFont(level: level))
                .fontWeight(.bold)
                .textSelection(.enabled)

        case .code(let language):
            CodeBlockView(code: block.content, language: language)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }
}

struct MarkdownBlock: Identifiable {
    let id = UUID()
    let type: BlockType
    let content: String

    enum BlockType {
        case text
        case heading(level: Int)
        case code(language: String)
    }
}
