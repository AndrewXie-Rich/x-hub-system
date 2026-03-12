import Foundation
import Testing
@testable import XTerminal

@MainActor
struct FunASRStreamingClientTests {

    @Test
    func parserEmitsPartialAndFinalTranscriptEvents() {
        let partial = FunASRTranscriptParser.parse(
            text: #"{"text":"supervisor","is_final":false,"language":"en"}"#
        )
        let final = FunASRTranscriptParser.parse(
            text: #"{"text":"supervisor report blockers","is_final":true,"language":"en"}"#
        )

        #expect(partial == [.transcript(VoiceTranscriptChunk(
            kind: .partial,
            text: "supervisor",
            confidence: nil,
            language: "en",
            isWakeMatch: false
        ))])
        #expect(final == [.transcript(VoiceTranscriptChunk(
            kind: .final,
            text: "supervisor report blockers",
            confidence: nil,
            language: "en",
            isWakeMatch: false
        ))])
    }

    @Test
    func parserEmitsWakeAndVadEvents() {
        let wake = FunASRTranscriptParser.parse(
            text: #"{"event":"wake_match","keyword":"Supervisor"}"#
        )
        let vadStart = FunASRTranscriptParser.parse(
            text: #"{"event":"vad_start"}"#
        )
        let vadEnd = FunASRTranscriptParser.parse(
            text: #"{"event":"vad_end"}"#
        )

        #expect(wake == [.wakeMatch("Supervisor")])
        #expect(vadStart == [.vadStart])
        #expect(vadEnd == [.vadEnd])
    }

    @Test
    func healthMonitorRejectsRemoteEndpoints() async {
        let monitor = FunASRSidecarHealthMonitor()
        let snapshot = await monitor.probe(
            config: FunASRSidecarConfig(
                enabled: true,
                transport: .websocket,
                webSocketURL: "ws://192.168.1.20:10096",
                healthcheckURL: "http://192.168.1.20:10095/health",
                wakeEnabled: true,
                partialsEnabled: true
            )
        )

        #expect(snapshot.status == .unreachable)
        #expect(snapshot.lastError == "funasr_remote_sidecar_not_allowed")
    }

    @Test
    func clientMapsHealthySidecarToReadyWhenAudioBridgeIsAvailable() async {
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
        let client = FunASRStreamingClient(
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

        let health = await client.refreshEngineHealth()

        #expect(health == .ready)
        #expect(client.healthReasonCode == nil)
    }

    @Test
    func clientDelegatesAuthorizationToInjectedAudioCapture() async {
        let audioCapture = MockVoicePCMDataCapture(authorizationStatus: .denied)
        let client = FunASRStreamingClient(
            config: .default(),
            audioCapture: audioCapture
        )

        let status = await client.requestAuthorization()

        #expect(status == .denied)
        #expect(client.authorizationStatus == .denied)
        #expect(audioCapture.requestAuthorizationCallCount == 1)
    }
}

@MainActor
private final class MockVoicePCMDataCapture: VoicePCMDataCapturing {
    private(set) var requestAuthorizationCallCount: Int = 0
    private(set) var startCallCount: Int = 0
    private(set) var stopCallCount: Int = 0

    var authorizationStatus: VoiceTranscriberAuthorizationStatus
    var startError: Error?
    var onPCMData: ((Data) -> Void)?
    var onFailure: ((String) -> Void)?

    init(
        authorizationStatus: VoiceTranscriberAuthorizationStatus = .authorized,
        startError: Error? = nil
    ) {
        self.authorizationStatus = authorizationStatus
        self.startError = startError
    }

    func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus {
        requestAuthorizationCallCount += 1
        return authorizationStatus
    }

    func start(
        onPCMData: @escaping (Data) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
        self.onPCMData = onPCMData
        self.onFailure = onFailure
    }

    func stop() {
        stopCallCount += 1
    }
}
