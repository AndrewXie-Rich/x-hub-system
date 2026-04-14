import Foundation

enum VoiceRouteMode: String, Codable, CaseIterable, Identifiable {
    case funasrStreaming = "funasr_streaming"
    case whisperKitLocal = "whisperkit_local"
    case systemSpeechCompatibility = "system_speech_compatibility"
    case manualText = "manual_text"
    case failClosed = "fail_closed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .funasrStreaming:
            return "FunASR 流式"
        case .whisperKitLocal:
            return "WhisperKit 本地"
        case .systemSpeechCompatibility:
            return "系统语音"
        case .manualText:
            return "手动文本"
        case .failClosed:
            return "安全关闭"
        }
    }

    var supportsLiveCapture: Bool {
        switch self {
        case .funasrStreaming, .whisperKitLocal, .systemSpeechCompatibility:
            return true
        case .manualText, .failClosed:
            return false
        }
    }
}

enum VoicePreferredRoute: String, Codable, CaseIterable, Identifiable {
    case automatic = "automatic"
    case funasrStreaming = "funasr_streaming"
    case whisperKitLocal = "whisperkit_local"
    case systemSpeechCompatibility = "system_speech_compatibility"
    case manualText = "manual_text"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "自动"
        case .funasrStreaming:
            return "FunASR 流式"
        case .whisperKitLocal:
            return "WhisperKit 本地"
        case .systemSpeechCompatibility:
            return "系统语音"
        case .manualText:
            return "手动文本"
        }
    }
}

enum VoiceWakeMode: String, Codable, CaseIterable, Identifiable {
    case pushToTalk = "push_to_talk"
    case wakePhrase = "wake_phrase"
    case promptPhraseOnly = "prompt_phrase_only"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pushToTalk:
            return "按住说话"
        case .wakePhrase:
            return "唤醒词"
        case .promptPhraseOnly:
            return "仅提示词"
        }
    }
}

enum VoiceAutoReportMode: String, Codable, CaseIterable, Identifiable {
    case silent = "silent"
    case blockersOnly = "blockers_only"
    case summary = "summary"
    case full = "full"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .silent:
            return "静默"
        case .blockersOnly:
            return "仅阻塞"
        case .summary:
            return "摘要"
        case .full:
            return "全量"
        }
    }
}

enum VoicePersonaPreset: String, Codable, CaseIterable, Identifiable {
    case briefing = "briefing"
    case conversational = "conversational"
    case calm = "calm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .briefing:
            return "简报"
        case .conversational:
            return "对话"
        case .calm:
            return "平静"
        }
    }
}

enum VoiceSupportedLocale: String, Codable, CaseIterable, Identifiable {
    case chineseMainland = "zh-CN"
    case englishUS = "en-US"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chineseMainland:
            return "中文"
        case .englishUS:
            return "英文"
        }
    }
}

enum VoiceTimbrePreset: String, Codable, CaseIterable, Identifiable {
    case neutral = "neutral"
    case warm = "warm"
    case clear = "clear"
    case bright = "bright"
    case calm = "calm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neutral:
            return "中性"
        case .warm:
            return "温暖"
        case .clear:
            return "清晰"
        case .bright:
            return "明亮"
        case .calm:
            return "平静"
        }
    }
}

enum VoicePlaybackPreference: String, Codable, CaseIterable, Identifiable {
    case automatic = "automatic"
    case hubVoicePack = "hub_voice_pack"
    case systemSpeech = "system_speech"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "自动"
        case .hubVoicePack:
            return "Hub 语音包"
        case .systemSpeech:
            return "系统语音"
        }
    }
}

enum VoicePlaybackSource: String, Codable, Equatable, Sendable {
    case hubVoicePack = "hub_voice_pack"
    case systemSpeech = "system_speech"

    var displayName: String {
        switch self {
        case .hubVoicePack:
            return "Hub 语音包"
        case .systemSpeech:
            return "系统语音"
        }
    }
}

enum VoicePlaybackActivityState: String, Equatable, Sendable {
    case idle = "idle"
    case played = "played"
    case fallbackPlayed = "fallback_played"
    case suppressed = "suppressed"
    case failed = "failed"

