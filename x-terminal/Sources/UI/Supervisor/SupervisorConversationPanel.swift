import SwiftUI
import AppKit

struct SupervisorConversationPanel: View {
    @ObservedObject var supervisor: SupervisorManager
    @Binding var inputText: String
    @Binding var autoSendVoice: Bool
    var focusRequestID: Int = 0

    @FocusState private var isInputFocused: Bool
    @State private var draftText: String = ""
    @State private var lastHandledFocusRequestID: Int = 0
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            voiceStatusRail

            Divider()

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

    private var pendingMemoryFollowUpQuestion: String? {
        let trimmed = supervisor.supervisorPendingMemoryFactFollowUpQuestion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var quickIntents: [SupervisorConversationQuickIntent] {
        SupervisorConversationQuickIntentSupport.build(
            appModel: appModel,
            supervisor: supervisor
        )
    }

    private func requestInputFocus() {
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }

    private var voiceRailPresentation: SupervisorConversationVoiceRailPresentation {
        SupervisorConversationVoiceRailPresentationBuilder.build(
            routeDecision: supervisor.voiceRouteDecision,
            readinessSnapshot: supervisor.voiceReadinessSnapshot,
            authorizationStatus: supervisor.voiceAuthorizationStatus,
            runtimeState: supervisor.voiceRuntimeState,
            conversationSession: supervisor.conversationSessionSnapshot,
            playbackActivity: supervisor.voicePlaybackActivity,
            activeHealthReasonCode: supervisor.voiceActiveHealthReasonCode,
            latestRuntimeActivityText: supervisor.latestRuntimeActivity?.text,
            recentVoiceDispatchAuditEntries: supervisor.voiceDispatchAuditEntries
        )
    }

    private var voiceStatusRail: some View {
        let presentation = voiceRailPresentation
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label {
                    Text(presentation.phaseLabel)
                } icon: {
                    Image(systemName: presentation.phaseIconName)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(presentation.phaseState.tint)

                Spacer()

                if supervisor.isProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Supervisor 思考中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("就绪")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                if presentation.canEndSession {
                    Button("结束语音会话") {
                        supervisor.endConversationSession()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presentation.chips) { chip in
                        voiceRailChip(chip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, presentation.notice == nil && pendingMemoryFollowUpQuestion == nil ? 10 : 8)
            }

            if let notice = presentation.notice {
                Divider()
                voiceRailNotice(notice)
            }

            if let pendingMemoryFollowUpQuestion {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .foregroundStyle(.orange)
                    Text("待补背景：\(pendingMemoryFollowUpQuestion)")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.06))
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
    }

    private func voiceRailChip(
        _ chip: SupervisorConversationVoiceRailChip
    ) -> some View {
        Text(chip.text)
            .font(chip.prefersMonospacedText ? .caption2.monospaced() : .caption2)
            .foregroundStyle(chip.state.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(chip.state.tint.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(chip.state.tint.opacity(0.22), lineWidth: 1)
            )
            .help(chip.helpText ?? chip.text)
    }

    private func voiceRailNotice(
        _ notice: SupervisorConversationVoiceRailNotice
    ) -> some View {
        let repairPlan = notice.repairEntry.map { destination in
            SupervisorConversationRepairActionPlanner.plan(
                for: destination,
                systemSettingsTarget: destination == .systemPermissions
                    ? XTVoicePermissionRepairTargetResolver.resolve(
                        microphone: supervisor.voicePermissionSnapshot.microphone,
                        speechRecognition: supervisor.voicePermissionSnapshot.speechRecognition
                    )
                    : .voiceCapture
            )
        }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.iconName)
                .foregroundStyle(notice.state.tint)
                .font(.caption.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(notice.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nextStep = notice.nextStep {
                    Text("下一步：\(nextStep)")
                        .font(.caption2)
                        .foregroundStyle(notice.state.tint)
                }
                if let repairEntry = notice.repairEntry {
                    Text("修复入口：\(repairEntry.label)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let repairPlan {
                Button(repairPlan.buttonTitle) {
                    performVoiceRailRepair(repairPlan, notice: notice)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(notice.state.tint.opacity(0.06))
    }

    private func performVoiceRailRepair(
        _ plan: SupervisorConversationRepairActionPlan,
        notice: SupervisorConversationVoiceRailNotice
    ) {
        let detail = [notice.summary, notice.nextStep]
            .compactMap { value -> String? in
                let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n")
        let normalizedDetail = detail.isEmpty ? nil : detail

        switch plan.action {
        case let .openXTSettings(sectionId):
            appModel.requestSettingsFocus(
                sectionId: sectionId,
                title: notice.title,
                detail: normalizedDetail
            )
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case let .openHubSetup(sectionId):
            appModel.requestHubSetupFocus(
                sectionId: sectionId,
                title: notice.title,
                detail: normalizedDetail
            )
            openWindow(id: "hub_setup")
        case let .openSystemPrivacy(target):
            XTSystemSettingsLinks.openPrivacy(target)
        case .focusSupervisor:
            requestInputFocus()
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
                            SupervisorMessageBubble(message: message)
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("欢迎使用 Supervisor AI")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("我可以帮你管理所有项目，了解进度、分析卡点、提供下一步建议。")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("• 查看所有项目进度")
                Text("• 哪个项目卡住了")
                Text("• 接下来该做什么")
                Text("• 告诉项目 A 先做什么")
            }
            .font(.body)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inputArea: some View {
        VStack(spacing: 12) {
            if !quickIntents.isEmpty {
                quickIntentRail
            }

            HStack(alignment: .bottom, spacing: 12) {
                TextEditor(text: $draftText)
                    .focused($isInputFocused)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .onTapGesture {
                        isInputFocused = true
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
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 16)

            HStack {
                Text("💡 支持语音输入与 /automation status|start|recover|cancel|advance running")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("语音自动发送", isOn: $autoSendVoice)
                    .toggleStyle(.switch)
                    .font(.caption)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var quickIntentRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickIntents) { intent in
                    quickIntentChip(intent)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func quickIntentChip(
        _ intent: SupervisorConversationQuickIntent
    ) -> some View {
        let tint = quickIntentTint(intent.tone)
        return Button {
            supervisor.sendMessage(intent.prompt, fromVoice: false)
            requestInputFocus()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: intent.systemImage)
                    .font(.caption.weight(.semibold))
                Text(intent.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(intent.helpText)
    }

    private func quickIntentTint(
        _ tone: SupervisorConversationQuickIntent.Tone
    ) -> Color {
        switch tone {
        case .resume:
            return .blue
        case .focus:
            return .accentColor
        case .caution:
            return .orange
        case .diagnostic:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private func submitInput() {
        guard let transition = SupervisorConversationComposerSupport.submissionTransition(
            draft: draftText
        ) else {
            return
        }

        supervisor.sendMessage(transition.payload, fromVoice: false)
        draftText = transition.nextDraft
        inputText = transition.nextInput
        isInputFocused = true
    }

    private func handleVoiceRecognized(_ recognized: String) {
        guard let transition = SupervisorConversationComposerSupport.autoSendVoiceTransition(
            recognized: recognized,
            autoSendVoice: autoSendVoice
        ) else {
            return
        }

        supervisor.sendMessage(transition.payload, fromVoice: true)
        draftText = transition.nextDraft
        inputText = transition.nextInput
        isInputFocused = true
    }
}

struct SupervisorMessageBubble: View {
    let message: SupervisorMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
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

                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(backgroundColor)
                    .cornerRadius(12)
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
