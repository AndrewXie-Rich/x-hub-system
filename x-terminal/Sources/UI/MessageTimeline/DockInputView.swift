import SwiftUI

private struct DockInputRuntimeStatusSnapshot: Equatable {
    var configuredModelId: String
    var coderSnapshot: AXRoleExecutionSnapshot
    var latestGovernanceInterception: ProjectGovernanceInterceptionPresentation?
    var primaryStatusAction: ProjectCoderExecutionStatusPrimaryActionPresentation?

    static let empty = DockInputRuntimeStatusSnapshot(
        configuredModelId: "",
        coderSnapshot: .empty(role: .coder, source: "dock_input"),
        latestGovernanceInterception: nil,
        primaryStatusAction: nil
    )
}

/// 现代化的底部 Dock 输入框，替代原来的 inputBar
struct DockInputView: View {
    let ctx: AXProjectContext
    let memory: AXMemory?
    let config: AXProjectConfig?
    let hubConnected: Bool
    let session: ChatSessionModel
    @ObservedObject var composer: ChatComposerState
    let status: XTChatStatusSnapshot
    @Environment(\.xtAppModelReference) private var appModelReference
    @Environment(\.openWindow) private var openWindow
    @StateObject private var modelManager = HubModelManager.shared

    @State private var isFocused: Bool = false
    @State private var showSlashSuggestions = false
    @State private var slashSuggestions: [XTDockSlashSuggestion] = []
    @State private var isAttachmentDropTarget = false
    @State private var attachmentDropIntent: XTChatComposerDropIntent? = nil
    @State private var visibleModelInventory = XTVisibleHubModelInventory.empty
    @State private var runtimeStatusSnapshot = DockInputRuntimeStatusSnapshot.empty

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                if showSlashSuggestions {
                    SlashSuggestionsView(
                        suggestions: slashSuggestions,
                        onSelect: { suggestion in
                            composer.draft = suggestion
                            showSlashSuggestions = false
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                VStack(alignment: .leading, spacing: 12) {
                    toolbarRow

                    if !composer.draftAttachments.isEmpty {
                        XTChatProjectInboxPanel(
                            attachments: composer.draftAttachments,
                            projectImportEnabled: true,
                            continuation: composer.importContinuation,
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
                                !status.isSending &&
                                status.pendingToolCalls.isEmpty &&
                                AXChatAttachmentSupport.hasSubmittableContent(
                                    draft: composer.draft,
                                    attachments: composer.draftAttachments
                                ),
                            onDismissContinuation: session.dismissImportContinuation
                        )
                    }

                    if !status.pendingToolCalls.isEmpty {
                        DockPendingToolApprovalPanel(
                            session: session,
                            status: status,
                            hubConnected: hubConnected,
                            onApprove: {
                                session.approvePendingTools(router: appModel.llmRouter)
                            },
                            onReject: {
                                session.rejectPendingTools()
                            },
                            onFocusHistory: {
                                appModel.requestProjectToolApprovalFocus(
                                    projectId: projectId,
                                    requestId: status.pendingToolCalls.first?.id
                                )
                            }
                        )
                    } else if let blockerPresentation {
                        DockInputBlockerBanner(presentation: blockerPresentation)
                    }

                    composerRow
                    if blockerPresentation == nil {
                        footerRow
                    }

                    if blockerPresentation == nil,
                       let error = status.lastError,
                       !error.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(14)
                .background(
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                        .allowsHitTesting(false)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .onAppear {
            modelManager.setAppModel(appModel)
            refreshRuntimeStatusSnapshot()
            syncVisibleModelInventory()
            refreshSlashSuggestions()
            if hubConnected {
                Task {
                    await modelManager.fetchModels()
                }
            }
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: modelInventorySnapshot) { _ in
            syncVisibleModelInventory()
            refreshSlashSuggestions()
        }
        .onChange(of: runtimeStatusRefreshSignature) { _ in
            refreshRuntimeStatusSnapshot()
        }
        .onChange(of: status.pendingToolCalls.count) { _ in
            refreshSlashSuggestions()
        }
        .onChange(of: hubConnected) { connected in
            if connected {
                Task {
                    await modelManager.fetchModels()
                }
            }
        }
    }

    private var toolbarRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                toolbarLeadingControls

                Spacer(minLength: 8)

                toolbarStatusChip
            }

            VStack(alignment: .leading, spacing: 8) {
                toolbarLeadingControls
                toolbarStatusChip
            }
        }
    }

    @ViewBuilder
    private var toolbarLeadingControls: some View {
        ModelSelectorButton(ctx: ctx, config: config)

        VoiceInputButton(
            text: $composer.draft,
            style: .compact
        )

        Toggle(isOn: $composer.autoRunTools) {
            Label("自动执行", systemImage: composer.autoRunTools ? "bolt.fill" : "bolt")
                .font(.caption.weight(.semibold))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .disabled(!hubConnected)
        .help("自动执行普通待确认工具；策略拒绝、权限不足和强制审批的工具仍会停在审批区。")
        .fixedSize()

        if !composer.draftAttachments.isEmpty {
            DockComposerChip(
                icon: "paperclip",
                text: "\(composer.draftAttachments.count) 个附件",
                tone: .neutral
            )
        }
    }

    @ViewBuilder
    private var toolbarStatusChip: some View {
        if blockerPresentation == nil,
           let statusChip = composerStatusChip {
            DockComposerChip(
                icon: statusChip.icon,
                text: statusChip.text,
                tone: statusChip.tone
            )
        }
    }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if composer.draft.isEmpty && composer.draftAttachments.isEmpty && !isFocused {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.tertiary)
                        Text(placeholderText)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
                }

                XTChatComposerTextView(
                    text: $composer.draft,
                    isFocused: $isFocused,
                    canSubmit: canSend && !status.isSending,
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
                .disabled(false)
                .onChange(of: composer.draft) { _ in
                    refreshSlashSuggestions()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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

            VStack(spacing: 8) {
                Button {
                    if status.isSending {
                        session.cancel()
                    } else {
                        sendMessage()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(sendButtonBackground)
                            .frame(width: 46, height: 46)

                        Image(systemName: sendButtonIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .shadow(color: sendButtonShadow, radius: 4, y: 2)

                Text(status.isSending ? "停止" : "发送")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(canSend ? .primary : .secondary)
            }
        }
    }

    private var footerRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                footerGuidanceText

                Spacer(minLength: 8)

                footerShortcutText
            }

            VStack(alignment: .leading, spacing: 4) {
                footerGuidanceText
                footerShortcutText
            }
        }
    }

    private var footerGuidanceText: some View {
        Text(composerGuidanceText)
            .font(.caption)
            .foregroundStyle(composerGuidanceColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footerShortcutText: some View {
        Text("/ 查看命令 · ↩ 发送 · ⇧↩ 换行")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }

    private var canSend: Bool {
        if status.isSending {
            return true
        }
        return hubConnected &&
            AXChatAttachmentSupport.hasSubmittableContent(
                draft: composer.draft,
                attachments: composer.draftAttachments
            ) &&
            status.pendingToolCalls.isEmpty
    }

    private var sendButtonIcon: String {
        status.isSending ? "stop.fill" : "arrow.up"
    }

    private var sendButtonBackground: LinearGradient {
        if !canSend {
            return LinearGradient(
                colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if status.isSending {
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
        if status.isSending {
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

    private var placeholderText: String {
        if !hubConnected {
            return "Hub 未连接。你可以先写好需求，连上后再发送。"
        }
        if !status.pendingToolCalls.isEmpty {
            return "先审批上方工具请求，审批后会继续这一轮。"
        }
        return "直接说要完成什么；输入 / 可查看常用命令。"
    }

    private var composerGuidanceText: String {
        if !hubConnected {
            return "当前还不能发出请求。先在 Control 里修复 Hub 连接，然后继续。"
        }
        if !status.pendingToolCalls.isEmpty {
            return "这轮有待审批工具请求，先审批或拒绝，再继续输入或发送。"
        }
        if composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
            return "选择一个命令，或继续输入来缩小建议范围。"
        }
        if composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "直接描述目标即可；XT 会优先按当前项目上下文让 Coder 开工。"
        }
        return "内容已准备好，可以直接发送。"
    }

    private var composerGuidanceColor: Color {
        if !hubConnected {
            return .red
        }
        if !status.pendingToolCalls.isEmpty {
            return .orange
        }
        return .secondary
    }

    private var composerStatusChip: (icon: String, text: String, tone: DockComposerChipTone)? {
        if !hubConnected {
            return ("wifi.slash", "Hub 未连接", .danger)
        }
        if !status.pendingToolCalls.isEmpty {
            return ("hand.raised.fill", "待审批 \(status.pendingToolCalls.count)", .warning)
        }
        if status.isSending {
            return ("ellipsis.circle.fill", "正在执行", .success)
        }
        return nil
    }

    private func sendMessage() {
        guard hubConnected,
              !status.isSending,
              status.pendingToolCalls.isEmpty,
              AXChatAttachmentSupport.hasSubmittableContent(
                draft: composer.draft,
                attachments: composer.draftAttachments
              ) else {
            return
        }
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

    private var modelInventorySnapshot: ModelStateSnapshot {
        modelManager.visibleSnapshot(fallback: appModel.modelsState)
    }

    private var projectId: String {
        AXProjectRegistryStore.projectId(forRoot: ctx.root)
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("DockInputView requires xtAppModelReference")
        }
        return appModelReference
    }

    private var runtimeStatusRefreshSignature: String {
        [
            ctx.root.standardizedFileURL.path,
            hubConnected ? "hub=1" : "hub=0",
            status.lastError ?? "",
            status.pendingToolCallIDSignature,
            resolveConfiguredModelId(),
            appModel.settingsStore.settings.interfaceLanguage.rawValue
        ].joined(separator: "|")
    }

    private var coderSnapshot: AXRoleExecutionSnapshot {
        runtimeStatusSnapshot.coderSnapshot
    }

    private var configuredModelId: String {
        runtimeStatusSnapshot.configuredModelId
    }

    private func resolveConfiguredModelId() -> String {
        AXRoleExecutionSnapshots.configuredModelId(
            for: .coder,
            projectConfig: config,
            settings: appModel.settingsStore.settings
        )
    }

    private var latestGovernanceInterception: ProjectGovernanceInterceptionPresentation? {
        runtimeStatusSnapshot.latestGovernanceInterception
    }

    private var primaryStatusAction: ProjectCoderExecutionStatusPrimaryActionPresentation? {
        runtimeStatusSnapshot.primaryStatusAction
    }

    private var blockerPresentation: DockInputBlockerPresentation? {
        if !hubConnected {
            return DockInputBlockerPresentation(
                icon: "wifi.slash",
                title: "Hub 当前未连通",
                detail: "先打开 Hub Recovery 检查连接、配对和可执行模型，再继续这一轮。",
                tone: .danger,
                actionTitle: "修复 Hub",
                actionHelpText: "打开 Hub Recovery，直接进入当前连接修复入口。",
                action: {
                    appModel.requestHubSetupFocus(
                        sectionId: "troubleshoot",
                        title: "Hub Recovery",
                        detail: "当前项目聊天输入被 Hub 连接阻塞；先检查连接、配对和模型可执行状态。"
                    )
                    openWindow(id: "hub_setup")
                }
            )
        }

        let trimmedError = status.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedError.isEmpty,
           let primaryStatusAction {
            return DockInputBlockerPresentation(
                icon: blockerIcon(for: primaryStatusAction.kind),
                title: "需要先修复后继续",
                detail: trimmedError,
                tone: blockerTone(for: primaryStatusAction.kind),
                actionTitle: primaryStatusAction.title,
                actionHelpText: primaryStatusAction.helpText,
                action: {
                    ProjectCoderExecutionStatusPrimaryActionResolver.perform(
                        primaryStatusAction.kind,
                        configuredModelId: configuredModelId,
                        snapshot: coderSnapshot,
                        ctx: ctx,
                        config: config,
                        session: session,
                        appModel: appModel,
                        openWindow: openWindow,
                        governanceInterception: latestGovernanceInterception,
                        interfaceLanguage: appModel.settingsStore.settings.interfaceLanguage
                    )
                }
            )
        }

        return nil
    }

    private func refreshRuntimeStatusSnapshot() {
        let configuredModelId = resolveConfiguredModelId()
        let coderSnapshot = XTProjectUIPresentationReadCache.roleExecutionSnapshot(
            for: ctx,
            role: .coder
        ) {
            AXRoleExecutionSnapshots.latestSnapshots(for: ctx)[.coder]
                ?? .empty(role: .coder, source: "dock_input")
        }
        let latestGovernanceInterception = XTProjectUIPresentationReadCache.latestGovernanceInterception(
            for: ctx,
            limit: 12
        ) {
            ProjectGovernanceInterceptionPresentation.latest(
                from: AXProjectSkillActivityStore.loadRecentActivities(ctx: ctx, limit: 12)
            )
        }
        let primaryStatusAction = ProjectCoderExecutionStatusPrimaryActionResolver.resolve(
            configuredModelId: configuredModelId,
            snapshot: coderSnapshot,
            hubConnected: hubConnected,
            governanceInterception: latestGovernanceInterception,
            language: appModel.settingsStore.settings.interfaceLanguage
        )
        let nextSnapshot = DockInputRuntimeStatusSnapshot(
            configuredModelId: configuredModelId,
            coderSnapshot: coderSnapshot,
            latestGovernanceInterception: latestGovernanceInterception,
            primaryStatusAction: primaryStatusAction
        )
        guard runtimeStatusSnapshot != nextSnapshot else { return }
        runtimeStatusSnapshot = nextSnapshot
    }

    private func syncVisibleModelInventory() {
        visibleModelInventory = XTVisibleHubModelInventorySupport.build(
            snapshot: modelInventorySnapshot
        )
    }

    private func refreshSlashSuggestions() {
        showSlashSuggestions = composer.draft.hasPrefix("/") && status.pendingToolCalls.isEmpty
        guard showSlashSuggestions else {
            slashSuggestions = []
            return
        }
        slashSuggestions = XTDockSlashSuggestionSupport.suggestions(
            for: composer.draft,
            models: visibleModelInventory.sortedModels
        )
    }

    private func blockerIcon(
        for kind: ProjectCoderExecutionStatusPrimaryActionKind
    ) -> String {
        switch kind {
        case .routeDiagnose:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .openModelSettings:
            return "cpu"
        case .openDiagnostics:
            return "stethoscope"
        case .openHubRecovery:
            return "wifi.exclamationmark"
        case .openHubConnectionLog:
            return "list.bullet.rectangle"
        case .openExecutionTier:
            return "slider.horizontal.3"
        case .openGovernanceOverview:
            return "shield.lefthalf.filled"
        }
    }

    private func blockerTone(
        for kind: ProjectCoderExecutionStatusPrimaryActionKind
    ) -> ProjectCoderExecutionStatusTone {
        switch kind {
        case .openHubRecovery, .openDiagnostics:
            return .danger
        case .openExecutionTier, .openGovernanceOverview:
            return .warning
        case .routeDiagnose, .openModelSettings, .openHubConnectionLog:
            return .caution
        }
    }
}

private struct DockPendingToolApprovalPanel: View {
    let session: ChatSessionModel
    let status: XTChatStatusSnapshot
    let hubConnected: Bool
    let onApprove: () -> Void
    let onReject: () -> Void
    let onFocusHistory: () -> Void
    @State private var pendingSkillItems: [String: ProjectSkillActivityItem] = [:]

    var body: some View {
        let pendingToolCalls = status.pendingToolCalls
        let batchPresentation = XTPendingApprovalPresentation.pendingBatchPresentation(
            calls: pendingToolCalls,
            activityByRequestID: pendingSkillItems
        )
        let batchDeltaLines = XTPendingApprovalPresentation.pendingBatchDeltaLines(
            calls: pendingToolCalls,
            activityByRequestID: pendingSkillItems
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("待审批")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(batchPresentation.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button("历史") {
                    onFocusHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("定位到历史区里的待审批记录")

                Button("拒绝") {
                    onReject()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onApprove()
                } label: {
                    Label(
                        batchPresentation.primaryActionTitle,
                        systemImage: batchPresentation.primaryActionSystemImage
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(status.isSending)
                .help(hubConnected ? batchPresentation.footerNote : batchPresentation.hubDisconnectedNote)
            }

            if !batchDeltaLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(batchDeltaLines.prefix(3)), id: \.self) { line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pendingToolCalls) { call in
                        PendingToolCallChip(
                            toolCall: call,
                            activity: pendingSkillItems[call.id]
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
        .onAppear {
            refreshPendingSkillItems()
        }
        .onChange(of: status.pendingToolCallIDSignature) { _ in
            refreshPendingSkillItems()
        }
    }

    private func refreshPendingSkillItems() {
        pendingSkillItems = session.pendingProjectSkillActivityItems()
    }
}

private struct DockInputBlockerPresentation {
    let icon: String
    let title: String
    let detail: String
    let tone: ProjectCoderExecutionStatusTone
    let actionTitle: String
    let actionHelpText: String?
    let action: () -> Void
}

private struct DockInputBlockerBanner: View {
    let presentation: DockInputBlockerPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(presentation.tone.color.opacity(0.14))
                    .frame(width: 28, height: 28)

                Image(systemName: presentation.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(presentation.tone.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            Button(presentation.actionTitle) {
                presentation.action()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(presentation.tone.color)
            .help(presentation.actionHelpText ?? presentation.detail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(presentation.tone.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(presentation.tone.color.opacity(0.18), lineWidth: 1)
        )
    }
}

struct ModelSelectorButton: View {
    let ctx: AXProjectContext
    let config: AXProjectConfig?
    @Environment(\.xtAppModelReference) private var appModelReference
    @State private var showModelPicker = false

    var body: some View {
        Button {
            showModelPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("模型")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(modelLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("选择模型（Select Model）")
        .popover(isPresented: $showModelPicker) {
            ModelSelectorView(projectContext: ctx, config: config)
                .frame(width: 300)
        }
    }

    private var modelLabel: String {
        let configuredModelId = AXRoleExecutionSnapshots.configuredModelId(
            for: .coder,
            projectConfig: config,
            settings: appModel.settingsStore.settings
        )
        let trimmed = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "auto" }
        return ExecutionRoutePresentation.shortModelLabel(trimmed)
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ModelSelectorButton requires xtAppModelReference")
        }
        return appModelReference
    }
}

struct SlashSuggestionsView: View {
    let suggestions: [XTDockSlashSuggestion]
    let onSelect: (String) -> Void

    var body: some View {
        let visibleSuggestions = Array(suggestions.prefix(8))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleSuggestions) { suggestion in
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

                    if suggestion.id != visibleSuggestions.last?.id {
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

enum DockComposerChipTone {
    case neutral
    case success
    case warning
    case danger

    var foreground: Color {
        switch self {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

struct DockComposerChip: View {
    let icon: String
    let text: String
    var tone: DockComposerChipTone = .neutral

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tone.foreground.opacity(0.10))
        .clipShape(Capsule())
    }
}

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
