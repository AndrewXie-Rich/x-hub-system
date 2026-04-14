import Foundation

@MainActor
final class VoiceSessionCoordinator: ObservableObject {
    private static var sharedStorage: VoiceSessionCoordinator?

    static var shared: VoiceSessionCoordinator {
        if let sharedStorage {
            return sharedStorage
        }
        let coordinator = VoiceSessionCoordinator()
        sharedStorage = coordinator
        return coordinator
    }

    static var sharedIfInitialized: VoiceSessionCoordinator? {
        sharedStorage
    }

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var recognizedText: String = ""
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var authorizationStatus: VoiceTranscriberAuthorizationStatus = .undetermined
    @Published private(set) var permissionSnapshot: VoicePermissionSnapshot = VoicePermissionSnapshotInspector.current()
    @Published private(set) var runtimeState: SupervisorVoiceRuntimeState
    @Published private(set) var routeDecision: VoiceRouteDecision
    @Published private(set) var activeHealthReasonCode: String?
    @Published private(set) var funASRSidecarHealth: VoiceSidecarHealthSnapshot?
    @Published private(set) var lastWakeEvent: VoiceWakeEvent?
    @Published private(set) var lastCommittedUtterance: VoiceCommittedUtterance?
    @Published private(set) var currentCaptureSource: VoiceCaptureSource?

    private var transcribers: [VoiceRouteMode: any VoiceStreamingTranscriber]
    private var preferences: VoiceRuntimePreferences
    private var lastFinalTranscript: String = ""
    private var activeCaptureSource: VoiceCaptureSource = .manualComposer
    private var activeWakePhrase: String?
    private var captureStartInFlight: Bool = false

    init(
        transcribers: [any VoiceStreamingTranscriber]? = nil,
        transcriber: (any VoiceStreamingTranscriber)? = nil,
        preferences: VoiceRuntimePreferences = .default()
    ) {
        let resolvedTranscribers: [any VoiceStreamingTranscriber] = {
            if let transcribers, !transcribers.isEmpty {
                return transcribers
            }
            if let transcriber {
                return [transcriber]
            }
            return [
                FunASRStreamingClient(config: preferences.funASR),
                SystemSpeechCompatibilityTranscriber(localeIdentifier: preferences.localeIdentifier)
            ]
        }()
        self.transcribers = Dictionary(uniqueKeysWithValues: resolvedTranscribers.map { ($0.routeMode, $0) })
        self.preferences = preferences
        let initialDecision = VoiceRoutePolicy.decide(
            preferredRoute: preferences.preferredRoute,
            availability: Self.makeAvailability(for: self.transcribers)
        )
        self.routeDecision = initialDecision
        self.runtimeState = SupervisorVoiceRuntimeState(
            state: .idle,
            route: initialDecision.route,
            recognizedText: "",
            reasonCode: nil
        )
        let initialAuthorizationStatus = resolvedAuthorizationStatus(for: initialDecision.route)
        self.authorizationStatus = initialAuthorizationStatus
        self.permissionSnapshot = VoicePermissionSnapshotInspector.current()
        self.isAuthorized = initialAuthorizationStatus.isAuthorized
        refreshRuntimeDiagnostics()
    }

    var isCaptureStartInFlight: Bool {
        captureStartInFlight
    }

    func setPreferences(_ preferences: VoiceRuntimePreferences) {
        self.preferences = preferences
        if let funASRTranscriber = transcribers[.funasrStreaming] as? FunASRStreamingClient {
            funASRTranscriber.updateConfig(preferences.funASR)
        }
        if let systemSpeechTranscriber = transcribers[.systemSpeechCompatibility] as? SystemSpeechCompatibilityTranscriber,
           !systemSpeechTranscriber.isRunning {
            systemSpeechTranscriber.updateLocaleIdentifier(preferences.localeIdentifier)
        }
        refreshRouteDecision()
    }

    func refreshRouteAvailability() async {
        for transcriber in transcribers.values {
            _ = await transcriber.refreshEngineHealth()
        }
        permissionSnapshot = VoicePermissionSnapshotInspector.current()
        refreshRouteDecision()
    }

    func refreshAuthorizationStatus(requestIfNeeded: Bool = false) async {
        await refreshRouteAvailability()
        guard let activeTranscriber = activeTranscriber(for: routeDecision.route) else {
            authorizationStatus = resolvedAuthorizationStatus(for: routeDecision.route)
            isAuthorized = false
            refreshRouteDecision()
            return
        }
        let status: VoiceTranscriberAuthorizationStatus
        if requestIfNeeded {
            status = await activeTranscriber.requestAuthorization()
        } else {
            status = activeTranscriber.authorizationStatus
        }
        permissionSnapshot = VoicePermissionSnapshotInspector.current()
        authorizationStatus = status
        isAuthorized = status.isAuthorized
        refreshRouteDecision()
    }