    var displayName: String {
        switch self {
        case .idle:
            return "还没有真实播放"
        case .played:
            return "播放成功"
        case .fallbackPlayed:
            return "已回退播放"
        case .suppressed:
            return "播放被抑制"
        case .failed:
            return "播放失败"
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            return "waveform.slash"
        case .played:
            return "speaker.wave.2.fill"
        case .fallbackPlayed:
            return "arrow.trianglehead.branch"
        case .suppressed:
            return "speaker.slash.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct VoicePlaybackActivity: Equatable, Sendable {
    var state: VoicePlaybackActivityState
    var configuredResolution: VoicePlaybackResolution?
    var actualSource: VoicePlaybackSource?
    var reasonCode: String
    var detail: String
    var provider: String
    var modelID: String
    var engineName: String
    var speakerId: String
    var deviceBackend: String
    var nativeTTSUsed: Bool?
    var fallbackMode: String
    var fallbackReasonCode: String
    var audioFormat: String
    var voiceName: String
    var auditLine: String
    var updatedAt: TimeInterval

    init(
        state: VoicePlaybackActivityState,
        configuredResolution: VoicePlaybackResolution?,
        actualSource: VoicePlaybackSource?,
        reasonCode: String,
        detail: String,
        provider: String,
        modelID: String,
        engineName: String,
        speakerId: String,
        deviceBackend: String,
        nativeTTSUsed: Bool?,
        fallbackMode: String,
        fallbackReasonCode: String,
        audioFormat: String,
        voiceName: String,
        auditLine: String = "",
        updatedAt: TimeInterval
    ) {
        self.state = state
        self.configuredResolution = configuredResolution
        self.actualSource = actualSource
        self.reasonCode = reasonCode
        self.detail = detail
        self.provider = provider
        self.modelID = modelID
        self.engineName = engineName
        self.speakerId = speakerId
        self.deviceBackend = deviceBackend
        self.nativeTTSUsed = nativeTTSUsed
        self.fallbackMode = fallbackMode
        self.fallbackReasonCode = fallbackReasonCode
        self.audioFormat = audioFormat
        self.voiceName = voiceName
        self.auditLine = auditLine
        self.updatedAt = updatedAt
    }

    static let empty = VoicePlaybackActivity(
        state: .idle,
        configuredResolution: nil,
        actualSource: nil,
        reasonCode: "voice_playback_idle",
        detail: "",
        provider: "",
        modelID: "",
        engineName: "",
        speakerId: "",
        deviceBackend: "",
        nativeTTSUsed: nil,
        fallbackMode: "",
        fallbackReasonCode: "",
        audioFormat: "",
        voiceName: "",
        auditLine: "",
        updatedAt: 0
    )

    var actualSourceDisplayName: String {
        actualSource?.displayName ?? "还没有真实播放"
    }

    var engineDisplayName: String {
        if let engineName = Self.normalized(engineName) {
            return engineName
        }
        let normalizedFallback = Self.normalized(fallbackMode)
        let normalizedBackend = Self.normalized(deviceBackend)
        if normalizedFallback == "system_voice_compatibility" || normalizedBackend == "system_voice_compatibility" {
            return "Hub 系统语音兼容层"
        }
        if let fallback = normalizedFallback {
            return fallback
        }
        if let backend = normalizedBackend {
            return backend
        }
        if let actualSource {
            switch actualSource {
            case .hubVoicePack:
                return "Hub 语音包"
            case .systemSpeech:
                return "macOS 系统语音"
            }
        }
        return "还没有真实播放"
    }

    var speakerDisplayName: String {
        Self.normalized(speakerId) ?? "默认 / 未指定"
    }

    var hasFallbackContext: Bool {
        Self.normalized(fallbackReasonCode) != nil
            || Self.normalized(fallbackMode) != nil
            || configuredResolution?.fallbackFrom != nil
    }

    var shouldDisplayExecutionMode: Bool {
        actualSource == .hubVoicePack || nativeTTSUsed != nil || hasFallbackContext
    }

    var executionModeDisplayName: String {
        guard let nativeTTSUsed else {
            if actualSource == .systemSpeech {
                return hasFallbackContext ? "系统语音回退" : "系统语音"
            }
            return "未知"
        }
        return nativeTTSUsed ? "原生 TTS" : "兼容回退"
    }

    var fallbackReasonDisplayName: String {
        Self.normalized(fallbackReasonCode) ?? "无"
    }

    var compactRailSummaryLine: String? {
        guard state != .idle else { return nil }

        var parts: [String] = []
        if let actualSource {
            switch actualSource {
            case .hubVoicePack:
                parts.append("tts=\(engineDisplayName)")
            case .systemSpeech:
                parts.append("tts=system")
            }
        } else {
            parts.append("tts=unknown")
        }

        if let speaker = Self.normalized(speakerId) {
            parts.append("spk=\(speaker)")
        }

        if shouldDisplayExecutionMode {
            parts.append("mode=\(executionModeDisplayName.replacingOccurrences(of: " ", with: "_").lowercased())")
        }

        if let reason = Self.normalized(fallbackReasonCode) {
            parts.append("why=\(reason)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var runtimeLogSummaryLine: String? {
        guard state != .idle else { return nil }

        var parts: [String] = ["voice_playback", "state=\(state.rawValue)"]

        if let actualSource {
            parts.append("output=\(actualSource.rawValue)")
        }

        if let compactSummary = compactRailSummaryLine {
            parts.append(compactSummary)
        }

        let fallbackFromSource = configuredResolution?.fallbackFrom
            ?? (state == .fallbackPlayed ? configuredResolution?.resolvedSource : nil)
        if let fallbackFrom = fallbackFromSource?.rawValue {
            parts.append("fallback_from=\(fallbackFrom)")
        }

        if let modelID = Self.normalized(modelID) {
            parts.append("model=\(modelID)")
        }

        if let provider = Self.normalized(provider),
           actualSource == .hubVoicePack || provider == "hub_voice_pack" {
            parts.append("provider=\(provider)")
        }

        if parts.count == 2,
           let reason = Self.normalized(reasonCode) {
            parts.append("reason=\(reason)")
        }

        return parts.joined(separator: " ")
    }

    var headline: String {
        switch state {
        case .idle:
            return "还没有真实播放记录"
        case .played:
            return "最近一次播放成功"
        case .fallbackPlayed:
            return "最近一次播放已回退"
        case .suppressed:
            return "最近一次播放请求被抑制"
        case .failed:
            return "最近一次播放失败"
        }
    }

    var summaryLine: String {
        switch state {
        case .idle:
            return "可以先点“试听语音”，用当前设置捕获实际播放后端。"
        case .played:
            if let nativeTTSUsed {
                let mode = nativeTTSUsed ? "原生合成" : "兼容回退"
                return "实际输出使用 \(actualSourceDisplayName)，引擎为 \(engineDisplayName)（\(mode)）。"
            }
            return "实际输出使用 \(actualSourceDisplayName)，引擎为 \(engineDisplayName)。"
        case .fallbackPlayed:
            let fallbackFrom = configuredResolution?.fallbackFrom?.displayName ?? "Hub 语音包"
            return "播放已从 \(fallbackFrom) 回退到 \(actualSourceDisplayName)。"
        case .suppressed:
            return "最近一次播放请求在真正输出前被 XT 主动抑制。"
        case .failed:
            return "最近一次播放尝试没有成功抵达输出设备。"
        }
    }

    var recommendedNextStep: String? {
        switch state {
        case .fallbackPlayed:
            if let detail = Self.normalized(detail) {
                return detail
            }
            if configuredResolution?.fallbackFrom == .hubVoicePack {
                return "如果你想恢复 Hub 语音包，请打开 Supervisor 设置，检查语音包是否仍在 Hub Library，且本机 Hub IPC 已报告 ready。"
            }
            return "当前已经安全回退到系统语音；如果你想恢复原始播放链路，请打开 Supervisor 设置检查当前输出配置。"
        case .failed:
            return Self.normalized(detail) ?? "打开 Supervisor 设置，确认当前播放输出链路。"
        case .idle, .played, .suppressed:
            return nil
        }
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct VoiceQuietHours: Codable, Equatable {
    var enabled: Bool
    var fromLocal: String
    var toLocal: String

    static func `default`() -> VoiceQuietHours {
        VoiceQuietHours(
            enabled: false,
            fromLocal: "22:00",
            toLocal: "08:00"
        )
    }
}

struct VoiceRuntimePreferences: Codable, Equatable {
    var preferredRoute: VoicePreferredRoute
    var playbackPreference: VoicePlaybackPreference
    var wakeMode: VoiceWakeMode
    var autoReportMode: VoiceAutoReportMode
    var persona: VoicePersonaPreset
    var timbre: VoiceTimbrePreset
    var preferredHubVoicePackID: String
    var speechRateMultiplier: Float
    var interruptOnSpeech: Bool
    var quietHours: VoiceQuietHours
    var localeIdentifier: String
    var funASR: FunASRSidecarConfig

    enum CodingKeys: String, CodingKey {
        case preferredRoute
        case playbackPreference
        case wakeMode
        case autoReportMode
        case persona
        case timbre
        case preferredHubVoicePackID
        case speechRateMultiplier
        case interruptOnSpeech
        case quietHours
        case localeIdentifier
        case funASR
    }

    static func `default`() -> VoiceRuntimePreferences {
        VoiceRuntimePreferences(
            preferredRoute: .automatic,
            playbackPreference: .automatic,
            wakeMode: .pushToTalk,
            autoReportMode: .summary,
            persona: .conversational,
            timbre: .neutral,
            preferredHubVoicePackID: "",
            speechRateMultiplier: 1.0,
            interruptOnSpeech: true,
            quietHours: .default(),
            localeIdentifier: VoiceSupportedLocale.chineseMainland.rawValue,
            funASR: .default()
        )
    }

    init(
        preferredRoute: VoicePreferredRoute,
        playbackPreference: VoicePlaybackPreference,
        wakeMode: VoiceWakeMode,
        autoReportMode: VoiceAutoReportMode,
        persona: VoicePersonaPreset,
        timbre: VoiceTimbrePreset,
        preferredHubVoicePackID: String,
        speechRateMultiplier: Float,
        interruptOnSpeech: Bool,
        quietHours: VoiceQuietHours,
        localeIdentifier: String,
        funASR: FunASRSidecarConfig
    ) {
        self.preferredRoute = preferredRoute
        self.playbackPreference = playbackPreference
        self.wakeMode = wakeMode
        self.autoReportMode = autoReportMode
        self.persona = persona
        self.timbre = timbre
        self.preferredHubVoicePackID = preferredHubVoicePackID
        self.speechRateMultiplier = speechRateMultiplier
        self.interruptOnSpeech = interruptOnSpeech
        self.quietHours = quietHours
        self.localeIdentifier = localeIdentifier
        self.funASR = funASR
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredRoute = (try? container.decode(VoicePreferredRoute.self, forKey: .preferredRoute)) ?? .automatic
        playbackPreference = (try? container.decode(VoicePlaybackPreference.self, forKey: .playbackPreference)) ?? .automatic
        wakeMode = (try? container.decode(VoiceWakeMode.self, forKey: .wakeMode)) ?? .pushToTalk
        autoReportMode = (try? container.decode(VoiceAutoReportMode.self, forKey: .autoReportMode)) ?? .summary
        persona = (try? container.decode(VoicePersonaPreset.self, forKey: .persona)) ?? .conversational
        timbre = (try? container.decode(VoiceTimbrePreset.self, forKey: .timbre)) ?? .neutral
        preferredHubVoicePackID = (try? container.decode(String.self, forKey: .preferredHubVoicePackID)) ?? ""
        speechRateMultiplier = (try? container.decode(Float.self, forKey: .speechRateMultiplier)) ?? 1.0
        interruptOnSpeech = (try? container.decode(Bool.self, forKey: .interruptOnSpeech)) ?? true
        quietHours = (try? container.decode(VoiceQuietHours.self, forKey: .quietHours)) ?? .default()
        localeIdentifier = (try? container.decode(String.self, forKey: .localeIdentifier))
            ?? VoiceSupportedLocale.chineseMainland.rawValue
        funASR = (try? container.decode(FunASRSidecarConfig.self, forKey: .funASR)) ?? .default()
    }
}

enum VoiceSidecarTransport: String, Codable, Equatable, CaseIterable, Identifiable {
    case websocket
    case http
    case grpc

    var id: String { rawValue }
}

enum VoiceSidecarStatus: String, Codable, Equatable {
    case ready
    case degraded
    case unreachable
    case disabled
}

struct FunASRSidecarConfig: Codable, Equatable {
    var enabled: Bool
    var transport: VoiceSidecarTransport
    var webSocketURL: String
    var healthcheckURL: String?
    var wakeEnabled: Bool
    var partialsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case transport
        case webSocketURL
        case healthcheckURL
        case wakeEnabled
        case partialsEnabled
    }

    static func `default`() -> FunASRSidecarConfig {
        FunASRSidecarConfig(
            enabled: false,
            transport: .websocket,
            webSocketURL: "ws://127.0.0.1:10096",
            healthcheckURL: nil,
            wakeEnabled: true,
            partialsEnabled: true
        )
    }

    init(
        enabled: Bool,
        transport: VoiceSidecarTransport,
        webSocketURL: String,
        healthcheckURL: String?,
        wakeEnabled: Bool,
        partialsEnabled: Bool
    ) {
        self.enabled = enabled
        self.transport = transport
        self.webSocketURL = webSocketURL
        self.healthcheckURL = healthcheckURL
        self.wakeEnabled = wakeEnabled
        self.partialsEnabled = partialsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? false
        transport = (try? container.decode(VoiceSidecarTransport.self, forKey: .transport)) ?? .websocket
        webSocketURL = (try? container.decode(String.self, forKey: .webSocketURL)) ?? "ws://127.0.0.1:10096"
        healthcheckURL = try? container.decodeIfPresent(String.self, forKey: .healthcheckURL)
        wakeEnabled = (try? container.decode(Bool.self, forKey: .wakeEnabled)) ?? true
        partialsEnabled = (try? container.decode(Bool.self, forKey: .partialsEnabled)) ?? true
    }
}

struct VoiceSidecarHealthSnapshot: Codable, Equatable {
    var engine: String
    var transport: VoiceSidecarTransport
    var endpoint: String
    var status: VoiceSidecarStatus
    var vadReady: Bool
    var wakeReady: Bool
    var partialReady: Bool
    var lastError: String?

    static func disabled(engine: String = "funasr", config: FunASRSidecarConfig) -> VoiceSidecarHealthSnapshot {
        VoiceSidecarHealthSnapshot(
            engine: engine,
            transport: config.transport,
            endpoint: config.webSocketURL,
            status: .disabled,
            vadReady: false,
            wakeReady: false,
            partialReady: false,
            lastError: nil
        )
    }
}

enum VoiceEngineHealth: String, Codable, Equatable {
    case ready
    case loading
    case degraded
    case unauthorized
    case unavailable
    case disabled
}

struct VoiceRouteAvailability: Equatable {
    var funasr: VoiceEngineHealth
    var whisperKit: VoiceEngineHealth
    var systemSpeech: VoiceEngineHealth
}

struct VoiceRouteDecision: Codable, Equatable {
    var route: VoiceRouteMode
    var reasonCode: String
    var funasrHealth: VoiceEngineHealth
    var whisperKitHealth: VoiceEngineHealth
    var systemSpeechHealth: VoiceEngineHealth
    var wakeCapability: String

    static let unavailable = VoiceRouteDecision(
        route: .manualText,
        reasonCode: "voice_runtime_not_initialized",
        funasrHealth: .disabled,
        whisperKitHealth: .disabled,
        systemSpeechHealth: .loading,
        wakeCapability: "push_to_talk_only"
    )
}

enum VoiceTranscriptKind: String, Codable, Equatable {
    case partial
    case final
    case revisedFinal = "revised_final"
}

enum VoiceCaptureSource: String, Codable, Equatable {
    case manualComposer = "manual_composer"
    case wakeArmed = "wake_armed"
    case wakeFollowup = "wake_followup"
    case continuousConversation = "continuous_conversation"
    case talkLoop = "talk_loop"

    var autoCommitsOnFinalTranscript: Bool {
        switch self {
        case .manualComposer, .wakeArmed:
            return false
        case .wakeFollowup, .continuousConversation, .talkLoop:
            return true
        }
    }
}

enum VoiceCommitTrigger: String, Codable, Equatable {
    case manualStop = "manual_stop"
    case finalTranscript = "final_transcript"
}

struct VoiceTranscriptChunk: Codable, Equatable {
    var kind: VoiceTranscriptKind
    var text: String
    var confidence: Double?
    var language: String?
    var isWakeMatch: Bool

    init(
        kind: VoiceTranscriptKind,
        text: String,
        confidence: Double? = nil,
        language: String? = nil,
        isWakeMatch: Bool = false
    ) {
        self.kind = kind
        self.text = text
        self.confidence = confidence
        self.language = language
        self.isWakeMatch = isWakeMatch
    }
}

struct VoiceWakeEvent: Identifiable, Codable, Equatable {
    var id: String
    var phrase: String
    var route: VoiceRouteMode
    var timestamp: Double

    init(
        id: String = UUID().uuidString.lowercased(),
        phrase: String,
        route: VoiceRouteMode,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.phrase = phrase
        self.route = route
        self.timestamp = timestamp
    }
}

struct VoiceCommittedUtterance: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var route: VoiceRouteMode
    var captureSource: VoiceCaptureSource
    var trigger: VoiceCommitTrigger
    var wakePhrase: String?
    var timestamp: Double

    init(
        id: String = UUID().uuidString.lowercased(),
        text: String,
        route: VoiceRouteMode,
        captureSource: VoiceCaptureSource,
        trigger: VoiceCommitTrigger,
        wakePhrase: String? = nil,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.text = text
        self.route = route
        self.captureSource = captureSource
        self.trigger = trigger
        self.wakePhrase = wakePhrase
        self.timestamp = timestamp
    }
}

enum VoiceTranscriberAuthorizationStatus: String, Codable, Equatable, Sendable {
    case undetermined
    case authorized
    case denied
    case restricted
    case unavailable

    var isAuthorized: Bool {
        self == .authorized
    }
}

struct VoicePermissionSnapshot: Codable, Equatable, Sendable {
    var microphone: VoiceTranscriberAuthorizationStatus
    var speechRecognition: VoiceTranscriberAuthorizationStatus

    static let unknown = VoicePermissionSnapshot(
        microphone: .undetermined,
        speechRecognition: .undetermined
    )
}

enum VoiceSessionPhase: String, Codable, Equatable {
    case idle
    case listening
    case transcribing
    case completed
    case failClosed = "fail_closed"
}

struct SupervisorVoiceRuntimeState: Codable, Equatable {
    var state: VoiceSessionPhase
    var route: VoiceRouteMode
    var recognizedText: String
    var reasonCode: String?

    static let idle = SupervisorVoiceRuntimeState(
        state: .idle,
        route: .manualText,
        recognizedText: "",
        reasonCode: nil
    )
}

enum VoiceTranscriberError: LocalizedError {
    case alreadyRunning
    case notAuthorized
    case engineUnavailable(String)
    case runtimeFailure(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "voice_transcriber_already_running"
        case .notAuthorized:
            return "voice_transcriber_not_authorized"
        case .engineUnavailable(let reason):
            return reason
        case .runtimeFailure(let reason):
            return reason
        }
    }
}

@MainActor
protocol VoiceStreamingTranscriber: AnyObject {
    var routeMode: VoiceRouteMode { get }
    var authorizationStatus: VoiceTranscriberAuthorizationStatus { get }
    var engineHealth: VoiceEngineHealth { get }
    var healthReasonCode: String? { get }
    var isRunning: Bool { get }

    func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus
    func refreshEngineHealth() async -> VoiceEngineHealth
    func startTranscribing(
        onChunk: @escaping (VoiceTranscriptChunk) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws
    func stopTranscribing()
}
