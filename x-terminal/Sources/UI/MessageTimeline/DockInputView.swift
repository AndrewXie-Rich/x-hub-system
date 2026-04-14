import SwiftUI

/// 现代化的底部 Dock 输入框，替代原来的 inputBar
struct DockInputView: View {
    let ctx: AXProjectContext
    let memory: AXMemory?
    let config: AXProjectConfig?
    let hubConnected: Bool
    @ObservedObject var session: ChatSessionModel
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var modelManager = HubModelManager.shared

    @State private var isFocused: Bool = false
    @State private var inputHeight: CGFloat = 44
    @State private var showSlashSuggestions = false
    @State private var isAttachmentDropTarget = false
    @State private var attachmentDropIntent: XTChatComposerDropIntent? = nil

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
                        modelsState: modelManager.visibleSnapshot(fallback: appModel.modelsState),
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
                        ModelSelectorButton(ctx: ctx, config: config)
                            .environmentObject(appModel)

                        // 语音输入
                        VoiceInputButton(text: $session.draft)
                    }

                    // 中间：输入框
                    VStack(alignment: .leading, spacing: 10) {
                        if !session.draftAttachments.isEmpty {
                            XTChatProjectInboxPanel(
                                attachments: session.draftAttachments,
                                projectImportEnabled: true,
                                continuation: session.importContinuation,
                                onRemove: session.removeDraftAttachment,
                                onImport: { session.importAttachmentToProject($0, ctx: ctx) },
                                onImportAll: { session.importAllExternalDraftAttachments(ctx: ctx) },
                                onContinue: {
                                    session.dismissImportContinuation()
                                    isFocused = true
                                },
                                onContinueAndSend: {
                                    session.dismissImportContinuation()
                                    sendMessage()
                                },
                                canContinueAndSend: hubConnected &&
                                    !session.isSending &&
                                    session.pendingToolCalls.isEmpty &&
                                    AXChatAttachmentSupport.hasSubmittableContent(
                                        draft: session.draft,
                                        attachments: session.draftAttachments
                                    ),
                                onDismissContinuation: session.dismissImportContinuation
                            )
                        }

                        ZStack(alignment: .topLeading) {
                            // 占位符
                            if session.draft.isEmpty && session.draftAttachments.isEmpty && !isFocused {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.tertiary)
                                    Text("想问什么都可以，输入 / 查看命令…")
                                        .foregroundStyle(.tertiary)
                                }
                                .font(.body)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                            }

                            // 自动扩展的文本编辑器
                            XTChatComposerTextView(
                                text: $session.draft,
                                isFocused: $isFocused,
                                canSubmit: canSend && !session.isSending,
                                diagnosticScope: "coder_dock",
                                onSubmit: sendMessage,
                                allowsImportDrop: true,
                                onDropFiles: handleDroppedFiles,
                                onDropHoverChange: {
                                    isAttachmentDropTarget = $0
                                    if !$0 {
                                        attachmentDropIntent = nil
                                    }
                                },
                                onDropIntentChange: { attachmentDropIntent = $0 }
                            )
                                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 200)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .disabled(false) // 始终允许输入
                                .onChange(of: session.draft) { newValue in
                                    showSlashSuggestions = newValue.hasPrefix("/") && session.pendingToolCalls.isEmpty
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isAttachmentDropTarget ? Color.orange.opacity(0.7) : inputBorderColor,
                                lineWidth: isAttachmentDropTarget ? 2 : (isFocused ? 2 : 1)
                            )
                            .allowsHitTesting(false)
                    )
                    .overlay {
                        if isAttachmentDropTarget {
                            XTChatContextDock(
                                activeIntent: attachmentDropIntent,
                                importEnabled: true
                            )
                            .padding(10)
                            .allowsHitTesting(false)
                        }
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
                            .help("自动执行工具（Auto-run tools）")
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
                            Text("Hub 未连接")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已连接")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // 快捷键提示
                    HStack(spacing: 4) {
                        Text("↩")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text("发送")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("⇧↩")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text("换行")
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
            modelManager.setAppModel(appModel)
            if appModel.hubInteractive {
                Task {
                    await modelManager.fetchModels()
                }
            }
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: appModel.hubInteractive) { connected in
            if connected {
                Task {
                    await modelManager.fetchModels()
                }
            }
        }
    }

    private var canSend: Bool {
        if session.isSending {
            return true // 可以取消
        }
        return hubConnected &&
            AXChatAttachmentSupport.hasSubmittableContent(
                draft: session.draft,
                attachments: session.draftAttachments
            ) &&
            session.pendingToolCalls.isEmpty
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

    private func handleDroppedFiles(
        _ urls: [URL],
        intent: XTChatComposerDropIntent
    ) {
        switch intent {
        case .attachReadOnly:
            session.handleDroppedFiles(urls, ctx: ctx)
        case .importToProject:
            session.importDroppedFilesToProject(urls, ctx: ctx)
        }
        attachmentDropIntent = nil
        isFocused = true
    }
}

/// 模型选择器按钮
struct ModelSelectorButton: View {
    let ctx: AXProjectContext
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
        .help("选择模型（Select Model）")
        .popover(isPresented: $showModelPicker) {
            ModelSelectorView(projectContext: ctx, config: config)
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
                        subtitle: "使用默认模型",
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
            SlashSuggestion(title: "/models", subtitle: "查看可用模型", insertion: "/models"),
            SlashSuggestion(title: "/model <id>", subtitle: "选择模型", insertion: "/model "),
            SlashSuggestion(title: "/tools", subtitle: "工具策略设置", insertion: "/tools"),
            SlashSuggestion(title: "/hub route", subtitle: "Hub 传输模式", insertion: "/hub route"),
            SlashSuggestion(title: "/route diagnose", subtitle: "诊断当前模型路由", insertion: "/route diagnose"),
            SlashSuggestion(title: "/network 30m", subtitle: "申请网络访问", insertion: "/network 30m"),
            SlashSuggestion(title: "/clear", subtitle: "清空聊天记录", insertion: "/clear"),
            SlashSuggestion(title: "/help", subtitle: "查看帮助", insertion: "/help"),
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