    func startRecording() async {
        _ = await beginCapture(
            markReason: nil,
            captureSource: .manualComposer
        )
    }

    @discardableResult
    func startConversationCapture() async -> Bool {
        await beginCapture(
            markReason: "voice_call_started",
            captureSource: .continuousConversation
        )
    }

    @discardableResult
    func startWakeArmedCapture() async -> Bool {
        await beginCapture(
            markReason: "wake_armed",
            captureSource: .wakeArmed
        )
    }

    @discardableResult
    func resumeListeningForTalkLoop() async -> Bool {
        await beginCapture(
            markReason: "talk_loop_resumed",
            captureSource: .talkLoop
        )
    }

    @discardableResult
    private func beginCapture(
        markReason: String?,
        captureSource: VoiceCaptureSource
    ) async -> Bool {
        guard !isRecording else { return true }
        guard !captureStartInFlight else { return false }
        captureStartInFlight = true
        defer { captureStartInFlight = false }

        await refreshRouteAvailability()
        if let systemSpeechTranscriber = transcribers[.systemSpeechCompatibility] as? SystemSpeechCompatibilityTranscriber,
           !systemSpeechTranscriber.isRunning {
            systemSpeechTranscriber.updateLocaleIdentifier(preferences.localeIdentifier)
        }
        guard let activeTranscriber = activeTranscriber(for: routeDecision.route) else {
            runtimeState = SupervisorVoiceRuntimeState(
                state: .failClosed,
                route: routeDecision.route,
                recognizedText: recognizedText,
                reasonCode: routeDecision.reasonCode
            )
            return false
        }

        let status = await activeTranscriber.requestAuthorization()
        permissionSnapshot = VoicePermissionSnapshotInspector.current()
        isAuthorized = status.isAuthorized
        refreshRouteDecision()

        guard routeDecision.route.supportsLiveCapture else {
            runtimeState = SupervisorVoiceRuntimeState(
                state: .failClosed,
                route: routeDecision.route,
                recognizedText: recognizedText,
                reasonCode: routeDecision.reasonCode
            )
            return false
        }

        guard status.isAuthorized else {
            runtimeState = SupervisorVoiceRuntimeState(
                state: .failClosed,
                route: routeDecision.route,
                recognizedText: recognizedText,
                reasonCode: routeDecision.reasonCode.isEmpty
                    ? "speech_authorization_required"
                    : routeDecision.reasonCode
            )
            return false
        }

        recognizedText = ""
        lastFinalTranscript = ""
        activeCaptureSource = captureSource
        currentCaptureSource = captureSource
        activeWakePhrase = nil
        runtimeState = SupervisorVoiceRuntimeState(
            state: .listening,
            route: routeDecision.route,
            recognizedText: "",
            reasonCode: markReason
        )

        do {
            try activeTranscriber.startTranscribing(
                onChunk: { [weak self] chunk in
                    self?.handleTranscriptChunk(chunk)
                },
                onFailure: { [weak self] reason in
                    self?.handleTranscriberFailure(reason)
                }
            )
            isRecording = true
            return true
        } catch {
            handleTranscriberFailure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return false
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        finishCapture(
            commitTrigger: .manualStop,
            committedText: committedTranscript()
        )
    }

    func discardRecording(reasonCode: String? = "capture_cancelled") {
        guard isRecording else {
            clearTranscript()
            return
        }
        activeTranscriber(for: routeDecision.route)?.stopTranscribing()
        isRecording = false
        activeCaptureSource = .manualComposer
        currentCaptureSource = nil
        activeWakePhrase = nil
        recognizedText = ""
        lastFinalTranscript = ""
        runtimeState = SupervisorVoiceRuntimeState(
            state: .idle,
            route: routeDecision.route,
            recognizedText: "",
            reasonCode: reasonCode
        )
    }

    func committedTranscript() -> String {
        let primary = lastFinalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty {
            return primary
        }
        return recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearTranscript() {
        recognizedText = ""
        lastFinalTranscript = ""
        if !isRecording {
            runtimeState = SupervisorVoiceRuntimeState(
                state: .idle,
                route: routeDecision.route,
                recognizedText: "",
                reasonCode: nil
            )
        }
    }

    private func handleTranscriptChunk(_ chunk: VoiceTranscriptChunk) {
        guard isRecording else { return }
        if chunk.isWakeMatch {
            let phrase = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            lastWakeEvent = VoiceWakeEvent(
                phrase: phrase.isEmpty ? "wake_match" : phrase,
                route: routeDecision.route
            )
            if activeCaptureSource == .wakeArmed {
                activeCaptureSource = .wakeFollowup
                currentCaptureSource = .wakeFollowup
                activeWakePhrase = phrase.isEmpty ? nil : phrase
            }
        }
        recognizedText = chunk.text
        if chunk.kind == .final || chunk.kind == .revisedFinal {
            lastFinalTranscript = chunk.text
        }
        runtimeState = SupervisorVoiceRuntimeState(
            state: .transcribing,
            route: routeDecision.route,
            recognizedText: chunk.text,
            reasonCode: nil
        )
        if (chunk.kind == .final || chunk.kind == .revisedFinal) &&
            activeCaptureSource.autoCommitsOnFinalTranscript {
            finishCapture(
                commitTrigger: .finalTranscript,
                committedText: chunk.text
            )
        }
    }

    private func handleTranscriberFailure(_ reason: String) {
        activeTranscriber(for: routeDecision.route)?.stopTranscribing()
        isRecording = false
        activeCaptureSource = .manualComposer
        currentCaptureSource = nil
        activeWakePhrase = nil
        runtimeState = SupervisorVoiceRuntimeState(
            state: .failClosed,
            route: routeDecision.route,
            recognizedText: recognizedText,
            reasonCode: reason.isEmpty ? "voice_transcriber_runtime_failure" : reason
        )
    }

    private func refreshRouteDecision() {
        routeDecision = VoiceRoutePolicy.decide(
            preferredRoute: preferences.preferredRoute,
            availability: Self.makeAvailability(for: transcribers)
        )
        authorizationStatus = resolvedAuthorizationStatus(for: routeDecision.route)
        isAuthorized = authorizationStatus.isAuthorized
        refreshRuntimeDiagnostics()
        if !isRecording {
            runtimeState = SupervisorVoiceRuntimeState(
                state: runtimeState.state == .failClosed ? .failClosed : .idle,
                route: routeDecision.route,
                recognizedText: recognizedText,
                reasonCode: runtimeState.state == .failClosed ? runtimeState.reasonCode : nil
            )
        }
    }

    private static func makeAvailability(
        for transcribers: [VoiceRouteMode: any VoiceStreamingTranscriber]
    ) -> VoiceRouteAvailability {
        VoiceRouteAvailability(
            funasr: transcribers[.funasrStreaming]?.engineHealth ?? .disabled,
            whisperKit: transcribers[.whisperKitLocal]?.engineHealth ?? .disabled,
            systemSpeech: transcribers[.systemSpeechCompatibility]?.engineHealth ?? .disabled
        )
    }

    private func activeTranscriber(
        for route: VoiceRouteMode
    ) -> (any VoiceStreamingTranscriber)? {
        transcribers[route]
    }

    private func refreshRuntimeDiagnostics() {
        if let funASRTranscriber = transcribers[.funasrStreaming] as? FunASRStreamingClient {
            funASRSidecarHealth = funASRTranscriber.latestSidecarHealth
        } else {
            funASRSidecarHealth = nil
        }

        if let activeTranscriber = activeTranscriber(for: routeDecision.route),
           let reason = normalizedHealthReasonCode(activeTranscriber.healthReasonCode) {
            activeHealthReasonCode = reason
            return
        }

        activeHealthReasonCode = diagnosticsTranscribers()
            .compactMap { normalizedHealthReasonCode($0.healthReasonCode) }
            .first
    }

    private func resolvedAuthorizationStatus(
        for route: VoiceRouteMode
    ) -> VoiceTranscriberAuthorizationStatus {
        if let activeTranscriber = activeTranscriber(for: route) {
            return activeTranscriber.authorizationStatus
        }

        let diagnosticStatuses = diagnosticsTranscribers().map { $0.authorizationStatus }
        if let blockedStatus = diagnosticStatuses.first(where: { status in
            status == .denied || status == .restricted || status == .unavailable
        }) {
            return blockedStatus
        }

        return .unavailable
    }

    private func diagnosticsTranscribers() -> [any VoiceStreamingTranscriber] {
        [
            transcribers[.funasrStreaming],
            transcribers[.whisperKitLocal],
            transcribers[.systemSpeechCompatibility]
        ].compactMap { $0 }
    }

    private func normalizedHealthReasonCode(_ reason: String?) -> String? {
        guard let reason else { return nil }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func finishCapture(
        commitTrigger: VoiceCommitTrigger,
        committedText: String
    ) {
        guard isRecording else { return }
        let captureSource = activeCaptureSource
        let committed = committedText.trimmingCharacters(in: .whitespacesAndNewlines)
        isRecording = false
        activeTranscriber(for: routeDecision.route)?.stopTranscribing()
        activeCaptureSource = .manualComposer
        currentCaptureSource = nil
        runtimeState = SupervisorVoiceRuntimeState(
            state: committed.isEmpty ? .idle : .completed,
            route: routeDecision.route,
            recognizedText: committed,
            reasonCode: committed.isEmpty ? nil : "capture_completed"
        )
        guard !committed.isEmpty else { return }
        lastCommittedUtterance = VoiceCommittedUtterance(
            text: committed,
            route: routeDecision.route,
            captureSource: captureSource,
            trigger: commitTrigger,
            wakePhrase: activeWakePhrase
        )
        activeWakePhrase = nil
    }
}
