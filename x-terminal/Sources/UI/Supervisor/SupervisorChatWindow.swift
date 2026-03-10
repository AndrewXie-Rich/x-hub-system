//
//  SupervisorChatWindow.swift
//  XTerminal
//
//  Created by Claude on 2026-02-27.
//

import SwiftUI

/// Supervisor 对话窗口
/// 提供与 Supervisor 的对话界面
struct SupervisorChatWindow: View {
    @ObservedObject var supervisor: SupervisorModel
    @State private var inputText: String = ""
    @State private var showQuickCommands: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            titleBar

            Divider()

            // 消息时间线
            messageTimeline

            Divider()

            // 输入区域
            inputArea
        }
        .frame(width: 600, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Subviews

    private var titleBar: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.purple)
                .font(.system(size: 16))

            Text("Supervisor Chat")
                .font(.headline)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var messageTimeline: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 欢迎消息
                welcomeMessage

                // 实际消息列表
                // 这里应该复用 MessageTimelineView
                // 简化实现：显示占位符
                ForEach(0..<3, id: \.self) { index in
                    messagePlaceholder(index: index)
                }
            }
            .padding()
        }
    }

    private var welcomeMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                Text("Supervisor")
                    .font(.headline)
                Spacer()
                Text("刚刚")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("你好！我是 Supervisor，负责管理所有项目。有什么我可以帮助你的吗？")
                .font(.body)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.1))
                )

            Text("💡 快速命令: /status /authorize /memory /help")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func messagePlaceholder(index: Int) -> some View {
        HStack {
            if index % 2 == 0 {
                Spacer()
            }

            VStack(alignment: index % 2 == 0 ? .trailing : .leading, spacing: 4) {
                Text(index % 2 == 0 ? "You" : "Supervisor")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("消息内容 \(index + 1)")
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(index % 2 == 0 ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
                    )
            }
            .frame(maxWidth: 400)

            if index % 2 != 0 {
                Spacer()
            }
        }
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            // 快速命令建议
            if showQuickCommands {
                QuickCommandsView { command in
                    inputText = command
                    showQuickCommands = false
                }
            }

            // 输入框和发送按钮
            HStack(spacing: 12) {
                TextField("Ask Supervisor anything...", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .onChange(of: inputText) { newValue in
                        showQuickCommands = newValue.hasPrefix("/")
                    }
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }

            // 提示文本
            Text("💡 快速命令: /status /authorize /memory /help")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        let message = inputText
        inputText = ""

        Task {
            await supervisor.sendMessage(message)
        }
    }
}

/// 快速命令视图
struct QuickCommandsView: View {
    let onSelect: (String) -> Void

    let commands = [
        ("/status", "显示所有项目状态"),
        ("/authorize", "显示待审批列表"),
        ("/memory", "查看记忆管理"),
        ("/help", "显示帮助信息")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(commands, id: \.0) { command, description in
                Button(action: { onSelect(command) }) {
                    HStack {
                        Text(command)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)

                        Spacer()

                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(radius: 4)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct SupervisorChatWindow_Previews: PreviewProvider {
    static var previews: some View {
        SupervisorChatWindow(supervisor: SupervisorModel.preview)
    }
}
#endif
