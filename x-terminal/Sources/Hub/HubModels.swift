import Foundation

struct AIRuntimeStatus: Codable, Equatable {
    var pid: Int
    var updatedAt: Double
    var mlxOk: Bool
    var runtimeVersion: String?
    var importError: String?
    var activeMemoryBytes: Int64?
    var peakMemoryBytes: Int64?
    var loadedModelCount: Int?

    func isAlive(ttl: Double = 3.0) -> Bool {
        (Date().timeIntervalSince1970 - updatedAt) < ttl
    }
}

enum HubModelState: String, Codable {
    case loaded
    case available
    case sleeping
}

struct HubLocalModelVisionLoadProfile: Codable, Equatable {
    var imageMaxDimension: Int?

    enum CodingKeys: String, CodingKey {
        case imageMaxDimension
    }

    enum SnakeCodingKeys: String, CodingKey {
        case imageMaxDimension = "image_max_dimension"
    }

    init(imageMaxDimension: Int? = nil) {
        guard let imageMaxDimension, imageMaxDimension > 0 else {
            self.imageMaxDimension = nil
            return
        }
        self.imageMaxDimension = min(16_384, max(32, imageMaxDimension))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            imageMaxDimension: (try? c.decodeIfPresent(Int.self, forKey: .imageMaxDimension))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .imageMaxDimension))
        )
    }
}

struct HubLocalModelLoadProfile: Codable, Equatable {
    var contextLength: Int
    var gpuOffloadRatio: Double?
    var ropeFrequencyBase: Double?
    var ropeFrequencyScale: Double?
    var evalBatchSize: Int?
    var ttl: Int?
    var parallel: Int?
    var identifier: String?
    var vision: HubLocalModelVisionLoadProfile?

    enum CodingKeys: String, CodingKey {
        case contextLength
        case gpuOffloadRatio
        case ropeFrequencyBase
        case ropeFrequencyScale
        case evalBatchSize
        case ttl
        case parallel
        case identifier
        case vision
    }

    enum SnakeCodingKeys: String, CodingKey {
        case contextLength = "context_length"
        case gpuOffloadRatio = "gpu_offload_ratio"
        case ropeFrequencyBase = "rope_frequency_base"
        case ropeFrequencyScale = "rope_frequency_scale"
        case evalBatchSize = "eval_batch_size"
        case ttl
        case parallel
        case identifier
        case vision
    }

    enum FlatVisionCodingKeys: String, CodingKey {
        case visionImageMaxDimension = "vision_image_max_dimension"
        case visionImageMaxDimensionCamel = "visionImageMaxDimension"
    }

    init(
        contextLength: Int,
        gpuOffloadRatio: Double? = nil,
        ropeFrequencyBase: Double? = nil,
        ropeFrequencyScale: Double? = nil,
        evalBatchSize: Int? = nil,
        ttl: Int? = nil,
        parallel: Int? = nil,
        identifier: String? = nil,
        vision: HubLocalModelVisionLoadProfile? = nil
    ) {
        self.contextLength = max(512, contextLength)
        self.gpuOffloadRatio = HubLocalModelLoadProfile.normalizedRatio(gpuOffloadRatio)
        self.ropeFrequencyBase = HubLocalModelLoadProfile.normalizedPositive(ropeFrequencyBase)
        self.ropeFrequencyScale = HubLocalModelLoadProfile.normalizedPositive(ropeFrequencyScale)
        self.evalBatchSize = HubLocalModelLoadProfile.normalizedPositiveInt(evalBatchSize)
        self.ttl = HubLocalModelLoadProfile.normalizedPositiveInt(ttl)
        self.parallel = HubLocalModelLoadProfile.normalizedPositiveInt(parallel)
        self.identifier = HubLocalModelLoadProfile.normalizedIdentifier(identifier)
        self.vision = vision?.imageMaxDimension == nil ? nil : vision
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        let v = try decoder.container(keyedBy: FlatVisionCodingKeys.self)
        contextLength = max(
            512,
            (try? c.decode(Int.self, forKey: .contextLength))
                ?? (try? s.decode(Int.self, forKey: .contextLength))
                ?? 8192
        )
        gpuOffloadRatio = HubLocalModelLoadProfile.normalizedRatio(
            (try? c.decodeIfPresent(Double.self, forKey: .gpuOffloadRatio))
                ?? (try? s.decodeIfPresent(Double.self, forKey: .gpuOffloadRatio))
        )
        ropeFrequencyBase = HubLocalModelLoadProfile.normalizedPositive(
            (try? c.decodeIfPresent(Double.self, forKey: .ropeFrequencyBase))
                ?? (try? s.decodeIfPresent(Double.self, forKey: .ropeFrequencyBase))
        )
        ropeFrequencyScale = HubLocalModelLoadProfile.normalizedPositive(
            (try? c.decodeIfPresent(Double.self, forKey: .ropeFrequencyScale))
                ?? (try? s.decodeIfPresent(Double.self, forKey: .ropeFrequencyScale))
        )
        evalBatchSize = HubLocalModelLoadProfile.normalizedPositiveInt(
            (try? c.decodeIfPresent(Int.self, forKey: .evalBatchSize))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .evalBatchSize))
        )
        ttl = HubLocalModelLoadProfile.normalizedPositiveInt(
            (try? c.decodeIfPresent(Int.self, forKey: .ttl))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .ttl))
        )
        parallel = HubLocalModelLoadProfile.normalizedPositiveInt(
            (try? c.decodeIfPresent(Int.self, forKey: .parallel))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .parallel))
        )
        identifier = HubLocalModelLoadProfile.normalizedIdentifier(
            (try? c.decodeIfPresent(String.self, forKey: .identifier))
                ?? (try? s.decodeIfPresent(String.self, forKey: .identifier))
        )
        vision = (try? c.decodeIfPresent(HubLocalModelVisionLoadProfile.self, forKey: .vision))
            ?? (try? s.decodeIfPresent(HubLocalModelVisionLoadProfile.self, forKey: .vision))
            ?? {
                let imageMaxDimension = (try? v.decodeIfPresent(Int.self, forKey: .visionImageMaxDimension))
                    ?? (try? v.decodeIfPresent(Int.self, forKey: .visionImageMaxDimensionCamel))
                guard imageMaxDimension != nil else { return nil }
                return HubLocalModelVisionLoadProfile(imageMaxDimension: imageMaxDimension)
            }()
    }

    func normalized(maxContextLength: Int?) -> HubLocalModelLoadProfile {
        let upperBound = max(512, maxContextLength ?? contextLength)
        return HubLocalModelLoadProfile(
            contextLength: min(max(512, contextLength), upperBound),
            gpuOffloadRatio: gpuOffloadRatio,
            ropeFrequencyBase: ropeFrequencyBase,
            ropeFrequencyScale: ropeFrequencyScale,
            evalBatchSize: evalBatchSize,
            ttl: ttl,
            parallel: parallel,
            identifier: identifier,
            vision: vision
        )
    }

    private static func normalizedRatio(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(1.0, max(0.0, value))
    }

    private static func normalizedPositive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func normalizedPositiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        let token = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }
}

