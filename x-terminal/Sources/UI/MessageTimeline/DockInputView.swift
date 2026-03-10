import SwiftUI

/// 现代化的底部 Dock 输入框，替代原来的 inputBar
struct DockInputView: View {
    let ctx: AXProjectContext
    let memory: AXMemory?
    let config: AXProjectConfig?
    let hubConnected: Bool
    @ObservedObject var session: ChatSessionModel
    @EnvironmentObject private var appModel: AppModel

    @FocusState private var isFocused: Bool
    @State private var inputHeight: CGFloat = 44
    @State private var showSlashSuggestions = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部渐变阴影
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0.08), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 12)
                .allowsHitTesting(false)

            // 主输入区域
            VStack(spacing: 12) {
                // Slash 命令建议
                if showSlashSuggestions {
                    SlashSuggestionsView(
                        draft: $session.draft,
                        modelsState: appModel.modelsState,
                        onSelect: { suggestion in
                            session.draft = suggestion
                            showSlashSuggestions = false
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 输入框容器
                HStack(alignment: .bottom, spacing: 12) {
                    // 左侧：附件和设置按钮
                    VStack(spacing: 8) {
                        // 模型选择器
                        ModelSelectorButton(config: config)
                            .environmentObject(appModel)

                        // 语音输入
                        VoiceInputButton(text: $session.draft)
                    }

                    // 中间：输入框
                    ZStack(alignment: .topLeading) {
                        // 占位符
                        if session.draft.isEmpty && !isFocused {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.tertiary)
                                Text("Ask anything or type / for commands...")
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                        }

                        // 自动扩展的文本编辑器
                        TextEditor(text: $session.draft)
                            .font(.body)
                            .focused($isFocused)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 44, maxHeight: 200)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .disabled(false) // 始终允许输入
                            .onChange(of: session.draft) { newValue in
                                showSlashSuggestions = newValue.hasPrefix("/") && session.pendingToolCalls.isEmpty
                            }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(inputBorderColor, lineWidth: isFocused ? 2 : 1)
                    )
                    .onTapGesture {
                        isFocused = true
                    }

                    // 右侧：发送/取消按钮
                    VStack(spacing: 8) {
                        // 发送按钮
                        Button {
                            if session.isSending {
                                session.cancel()
                            } else {
                                sendMessage()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(sendButtonBackground)
                                    .frame(width: 44, height: 44)

                                Image(systemName: sendButtonIcon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .shadow(color: sendButtonShadow, radius: 4, y: 2)

                        // 自动运行工具开关
                        Toggle("", isOn: $session.autoRunTools)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!hubConnected)
                            .help("Auto-run tools")
                    }
                }
                .padding(.horizontal, 20)

                // 底部状态栏
                HStack(spacing: 12) {
                    // 连接状态
                    if !hubConnected {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.red)
                            Text("Hub not connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // 快捷键提示
                    HStack(spacing: 4) {
                        Text("⌘↩")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text("to send")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // 错误提示
                if let error = session.lastError, !error.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .padding(.vertical, 12)
            .background(
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                        .allowsHitTesting(false)
            )
        }
        .frame(maxWidth: 900) // 限制最大宽度
        .frame(maxWidth: .infinity)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    private var canSend: Bool {
        if session.isSending {
            return true // 可以取消
        }
        return hubConnected && !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && session.pendingToolCalls.isEmpty
    }

    private var sendButtonIcon: String {
        session.isSending ? "stop.fill" : "arrow.up"
    }

    private var sendButtonBackground: LinearGradient {
        if !canSend {
            return LinearGradient(
                colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if session.isSending {
            return LinearGradient(
                colors: [Color.red, Color.red.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sendButtonShadow: Color {
        if session.isSending {
            return Color.red.opacity(0.3)
        }
        return canSend ? Color.accentColor.opacity(0.3) : Color.clear
    }

    private var inputBorderColor: Color {
        if !hubConnected {
            return Color.red.opacity(0.3)
        }
        return isFocused ? Color.accentColor : Color.secondary.opacity(0.2)
    }

    private func sendMessage() {
        session.send(ctx: ctx, memory: memory, config: config, router: appModel.llmRouter)
        isFocused = true
    }
}

/// 模型选择器按钮
struct ModelSelectorButton: View {
    let config: AXProjectConfig?
    @EnvironmentObject private var appModel: AppModel
    @State private var showModelPicker = false

    var body: some View {
        Button {
            showModelPicker = true
        } label: {
            Image(systemName: "cpu")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .help("Select Model")
        .popover(isPresented: $showModelPicker) {
            ModelSelectorView(config: config)
                .environmentObject(appModel)
                .frame(width: 300)
        }
    }
}

/// Slash 命令建议视图
struct SlashSuggestionsView: View {
    @Binding var draft: String
    let modelsState: ModelStateSnapshot
    let onSelect: (String) -> Void

    private var suggestions: [SlashSuggestion] {
        let lower = draft.lowercased()

        // /model 命令
        if lower == "/model" || lower.hasPrefix("/model ") {
            let query = String(lower.dropFirst("/model".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            var items = modelsState.models
                .filter { $0.state == .loaded }
                .sorted { $0.id.lowercased() < $1.id.lowercased() }
                .map { model in
                    SlashSuggestion(
                        title: "/model \(model.id)",
                        subtitle: model.backend,
                        insertion: "/model \(model.id)"
                    )
                }

            if query.isEmpty || "auto".hasPrefix(query) {
                items.insert(
                    SlashSuggestion(
                        title: "/model auto",
                        subtitle: "Use default model",
                        insertion: "/model auto"
                    ),
                    at: 0
                )
            }

            if !query.isEmpty {
                items = items.filter { $0.insertion.lowercased().contains(query) }
            }

            return items
        }

        // 基础命令
        let base: [SlashSuggestion] = [
            SlashSuggestion(title: "/models", subtitle: "Show available models", insertion: "/models"),
            SlashSuggestion(title: "/model <id>", subtitle: "Select a model", insertion: "/model "),
            SlashSuggestion(title: "/tools", subtitle: "Tool policy settings", insertion: "/tools"),
            SlashSuggestion(title: "/hub route", subtitle: "Hub transport mode", insertion: "/hub route"),
            SlashSuggestion(title: "/network 30m", subtitle: "Request network access", insertion: "/network 30m"),
            SlashSuggestion(title: "/clear", subtitle: "Clear chat history", insertion: "/clear"),
            SlashSuggestion(title: "/help", subtitle: "Show help", insertion: "/help"),
        ]

        if lower == "/" {
            return base
        }

        let query = String(lower.dropFirst())
        return base.filter { $0.insertion.lowercased().contains(query) || $0.title.lowercased().contains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions.prefix(8)) { suggestion in
                    Button {
                        onSelect(suggestion.insertion)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "command")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 14))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.primary)

                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                    if suggestion.id != suggestions.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: 300)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal, 20)
    }
}

struct SlashSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let insertion: String
}

/// 毛玻璃效果
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
