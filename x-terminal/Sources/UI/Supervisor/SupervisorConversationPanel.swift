import SwiftUI
import AppKit

struct SupervisorConversationPanel: View {
    @EnvironmentObject private var workSurfaceStore: XTWorkSurfaceStore
    let supervisor: SupervisorManager
    @Binding var inputText: String
    @Binding var autoSendVoice: Bool
    var focusRequestID: Int = 0

    @StateObject private var timelineStore = SupervisorConversationTimelineStore(
        minimumUpdateIntervalNanoseconds: 16_000_000
    )
    @State private var isInputFocused: Bool = false
    @State private var draftText: String = ""
    @State private var draftAttachments: [AXChatAttachment] = []
    @State private var importContinuation: AXChatImportContinuationSuggestion?
    @State private var isAttachmentDropTarget = false
    @State private var attachmentDropIntent: XTChatComposerDropIntent? = nil
    @State private var lastHandledFocusRequestID: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            messageList
                .frame(maxHeight: .infinity)

            Divider()

            inputArea
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            timelineStore.bind(to: supervisor)
            lastHandledFocusRequestID = focusRequestID
            draftText = SupervisorConversationComposerSupport.syncedDraft(
                currentDraft: draftText,
                externalInput: inputText
            )
            if SupervisorConversationFocusSupport.shouldFocusOnAppear(
                latestWindowRequest: SupervisorConversationWindowBridge.shared.latestRequest
            ) {
                requestInputFocus()
            }
        }
        .onChange(of: supervisorIdentity) { _ in
            timelineStore.bind(to: supervisor)
        }
        .onChange(of: inputText) { newValue in
            draftText = SupervisorConversationComposerSupport.syncedDraft(
                currentDraft: draftText,
                externalInput: newValue
            )
        }
        .onChange(of: focusRequestID) { _ in
            guard SupervisorConversationFocusSupport.shouldFocusForExplicitRequest(
                lastHandledRequestID: lastHandledFocusRequestID,
                currentRequestID: focusRequestID
            ) else { return }
            lastHandledFocusRequestID = focusRequestID
            requestInputFocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .xterminalOpenSupervisorWindow)) { notification in
            let request = SupervisorConversationWindowOpenRequest(notification: notification)
            guard SupervisorConversationFocusSupport.shouldFocusForWindowOpenRequest(request) else { return }
            requestInputFocus()
        }
    }

    private func requestInputFocus() {
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }

    private var messageList: some View {
        let snapshot = timelineSnapshot
        let rows = snapshot.rows

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if rows.isEmpty {
                        emptyState
                    } else {
                        ForEach(rows) { row in
                            SupervisorMessageBubble(
                                message: row.message,
                                thinkingPresentation: row.thinkingPresentation,
                                onImportAttachment: handleImportAttachmentFromMessage
                            )
                            .id(row.message.id)
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: snapshot.messageCount) { _ in
                if let lastMessage = rows.last?.message {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: snapshot.lastMessageContent) { _ in
                if let lastMessage = rows.last?.message {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .onChange(of: snapshot.processingStatusText) { _ in
                if let lastMessage = rows.last?.message {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .onChange(of: snapshot.placeholderStatusText) { _ in
                if let lastMessage = rows.last?.message {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    private var timelineSnapshot: SupervisorConversationTimelineSnapshot {
        if timelineStore.isBound(to: supervisor) {
            return timelineStore.snapshot
        }
        return SupervisorConversationTimelineSnapshot.make(from: supervisor)
    }

    private var supervisorIdentity: ObjectIdentifier {
        ObjectIdentifier(supervisor)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34))
                .foregroundColor(.secondary)

            Text("开始和 Supervisor 对话")
                .font(.title3.weight(.semibold))

            Text("这里会显示对话历史。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !draftAttachments.isEmpty {
                XTChatProjectInboxPanel(
                    attachments: draftAttachments,
                    title: "Supervisor Inbox",
                    projectImportEnabled: projectContext != nil,
                    continuation: importContinuation,
                    onRemove: removeDraftAttachment,
                    onImport: importDraftAttachment,
                    onImportAll: importAllDraftAttachments,
                    onContinue: applyImportContinuation,
                    onContinueAndSend: {
                        guard let transition = SupervisorConversationComposerSupport.continueAndSendTransition(
                            draft: draftText,
                            attachments: draftAttachments,
                            continuation: importContinuation
                        ) else {
                            return
                        }
                        supervisor.sendMessage(
                            transition.payload,
                            attachments: transition.attachments,
                            fromVoice: false
                        )
                        draftText = transition.nextDraft
                        inputText = transition.nextInput
                        draftAttachments = transition.nextAttachments
                        importContinuation = nil
                        isInputFocused = true
                    },
                    canContinueAndSend: canSubmitConversation,
                    onDismissContinuation: { importContinuation = nil }
                )
            }

            HStack(alignment: .bottom, spacing: 12) {
                XTChatComposerTextView(
                    text: $draftText,
                    isFocused: $isInputFocused,
                    font: .preferredFont(forTextStyle: .body),
                    canSubmit: canSubmitConversation,
                    diagnosticScope: "supervisor_conversation",
                    onSubmit: submitInput,
                    allowsImportDrop: projectContext != nil,
                    onDropFiles: handleDroppedFiles,
                    onDropHoverChange: {
                        isAttachmentDropTarget = $0
                        if !$0 {
                            attachmentDropIntent = nil
                        }
                    },
                    onDropIntentChange: { attachmentDropIntent = $0 }
                )
                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 120)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isAttachmentDropTarget
                                    ? Color.orange.opacity(0.7)
                                : Color.secondary.opacity(0.3),
                            lineWidth: isAttachmentDropTarget ? 2 : 1
                            )
                            .allowsHitTesting(false)
                    )
                    .overlay {
                        if isAttachmentDropTarget {
                            XTChatContextDock(
                                activeIntent: attachmentDropIntent,
                                importEnabled: projectContext != nil
                            )
                            .padding(10)
                            .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: draftText) { newValue in
                        inputText = SupervisorConversationComposerSupport.syncedInput(
                            currentInput: inputText,
                            draft: newValue
                        )
                    }

                VStack(spacing: 8) {
                    VoiceInputButton(text: $draftText, autoAppend: !autoSendVoice) { recognized in
                        handleVoiceRecognized(recognized)
                    }

                    Button(action: submitInput) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmitConversation)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func submitInput() {
        guard let transition = SupervisorConversationComposerSupport.submissionTransition(
            draft: draftText,
            attachments: draftAttachments
        ) else {
            return
        }

        supervisor.sendMessage(
            transition.payload,
            attachments: transition.attachments,
            fromVoice: false
        )
        draftText = transition.nextDraft
        inputText = transition.nextInput
        draftAttachments = transition.nextAttachments
        importContinuation = nil
        isInputFocused = true
    }

    private func handleVoiceRecognized(_ recognized: String) {
        guard let transition = SupervisorConversationComposerSupport.autoSendVoiceTransition(
            recognized: recognized,
            autoSendVoice: autoSendVoice,
            attachments: draftAttachments
        ) else {
            return
        }

        supervisor.sendMessage(
            transition.payload,
            attachments: transition.attachments,
            fromVoice: true
        )
        draftText = transition.nextDraft
        inputText = transition.nextInput
        draftAttachments = transition.nextAttachments
        importContinuation = nil
        isInputFocused = true
    }

    private var canSubmitConversation: Bool {
        AXChatAttachmentSupport.hasSubmittableContent(
            draft: draftText,
            attachments: draftAttachments
        )
    }

    private func handleDroppedFiles(
        _ urls: [URL],
        intent: XTChatComposerDropIntent
    ) {
        switch intent {
        case .attachReadOnly:
            attachDroppedFiles(urls)
        case .importToProject:
            importDroppedFilesToProject(urls)
        }
        attachmentDropIntent = nil
        isInputFocused = true
    }

    private func attachDroppedFiles(_ urls: [URL]) {
        let resolved = AXChatAttachmentSupport.resolveDroppedURLs(
            urls,
            projectRoot: projectContext?.root
        )
        guard !resolved.isEmpty else { return }
        draftAttachments = AXChatAttachmentSupport.merge(
            existing: draftAttachments,
            resolved: resolved
        )
        isInputFocused = true
    }

    private func importDroppedFilesToProject(_ urls: [URL]) {
        guard let ctx = projectContext else {
            attachDroppedFiles(urls)
            _ = supervisor.appendLocalAssistantNotice("当前没有选中项目，已先把文件作为只读附件加入会话。")
            return
        }

        let resolved = AXChatAttachmentSupport.resolveDroppedURLs(
            urls,
            projectRoot: ctx.root
        )
        guard !resolved.isEmpty else { return }

        let workspaceAttachments = resolved.filter { !$0.isReadOnlyExternal }
        if !workspaceAttachments.isEmpty {
            draftAttachments = AXChatAttachmentSupport.merge(
                existing: draftAttachments,
                resolved: workspaceAttachments
            )
        }

        let externalAttachments = resolved.filter(\.isReadOnlyExternal)
        guard !externalAttachments.isEmpty else { return }
        importAttachmentsToProject(externalAttachments, ctx: ctx)
    }

    private func removeDraftAttachment(_ attachment: AXChatAttachment) {
        draftAttachments.removeAll { $0.id == attachment.id }
        refreshImportContinuation()
    }

    private func importDraftAttachment(_ attachment: AXChatAttachment) {
        guard let ctx = projectContext else {
            _ = supervisor.appendLocalAssistantNotice("当前没有选中项目，暂时不能把附件导入工作区。")
            return
        }

        importAttachmentsToProject([attachment], ctx: ctx)
    }

    private func importAllDraftAttachments() {
        guard let ctx = projectContext else {
            _ = supervisor.appendLocalAssistantNotice("当前没有选中项目，暂时不能把附件导入工作区。")
            return
        }

        let pending = draftAttachments.filter(\.isReadOnlyExternal)
        guard !pending.isEmpty else { return }
        importAttachmentsToProject(pending, ctx: ctx)
    }

    private func handleImportAttachmentFromMessage(_ attachment: AXChatAttachment) {
        guard let ctx = projectContext else {
            _ = supervisor.appendLocalAssistantNotice("当前没有选中项目，暂时不能把附件导入工作区。")
            return
        }

        importAttachmentsToProject([attachment], ctx: ctx)
        requestInputFocus()
    }

    private func importAttachmentsToProject(
        _ attachments: [AXChatAttachment],
        ctx: AXProjectContext
    ) {
        var importedResults: [AXChatAttachmentImportResult] = []
        var failures: [String] = []

        for attachment in attachments {
            do {
                let result = try AXChatAttachmentSupport.importAttachment(attachment, into: ctx.root)
                AXProjectStore.appendRawLog(
                    [
                        "type": "attachment_import",
                        "created_at": Date().timeIntervalSince1970,
                        "source_path": attachment.path,
                        "destination_path": result.destinationURL.path,
                        "kind": attachment.kind.rawValue,
                        "scope": attachment.scope.rawValue,
                    ],
                    for: ctx
                )
                draftAttachments.removeAll {
                    PathGuard.resolve(URL(fileURLWithPath: $0.path)).path ==
                        PathGuard.resolve(URL(fileURLWithPath: attachment.path)).path
                }
                draftAttachments = AXChatAttachmentSupport.merge(
                    existing: draftAttachments,
                    resolved: [result.importedAttachment]
                )
                importedResults.append(result)
            } catch {
                failures.append("\(attachment.displayName)：\(error.localizedDescription)")
            }
        }

        if let notice = AXChatAttachmentSupport.importSuccessNotice(results: importedResults) {
            _ = supervisor.appendLocalAssistantNotice(notice)
        }

        importContinuation = AXChatAttachmentSupport.importContinuationSuggestion(
            results: importedResults,
            projectRoot: ctx.root
        )

        for failure in failures {
            _ = supervisor.appendLocalAssistantNotice("导入附件失败：\(failure)")
        }
    }

    private func applyImportContinuation() {
        draftText = SupervisorConversationComposerSupport.applyingImportContinuation(
            draft: draftText,
            continuation: importContinuation
        )
        inputText = draftText
        importContinuation = nil
        requestInputFocus()
    }

    private func refreshImportContinuation() {
        guard let importContinuation else { return }
        guard importContinuation.isRelevant(to: draftAttachments) else {
            self.importContinuation = nil
            return
        }
    }

    private var workSurfaceSnapshot: XTWorkSurfaceSnapshot {
        workSurfaceStore.snapshot
    }

    private var projectContext: AXProjectContext? {
        workSurfaceSnapshot.projectContext
    }
}

struct SupervisorMessageBubble: View {
    let message: SupervisorMessage
    var thinkingPresentation: XTStreamingPlaceholderPresentation? = nil
    var onImportAttachment: ((AXChatAttachment) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(roleText)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if message.isVoice {
                        Image(systemName: "mic.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Group {
                    if let thinkingPresentation,
                       message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        XTStreamingPlaceholderView(presentation: thinkingPresentation)
                    } else {
                        Text(message.content)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .background(backgroundColor)
                .cornerRadius(12)

                if !message.attachments.isEmpty {
                    XTChatAttachmentStrip(
                        attachments: message.attachments,
                        showsPath: true,
                        onImport: onImportAttachment
                    )
                }
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
                .frame(width: 32, height: 32)

            Image(systemName: iconName)
                .foregroundColor(.white)
                .font(.system(size: 14))
        }
    }

    private var roleText: String {
        switch message.role {
        case .user:
            return "你"
        case .assistant:
            return "Supervisor"
        case .system:
            return "系统"
        }
    }

    private var iconName: String {
        switch message.role {
        case .user:
            return "person.fill"
        case .assistant:
            return "person.3.fill"
        case .system:
            return "gear.fill"
        }
    }

    private var avatarColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return .accentColor
        case .system:
            return .gray
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.12)
        case .assistant:
            return Color.accentColor.opacity(0.12)
        case .system:
            return Color.secondary.opacity(0.1)
        }
    }

    private var timeText: String {
        let date = Date(timeIntervalSince1970: message.timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
