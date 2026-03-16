import Foundation
import Testing
@testable import XTerminal

@MainActor
struct VoiceSessionCoordinatorTests {

    @Test
    func startRecordingTracksTranscriptLifecycle() async {
        let transcriber = MockVoiceStreamingTranscriber()
        let coordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )

        await coordinator.startRecording()
        #expect(coordinator.isRecording == true)
        #expect(coordinator.runtimeState.state == .listening)

        transcriber.emit(.init(kind: .partial, text: "supervisor"))
        #expect(coordinator.runtimeState.state == .transcribing)
        #expect(coordinator.recognizedText == "supervisor")

        transcriber.emit(.init(kind: .final, text: "supervisor report blockers"))
        coordinator.stopRecording()

        #expect(coordinator.isRecording == false)
        #expect(coordinator.committedTranscript() == "supervisor report blockers")
        #expect(coordinator.runtimeState.state == .completed)
    }

    @Test
    func deniedAuthorizationFailsClosedWithoutStartingCapture() async {
        let transcriber = MockVoiceStreamingTranscriber(
            authorizationStatus: .denied
        )
        let coordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )

        await coordinator.startRecording()

        #expect(coordinator.isRecording == false)
        #expect(coordinator.runtimeState.state == .failClosed)
        #expect(coordinator.runtimeState.reasonCode == "microphone_or_speech_unauthorized")
    }

    @Test
    func coordinatorPublishesAuthorizationAndHealthDiagnostics() async {
        let transcriber = MockVoiceStreamingTranscriber(
            authorizationStatus: .denied
        )
        let coordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )

        await coordinator.refreshAuthorizationStatus(requestIfNeeded: false)

        #expect(coordinator.authorizationStatus == .denied)
        #expect(coordinator.activeHealthReasonCode == "authorization_denied")
    }

    @Test
    func coordinatorPublishesFunASRSidecarSnapshot() async {
        let monitor = FunASRSidecarHealthMonitor(probeHandler: { config in
            VoiceSidecarHealthSnapshot(
                engine: "funasr",
                transport: config.transport,
                endpoint: config.webSocketURL,
                status: .ready,
                vadReady: true,
                wakeReady: true,
                partialReady: true,
                lastError: nil
            )
        })
        let transcriber = FunASRStreamingClient(
            config: FunASRSidecarConfig(
                enabled: true,
                transport: .websocket,
                webSocketURL: "ws://127.0.0.1:10096",
                healthcheckURL: "http://127.0.0.1:10095/health",
                wakeEnabled: true,
                partialsEnabled: true
            ),
            monitor: monitor,
            audioCapture: MockVoicePCMDataCapture()
        )
        let coordinator = VoiceSessionCoordinator(
            transcribers: [transcriber],
            preferences: .default()
        )

        await coordinator.refreshRouteAvailability()

        #expect(coordinator.funASRSidecarHealth?.status == .ready)
        #expect(coordinator.funASRSidecarHealth?.endpoint == "ws://127.0.0.1:10096")
    }

    @Test
    func resumeListeningForTalkLoopRestartsCaptureAfterCompletedTurn() async {
        let transcriber = MockVoiceStreamingTranscriber()
        let coordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )

        await coordinator.startRecording()
        transcriber.emit(.init(kind: .final, text: "supervisor"))
        coordinator.stopRecording()

        let resumed = await coordinator.resumeListeningForTalkLoop()

        #expect(resumed)
        #expect(coordinator.isRecording)
        #expect(coordinator.runtimeState.state == .listening)
        #expect(coordinator.runtimeState.reasonCode == "talk_loop_resumed")
        #expect(coordinator.recognizedText.isEmpty)
    }
}

@MainActor
private final class MockVoiceStreamingTranscriber: VoiceStreamingTranscriber {
    let routeMode: VoiceRouteMode
    private(set) var authorizationStatus: VoiceTranscriberAuthorizationStatus
    private(set) var engineHealth: VoiceEngineHealth
    private(set) var healthReasonCode: String?
    private(set) var isRunning: Bool = false

    private var onChunk: ((VoiceTranscriptChunk) -> Void)?
    private var onFailure: ((String) -> Void)?

    init(
        routeMode: VoiceRouteMode = .systemSpeechCompatibility,
        authorizationStatus: VoiceTranscriberAuthorizationStatus = .authorized,
        engineHealth: VoiceEngineHealth? = nil,
        healthReasonCode: String? = nil
    ) {
        self.routeMode = routeMode
        self.authorizationStatus = authorizationStatus
        self.engineHealth = engineHealth ?? Self.defaultEngineHealth(for: authorizationStatus)
        self.healthReasonCode = healthReasonCode ?? Self.defaultHealthReason(for: authorizationStatus)
    }

    func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus {
        authorizationStatus
    }

    func refreshEngineHealth() async -> VoiceEngineHealth {
        engineHealth
    }

    func startTranscribing(
        onChunk: @escaping (VoiceTranscriptChunk) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        guard authorizationStatus.isAuthorized else {
            throw VoiceTranscriberError.notAuthorized
        }
        isRunning = true
        self.onChunk = onChunk
        self.onFailure = onFailure
    }

    func stopTranscribing() {
        isRunning = false
    }

    func emit(_ chunk: VoiceTranscriptChunk) {
        onChunk?(chunk)
    }

    func fail(_ reason: String) {
        onFailure?(reason)
    }

    private static func defaultEngineHealth(
        for authorizationStatus: VoiceTranscriberAuthorizationStatus
    ) -> VoiceEngineHealth {
        switch authorizationStatus {
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

    private static func defaultHealthReason(
        for authorizationStatus: VoiceTranscriberAuthorizationStatus
    ) -> String? {
        switch authorizationStatus {
        case .authorized:
            return nil
        case .undetermined:
            return "authorization_pending"
        case .denied:
            return "authorization_denied"
        case .restricted:
            return "authorization_restricted"
        case .unavailable:
            return "engine_unavailable"
        }
    }
}

@MainActor
private final class MockVoicePCMDataCapture: VoicePCMDataCapturing {
    var authorizationStatus: VoiceTranscriberAuthorizationStatus

    init(authorizationStatus: VoiceTranscriberAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
    }

    func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus {
        authorizationStatus
    }

    func start(
        onPCMData: @escaping (Data) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {}

    func stop() {}
}
