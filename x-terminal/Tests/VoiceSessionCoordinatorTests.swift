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

    @Test
    func startConversationCaptureAutoCommitsFinalTranscript() async {
        let transcriber = MockVoiceStreamingTranscriber()
        let coordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )

        let started = await coordinator.startConversationCapture()
        #expect(started)
        #expect(coordinator.isRecording)
        #expect(coordinator.runtimeState.reasonCode == "voice_call_started")

        transcriber.emit(.init(kind: .final, text: "汇报一下当前进度"))

        #expect(!coordinator.isRecording)
        #expect(coordinator.runtimeState.state == .completed)
        #expect(coordinator.lastCommittedUtterance?.text == "汇报一下当前进度")
        #expect(coordinator.lastCommittedUtterance?.captureSource == .continuousConversation)
        #expect(coordinator.lastCommittedUtterance?.trigger == .finalTranscript)
    }

    @Test
    func manualRecordingPublishesCommittedUtteranceOnlyAfterStop() async {
        let transcriber = MockVoiceStreamingTranscriber()
        let coordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )

        await coordinator.startRecording()
        transcriber.emit(.init(kind: .final, text: "先别自动提交"))

        #expect(coordinator.isRecording)
        #expect(coordinator.lastCommittedUtterance == nil)

        coordinator.stopRecording()

        #expect(coordinator.lastCommittedUtterance?.text == "先别自动提交")
        #expect(coordinator.lastCommittedUtterance?.captureSource == .manualComposer)
        #expect(coordinator.lastCommittedUtterance?.trigger == .manualStop)
    }

    @Test
    func wakeArmedCapturePromotesToWakeFollowupAndCommitsWithWakePhrase() async {
        let transcriber = MockVoiceStreamingTranscriber(routeMode: .funasrStreaming)
        let coordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )

        let started = await coordinator.startWakeArmedCapture()
        #expect(started)
        #expect(coordinator.currentCaptureSource == .wakeArmed)

        transcriber.emit(.init(kind: .partial, text: "supervisor", isWakeMatch: true))

        #expect(coordinator.currentCaptureSource == .wakeFollowup)
        #expect(coordinator.lastWakeEvent?.phrase == "supervisor")

        transcriber.emit(.init(kind: .final, text: "supervisor /automation"))

        #expect(!coordinator.isRecording)
        #expect(coordinator.lastCommittedUtterance?.captureSource == .wakeFollowup)
        #expect(coordinator.lastCommittedUtterance?.wakePhrase == "supervisor")
        #expect(coordinator.lastCommittedUtterance?.text == "supervisor /automation")
    }

    @Test
    func duplicateWakeArmedStartAttemptsCollapseIntoSingleCaptureBootstrap() async {
        let transcriber = MockVoiceStreamingTranscriber(routeMode: .funasrStreaming)
        transcriber.refreshEngineHealthDelayNs = 50_000_000
        transcriber.requestAuthorizationDelayNs = 50_000_000
        let coordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )

        async let first = coordinator.startWakeArmedCapture()
        async let second = coordinator.startWakeArmedCapture()
        let (firstStarted, secondStarted) = await (first, second)

        #expect(firstStarted)
        #expect(!secondStarted)
        #expect(coordinator.isRecording)
        #expect(transcriber.refreshEngineHealthCallCount == 1)
        #expect(transcriber.requestAuthorizationCallCount == 1)
        #expect(transcriber.startTranscribingCallCount == 1)
    }
}

@MainActor
private final class MockVoiceStreamingTranscriber: VoiceStreamingTranscriber {
    let routeMode: VoiceRouteMode
    private(set) var authorizationStatus: VoiceTranscriberAuthorizationStatus
    private(set) var engineHealth: VoiceEngineHealth
    private(set) var healthReasonCode: String?
    private(set) var isRunning: Bool = false
    private(set) var requestAuthorizationCallCount: Int = 0
    private(set) var refreshEngineHealthCallCount: Int = 0
    private(set) var startTranscribingCallCount: Int = 0

    var requestAuthorizationDelayNs: UInt64 = 0
    var refreshEngineHealthDelayNs: UInt64 = 0

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
        requestAuthorizationCallCount += 1
        if requestAuthorizationDelayNs > 0 {
            try? await Task.sleep(nanoseconds: requestAuthorizationDelayNs)
        }
        return authorizationStatus
    }

    func refreshEngineHealth() async -> VoiceEngineHealth {
        refreshEngineHealthCallCount += 1
        if refreshEngineHealthDelayNs > 0 {
            try? await Task.sleep(nanoseconds: refreshEngineHealthDelayNs)
        }
        return engineHealth
    }

    func startTranscribing(
        onChunk: @escaping (VoiceTranscriptChunk) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        guard authorizationStatus.isAuthorized else {
            throw VoiceTranscriberError.notAuthorized
        }
        startTranscribingCallCount += 1
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