extension HubLocalModelLoadProfile {
    var xtSummaryLine: String {
        var parts = ["ctx \(contextLength)"]
        if let ttl {
            parts.append("ttl \(ttl)s")
        }
        if let parallel {
            parts.append("par \(parallel)")
        }
        if let identifier {
            let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedIdentifier.isEmpty {
                parts.append("id \(trimmedIdentifier)")
            }
        }
        if let imageMaxDimension = vision?.imageMaxDimension {
            parts.append("vision \(imageMaxDimension)px")
        }
        return parts.joined(separator: " · ")
    }
}

struct HubModelResourceProfile: Codable, Equatable {
    var preferredDevice: String
    var memoryFloorMB: Int
    var dtype: String

    enum CodingKeys: String, CodingKey {
        case preferredDevice
        case memoryFloorMB
        case dtype
    }

    enum SnakeCodingKeys: String, CodingKey {
        case preferredDevice = "preferred_device"
        case memoryFloorMB = "memory_floor_mb"
        case dtype
    }

    init(
        preferredDevice: String = "unknown",
        memoryFloorMB: Int = 0,
        dtype: String = "unknown"
    ) {
        self.preferredDevice = preferredDevice
        self.memoryFloorMB = memoryFloorMB
        self.dtype = dtype
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        preferredDevice = (try? c.decode(String.self, forKey: .preferredDevice))
            ?? (try? s.decode(String.self, forKey: .preferredDevice))
            ?? "unknown"
        memoryFloorMB = (try? c.decode(Int.self, forKey: .memoryFloorMB))
            ?? (try? s.decode(Int.self, forKey: .memoryFloorMB))
            ?? 0
        dtype = (try? c.decode(String.self, forKey: .dtype))
            ?? (try? s.decode(String.self, forKey: .dtype))
            ?? "unknown"
    }
}

struct HubModelTrustProfile: Codable, Equatable {
    var allowSecretInput: Bool
    var allowRemoteExport: Bool

    enum CodingKeys: String, CodingKey {
        case allowSecretInput
        case allowRemoteExport
    }

    enum SnakeCodingKeys: String, CodingKey {
        case allowSecretInput = "allow_secret_input"
        case allowRemoteExport = "allow_remote_export"
    }

    init(
        allowSecretInput: Bool = false,
        allowRemoteExport: Bool = false
    ) {
        self.allowSecretInput = allowSecretInput
        self.allowRemoteExport = allowRemoteExport
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        allowSecretInput = (try? c.decode(Bool.self, forKey: .allowSecretInput))
            ?? (try? s.decode(Bool.self, forKey: .allowSecretInput))
            ?? false
        allowRemoteExport = (try? c.decode(Bool.self, forKey: .allowRemoteExport))
            ?? (try? s.decode(Bool.self, forKey: .allowRemoteExport))
            ?? false
    }
}

struct HubModelProcessorRequirements: Codable, Equatable {
    var tokenizerRequired: Bool
    var processorRequired: Bool
    var featureExtractorRequired: Bool

    enum CodingKeys: String, CodingKey {
        case tokenizerRequired
        case processorRequired
        case featureExtractorRequired
    }

    enum SnakeCodingKeys: String, CodingKey {
        case tokenizerRequired = "tokenizer_required"
        case processorRequired = "processor_required"
        case featureExtractorRequired = "feature_extractor_required"
    }

