import SwiftUI

struct SupervisorChatWindow: View {
    @StateObject private var supervisor = SupervisorManager.shared
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = ""
    @State private var autoSendVoice: Bool = true
    @State private var focusRequestID: Int = 0

    private var selectedAutomationProject: AXProjectEntry? {
        guard let projectID = appModel.selectedProjectId,
              projectID != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return appModel.registry.project(for: projectID)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            Divider()

            SupervisorConversationPanel(
                supervisor: supervisor,
                inputText: $inputText,
                autoSendVoice: $autoSendVoice,
                focusRequestID: focusRequestID
            )
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            supervisor.setAppModel(appModel)
            supervisor.syncAutomationRuntimeSnapshot(forSelectedProject: selectedAutomationProject)
            supervisor.openConversationSession()
            requestFocus()
        }
        .onChange(of: appModel.selectedProjectId) { _ in
            supervisor.syncAutomationRuntimeSnapshot(forSelectedProject: selectedAutomationProject)
        }
        .onDisappear {
            supervisor.endConversationSession()
        }
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Supervisor Conversation")
                    .font(.headline)
                Text("Wake, voice input, and short-session follow-up land here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if supervisor.isProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("处理中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("清空") {
                supervisor.clearMessages()
                requestFocus()
            }
            .buttonStyle(.borderless)

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func requestFocus() {
        focusRequestID += 1
    }
}

#if DEBUG
struct SupervisorChatWindow_Previews: PreviewProvider {
    static var previews: some View {
        SupervisorChatWindow()
            .environmentObject(AppModel())
    }
}
#endif
