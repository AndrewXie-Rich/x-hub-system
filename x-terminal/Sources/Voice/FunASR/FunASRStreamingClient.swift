import Foundation

@MainActor
final class FunASRStreamingClient: VoiceStreamingTranscriber {
    let routeMode: VoiceRouteMode = .funasrStreaming

    private(set) var authorizationStatus: VoiceTranscriberAuthorizationStatus = .authorized
    private(set) var engineHealth: VoiceEngineHealth = .disabled
    private(set) var healthReasonCode: String?
    private(set) var isRunning: Bool = false
    private(set) var latestSidecarHealth: VoiceSidecarHealthSnapshot

    private var config: FunASRSidecarConfig
    private let monitor: FunASRSidecarHealthMonitor
    private let audioCapture: any VoicePCMDataCapturing
    private var onChunk: ((VoiceTranscriptChunk) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var streamID: String?

    init(
        config: FunASRSidecarConfig = .default(),
        monitor: FunASRSidecarHealthMonitor? = nil,
        audioCapture: (any VoicePCMDataCapturing)? = nil
    ) {
        self.config = config
        self.monitor = monitor ?? FunASRSidecarHealthMonitor()
        self.audioCapture = audioCapture ?? VoiceAudioCapture()
        self.latestSidecarHealth = .disabled(config: config)
        applyHealthSnapshot(latestSidecarHealth)
    }

    func updateConfig(_ config: FunASRSidecarConfig) {
        self.config = config
        if !config.enabled {
            latestSidecarHealth = .disabled(config: config)
            applyHealthSnapshot(latestSidecarHealth)
        }
    }

    func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus {
        authorizationStatus = await audioCapture.requestAuthorization()
        return authorizationStatus
    }

    func refreshEngineHealth() async -> VoiceEngineHealth {
        let snapshot = await monitor.probe(config: config)
        latestSidecarHealth = snapshot
        applyHealthSnapshot(snapshot)
        return engineHealth
    }

    func startTranscribing(
        onChunk: @escaping (VoiceTranscriptChunk) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        self.onChunk = onChunk
        self.onFailure = onFailure

        guard engineHealth == .ready else {
            throw VoiceTranscriberError.engineUnavailable(healthReasonCode ?? "funasr_sidecar_not_ready")
        }

        guard config.transport == .websocket else {
            throw VoiceTranscriberError.engineUnavailable("funasr_transport_not_supported")
        }

        guard let webSocketURL = URL(string: config.webSocketURL) else {
            throw VoiceTranscriberError.engineUnavailable("funasr_websocket_url_invalid")
        }

        let session = URLSession(configuration: .ephemeral)
        let webSocketTask = session.webSocketTask(with: webSocketURL)
        self.session = session
        self.webSocketTask = webSocketTask
        self.streamID = "xt_funasr_\(UUID().uuidString.lowercased())"
        isRunning = true
        webSocketTask.resume()
        startReceiveLoop()

        Task { @MainActor [weak self] in
            await self?.startStreamingHandshake()
        }
    }

    func stopTranscribing() {
        guard isRunning else {
            cleanupStreaming()
            return
        }
        let webSocketTask = self.webSocketTask
        let streamID = self.streamID
        let audioCapture = self.audioCapture
        cleanupStreaming()

        Task {
            audioCapture.stop()
            guard let webSocketTask else { return }
            let payload = FunASRStartFrame(
                mode: "2pass",
                wavName: streamID ?? "xt_funasr_stream",
                isSpeaking: false,
                wavFormat: "pcm",
                chunkSize: [5, 10, 5],
                chunkInterval: 10,
                audioFS: 16_000,
                hotwords: nil,
                itn: false
            )
            if let data = try? JSONEncoder().encode(payload),
               let text = String(data: data, encoding: .utf8) {
                try? await webSocketTask.send(.string(text))
            }
            webSocketTask.cancel(with: .normalClosure, reason: nil)
        }
    }

    private func startStreamingHandshake() async {
        guard let webSocketTask, let streamID else { return }

        do {
            let payload = FunASRStartFrame(
                mode: "2pass",
                wavName: streamID,
                isSpeaking: true,
                wavFormat: "pcm",
                chunkSize: [5, 10, 5],
                chunkInterval: 10,
                audioFS: 16_000,
                hotwords: nil,
                itn: false
            )
            let data = try JSONEncoder().encode(payload)
            guard let text = String(data: data, encoding: .utf8) else {
                handleStreamingFailure("funasr_start_frame_encoding_failed")
                return
            }
            try await webSocketTask.send(.string(text))
            try audioCapture.start(
                onPCMData: { [weak self] data in
                    Task { @MainActor [weak self] in
                        await self?.sendAudioData(data)
                    }
                },
                onFailure: { [weak self] reason in
                    Task { @MainActor [weak self] in
                        self?.handleStreamingFailure(reason)
                    }
                }
            )
        } catch {
            handleStreamingFailure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func sendAudioData(_ data: Data) async {
        guard isRunning, let webSocketTask else { return }
        do {
            try await webSocketTask.send(.data(data))
        } catch {
            handleStreamingFailure(error.localizedDescription)
        }
    }

    private func startReceiveLoop() {
        receiveLoopTask?.cancel()
        guard let webSocketTask else { return }
        receiveLoopTask = Task { @MainActor [weak self] in
            while let self, self.isRunning {
                do {
                    let message = try await webSocketTask.receive()
                    switch message {
                    case .string(let text):
                        self.ingestServerMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.ingestServerMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if self.isRunning {
                        self.handleStreamingFailure(error.localizedDescription)
                    }
                    break
                }
            }
        }
    }

    private func cleanupStreaming() {
        isRunning = false
        audioCapture.stop()
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        webSocketTask = nil
        session = nil
        streamID = nil
        onChunk = nil
        onFailure = nil
    }

    func ingestServerMessage(_ text: String) {
        for event in FunASRTranscriptParser.parse(text: text) {
            switch event {
            case .transcript(let chunk):
                onChunk?(chunk)
            case .wakeMatch(let phrase):
                onChunk?(VoiceTranscriptChunk(
                    kind: .partial,
                    text: phrase,
                    confidence: 1.0,
                    language: "multi",
                    isWakeMatch: true
                ))
            case .unknown, .keepalive, .vadStart, .vadEnd:
                break
            }
        }
    }

    private func applyHealthSnapshot(_ snapshot: VoiceSidecarHealthSnapshot) {
        switch snapshot.status {
        case .disabled:
            engineHealth = .disabled
            healthReasonCode = "funasr_sidecar_disabled"
        case .unreachable:
            engineHealth = .unavailable
            healthReasonCode = snapshot.lastError ?? "funasr_sidecar_unreachable"
        case .degraded:
            engineHealth = .degraded
            healthReasonCode = snapshot.lastError ?? "funasr_sidecar_degraded"
        case .ready:
            engineHealth = .ready
            healthReasonCode = nil
        }
    }

    private func handleStreamingFailure(_ reason: String) {
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = normalized.isEmpty ? "funasr_streaming_failed" : normalized
        healthReasonCode = message
        engineHealth = .degraded
        let callback = onFailure
        cleanupStreaming()
        callback?(message)
    }
}

private struct FunASRStartFrame: Codable {
    var mode: String
    var wavName: String
    var isSpeaking: Bool
    var wavFormat: String
    var chunkSize: [Int]
    var chunkInterval: Int
    var audioFS: Int
    var hotwords: String?
    var itn: Bool

    enum CodingKeys: String, CodingKey {
        case mode
        case wavName = "wav_name"
        case isSpeaking = "is_speaking"
        case wavFormat = "wav_format"
        case chunkSize = "chunk_size"
        case chunkInterval = "chunk_interval"
        case audioFS = "audio_fs"
        case hotwords
        case itn
    }
}