    init(
        tokenizerRequired: Bool = true,
        processorRequired: Bool = false,
        featureExtractorRequired: Bool = false
    ) {
        self.tokenizerRequired = tokenizerRequired
        self.processorRequired = processorRequired
        self.featureExtractorRequired = featureExtractorRequired
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        tokenizerRequired = (try? c.decode(Bool.self, forKey: .tokenizerRequired))
            ?? (try? s.decode(Bool.self, forKey: .tokenizerRequired))
            ?? true
        processorRequired = (try? c.decode(Bool.self, forKey: .processorRequired))
            ?? (try? s.decode(Bool.self, forKey: .processorRequired))
            ?? false
        featureExtractorRequired = (try? c.decode(Bool.self, forKey: .featureExtractorRequired))
            ?? (try? s.decode(Bool.self, forKey: .featureExtractorRequired))
            ?? false
    }
}

struct HubModelVoiceProfile: Codable, Equatable {
    var languageHints: [String]
    var styleHints: [String]
    var engineHints: [String]

    enum CodingKeys: String, CodingKey {
        case languageHints
        case styleHints
        case engineHints
    }

    enum SnakeCodingKeys: String, CodingKey {
        case languageHints = "language_hints"
        case styleHints = "style_hints"
        case engineHints = "engine_hints"
    }

    init(
        languageHints: [String] = [],
        styleHints: [String] = [],
        engineHints: [String] = []
    ) {
        self.languageHints = HubLocalModelCapabilityDefaults.normalizedStringList(languageHints, fallback: [])
        self.styleHints = HubLocalModelCapabilityDefaults.normalizedStringList(styleHints, fallback: [])
        self.engineHints = HubLocalModelCapabilityDefaults.normalizedStringList(engineHints, fallback: [])
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            languageHints: (try? c.decode([String].self, forKey: .languageHints))
                ?? (try? s.decode([String].self, forKey: .languageHints))
                ?? [],
            styleHints: (try? c.decode([String].self, forKey: .styleHints))
                ?? (try? s.decode([String].self, forKey: .styleHints))
                ?? [],
            engineHints: (try? c.decode([String].self, forKey: .engineHints))
                ?? (try? s.decode([String].self, forKey: .engineHints))
                ?? []
        )
    }

    var isEmpty: Bool {
        languageHints.isEmpty && styleHints.isEmpty && engineHints.isEmpty
    }
}

enum HubLocalModelCapabilityDefaults {
    static func defaultLoadProfile(contextLength: Int) -> HubLocalModelLoadProfile {
        HubLocalModelLoadProfile(contextLength: max(512, contextLength))
    }

    static func defaultMaxContextLength(
        contextLength: Int,
        defaultLoadProfile: HubLocalModelLoadProfile? = nil
    ) -> Int {
        let defaultContextLength = defaultLoadProfile?.contextLength ?? contextLength
        return max(512, max(contextLength, defaultContextLength))
    }

    static func defaultModelFormat(forBackend backend: String) -> String {
        switch normalizedToken(backend) {
        case "mlx":
            return "mlx"
        case "transformers":
            return "hf_transformers"
        case "onnx":
            return "onnx"
        default:
            return "other"
        }
    }

    static func defaultTaskKinds(forBackend backend: String, roles: [String]? = nil) -> [String] {
        let normalizedRoles = Set((roles ?? []).map(normalizedToken(_:)))
        if normalizedRoles.contains("embed") || normalizedRoles.contains("embedding") {
            return ["embedding"]
        }
        if normalizedRoles.contains("tts") || normalizedRoles.contains("voice") {
            return ["text_to_speech"]
        }
        switch normalizedToken(backend) {
        case "mlx":
            return ["text_generate"]
        default:
            return ["text_generate"]
        }
    }

    static func defaultInputModalities(forTaskKinds taskKinds: [String]) -> [String] {
        let normalized = normalizedStringList(taskKinds, fallback: ["text"])
        var values: [String] = []
        for kind in normalized {
            switch kind {
            case "speech_to_text":
                appendUnique("audio", into: &values)
            case "text_to_speech":
                appendUnique("text", into: &values)
            case "vision_understand", "ocr":
                appendUnique("image", into: &values)
            default:
                appendUnique("text", into: &values)
            }
        }
        return values.isEmpty ? ["text"] : values
    }

    static func defaultOutputModalities(forTaskKinds taskKinds: [String]) -> [String] {
        let normalized = normalizedStringList(taskKinds, fallback: ["text_generate"])
        var values: [String] = []
        for kind in normalized {
            switch kind {
            case "embedding":
                appendUnique("embedding", into: &values)
            case "rerank":
                appendUnique("scores", into: &values)
            case "classify":
                appendUnique("labels", into: &values)
            case "speech_to_text":
                appendUnique("text", into: &values)
                appendUnique("segments", into: &values)
            case "text_to_speech":
                appendUnique("audio", into: &values)
            case "ocr":
                appendUnique("text", into: &values)
                appendUnique("spans", into: &values)
            default:
                appendUnique("text", into: &values)
            }
        }
        return values.isEmpty ? ["text"] : values
    }

    static func defaultOfflineReady(backend: String, modelPath: String?) -> Bool {
        let path = normalizedToken(modelPath ?? "")
        if !path.isEmpty {
            return true
        }
        return normalizedToken(backend) == "mlx"
    }

