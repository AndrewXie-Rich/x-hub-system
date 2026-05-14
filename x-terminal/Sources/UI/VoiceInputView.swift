import SwiftUI

enum VoiceInputButtonStyle {
    case standard
    case compact
}

struct VoiceInputButton: View {
    @StateObject private var voiceCoordinator = VoiceSessionCoordinator.shared
    @Binding var text: String
    var autoAppend: Bool = true
    var onCommit: ((String) -> Void)? = nil
    var style: VoiceInputButtonStyle = .standard
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
                HStack(spacing: style == .compact ? 6 : 8) {
                    Image(systemName: manualCaptureActive ? "mic.fill" : "mic")
                    Text(buttonTitle)

                    if manualCaptureActive {
                        BreathingDotView(label: "R", isActive: true)
                    }
                }
                .font(buttonFont)
                .padding(.horizontal, style == .compact ? 10 : 12)
                .padding(.vertical, style == .compact ? 8 : 6)
                .background(buttonBackground)
                .foregroundColor(buttonForegroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: style == .compact ? 10 : 6, style: .continuous)
                        .stroke(buttonBorderColor, lineWidth: style == .compact ? 1 : 0)
                )
                .clipShape(RoundedRectangle(cornerRadius: style == .compact ? 10 : 6, style: .continuous))
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

    private var buttonTitle: String {
        if style == .compact {
            return manualCaptureActive ? "停止语音" : "语音"
        }
        return manualCaptureActive ? "Stop" : "Voice Input"
    }

    private var buttonFont: Font {
        switch style {
        case .standard:
            return .body
        case .compact:
            return .caption.weight(.semibold)
        }
    }

    private var buttonBackground: Color {
        if manualCaptureActive {
            return .red
        }
        switch style {
        case .standard:
            return .accentColor
        case .compact:
            return Color.secondary.opacity(0.10)
        }
    }

    private var buttonForegroundColor: Color {
        if manualCaptureActive || style == .standard {
            return .white
        }
        return .primary
    }

    private var buttonBorderColor: Color {
        switch style {
        case .standard:
            return .clear
        case .compact:
            return manualCaptureActive ? Color.red.opacity(0.2) : Color.secondary.opacity(0.14)
        }
    }
}
