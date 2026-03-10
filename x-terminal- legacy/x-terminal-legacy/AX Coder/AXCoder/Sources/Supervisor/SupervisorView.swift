import SwiftUI

struct SupervisorView: View {
    @StateObject private var supervisor = SupervisorManager.shared
    @State private var inputText: String = ""
    @State private var autoSendVoice: Bool = true
    @FocusState private var isInputFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appModel: AppModel
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()
            
            messageList
            
            Divider()
            
            inputArea
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            supervisor.setAppModel(appModel)
        }
    }
    
    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.accentColor)
                Text("Supervisor AI")
                    .font(.headline)
            }
            
            Spacer()
            
            if supervisor.isProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("处理中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 8) {
                Button(action: { openWindow(id: "supervisor_settings") }) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help("Supervisor 设置")
                
                Button(action: { openWindow(id: "model_settings") }) {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.borderless)
                .help("AI 模型设置")
                
                Button("清空") {
                    supervisor.clearMessages()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if supervisor.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(supervisor.messages) { message in
                            MessageBubble(message: message)
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
                Text("欢迎使用Supervisor AI")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("我可以帮你管理所有项目，了解进度、分析卡点、提供下一步建议")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("你可以问我：")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("• 查看所有项目进度")
                    Text("• 哪个项目卡住了")
                    Text("• 接下来该做什么")
                    Text("• 告诉项目A做xxx")
                }
                .font(.body)
                .foregroundStyle(.secondary)
            }
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
                
                VStack(spacing: 8) {
                    VoiceInputButton(text: $inputText, autoAppend: !autoSendVoice) { recognized in
                        handleVoiceRecognized(recognized)
                    }
                    
                    Button(action: sendMessage) {
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
                Text("💡 提示：你可以使用 Cmd+Enter 发送消息，或使用语音输入")
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
    
    private func sendMessage() {
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

private struct MessageBubble: View {
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
            return .secondary
        }
    }
    
    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.1)
        case .assistant:
            return Color.accentColor.opacity(0.1)
        case .system:
            return Color.secondary.opacity(0.1)
        }
    }
    
    private var timeText: String {
        let date = Date(timeIntervalSince1970: message.timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