    static func defaultVoiceProfile(
        modelID: String,
        name: String,
        note: String? = nil,
        taskKinds: [String],
        outputModalities: [String] = []
    ) -> HubModelVoiceProfile? {
        let normalizedTaskKinds = normalizedStringList(taskKinds, fallback: [])
        let normalizedOutputs = normalizedStringList(outputModalities, fallback: [])
        guard normalizedTaskKinds.contains("text_to_speech") || normalizedOutputs.contains("audio") else {
            return nil
        }

        let haystack = [modelID, name, note ?? ""]
            .joined(separator: " ")
            .lowercased()
        let tokens = tokenSet(from: haystack)

        var languageHints: [String] = []
        if containsAny(haystack, values: ["multilingual", "bilingual", "zh-en", "en-zh", "zh_en", "en_zh", "multi-language"]) {
            appendUnique("multi", into: &languageHints)
        } else {
            if tokens.contains("zh")
                || containsAny(haystack, values: ["zh-cn", "zh_cn", "chinese", "mandarin", "中文"]) {
                appendUnique("zh", into: &languageHints)
            }
            if tokens.contains("en")
                || containsAny(haystack, values: ["en-us", "en_us", "english", "英文"]) {
                appendUnique("en", into: &languageHints)
            }
        }

        var styleHints: [String] = []
        for (needle, token) in [
            ("warm", "warm"),
            ("clear", "clear"),
            ("bright", "bright"),
            ("calm", "calm"),
            ("neutral", "neutral"),
            ("soft", "calm"),
            ("gentle", "calm"),
            ("soothing", "calm"),
            ("studio", "clear"),
            ("crisp", "clear"),
            ("温暖", "warm"),
            ("清晰", "clear"),
            ("明亮", "bright"),
            ("沉稳", "calm"),
            ("中性", "neutral"),
        ] {
            if haystack.contains(needle) {
                appendUnique(token, into: &styleHints)
            }
        }

        var engineHints: [String] = []
        for (needle, token) in [
            ("kokoro", "kokoro"),
            ("cosyvoice", "cosyvoice"),
            ("cosy voice", "cosyvoice"),
            ("melo", "melotts"),
            ("melotts", "melotts"),
            ("melo-tts", "melotts"),
            ("chattts", "chattts"),
            ("chat-tts", "chattts"),
            ("f5-tts", "f5-tts"),
            ("f5_tts", "f5-tts"),
            ("f5tts", "f5-tts"),
            ("bark", "bark"),
            ("parler", "parler"),
            ("vits", "vits"),
        ] {
            if haystack.contains(needle) {
                appendUnique(token, into: &engineHints)
            }
        }

        let profile = HubModelVoiceProfile(
            languageHints: languageHints,
            styleHints: styleHints,
            engineHints: engineHints
        )
        return profile.isEmpty ? nil : profile
    }

    static func defaultResourceProfile(
        backend: String,
        quant: String,
        paramsB: Double
    ) -> HubModelResourceProfile {
        let normalizedBackend = normalizedToken(backend)
        let normalizedQuant = normalizedToken(quant)
        let preferredDevice: String = {
            switch normalizedBackend {
            case "mlx", "transformers":
                return "mps"
            default:
                return "unknown"
            }
        }()
        let bytesPerParam: Double = {
            if normalizedQuant.contains("int4") || normalizedQuant == "4" {
                return 0.5
            }
            if normalizedQuant.contains("int8") || normalizedQuant == "8" {
                return 1.0
            }
            return 2.0
        }()
        let memoryFloorMB = max(0, Int((paramsB * 1000.0 * bytesPerParam).rounded(.up)))
        let dtype: String = {
            if normalizedQuant.contains("bf16") {
                return "bfloat16"
            }
            if normalizedQuant.contains("fp16") || normalizedQuant.contains("float16") {
                return "float16"
            }
            if normalizedQuant.contains("fp32") || normalizedQuant.contains("float32") {
                return "float32"
            }
            return normalizedQuant.isEmpty ? "unknown" : normalizedQuant
        }()
        return HubModelResourceProfile(
            preferredDevice: preferredDevice,
            memoryFloorMB: memoryFloorMB,
            dtype: dtype
        )
    }

    static func defaultTrustProfile() -> HubModelTrustProfile {
        HubModelTrustProfile(
            allowSecretInput: false,
            allowRemoteExport: false
        )
    }

    static func defaultProcessorRequirements(
        backend: String,
        modelFormat: String,
        taskKinds: [String]
    ) -> HubModelProcessorRequirements {
        let normalizedTaskKinds = normalizedStringList(
            taskKinds,
            fallback: defaultTaskKinds(forBackend: backend)
        )
        let requiresTextTokenizer = normalizedTaskKinds.contains { kind in
            kind == "text_generate" || kind == "embedding" || kind == "rerank" || kind == "classify" || kind == "text_to_speech"
        }
        let requiresProcessor = normalizedTaskKinds.contains { kind in
            kind == "speech_to_text" || kind == "vision_understand" || kind == "ocr"
        }
        let requiresFeatureExtractor = normalizedTaskKinds.contains { kind in
            kind == "speech_to_text" || kind == "vision_understand" || kind == "ocr"
        }
        if normalizedToken(modelFormat) == "mlx" {
            return HubModelProcessorRequirements(
                tokenizerRequired: true,
                processorRequired: false,
                featureExtractorRequired: false
            )
        }
        return HubModelProcessorRequirements(
            tokenizerRequired: requiresTextTokenizer,
            processorRequired: requiresProcessor,
            featureExtractorRequired: requiresFeatureExtractor
        )
    }

    static func normalizedStringList(_ values: [String], fallback: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for raw in values {
            let token = normalizedToken(raw)
            if token.isEmpty || seen.contains(token) {
                continue
            }
            seen.insert(token)
            out.append(token)
        }
        return out.isEmpty ? fallback : out
    }

