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
            return "FunASR Streaming"
        case .whisperKitLocal:
            return "WhisperKit Local"
        case .systemSpeechCompatibility:
            return "System Speech"
        case .manualText:
            return "Manual Text"
        case .failClosed:
            return "Fail Closed"
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
}

enum VoiceWakeMode: String, Codable, CaseIterable, Identifiable {
    case pushToTalk = "push_to_talk"
    case wakePhrase = "wake_phrase"
    case promptPhraseOnly = "prompt_phrase_only"

    var id: String { rawValue }
}

enum VoiceAutoReportMode: String, Codable, CaseIterable, Identifiable {
    case silent = "silent"
    case blockersOnly = "blockers_only"
    case summary = "summary"
    case full = "full"

    var id: String { rawValue }
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
    var wakeMode: VoiceWakeMode
    var autoReportMode: VoiceAutoReportMode
    var quietHours: VoiceQuietHours
    var localeIdentifier: String
    var funASR: FunASRSidecarConfig

    enum CodingKeys: String, CodingKey {
        case preferredRoute
        case wakeMode
        case autoReportMode
        case quietHours
        case localeIdentifier
        case funASR
    }

    static func `default`() -> VoiceRuntimePreferences {
        VoiceRuntimePreferences(
            preferredRoute: .automatic,
            wakeMode: .pushToTalk,
            autoReportMode: .summary,
            quietHours: .default(),
            localeIdentifier: "zh-CN",
            funASR: .default()
        )
    }

    init(
        preferredRoute: VoicePreferredRoute,
        wakeMode: VoiceWakeMode,
        autoReportMode: VoiceAutoReportMode,
        quietHours: VoiceQuietHours,
        localeIdentifier: String,
        funASR: FunASRSidecarConfig
    ) {
        self.preferredRoute = preferredRoute
        self.wakeMode = wakeMode
        self.autoReportMode = autoReportMode
        self.quietHours = quietHours
        self.localeIdentifier = localeIdentifier
        self.funASR = funASR
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredRoute = (try? container.decode(VoicePreferredRoute.self, forKey: .preferredRoute)) ?? .automatic
        wakeMode = (try? container.decode(VoiceWakeMode.self, forKey: .wakeMode)) ?? .pushToTalk
        autoReportMode = (try? container.decode(VoiceAutoReportMode.self, forKey: .autoReportMode)) ?? .summary
        quietHours = (try? container.decode(VoiceQuietHours.self, forKey: .quietHours)) ?? .default()
        localeIdentifier = (try? container.decode(String.self, forKey: .localeIdentifier)) ?? "zh-CN"
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

enum VoiceTranscriberAuthorizationStatus: String, Codable, Equatable {
    case undetermined
    case authorized
    case denied
    case restricted
    case unavailable

    var isAuthorized: Bool {
        self == .authorized
    }
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
