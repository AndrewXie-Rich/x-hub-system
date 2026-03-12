import Foundation
import AVFoundation
import Speech

@MainActor
final class SystemSpeechCompatibilityTranscriber: NSObject, VoiceStreamingTranscriber {
    let routeMode: VoiceRouteMode = .systemSpeechCompatibility

    private(set) var authorizationStatus: VoiceTranscriberAuthorizationStatus
    private(set) var engineHealth: VoiceEngineHealth
    private(set) var healthReasonCode: String?
    private(set) var isRunning: Bool = false

    private let localeIdentifier: String
    private let speechRecognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onChunk: ((VoiceTranscriptChunk) -> Void)?
    private var onFailure: ((String) -> Void)?

    init(localeIdentifier: String = "zh-CN") {
        self.localeIdentifier = localeIdentifier
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        self.authorizationStatus = Self.mapAuthorizationStatus(SFSpeechRecognizer.authorizationStatus())
        self.engineHealth = Self.mapEngineHealth(Self.mapAuthorizationStatus(SFSpeechRecognizer.authorizationStatus()))
        self.healthReasonCode = Self.mapHealthReason(Self.mapAuthorizationStatus(SFSpeechRecognizer.authorizationStatus()))
        super.init()
    }

    func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus {
        let current = Self.mapAuthorizationStatus(SFSpeechRecognizer.authorizationStatus())
        if current != .undetermined {
            authorizationStatus = current
            return current
        }

        let granted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let mapped = Self.mapAuthorizationStatus(granted)
        authorizationStatus = mapped
        engineHealth = Self.mapEngineHealth(mapped)
        healthReasonCode = Self.mapHealthReason(mapped)
        return mapped
    }

    func refreshEngineHealth() async -> VoiceEngineHealth {
        let mapped = Self.mapAuthorizationStatus(SFSpeechRecognizer.authorizationStatus())
        authorizationStatus = mapped
        engineHealth = Self.mapEngineHealth(mapped)
        healthReasonCode = Self.mapHealthReason(mapped)
        return engineHealth
    }

    func startTranscribing(
        onChunk: @escaping (VoiceTranscriptChunk) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        guard !isRunning else {
            throw VoiceTranscriberError.alreadyRunning
        }
        guard authorizationStatus.isAuthorized else {
            throw VoiceTranscriberError.notAuthorized
        }
        guard let speechRecognizer else {
            healthReasonCode = "system_speech_recognizer_unavailable"
            throw VoiceTranscriberError.engineUnavailable("system_speech_recognizer_unavailable")
        }
        guard speechRecognizer.isAvailable else {
            healthReasonCode = "system_speech_recognizer_not_available"
            throw VoiceTranscriberError.engineUnavailable("system_speech_recognizer_not_available")
        }

        self.onChunk = onChunk
        self.onFailure = onFailure

        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        self.audioEngine = audioEngine
        self.recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let transcript = result.bestTranscription.formattedString
                let kind: VoiceTranscriptKind = result.isFinal ? .final : .partial
                self.onChunk?(VoiceTranscriptChunk(
                    kind: kind,
                    text: transcript,
                    language: self.localeIdentifier
                ))
            }

            if let error {
                self.onFailure?(error.localizedDescription)
            }
        }

        audioEngine.prepare()
            do {
            try audioEngine.start()
            isRunning = true
            engineHealth = .ready
            healthReasonCode = nil
        } catch {
            cleanupRuntime()
            engineHealth = .degraded
            healthReasonCode = error.localizedDescription
            throw VoiceTranscriberError.runtimeFailure(error.localizedDescription)
        }
    }

    func stopTranscribing() {
        cleanupRuntime()
    }

    private func cleanupRuntime() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRunning = false
        onChunk = nil
        onFailure = nil
    }

    private static func mapEngineHealth(
        _ status: VoiceTranscriberAuthorizationStatus
    ) -> VoiceEngineHealth {
        switch status {
        case .authorized:
            return .ready
        case .undetermined:
            return .loading
        case .denied, .restricted:
            return .unauthorized
        case .unavailable:
            return .unavailable
        }
    }

    private static func mapHealthReason(
        _ status: VoiceTranscriberAuthorizationStatus
    ) -> String? {
        switch status {
        case .authorized:
            return nil
        case .undetermined:
            return "system_speech_authorization_pending"
        case .denied:
            return "system_speech_authorization_denied"
        case .restricted:
            return "system_speech_authorization_restricted"
        case .unavailable:
            return "system_speech_recognizer_unavailable"
        }
    }

    private static func mapAuthorizationStatus(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> VoiceTranscriberAuthorizationStatus {
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .unavailable
        }
    }
}