    private static func appendUnique(_ value: String, into array: inout [String]) {
        if !array.contains(value) {
            array.append(value)
        }
    }

    private static func normalizedToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func containsAny(_ haystack: String, values: [String]) -> Bool {
        values.contains { haystack.contains($0) }
    }

    private static func tokenSet(from text: String) -> Set<String> {
        let normalized = String(
            text.unicodeScalars.map { scalar in
                CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
            }
        )
        return Set(normalized.split(separator: " ").map { String($0) })
    }
}

struct HubModel: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var backend: String
    var quant: String
    var contextLength: Int
    var maxContextLength: Int?
    var paramsB: Double
    var roles: [String]?
    var state: HubModelState
    var memoryBytes: Int64?
    var tokensPerSec: Double?
    var modelPath: String?
    var note: String?
    var modelFormat: String = "other"
    var defaultLoadProfile: HubLocalModelLoadProfile?
    var taskKinds: [String] = ["text_generate"]
    var inputModalities: [String] = ["text"]
    var outputModalities: [String] = ["text"]
    var offlineReady: Bool = false
    var voiceProfile: HubModelVoiceProfile?
    var resourceProfile: HubModelResourceProfile = HubModelResourceProfile()
    var trustProfile: HubModelTrustProfile = HubModelTrustProfile()
    var processorRequirements: HubModelProcessorRequirements = HubModelProcessorRequirements()

    init(
        id: String,
        name: String,
        backend: String,
        quant: String,
        contextLength: Int,
        maxContextLength: Int? = nil,
        paramsB: Double,
        roles: [String]? = nil,
        state: HubModelState,
        memoryBytes: Int64? = nil,
        tokensPerSec: Double? = nil,
        modelPath: String? = nil,
        note: String? = nil,
        modelFormat: String? = nil,
        defaultLoadProfile: HubLocalModelLoadProfile? = nil,
        taskKinds: [String]? = nil,
        inputModalities: [String]? = nil,
        outputModalities: [String]? = nil,
        offlineReady: Bool? = nil,
        voiceProfile: HubModelVoiceProfile? = nil,
        resourceProfile: HubModelResourceProfile? = nil,
        trustProfile: HubModelTrustProfile? = nil,
        processorRequirements: HubModelProcessorRequirements? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.quant = quant
        let resolvedModelFormat = modelFormat ?? HubLocalModelCapabilityDefaults.defaultModelFormat(forBackend: backend)
        let resolvedDefaultLoadProfile = (defaultLoadProfile ?? HubLocalModelCapabilityDefaults.defaultLoadProfile(contextLength: contextLength))
        let resolvedMaxContextLength = HubLocalModelCapabilityDefaults.defaultMaxContextLength(
            contextLength: maxContextLength ?? contextLength,
            defaultLoadProfile: resolvedDefaultLoadProfile
        )
        self.defaultLoadProfile = resolvedDefaultLoadProfile.normalized(maxContextLength: resolvedMaxContextLength)
        self.contextLength = self.defaultLoadProfile?.contextLength ?? max(512, contextLength)
        self.maxContextLength = max(self.contextLength, resolvedMaxContextLength)
        self.paramsB = paramsB
        self.roles = roles
        self.state = state
        self.memoryBytes = memoryBytes
        self.tokensPerSec = tokensPerSec
        self.modelPath = modelPath
        self.note = note
        self.modelFormat = resolvedModelFormat
        let resolvedTaskKinds = HubLocalModelCapabilityDefaults.normalizedStringList(
            taskKinds ?? HubLocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend, roles: roles),
            fallback: HubLocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend, roles: roles)
        )
        self.taskKinds = resolvedTaskKinds
        self.inputModalities = HubLocalModelCapabilityDefaults.normalizedStringList(
            inputModalities ?? HubLocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: resolvedTaskKinds),
            fallback: HubLocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: resolvedTaskKinds)
        )
        self.outputModalities = HubLocalModelCapabilityDefaults.normalizedStringList(
            outputModalities ?? HubLocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: resolvedTaskKinds),
            fallback: HubLocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: resolvedTaskKinds)
        )
        self.offlineReady = offlineReady ?? HubLocalModelCapabilityDefaults.defaultOfflineReady(backend: backend, modelPath: modelPath)
        self.voiceProfile = voiceProfile ?? HubLocalModelCapabilityDefaults.defaultVoiceProfile(
            modelID: id,
            name: name,
            note: note,
            taskKinds: resolvedTaskKinds,
            outputModalities: self.outputModalities
        )
        self.resourceProfile = resourceProfile ?? HubLocalModelCapabilityDefaults.defaultResourceProfile(
            backend: backend,
            quant: quant,
            paramsB: paramsB
        )
        self.trustProfile = trustProfile ?? HubLocalModelCapabilityDefaults.defaultTrustProfile()
        self.processorRequirements = processorRequirements ?? HubLocalModelCapabilityDefaults.defaultProcessorRequirements(
            backend: backend,
            modelFormat: resolvedModelFormat,
            taskKinds: resolvedTaskKinds
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case backend
        case quant
        case contextLength
        case maxContextLength
        case paramsB
        case roles
        case state
        case memoryBytes
        case tokensPerSec
        case modelPath
        case note
        case modelFormat
        case defaultLoadProfile
        case taskKinds
        case inputModalities
        case outputModalities
        case offlineReady
        case voiceProfile
        case resourceProfile
        case trustProfile
        case processorRequirements
    }

    enum SnakeCodingKeys: String, CodingKey {
        case contextLength = "context_length"
        case maxContextLength = "max_context_length"
        case paramsB = "params_b"
        case memoryBytes = "memory_bytes"
        case tokensPerSec = "tokens_per_sec"
        case modelPath = "model_path"
        case modelFormat = "model_format"
        case defaultLoadProfile = "default_load_profile"
        case taskKinds = "task_kinds"
        case inputModalities = "input_modalities"
        case outputModalities = "output_modalities"
        case offlineReady = "offline_ready"
        case voiceProfile = "voice_profile"
        case resourceProfile = "resource_profile"
        case trustProfile = "trust_profile"
        case processorRequirements = "processor_requirements"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)

        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        backend = (try? c.decode(String.self, forKey: .backend)) ?? "mlx"
        quant = (try? c.decode(String.self, forKey: .quant)) ?? "bf16"
        let legacyContextLength = (try? c.decode(Int.self, forKey: .contextLength))
            ?? (try? s.decode(Int.self, forKey: .contextLength))
            ?? 8192
        let decodedDefaultLoadProfile = (try? c.decodeIfPresent(HubLocalModelLoadProfile.self, forKey: .defaultLoadProfile))
            ?? (try? s.decodeIfPresent(HubLocalModelLoadProfile.self, forKey: .defaultLoadProfile))
        let decodedMaxContextLength = (try? c.decodeIfPresent(Int.self, forKey: .maxContextLength))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .maxContextLength))
            ?? HubLocalModelCapabilityDefaults.defaultMaxContextLength(
                contextLength: legacyContextLength,
                defaultLoadProfile: decodedDefaultLoadProfile
            )
        defaultLoadProfile = (decodedDefaultLoadProfile ?? HubLocalModelCapabilityDefaults.defaultLoadProfile(contextLength: legacyContextLength))
            .normalized(maxContextLength: decodedMaxContextLength)
        contextLength = defaultLoadProfile?.contextLength ?? legacyContextLength
        maxContextLength = max(contextLength, decodedMaxContextLength)
        paramsB = (try? c.decode(Double.self, forKey: .paramsB))
            ?? (try? s.decode(Double.self, forKey: .paramsB))
            ?? 0.0
        roles = try? c.decodeIfPresent([String].self, forKey: .roles)
        state = (try? c.decode(HubModelState.self, forKey: .state)) ?? .available
        memoryBytes = (try? c.decodeIfPresent(Int64.self, forKey: .memoryBytes))
            ?? (try? s.decodeIfPresent(Int64.self, forKey: .memoryBytes))
        tokensPerSec = (try? c.decodeIfPresent(Double.self, forKey: .tokensPerSec))
            ?? (try? s.decodeIfPresent(Double.self, forKey: .tokensPerSec))
        modelPath = (try? c.decodeIfPresent(String.self, forKey: .modelPath))
            ?? (try? s.decodeIfPresent(String.self, forKey: .modelPath))
        note = try? c.decodeIfPresent(String.self, forKey: .note)

        let taskFallback = HubLocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend, roles: roles)
        modelFormat = (try? c.decode(String.self, forKey: .modelFormat))
            ?? (try? s.decode(String.self, forKey: .modelFormat))
            ?? HubLocalModelCapabilityDefaults.defaultModelFormat(forBackend: backend)
        taskKinds = HubLocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .taskKinds))
                ?? (try? s.decode([String].self, forKey: .taskKinds))
                ?? taskFallback,
            fallback: taskFallback
        )
        inputModalities = HubLocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .inputModalities))
                ?? (try? s.decode([String].self, forKey: .inputModalities))
                ?? HubLocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds),
            fallback: HubLocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds)
        )
        outputModalities = HubLocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .outputModalities))
                ?? (try? s.decode([String].self, forKey: .outputModalities))
                ?? HubLocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds),
            fallback: HubLocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds)
        )
        offlineReady = (try? c.decode(Bool.self, forKey: .offlineReady))
            ?? (try? s.decode(Bool.self, forKey: .offlineReady))
            ?? HubLocalModelCapabilityDefaults.defaultOfflineReady(backend: backend, modelPath: modelPath)
        voiceProfile = (try? c.decodeIfPresent(HubModelVoiceProfile.self, forKey: .voiceProfile))
            ?? (try? s.decodeIfPresent(HubModelVoiceProfile.self, forKey: .voiceProfile))
            ?? HubLocalModelCapabilityDefaults.defaultVoiceProfile(
                modelID: id,
                name: name,
                note: note,
                taskKinds: taskKinds,
                outputModalities: outputModalities
            )
        resourceProfile = (try? c.decode(HubModelResourceProfile.self, forKey: .resourceProfile))
            ?? (try? s.decode(HubModelResourceProfile.self, forKey: .resourceProfile))
            ?? HubLocalModelCapabilityDefaults.defaultResourceProfile(backend: backend, quant: quant, paramsB: paramsB)
        trustProfile = (try? c.decode(HubModelTrustProfile.self, forKey: .trustProfile))
            ?? (try? s.decode(HubModelTrustProfile.self, forKey: .trustProfile))
            ?? HubLocalModelCapabilityDefaults.defaultTrustProfile()
        processorRequirements = (try? c.decode(HubModelProcessorRequirements.self, forKey: .processorRequirements))
            ?? (try? s.decode(HubModelProcessorRequirements.self, forKey: .processorRequirements))
            ?? HubLocalModelCapabilityDefaults.defaultProcessorRequirements(
                backend: backend,
                modelFormat: modelFormat,
                taskKinds: taskKinds
            )
    }
}

