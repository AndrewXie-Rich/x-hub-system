import SwiftUI

struct VoiceInputButton: View {
    @StateObject private var voiceCoordinator = VoiceSessionCoordinator.shared
    @Binding var text: String
    var autoAppend: Bool = true
    var onCommit: ((String) -> Void)? = nil
    @State private var showPreview: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                if voiceCoordinator.isRecording {
                    voiceCoordinator.stopRecording()
                    let recognized = voiceCoordinator.committedTranscript()
                    if !recognized.isEmpty {
                        if autoAppend {
                            if !text.isEmpty, !text.hasSuffix("\n") {
                                text += " "
                            }
                            text += recognized
                        }
                        onCommit?(recognized)
                    }
                    voiceCoordinator.clearTranscript()
                    showPreview = false
                } else {
                    Task {
                        await voiceCoordinator.startRecording()
                    }
                    showPreview = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: voiceCoordinator.isRecording ? "mic.fill" : "mic")
                    Text(voiceCoordinator.isRecording ? "Stop" : "Voice Input")
                    
                    if voiceCoordinator.isRecording {
                        BreathingDotView(label: "R", isActive: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(voiceCoordinator.isRecording ? Color.red : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(!voiceCoordinator.isAuthorized && !voiceCoordinator.isRecording)
            
            if showPreview && !voiceCoordinator.recognizedText.isEmpty {
                Text("识别中 [\(voiceCoordinator.routeDecision.route.displayName)]: \(voiceCoordinator.recognizedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else if showPreview && voiceCoordinator.runtimeState.state == .failClosed {
                Text("语音不可用: \(voiceCoordinator.runtimeState.reasonCode ?? voiceCoordinator.routeDecision.reasonCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
        }
    }
}
