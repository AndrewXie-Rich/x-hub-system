import SwiftUI
import AppKit

struct SupervisorConversationPanel: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var supervisor: SupervisorManager
    @Binding var inputText: String
    @Binding var autoSendVoice: Bool
    var focusRequestID: Int = 0

    @State private var isInputFocused: Bool = false
    @State private var draftText: String = ""
    @State private var draftAttachments: [AXChatAttachment] = []
    @State private var importContinuation: AXChatImportContinuationSuggestion?
    @State private var isAttachmentDropTarget = false
    @State private var attachmentDropIntent: XTChatComposerDropIntent? = nil
    @State private var lastHandledFocusRequestID: Int = 0
    @State private var voiceEvidenceExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            messageList
                .frame(maxHeight: .infinity)

            Divider()

            inputArea
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
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
        ScrollViewReader { proxy in
            let visibleMessages = supervisor.chatTimelineMessages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if visibleMessages.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleMessages) { message in
                            SupervisorMessageBubble(
                                message: message,
                                thinkingPresentation: supervisor.conversationStreamingPlaceholder(for: message),
                                onImportAttachment: handleImportAttachmentFromMessage
                            )
                                .id(message.id)
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: visibleMessages.count) { _ in
                if let lastMessage = visibleMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: visibleMessages.last?.content ?? "") { _ in
                if let lastMessage = visibleMessages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .onChange(of: supervisor.processingStatusText ?? "") { _ in
                if let lastMessage = visibleMessages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .onChange(of: supervisor.conversationPlaceholderStatusText ?? "") { _ in
                if let lastMessage = visibleMessages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
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
            callModeBar

            if shouldShowVoiceEvidenceStrip {
                voiceEvidenceStrip
            }

            if !draftAttachments.isEmpty {
                XTChatProjectInboxPanel(
                    attachments: draftAttachments,
                    title: "Supervisor Inbox",
                    projectImportEnabled: appModel.projectContext != nil,
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
                    allowsImportDrop: appModel.projectContext != nil,
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
                                importEnabled: appModel.projectContext != nil
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

    private var callModeBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggleHandsFreeCall) {
                HStack(spacing: 8) {
                    Image(systemName: callModeButtonIconName)
                    Text(callModeButtonTitle)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(callModeButtonColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                statusBadge
                Text(callModeHeadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(callModeDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private var shouldShowVoiceEvidenceStrip: Bool {
        !supervisor.voiceReplaySummary.isEmpty || supervisor.voiceSafetyInvariantReport.updatedAt > 0
    }

    private var voiceEvidenceStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $voiceEvidenceExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if !supervisor.voiceReplaySummary.isEmpty {
                        SupervisorVoiceEvidenceSummaryRowView(
                            title: "回放核对",
                            state: supervisor.voiceReplaySummary.overallState.surfaceState,
                            headline: supervisor.voiceReplaySummary.headline,
                            summary: supervisor.voiceReplaySummary.summaryLine,
                            detail: supervisor.voiceReplaySummary.compactTimelineText
                        )
                    }

                    if supervisor.voiceSafetyInvariantReport.updatedAt > 0 {
                        SupervisorVoiceEvidenceSummaryRowView(
                            title: "安全约束",
                            state: supervisor.voiceSafetyInvariantReport.overallState.surfaceState,
                            headline: supervisor.voiceSafetyInvariantReport.headline,
                            summary: supervisor.voiceSafetyInvariantReport.summaryLine,
                            detail: nil
                        )
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text("语音核对")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(voiceEvidenceExpanded ? "展开中" : "已折叠")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(UIThemeTokens.secondaryCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusBadgeColor)
                .frame(width: 8, height: 8)
            Text(statusBadgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusBadgeColor)
        }
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
            projectRoot: appModel.projectContext?.root
        )
        guard !resolved.isEmpty else { return }
        draftAttachments = AXChatAttachmentSupport.merge(
            existing: draftAttachments,
            resolved: resolved
        )
        isInputFocused = true
    }

    private func importDroppedFilesToProject(_ urls: [URL]) {
        guard let ctx = appModel.projectContext else {
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
        guard let ctx = appModel.projectContext else {
            _ = supervisor.appendLocalAssistantNotice("当前没有选中项目，暂时不能把附件导入工作区。")
            return
        }

        importAttachmentsToProject([attachment], ctx: ctx)
    }

    private func importAllDraftAttachments() {
        guard let ctx = appModel.projectContext else {
            _ = supervisor.appendLocalAssistantNotice("当前没有选中项目，暂时不能把附件导入工作区。")
            return
        }

        let pending = draftAttachments.filter(\.isReadOnlyExternal)
        guard !pending.isEmpty else { return }
        importAttachmentsToProject(pending, ctx: ctx)
    }

    private func handleImportAttachmentFromMessage(_ attachment: AXChatAttachment) {
        guard let ctx = appModel.projectContext else {
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

    private func toggleHandsFreeCall() {
        if supervisor.voiceCallModeActive {
            supervisor.stopHandsFreeVoiceConversation()
            return
        }
        Task { @MainActor in
            let started = await supervisor.startHandsFreeVoiceConversation()
            if started {
                requestInputFocus()
                return
            }
            if supervisor.voiceCallEntryPreflight?.blocksStart == true {
                performVoiceRepairAction()
            }
        }
    }

    private var callModeButtonColor: Color {
        if supervisor.voiceCallModeActive {
            return Color(red: 0.73, green: 0.16, blue: 0.16)
        }
        if let preflight = callModePreflight {
            switch preflight.disposition {
            case .block:
                return Color(red: 0.73, green: 0.16, blue: 0.16)
            case .advisory:
                return Color.orange
            }
        }
        if supervisor.voiceRouteDecision.route.supportsLiveCapture {
            return Color(red: 0.12, green: 0.54, blue: 0.31)
        }
        return Color.secondary
    }

    private var callModeButtonIconName: String {
        if supervisor.voiceCallModeActive {
            return "phone.down.fill"
        }
        if callModePreflight?.blocksStart == true {
            return "exclamationmark.triangle.fill"
        }
        return "phone.fill"
    }

    private var callModeButtonTitle: String {
        if supervisor.voiceCallModeActive {
            return "结束通话"
        }
        if callModePreflight?.blocksStart == true {
            return "先修复语音"
        }
        return "进入通话"
    }

    private var callModeHeadline: String {
        if supervisor.voiceCallModeActive {
            switch supervisor.voiceRuntimeState.state {
            case .listening:
                return "已接通，直接开口"
            case .transcribing:
                return "正在听你说话"
            case .completed:
                return "这一句已送进 Supervisor"
            case .failClosed:
                return "通话链路当前不可用"
            case .idle:
                return "通话已接通"
            }
        }
        if let preflight = callModePreflight {
            return preflight.headline
        }
        switch supervisor.voiceCaptureSource {
        case .wakeArmed:
            return "待命中，叫一声就行"
        case .wakeFollowup:
            return "已唤醒，继续说"
        case .talkLoop:
            return "我在继续听"
        case .continuousConversation:
            return "通话已接通"
        case .manualComposer, .none:
            break
        }
        return "像打电话一样连续说话"
    }

    private var callModeDetail: String {
        if supervisor.voiceCallModeActive {
            if supervisor.voiceRuntimeState.state == .failClosed {
                return SupervisorVoiceReasonPresentation.displayTextOrRaw(
                    supervisor.voiceRuntimeState.reasonCode
                ) ?? "请先修复当前语音链路。"
            }
            return "你说完一轮后会自动送进 Supervisor，并在回复后继续监听。"
        }
        if let preflight = callModePreflight {
            let detail = preflight.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty {
                return detail
            }
            return preflight.nextStep
        }

        switch supervisor.voiceCaptureSource {
        case .wakeArmed:
            return "当前在后台待命；命中唤醒词后，我会先接通，再继续听你下一句。"
        case .wakeFollowup:
            return "我已经听到唤醒词，现在直接说你的问题或指令。"
        case .talkLoop:
            return "上一轮刚结束；你可以继续接着说，不用重新点麦克风。"
        case .continuousConversation:
            return "当前已经在连续通话模式。"
        case .manualComposer, .none:
            break
        }

        if supervisor.voiceRouteDecision.route.supportsLiveCapture {
            return "这会直接启动连续语音会话，不需要每轮都手动点麦克风。"
        }
        return "当前还没在实时语音链路上，先修复语音就绪状态再进入通话。"
    }

    private var statusBadgeText: String {
        if supervisor.voiceCallModeActive {
            return "通话中"
        }
        if let preflight = callModePreflight {
            switch preflight.disposition {
            case .block:
                return "先修复"
            case .advisory:
                return "建议复检"
            }
        }
        switch supervisor.voiceCaptureSource {
        case .wakeArmed:
            return "待命中"
        case .wakeFollowup:
            return "已唤醒"
        case .talkLoop:
            return "跟进监听"
        case .continuousConversation:
            return "通话中"
        case .manualComposer:
            return "手动录音"
        case .none:
            if supervisor.voiceRuntimeState.state == .failClosed {
                return "需修复"
            }
            return "文本模式"
        }
    }

    private var statusBadgeColor: Color {
        if supervisor.voiceRuntimeState.state == .failClosed {
            return Color.red
        }
        if supervisor.voiceCallModeActive {
            return Color(red: 0.12, green: 0.54, blue: 0.31)
        }
        if let preflight = callModePreflight {
            switch preflight.disposition {
            case .block:
                return Color.red
            case .advisory:
                return Color.orange
            }
        }
        switch supervisor.voiceCaptureSource {
        case .wakeArmed:
            return Color.blue
        case .wakeFollowup:
            return Color.orange
        case .talkLoop, .continuousConversation:
            return Color(red: 0.12, green: 0.54, blue: 0.31)
        case .manualComposer:
            return Color.red
        case .none:
            return Color.secondary
        }
    }

    private var callModePreflight: SupervisorManager.SupervisorVoiceCallEntryPreflight? {
        guard !supervisor.voiceCallModeActive else { return nil }
        return supervisor.voiceCallEntryPreflight
    }

    private func performVoiceRepairAction() {
        guard let preflight = supervisor.voiceCallEntryPreflight else { return }
        guard let destination = preflight.repairDestination else {
            openVoiceRepairURLFallback()
            return
        }

        let detail: String? = {
            let trimmed = preflight.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        let plan = SupervisorConversationRepairActionPlanner.plan(for: destination)

        switch plan.action {
        case .openXTSettings(let sectionId):
            appModel.requestSettingsFocus(
                sectionId: sectionId,
                title: preflight.headline,
                detail: detail
            )
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .openSupervisorControlCenter(let sheet):
            if sheet == .modelSettings {
                appModel.requestModelSettingsFocus(
                    title: preflight.headline,
                    detail: detail
                )
            }
            supervisor.requestSupervisorWindow(
                sheet: sheet,
                reason: "voice_call_entry_repair",
                focusConversation: false,
                startConversation: false
            )
        case .openHubSetup(let sectionId):
            appModel.requestHubSetupFocus(
                sectionId: sectionId,
                title: preflight.headline,
                detail: detail
            )
            openWindow(id: "hub_setup")
        case .openSystemPrivacy(let target):
            XTSystemSettingsLinks.openPrivacy(target)
        case .focusSupervisor:
            NSApp.activate(ignoringOtherApps: true)
            requestInputFocus()
        }
    }

    private func openVoiceRepairURLFallback() {
        guard let raw = supervisor.voiceCallEntryPreflight?.actionURL,
              let url = URL(string: raw) else {
            return
        }
        openURL(url)
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
