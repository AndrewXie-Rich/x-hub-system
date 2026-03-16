import SwiftUI

struct SupervisorConversationPanel: View {
    @ObservedObject var supervisor: SupervisorManager
    @Binding var inputText: String
    @Binding var autoSendVoice: Bool
    var focusRequestID: Int = 0

    @FocusState private var isInputFocused: Bool
    @EnvironmentObject private var appModel: AppModel

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
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
        .onChange(of: focusRequestID) { _ in
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }

    private var pendingMemoryFollowUpQuestion: String? {
        let trimmed = supervisor.supervisorPendingMemoryFactFollowUpQuestion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var voiceStatusRail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label {
                    Text(voicePhaseLabel)
                } icon: {
                    Image(systemName: voicePhaseIcon)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(voicePhaseColor)

                Text(supervisor.voiceRouteDecision.route.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("auth=\(supervisor.voiceAuthorizationStatus.rawValue)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                Text("session=\(supervisor.conversationSessionSnapshot.windowState.rawValue)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                if supervisor.conversationSessionSnapshot.remainingTTLSeconds > 0 {
                    Text("ttl=\(supervisor.conversationSessionSnapshot.remainingTTLSeconds)s")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                let readinessReason = supervisor.voiceReadinessSnapshot.primaryReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if !readinessReason.isEmpty || !supervisor.voiceActiveHealthReasonCode.isEmpty {
                    Text(
                        readinessReason.isEmpty
                            ? supervisor.voiceActiveHealthReasonCode
                            : readinessReason
                    )
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if supervisor.isProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Supervisor thinking")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("ready")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                if supervisor.conversationSessionSnapshot.isConversing {
                    Button("End Voice Session") {
                        supervisor.endConversationSession()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

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

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if supervisor.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(supervisor.messages) { message in
                            SupervisorMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: supervisor.messages.count) { _ in
                if let lastMessage = supervisor.messages.last {
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
            HStack(alignment: .bottom, spacing: 12) {
                TextEditor(text: $inputText)
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

                VStack(spacing: 8) {
                    VoiceInputButton(text: $inputText, autoAppend: !autoSendVoice) { recognized in
                        handleVoiceRecognized(recognized)
                    }

                    Button(action: submitInput) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var voicePhaseLabel: String {
        switch supervisor.voiceRuntimeState.state {
        case .idle:
            return "idle"
        case .listening:
            return "listening"
        case .transcribing:
            return "transcribing"
        case .completed:
            return "completed"
        case .failClosed:
            return "fail_closed"
        }
    }

    private var voicePhaseIcon: String {
        switch supervisor.voiceRuntimeState.state {
        case .idle:
            return "waveform.circle"
        case .listening:
            return "mic.circle.fill"
        case .transcribing:
            return "waveform.badge.mic"
        case .completed:
            return "checkmark.circle.fill"
        case .failClosed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var voicePhaseColor: Color {
        switch supervisor.voiceRuntimeState.state {
        case .idle:
            return .secondary
        case .listening, .transcribing:
            return .accentColor
        case .completed:
            return .green
        case .failClosed:
            return .orange
        }
    }

    private func submitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        supervisor.sendMessage(trimmed, fromVoice: false)
        inputText = ""
        isInputFocused = true
    }

    private func handleVoiceRecognized(_ recognized: String) {
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard autoSendVoice, !trimmed.isEmpty else { return }
        supervisor.sendMessage(trimmed, fromVoice: true)
        inputText = ""
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
