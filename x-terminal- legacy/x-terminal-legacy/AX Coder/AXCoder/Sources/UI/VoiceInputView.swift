import SwiftUI
import Speech
import AVFoundation

@MainActor
final class VoiceInputManager: NSObject, ObservableObject {
    static let shared = VoiceInputManager()
    
    @Published var isRecording: Bool = false
    @Published var recognizedText: String = ""
    @Published var isAuthorized: Bool = false
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    
    private override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        super.init()
        requestAuthorization()
    }
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.isAuthorized = status == .authorized
            }
        }
    }
    
    func startRecording() {
        guard isAuthorized else {
            print("Not Authorized: Please authorize speech recognition in System Settings.")
            return
        }
        
        guard !isRecording else { return }
        
        do {
            try startRecordingInternal()
            isRecording = true
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
    }
    
    private func startRecordingInternal() throws {
        audioEngine = AVAudioEngine()
        
        let inputNode = audioEngine!.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, let request = self.recognitionRequest else { return }
            request.append(buffer)
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    print("Speech recognition error: \(error)")
                }
            }
        }
        
        audioEngine!.prepare()
        try audioEngine!.start()
    }
}

struct VoiceInputButton: View {
    @StateObject private var voiceManager = VoiceInputManager.shared
    @Binding var text: String
    var autoAppend: Bool = true
    var onCommit: ((String) -> Void)? = nil
    @State private var showPreview: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                if voiceManager.isRecording {
                    voiceManager.stopRecording()
                    let recognized = voiceManager.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !recognized.isEmpty {
                        if autoAppend {
                            if !text.isEmpty, !text.hasSuffix("\n") {
                                text += " "
                            }
                            text += recognized
                        }
                        onCommit?(recognized)
                    }
                    voiceManager.recognizedText = ""
                    showPreview = false
                } else {
                    voiceManager.startRecording()
                    showPreview = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: voiceManager.isRecording ? "mic.fill" : "mic")
                    Text(voiceManager.isRecording ? "Stop" : "Voice Input")
                    
                    if voiceManager.isRecording {
                        BreathingDotView(label: "R", isActive: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(voiceManager.isRecording ? Color.red : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(!voiceManager.isAuthorized)
            
            if showPreview && !voiceManager.recognizedText.isEmpty {
                Text("识别中: \(voiceManager.recognizedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
        }
    }
}
