import AppKit
import SwiftUI

struct TerminalChatView: View {
    let ctx: AXProjectContext
    let memory: AXMemory?
    let config: AXProjectConfig?
    let hubConnected: Bool
    @ObservedObject var session: ChatSessionModel
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var modelManager = HubModelManager.shared
    @State private var isInputFocused: Bool = false
    @State private var isAttachmentDropTarget: Bool = false
    @State private var attachmentDropIntent: XTChatComposerDropIntent? = nil

    private struct SlashSuggestion: Identifiable {
        var id: String { insertion }
        let title: String
        let subtitle: String
        let insertion: String
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript

            if !session.pendingToolCalls.isEmpty {
                pendingApprovalBar
            }

            Divider()

            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            session.ensureLoaded(ctx: ctx, limit: 200)
            modelManager.setAppModel(appModel)
            if appModel.hubInteractive {
                Task {
                    await modelManager.fetchModels()
                }
            }
        }
        .onChange(of: ctx.root.path) { _ in
            session.ensureLoaded(ctx: ctx, limit: 200)
        }
        .onChange(of: appModel.hubInteractive) { connected in
            if connected {
                Task {
                    await modelManager.fetchModels()
                }
            }
        }
    }

    private var transcript: some View {
        ZStack(alignment: .bottomLeading) {
            TranscriptTextView(attributedText: transcriptAttributed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if session.isSending {
                HStack(spacing: 8) {
                    Text("assistant")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    ThinkingDotsView()
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var pendingApprovalBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("待批准：\(session.pendingToolCalls.count) 个工具调用")
                    .font(.system(.body, design: .monospaced))
                Spacer(minLength: 0)
                Button("批准并执行") {
                    session.approvePendingTools(router: appModel.llmRouter)
                }
                .disabled(!hubConnected)
                Button("拒绝") {
                    session.rejectPendingTools()
                }
            }

            ScrollView(.horizontal) {
                Text(pendingSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
    }

    private var pendingSummary: String {
        session.pendingToolCalls.map { c in
            let keys = c.args.keys.sorted().joined(separator: ",")
            return "- \(c.tool.rawValue) id=\(c.id) args=\(keys)"
        }.joined(separator: "\n")
    }

    private var inputBar: some View {
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ModelSelectorView(projectContext: ctx, config: config)
                    .environmentObject(appModel)

                VoiceInputButton(text: $session.draft)

                Toggle("自动执行工具", isOn: $session.autoRunTools)
                    .toggleStyle(.switch)
                    .disabled(!hubConnected)

                Spacer(minLength: 0)

                Button("取消") { session.cancel() }
                    .disabled(!session.isSending)

                Button(session.isSending ? "发送中…" : "发送") {
                    sendMessage()
                }
                .disabled(
                    !hubConnected ||
                        session.isSending ||
                        !session.pendingToolCalls.isEmpty ||
                        !AXChatAttachmentSupport.hasSubmittableContent(
                            draft: session.draft,
                            attachments: session.draftAttachments
                        )
                )
                .keyboardShortcut(.return, modifiers: [.command])
            }

            memoryRouteRail
            coderExecutionStatusBar
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
                        isInputFocused = true
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
            XTChatComposerTextView(
                text: $session.draft,
                isFocused: $isInputFocused,
                font: .monospacedSystemFont(
                    ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
                    weight: .regular
                ),
                isEditable: session.pendingToolCalls.isEmpty,
                canSubmit: hubConnected &&
                    !session.isSending &&
                    session.pendingToolCalls.isEmpty &&
                    AXChatAttachmentSupport.hasSubmittableContent(
                        draft: session.draft,
                        attachments: session.draftAttachments
                    ),
                diagnosticScope: "terminal_chat",
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
                .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 140)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isAttachmentDropTarget
                                ? Color.orange.opacity(0.7)
                                : Color.secondary.opacity(0.3),
                            lineWidth: isAttachmentDropTarget ? 2 : 1
                        )
                        .allowsHitTesting(false)
                }
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

            if showSlashSuggestions {
                slashSuggestionsView
            }

            Text("回车发送 · Shift+回车换行 · Cmd+回车也可发送")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let err = session.lastError, !err.isEmpty {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            if !hubConnected {
                Text("Hub 未连接。按 Cmd+Opt+X 发起连接。")
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sendMessage() {
        guard hubConnected,
              !session.isSending,
              session.pendingToolCalls.isEmpty,
              AXChatAttachmentSupport.hasSubmittableContent(
                  draft: session.draft,
                  attachments: session.draftAttachments
              ) else {
            return
        }
        session.send(ctx: ctx, memory: memory, config: config, router: appModel.llmRouter)
        isInputFocused = true
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
        isInputFocused = true
    }

    private var memoryRouteRail: some View {
        let preferHubMemory = XTProjectMemoryGovernance.prefersHubMemory(config)
        let mode = XTProjectMemoryGovernance.modeLabel(config)
        let sourceLabel = preferHubMemory ? "优先 Hub" : "仅本地"

        return HStack(spacing: 8) {
            Label {
                Text("记忆")
            } icon: {
                Image(systemName: preferHubMemory ? "externaldrive.connected.to.line.below.fill" : "internaldrive")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(preferHubMemory ? Color.accentColor : Color.secondary)

            Text("mode=\(mode)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            Text(sourceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if preferHubMemory {
                Text(hubConnected ? "hub=reachable" : "hub=unreachable_fallback_local")
                    .font(.caption2.monospaced())
                    .foregroundStyle(hubConnected ? Color.secondary : Color.orange)
            }

            Spacer(minLength: 0)

            Button(preferHubMemory ? "改用本地" : "改用 Hub") {
                appModel.setProjectHubMemoryPreference(for: ctx, enabled: !preferHubMemory)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(session.isSending || !session.pendingToolCalls.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var coderExecutionStatusBar: some View {
        let snapshot = AXRoleExecutionSnapshots.latestSnapshots(for: ctx)[.coder]
            ?? .empty(role: .coder, source: "terminal_chat")
        let configuredModelId = AXRoleExecutionSnapshots.configuredModelId(
            for: .coder,
            projectConfig: config,
            settings: appModel.settingsStore.settings
        )
        let interfaceLanguage = appModel.settingsStore.settings.interfaceLanguage
        let primaryAction = ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            hubConnected: hubConnected,
            governanceInterception: latestGovernanceInterception,
            language: interfaceLanguage
        )

        return ProjectCoderExecutionStatusBar(
            presentation: ProjectCoderExecutionStatusResolver.map(
                configuredModelId: configuredModelId,
                snapshot: snapshot,
                hubConnected: hubConnected,
                governancePresentation: governancePresentation,
                governanceInterception: latestGovernanceInterception
            ),
            actionTitle: primaryAction?.title,
            actionHelpText: primaryAction?.helpText,
            actionDisabled: session.isSending || !session.pendingToolCalls.isEmpty,
            onAction: {
                guard let primaryAction else { return }
                ProjectCoderExecutionStatusPrimaryActionResolver.perform(
                    primaryAction.kind,
                    configuredModelId: configuredModelId,
                    snapshot: snapshot,
                    ctx: ctx,
                    config: config,
                    session: session,
                    appModel: appModel,
                    openWindow: openWindow,
                    governanceInterception: latestGovernanceInterception,
                    interfaceLanguage: interfaceLanguage
                )
            }
        )
    }

    private var governancePresentation: ProjectGovernancePresentation {
        ProjectGovernancePresentation(
            resolved: appModel.resolvedProjectGovernance(for: ctx, config: config)
        )
    }

    private var latestGovernanceInterception: ProjectGovernanceInterceptionPresentation? {
        ProjectGovernanceInterceptionPresentation.latest(
            from: AXProjectSkillActivityStore.loadRecentActivities(ctx: ctx, limit: 12)
        )
    }

    private var showSlashSuggestions: Bool {
        let t = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.hasPrefix("/") { return false }
        if !session.pendingToolCalls.isEmpty { return false }
        return true
    }

    private var slashSuggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(slashSuggestions.prefix(12)) { item in
                    Button {
                        session.draft = item.insertion
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if item.id != slashSuggestions.prefix(12).last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(minHeight: 44, maxHeight: 180)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        }
    }

    private var slashSuggestions: [SlashSuggestion] {
        let raw = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("/") else { return [] }
        let lower = raw.lowercased()

        if lower == "/model" || lower.hasPrefix("/model ") {
            let query = String(lower.dropFirst("/model".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let loaded = modelManager.visibleSnapshot(fallback: appModel.modelsState).models
                .filter { $0.state == .loaded }
                .sorted { $0.id.lowercased() < $1.id.lowercased() }
            var out = loaded.map { m in
                SlashSuggestion(
                    title: "/model \(m.id)",
                    subtitle: m.backend,
                    insertion: "/model \(m.id)"
                )
            }
            if query.isEmpty || "auto".hasPrefix(query) {
                out.insert(SlashSuggestion(title: "/model auto", subtitle: "清除项目 coder 覆盖", insertion: "/model auto"), at: 0)
            }
            if !query.isEmpty {
                out = out.filter { $0.insertion.lowercased().contains(query) }
            }
            return out
        }

        if lower == "/rolemodel" || lower.hasPrefix("/rolemodel ") {
            return [
                SlashSuggestion(title: "/rolemodel coder <model_id>", subtitle: "设置 coder", insertion: "/rolemodel coder "),
                SlashSuggestion(title: "/rolemodel coarse <model_id>", subtitle: "设置 coarse", insertion: "/rolemodel coarse "),
                SlashSuggestion(title: "/rolemodel refine <model_id>", subtitle: "设置 refine", insertion: "/rolemodel refine "),
                SlashSuggestion(title: "/rolemodel reviewer <model_id>", subtitle: "设置 reviewer", insertion: "/rolemodel reviewer "),
                SlashSuggestion(title: "/rolemodel advisor <model_id>", subtitle: "设置 advisor", insertion: "/rolemodel advisor "),
            ]
        }

        if lower == "/tools" || lower.hasPrefix("/tools ") {
            let items: [SlashSuggestion] = [
                SlashSuggestion(title: "/tools", subtitle: "show effective tool policy", insertion: "/tools"),
                SlashSuggestion(title: "/tools profile full", subtitle: "enable all built-in tools", insertion: "/tools profile full"),
                SlashSuggestion(title: "/tools profile coding", subtitle: "coding-focused tools", insertion: "/tools profile coding"),
                SlashSuggestion(title: "/tools profile minimal", subtitle: "safe read-only + status", insertion: "/tools profile minimal"),
                SlashSuggestion(title: "/tools allow group:network", subtitle: "allow need_network/web_fetch", insertion: "/tools allow group:network"),
                SlashSuggestion(title: "/tools allow group:device_automation", subtitle: "arm trusted automation surface for this project", insertion: "/tools allow group:device_automation"),
                SlashSuggestion(title: "/tools deny run_command", subtitle: "block local command execution", insertion: "/tools deny run_command"),
                SlashSuggestion(title: "/tools reset", subtitle: "reset to defaults", insertion: "/tools reset"),
            ]
            let q = String(lower.dropFirst("/tools".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                return items
            }
            return items.filter { $0.insertion.lowercased().contains(q) || $0.title.lowercased().contains(q) }
        }

        if lower == "/memory" || lower.hasPrefix("/memory ") {
            let items: [SlashSuggestion] = [
                SlashSuggestion(title: "/memory", subtitle: "show project memory routing mode", insertion: "/memory"),
                SlashSuggestion(title: "/memory on", subtitle: "prefer Hub memory for this project", insertion: "/memory on"),
                SlashSuggestion(title: "/memory off", subtitle: "use local-only project memory", insertion: "/memory off"),
                SlashSuggestion(title: "/memory default", subtitle: "reset to default Hub-preferred mode", insertion: "/memory default"),
            ]
            let q = String(lower.dropFirst("/memory".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                return items
            }
            return items.filter { $0.insertion.lowercased().contains(q) || $0.title.lowercased().contains(q) }
        }

        if lower == "/hub" || lower.hasPrefix("/hub ") {
            let items: [SlashSuggestion] = [
                SlashSuggestion(title: "/hub route", subtitle: "show current hub transport mode", insertion: "/hub route"),
                SlashSuggestion(title: "/hub route grpc", subtitle: "prefer gRPC-only session channel", insertion: "/hub route grpc"),
                SlashSuggestion(title: "/hub route auto", subtitle: "gRPC first, fallback to file IPC", insertion: "/hub route auto"),
                SlashSuggestion(title: "/hub route file", subtitle: "force local file IPC route", insertion: "/hub route file"),
            ]
            let q = String(lower.dropFirst("/hub".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                return items
            }
            return items.filter { $0.insertion.lowercased().contains(q) || $0.title.lowercased().contains(q) }
        }

        if lower == "/route" || lower.hasPrefix("/route ") {
            let items: [SlashSuggestion] = [
                SlashSuggestion(title: "/route diagnose", subtitle: "diagnose current project model route", insertion: "/route diagnose"),
            ]
            let q = String(lower.dropFirst("/route".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                return items
            }
            return items.filter { $0.insertion.lowercased().contains(q) || $0.title.lowercased().contains(q) }
        }

        if lower == "/trusted-automation" || lower.hasPrefix("/trusted-automation ") || lower == "/ta" || lower.hasPrefix("/ta ") {
            let items: [SlashSuggestion] = [
                SlashSuggestion(title: "/trusted-automation", subtitle: "show trusted automation status", insertion: "/trusted-automation"),
                SlashSuggestion(title: "/trusted-automation doctor", subtitle: "show permission owner readiness details", insertion: "/trusted-automation doctor"),
                SlashSuggestion(title: "/trusted-automation arm <device_id>", subtitle: "arm this project against a paired device", insertion: "/trusted-automation arm "),
                SlashSuggestion(title: "/trusted-automation open accessibility", subtitle: "open Accessibility settings", insertion: "/trusted-automation open accessibility"),
                SlashSuggestion(title: "/trusted-automation off", subtitle: "turn off project trusted automation", insertion: "/trusted-automation off"),
            ]
            let q = lower
                .replacingOccurrences(of: "/trusted-automation", with: "")
                .replacingOccurrences(of: "/ta", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                return items
            }
            return items.filter { $0.insertion.lowercased().contains(q) || $0.title.lowercased().contains(q) }
        }

        let base: [SlashSuggestion] = [
            SlashSuggestion(title: "/memory", subtitle: "project Hub memory preference", insertion: "/memory"),
            SlashSuggestion(title: "/tools", subtitle: "tool policy profile/allow/deny", insertion: "/tools"),
            SlashSuggestion(title: "/trusted-automation", subtitle: "project trusted automation binding", insertion: "/trusted-automation"),
            SlashSuggestion(title: "/hub route", subtitle: "set Hub transport auto/grpc/file", insertion: "/hub route"),
            SlashSuggestion(title: "/route diagnose", subtitle: "diagnose current project model route", insertion: "/route diagnose"),
            SlashSuggestion(title: "/models", subtitle: "show Hub loaded models", insertion: "/models"),
            SlashSuggestion(title: "/model <id>", subtitle: "set project coder model", insertion: "/model "),
            SlashSuggestion(title: "/network 30m", subtitle: "request network for paid models", insertion: "/network 30m"),
            SlashSuggestion(title: "/help", subtitle: "show slash help", insertion: "/help"),
            SlashSuggestion(title: "/clear", subtitle: "clear current chat view", insertion: "/clear"),
        ]

        if lower == "/" {
            return base
        }
        let q = lower.dropFirst()
        return base.filter { $0.insertion.lowercased().contains(q) || $0.title.lowercased().contains(q) }
    }

    private var transcriptAttributed: NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let small = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let out = NSMutableAttributedString()

        func appendLine(_ s: String, font: NSFont, color: NSColor) {
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: font, .foregroundColor: color]))
        }

        for msg in session.messages {
            let prefix: String
            let labelColor: NSColor = .secondaryLabelColor
            let bodyColor: NSColor
            switch msg.role {
            case .user:
                prefix = "user"
                bodyColor = .labelColor
            case .assistant:
                if let t = msg.tag, !t.isEmpty {
                    prefix = "assistant(\(t))"
                } else {
                    prefix = "assistant"
                }
                bodyColor = .labelColor
            case .tool:
                prefix = "tool"
                bodyColor = .secondaryLabelColor
            }

            appendLine(prefix, font: small, color: labelColor)
            appendLine(msg.content.isEmpty ? "…" : msg.content, font: font, color: bodyColor)
            if !msg.attachments.isEmpty {
                appendLine(
                    "attachments: " + msg.attachments.map(\.displayPath).joined(separator: ", "),
                    font: small,
                    color: .secondaryLabelColor
                )
            }
            appendLine("", font: font, color: bodyColor)
        }

        return out
    }
}
