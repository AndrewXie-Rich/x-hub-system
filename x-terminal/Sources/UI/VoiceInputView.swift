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
                if manualCaptureActive {
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
                        if voiceCoordinator.currentCaptureSource == .wakeArmed {
                            voiceCoordinator.discardRecording(reasonCode: "manual_composer_override")
                        }
                        await voiceCoordinator.startRecording()
                    }
                    showPreview = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: manualCaptureActive ? "mic.fill" : "mic")
                    Text(manualCaptureActive ? "Stop" : "Voice Input")
                    
                    if manualCaptureActive {
                        BreathingDotView(label: "R", isActive: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(manualCaptureActive ? Color.red : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(voiceInputDisabled)
            
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

    private var manualCaptureActive: Bool {
        voiceCoordinator.currentCaptureSource == .manualComposer && voiceCoordinator.isRecording
    }

    private var voiceInputDisabled: Bool {
        if manualCaptureActive {
            return false
        }
        if let captureSource = voiceCoordinator.currentCaptureSource {
            return captureSource != .wakeArmed
        }
        return !voiceCoordinator.isAuthorized
    }
}