extension HubModel {
    private var normalizedTaskKindSet: Set<String> {
        Set(
            taskKinds.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
    }

    var hubDefaultContextLength: Int {
        defaultLoadProfile?.contextLength ?? contextLength
    }

    var hubMaxContextLength: Int {
        max(maxContextLength ?? hubDefaultContextLength, hubDefaultContextLength)
    }

    var defaultLoadConfigSummaryLine: String? {
        defaultLoadProfile?.normalized(maxContextLength: hubMaxContextLength).xtSummaryLine
    }

    var defaultLoadConfigDisplayLine: String {
        let summary = defaultLoadConfigSummaryLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !summary.isEmpty {
            return "默认加载配置：\(summary)"
        }
        return "默认加载配置：ctx \(hubDefaultContextLength)"
    }

    var localLoadConfigLimitLine: String? {
        guard isLocalModel else { return nil }
        return "本地加载上限：ctx \(hubMaxContextLength)"
    }

    var isLocalModel: Bool {
        modelPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var isEmbeddingModel: Bool {
        normalizedTaskKindSet.contains("embedding")
    }

    var isEmbeddingOnlyModel: Bool {
        guard isEmbeddingModel else { return false }
        let interactiveTaskKinds: Set<String> = [
            "text_generate",
            "vision_understand",
            "speech_to_text",
            "ocr"
        ]
        return normalizedTaskKindSet.isDisjoint(with: interactiveTaskKinds)
    }

    var isTextToSpeechModel: Bool {
        normalizedTaskKindSet.contains("text_to_speech")
    }

    var isEligibleHubVoicePackModel: Bool {
        guard isTextToSpeechModel else { return false }
        let normalizedModelPath = (modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBackend = backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalizedModelPath.isEmpty || normalizedBackend == "mlx"
    }

    var isTextToSpeechOnlyModel: Bool {
        guard isTextToSpeechModel else { return false }
        let interactiveTaskKinds: Set<String> = [
            "text_generate",
            "vision_understand",
            "speech_to_text",
            "ocr"
        ]
        return normalizedTaskKindSet.isDisjoint(with: interactiveTaskKinds)
    }

    var isNonInteractiveOnlyModel: Bool {
        isEmbeddingOnlyModel || isTextToSpeechOnlyModel
    }

    var isSelectableForInteractiveRouting: Bool {
        !isNonInteractiveOnlyModel
    }

    var interactiveRoutingDisabledReason: String? {
        if isEmbeddingOnlyModel {
            return "向量/检索模型会由 Supervisor 和 Memory 检索链路按需调用，不作为聊天模型手动选择。"
        }
        if isTextToSpeechOnlyModel {
            return "语音合成模型会由 Supervisor Voice 播放链路按需调用，不作为聊天模型手动选择。"
        }
        return nil
    }

    var capabilitySummaryLine: String? {
        var parts: [String] = []
        let taskLabels = taskKinds.compactMap(Self.taskKindLabel(_:))
        if !taskLabels.isEmpty {
            parts.append("任务：\(taskLabels.joined(separator: " / "))")
        }
        let inputLabels = inputModalities.compactMap(Self.modalityLabel(_:))
        if !inputLabels.isEmpty {
            parts.append("输入：\(inputLabels.joined(separator: ", "))")
        }
        let outputLabels = outputModalities.compactMap(Self.modalityLabel(_:))
        if !outputLabels.isEmpty {
            parts.append("输出：\(outputLabels.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private static func taskKindLabel(_ taskKind: String) -> String? {
        switch taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "text_generate":
            return "文本生成"
        case "embedding":
            return "向量嵌入"
        case "rerank":
            return "重排"
        case "speech_to_text":
            return "语音转写"
        case "text_to_speech":
            return "文本转语音"
        case "vision_understand":
            return "图像理解"
        case "ocr":
            return "OCR"
        case "classify":
            return "分类"
        default:
            return nil
        }
    }

    private static func modalityLabel(_ modality: String) -> String? {
        switch modality.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "text":
            return "文本"
        case "audio":
            return "音频"
        case "image":
            return "图像"
        case "video":
            return "视频"
        case "pdf":
            return "PDF"
        case "embedding":
            return "向量"
        case "scores":
            return "分数"
        case "labels":
            return "标签"
        case "segments":
            return "片段"
        case "spans":
            return "文本框"
        default:
            return nil
        }
    }
}

struct ModelStateSnapshot: Codable, Equatable {
    var models: [HubModel]
    var updatedAt: Double

    static func empty() -> ModelStateSnapshot {
        ModelStateSnapshot(models: [], updatedAt: Date().timeIntervalSince1970)
    }
}

struct HubAIRequest: Codable {
    var type: String = "generate"
    var req_id: String
    var app_id: String
    var task_type: String
    var preferred_model_id: String?
    var model_id: String?
    var prompt: String
    var max_tokens: Int
    var temperature: Double
    var top_p: Double
    var created_at: Double
    var auto_load: Bool
}

struct HubAIResponseEvent: Codable {
    var type: String
    var req_id: String
    var ok: Bool?
    var reason: String?
    var text: String?
    var seq: Int?
    var model_id: String?
    var task_type: String?
    var promptTokens: Int?
    var generationTokens: Int?
    var generationTPS: Double?

    // Future-proof: keep any extra fields.
    var raw: [String: JSONValue]?

    init(
        type: String,
        req_id: String,
        ok: Bool? = nil,
        reason: String? = nil,
        text: String? = nil,
        seq: Int? = nil,
        model_id: String? = nil,
        task_type: String? = nil,
        promptTokens: Int? = nil,
        generationTokens: Int? = nil,
        generationTPS: Double? = nil,
        raw: [String: JSONValue]? = nil
    ) {
        self.type = type
        self.req_id = req_id
        self.ok = ok
        self.reason = reason
        self.text = text
        self.seq = seq
        self.model_id = model_id
        self.task_type = task_type
        self.promptTokens = promptTokens
        self.generationTokens = generationTokens
        self.generationTPS = generationTPS
        self.raw = raw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        req_id = (try? c.decode(String.self, forKey: .req_id)) ?? ""
        ok = try? c.decodeIfPresent(Bool.self, forKey: .ok)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        seq = try? c.decodeIfPresent(Int.self, forKey: .seq)
        model_id = try? c.decodeIfPresent(String.self, forKey: .model_id)
        task_type = try? c.decodeIfPresent(String.self, forKey: .task_type)
        promptTokens = try? c.decodeIfPresent(Int.self, forKey: .promptTokens)
        generationTokens = try? c.decodeIfPresent(Int.self, forKey: .generationTokens)
        generationTPS = try? c.decodeIfPresent(Double.self, forKey: .generationTPS)

        // Decode full payload as a dictionary of JSONValue.
        let any = try decoder.singleValueContainer()
        raw = (try? any.decode([String: JSONValue].self))
    }

    enum CodingKeys: String, CodingKey {
        case type
        case req_id
        case ok
        case reason
        case text
        case seq
        case model_id
        case task_type
        case promptTokens
        case generationTokens
        case generationTPS
    }

    var requestedModelIdFromMetadata: String? {
        metadataString("requested_model_id")
            ?? metadataString("preferred_model_id")
            ?? metadataString("requestedModelId")
    }

    var actualModelIdFromMetadata: String? {
        metadataString("actual_model_id")
            ?? metadataString("resolved_model_id")
            ?? metadataString("actualModelId")
            ?? model_id
    }

    var runtimeProviderFromMetadata: String? {
        metadataString("runtime_provider")
            ?? metadataString("provider")
    }

    var executionPathFromMetadata: String? {
        metadataString("execution_path")
    }

    var fallbackReasonCodeFromMetadata: String? {
        metadataString("fallback_reason_code")
            ?? metadataString("failure_reason_code")
    }

    var auditRefFromMetadata: String? {
        metadataString("audit_ref")
            ?? metadataString("auditRef")
    }

    var denyCodeFromMetadata: String? {
        metadataString("deny_code")
            ?? metadataString("denyCode")
            ?? fallbackReasonCodeFromMetadata
    }

    var remoteRetryAttemptedFromMetadata: Bool? {
        metadataBool("remote_retry_attempted")
    }

    var remoteRetryFromModelIdFromMetadata: String? {
        metadataString("remote_retry_from_model_id")
    }

    var remoteRetryToModelIdFromMetadata: String? {
        metadataString("remote_retry_to_model_id")
    }

    var remoteRetryReasonCodeFromMetadata: String? {
        metadataString("remote_retry_reason_code")
    }

    private func metadataString(_ key: String) -> String? {
        raw?[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func metadataBool(_ key: String) -> Bool? {
        switch raw?[key] {
        case .bool(let value):
            return value
        case .string(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

struct HubAIUsage: Equatable {
    var promptTokens: Int
    var generationTokens: Int
    var generationTPS: Double
    var requestedModelId: String?
    var actualModelId: String?
    var runtimeProvider: String?
    var executionPath: String?
    var fallbackReasonCode: String?
    var auditRef: String?
    var denyCode: String?
    var remoteRetryAttempted: Bool?
    var remoteRetryFromModelId: String?
    var remoteRetryToModelId: String?
    var remoteRetryReasonCode: String?
}

// Minimal JSON representation to preserve unknown fields.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var obj: [String: JSONValue] = [:]
            for k in c.allKeys {
                obj[k.stringValue] = (try? c.decode(JSONValue.self, forKey: k)) ?? .null
            }
            self = .object(obj)
            return
        }
        if var a = try? decoder.unkeyedContainer() {
            var arr: [JSONValue] = []
            while !a.isAtEnd {
                arr.append((try? a.decode(JSONValue.self)) ?? .null)
            }
            self = .array(arr)
            return
        }
        let s = try decoder.singleValueContainer()
        if s.decodeNil() { self = .null; return }
        if let b = try? s.decode(Bool.self) { self = .bool(b); return }
        if let n = try? s.decode(Double.self) { self = .number(n); return }
        if let str = try? s.decode(String.self) { self = .string(str); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .number(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .bool(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .object(let o):
            var c = encoder.container(keyedBy: DynamicCodingKey.self)
            for (k, v) in o {
                try c.encode(v, forKey: DynamicCodingKey(k))
            }
        case .array(let a):
            var c = encoder.unkeyedContainer()
            for v in a { try c.encode(v) }
        case .null:
            var c = encoder.singleValueContainer(); try c.encodeNil()
        }
    }

    struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? = nil
        init(_ s: String) { self.stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

extension JSONValue {
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }
}
