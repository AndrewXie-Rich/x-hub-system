import Foundation

public enum HubModelState: String, Codable, Sendable {
    case loaded
    case available
    case sleeping
}

public struct ModelResourceProfile: Codable, Equatable, Sendable {
    public var preferredDevice: String
    public var memoryFloorMB: Int
    public var dtype: String

    public init(
        preferredDevice: String = "unknown",
        memoryFloorMB: Int = 0,
        dtype: String = "unknown"
    ) {
        self.preferredDevice = preferredDevice
        self.memoryFloorMB = memoryFloorMB
        self.dtype = dtype
    }

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

    public init(from decoder: Decoder) throws {
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

public struct ModelTrustProfile: Codable, Equatable, Sendable {
    public var allowSecretInput: Bool
    public var allowRemoteExport: Bool

    public init(
        allowSecretInput: Bool = false,
        allowRemoteExport: Bool = false
    ) {
        self.allowSecretInput = allowSecretInput
        self.allowRemoteExport = allowRemoteExport
    }

    enum CodingKeys: String, CodingKey {
        case allowSecretInput
        case allowRemoteExport
    }

    enum SnakeCodingKeys: String, CodingKey {
        case allowSecretInput = "allow_secret_input"
        case allowRemoteExport = "allow_remote_export"
    }

    public init(from decoder: Decoder) throws {
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

public struct ModelProcessorRequirements: Codable, Equatable, Sendable {
    public var tokenizerRequired: Bool
    public var processorRequired: Bool
    public var featureExtractorRequired: Bool

    public init(
        tokenizerRequired: Bool = true,
        processorRequired: Bool = false,
        featureExtractorRequired: Bool = false
    ) {
        self.tokenizerRequired = tokenizerRequired
        self.processorRequired = processorRequired
        self.featureExtractorRequired = featureExtractorRequired
    }

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

    public init(from decoder: Decoder) throws {
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

public enum LocalModelCapabilityDefaults {
    public static func defaultLoadProfile(contextLength: Int) -> LocalModelLoadProfile {
        LocalModelLoadProfile(contextLength: max(512, contextLength))
    }

    public static func defaultMaxContextLength(
        contextLength: Int,
        defaultLoadProfile: LocalModelLoadProfile? = nil
    ) -> Int {
        let defaultContextLength = defaultLoadProfile?.contextLength ?? contextLength
        return max(512, max(contextLength, defaultContextLength))
    }

    public static func defaultModelFormat(forBackend backend: String) -> String {
        switch backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
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

    public static func defaultTaskKinds(forBackend backend: String, roles: [String]? = nil) -> [String] {
        let normalizedRoles = Set((roles ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if normalizedRoles.contains("embed") || normalizedRoles.contains("embedding") {
            return ["embedding"]
        }
        switch backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mlx":
            return ["text_generate"]
        default:
            return ["text_generate"]
        }
    }

    public static func defaultInputModalities(forTaskKinds taskKinds: [String]) -> [String] {
        let normalized = normalizedStringList(taskKinds, fallback: ["text"])
        var out: [String] = []
        for kind in normalized {
            switch kind {
            case "speech_to_text":
                appendUnique("audio", into: &out)
            case "vision_understand", "ocr":
                appendUnique("image", into: &out)
            default:
                appendUnique("text", into: &out)
            }
        }
        return out.isEmpty ? ["text"] : out
    }

    public static func defaultOutputModalities(forTaskKinds taskKinds: [String]) -> [String] {
        let normalized = normalizedStringList(taskKinds, fallback: ["text_generate"])
        var out: [String] = []
        for kind in normalized {
            switch kind {
            case "embedding":
                appendUnique("embedding", into: &out)
            case "rerank":
                appendUnique("scores", into: &out)
            case "classify":
                appendUnique("labels", into: &out)
            case "speech_to_text":
                appendUnique("text", into: &out)
                appendUnique("segments", into: &out)
            case "ocr":
                appendUnique("text", into: &out)
                appendUnique("spans", into: &out)
            default:
                appendUnique("text", into: &out)
            }
        }
        return out.isEmpty ? ["text"] : out
    }

    public static func defaultOfflineReady(backend: String, modelPath: String?) -> Bool {
        let path = (modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            return true
        }
        return backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mlx"
    }

    public static func defaultResourceProfile(
        backend: String,
        quant: String,
        paramsB: Double
    ) -> ModelResourceProfile {
        let normalizedBackend = backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedQuant = quant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        return ModelResourceProfile(
            preferredDevice: preferredDevice,
            memoryFloorMB: memoryFloorMB,
            dtype: dtype
        )
    }

    public static func defaultTrustProfile() -> ModelTrustProfile {
        ModelTrustProfile(
            allowSecretInput: false,
            allowRemoteExport: false
        )
    }

    public static func defaultProcessorRequirements(
        backend: String,
        modelFormat: String,
        taskKinds: [String]
    ) -> ModelProcessorRequirements {
        let normalizedTaskKinds = normalizedStringList(taskKinds, fallback: defaultTaskKinds(forBackend: backend))
        let requiresTextTokenizer = normalizedTaskKinds.contains { kind in
            kind == "text_generate" || kind == "embedding" || kind == "rerank" || kind == "classify"
        }
        let requiresProcessor = normalizedTaskKinds.contains { kind in
            kind == "speech_to_text" || kind == "vision_understand" || kind == "ocr"
        }
        let requiresFeatureExtractor = normalizedTaskKinds.contains { kind in
            kind == "speech_to_text" || kind == "vision_understand" || kind == "ocr"
        }
        if modelFormat == "mlx" {
            return ModelProcessorRequirements(
                tokenizerRequired: true,
                processorRequired: false,
                featureExtractorRequired: false
            )
        }
        return ModelProcessorRequirements(
            tokenizerRequired: requiresTextTokenizer,
            processorRequired: requiresProcessor,
            featureExtractorRequired: requiresFeatureExtractor
        )
    }

    public static func normalizedStringList(_ values: [String], fallback: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for raw in values {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
}

public struct HubModel: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var backend: String
    public var quant: String
    public var contextLength: Int
    public var maxContextLength: Int
    public var paramsB: Double
    public var roles: [String]?
    public var state: HubModelState
    public var memoryBytes: Int64?
    public var tokensPerSec: Double?
    public var modelPath: String?
    public var note: String?
    public var modelFormat: String
    public var defaultLoadProfile: LocalModelLoadProfile
    public var taskKinds: [String]
    public var inputModalities: [String]
    public var outputModalities: [String]
    public var offlineReady: Bool
    public var resourceProfile: ModelResourceProfile
    public var trustProfile: ModelTrustProfile
    public var processorRequirements: ModelProcessorRequirements

    public init(
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
        defaultLoadProfile: LocalModelLoadProfile? = nil,
        taskKinds: [String]? = nil,
        inputModalities: [String]? = nil,
        outputModalities: [String]? = nil,
        offlineReady: Bool? = nil,
        resourceProfile: ModelResourceProfile? = nil,
        trustProfile: ModelTrustProfile? = nil,
        processorRequirements: ModelProcessorRequirements? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.quant = quant
        let resolvedModelFormat = modelFormat ?? LocalModelCapabilityDefaults.defaultModelFormat(forBackend: backend)
        let resolvedDefaultLoadProfile = (defaultLoadProfile ?? LocalModelCapabilityDefaults.defaultLoadProfile(contextLength: contextLength))
        let resolvedMaxContextLength = LocalModelCapabilityDefaults.defaultMaxContextLength(
            contextLength: maxContextLength ?? contextLength,
            defaultLoadProfile: resolvedDefaultLoadProfile
        )
        self.defaultLoadProfile = resolvedDefaultLoadProfile.normalized(maxContextLength: resolvedMaxContextLength)
        self.contextLength = self.defaultLoadProfile.contextLength
        self.maxContextLength = max(self.contextLength, resolvedMaxContextLength)
        self.paramsB = paramsB
        self.roles = roles
        self.state = state
        self.memoryBytes = memoryBytes
        self.tokensPerSec = tokensPerSec
        self.modelPath = modelPath
        self.note = note
        let resolvedTaskKinds = LocalModelCapabilityDefaults.normalizedStringList(
            taskKinds ?? LocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend, roles: roles),
            fallback: LocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend, roles: roles)
        )
        self.modelFormat = resolvedModelFormat
        self.taskKinds = resolvedTaskKinds
        self.inputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            inputModalities ?? LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: resolvedTaskKinds),
            fallback: LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: resolvedTaskKinds)
        )
        self.outputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            outputModalities ?? LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: resolvedTaskKinds),
            fallback: LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: resolvedTaskKinds)
        )
        self.offlineReady = offlineReady ?? LocalModelCapabilityDefaults.defaultOfflineReady(backend: backend, modelPath: modelPath)
        self.resourceProfile = resourceProfile ?? LocalModelCapabilityDefaults.defaultResourceProfile(
            backend: backend,
            quant: quant,
            paramsB: paramsB
        )
        self.trustProfile = trustProfile ?? LocalModelCapabilityDefaults.defaultTrustProfile()
        self.processorRequirements = processorRequirements ?? LocalModelCapabilityDefaults.defaultProcessorRequirements(
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
        case resourceProfile
        case trustProfile
        case processorRequirements
    }

    enum SnakeCodingKeys: String, CodingKey {
        case maxContextLength = "max_context_length"
        case defaultLoadProfile = "default_load_profile"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        backend = (try? c.decode(String.self, forKey: .backend)) ?? "mlx"
        quant = (try? c.decode(String.self, forKey: .quant)) ?? "bf16"
        let legacyContextLength = (try? c.decode(Int.self, forKey: .contextLength)) ?? 8192
        paramsB = (try? c.decode(Double.self, forKey: .paramsB)) ?? 0.0
        roles = try? c.decodeIfPresent([String].self, forKey: .roles)
        state = (try? c.decode(HubModelState.self, forKey: .state)) ?? .available
        memoryBytes = try? c.decodeIfPresent(Int64.self, forKey: .memoryBytes)
        tokensPerSec = try? c.decodeIfPresent(Double.self, forKey: .tokensPerSec)
        modelPath = try? c.decodeIfPresent(String.self, forKey: .modelPath)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        let defaultTaskKinds = LocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend, roles: roles)
        modelFormat = (try? c.decode(String.self, forKey: .modelFormat)) ?? LocalModelCapabilityDefaults.defaultModelFormat(forBackend: backend)
        let decodedDefaultLoadProfile = (try? c.decode(LocalModelLoadProfile.self, forKey: .defaultLoadProfile))
            ?? (try? s.decode(LocalModelLoadProfile.self, forKey: .defaultLoadProfile))
        let decodedMaxContextLength = (try? c.decode(Int.self, forKey: .maxContextLength))
            ?? (try? s.decode(Int.self, forKey: .maxContextLength))
            ?? LocalModelCapabilityDefaults.defaultMaxContextLength(
                contextLength: legacyContextLength,
                defaultLoadProfile: decodedDefaultLoadProfile
            )
        defaultLoadProfile = (decodedDefaultLoadProfile ?? LocalModelCapabilityDefaults.defaultLoadProfile(contextLength: legacyContextLength))
            .normalized(maxContextLength: decodedMaxContextLength)
        contextLength = defaultLoadProfile.contextLength
        maxContextLength = max(contextLength, decodedMaxContextLength)
        taskKinds = LocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .taskKinds)) ?? defaultTaskKinds,
            fallback: defaultTaskKinds
        )
        inputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .inputModalities)) ?? LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds),
            fallback: LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds)
        )
        outputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .outputModalities)) ?? LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds),
            fallback: LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds)
        )
        offlineReady = (try? c.decode(Bool.self, forKey: .offlineReady))
            ?? LocalModelCapabilityDefaults.defaultOfflineReady(backend: backend, modelPath: modelPath)
        resourceProfile = (try? c.decode(ModelResourceProfile.self, forKey: .resourceProfile))
            ?? LocalModelCapabilityDefaults.defaultResourceProfile(backend: backend, quant: quant, paramsB: paramsB)
        trustProfile = (try? c.decode(ModelTrustProfile.self, forKey: .trustProfile))
            ?? LocalModelCapabilityDefaults.defaultTrustProfile()
        processorRequirements = (try? c.decode(ModelProcessorRequirements.self, forKey: .processorRequirements))
            ?? LocalModelCapabilityDefaults.defaultProcessorRequirements(backend: backend, modelFormat: modelFormat, taskKinds: taskKinds)
    }
}

public struct ModelCatalogEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var backend: String
    public var quant: String
    public var contextLength: Int
    public var maxContextLength: Int
    public var paramsB: Double
    public var modelPath: String
    public var roles: [String]?
    public var note: String?
    public var modelFormat: String
    public var defaultLoadProfile: LocalModelLoadProfile
    public var taskKinds: [String]
    public var inputModalities: [String]
    public var outputModalities: [String]
    public var offlineReady: Bool
    public var resourceProfile: ModelResourceProfile
    public var trustProfile: ModelTrustProfile
    public var processorRequirements: ModelProcessorRequirements

    public init(
        id: String,
        name: String,
        backend: String = "mlx",
        quant: String = "bf16",
        contextLength: Int = 8192,
        maxContextLength: Int? = nil,
        paramsB: Double = 0.0,
        modelPath: String,
        roles: [String]? = nil,
        note: String? = nil,
        modelFormat: String? = nil,
        defaultLoadProfile: LocalModelLoadProfile? = nil,
        taskKinds: [String]? = nil,
        inputModalities: [String]? = nil,
        outputModalities: [String]? = nil,
        offlineReady: Bool? = nil,
        resourceProfile: ModelResourceProfile? = nil,
        trustProfile: ModelTrustProfile? = nil,
        processorRequirements: ModelProcessorRequirements? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.quant = quant
        let resolvedModelFormat = modelFormat ?? LocalModelCapabilityDefaults.defaultModelFormat(forBackend: backend)
        let resolvedDefaultLoadProfile = (defaultLoadProfile ?? LocalModelCapabilityDefaults.defaultLoadProfile(contextLength: contextLength))
        let resolvedMaxContextLength = LocalModelCapabilityDefaults.defaultMaxContextLength(
            contextLength: maxContextLength ?? contextLength,
            defaultLoadProfile: resolvedDefaultLoadProfile
        )
        self.defaultLoadProfile = resolvedDefaultLoadProfile.normalized(maxContextLength: resolvedMaxContextLength)
        self.contextLength = self.defaultLoadProfile.contextLength
        self.maxContextLength = max(self.contextLength, resolvedMaxContextLength)
        self.paramsB = paramsB
        self.modelPath = modelPath
        self.roles = roles
        self.note = note
        let resolvedTaskKinds = LocalModelCapabilityDefaults.normalizedStringList(
            taskKinds ?? LocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend, roles: roles),
            fallback: LocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend, roles: roles)
        )
        self.modelFormat = resolvedModelFormat
        self.taskKinds = resolvedTaskKinds
        self.inputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            inputModalities ?? LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: resolvedTaskKinds),
            fallback: LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: resolvedTaskKinds)
        )
        self.outputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            outputModalities ?? LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: resolvedTaskKinds),
            fallback: LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: resolvedTaskKinds)
        )
        self.offlineReady = offlineReady ?? LocalModelCapabilityDefaults.defaultOfflineReady(backend: backend, modelPath: modelPath)
        self.resourceProfile = resourceProfile ?? LocalModelCapabilityDefaults.defaultResourceProfile(
            backend: backend,
            quant: quant,
            paramsB: paramsB
        )
        self.trustProfile = trustProfile ?? LocalModelCapabilityDefaults.defaultTrustProfile()
        self.processorRequirements = processorRequirements ?? LocalModelCapabilityDefaults.defaultProcessorRequirements(
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
        case modelPath
        case roles
        case note
        case modelFormat
        case defaultLoadProfile
        case taskKinds
        case inputModalities
        case outputModalities
        case offlineReady
        case resourceProfile
        case trustProfile
        case processorRequirements
    }

    enum SnakeCodingKeys: String, CodingKey {
        case maxContextLength = "max_context_length"
        case defaultLoadProfile = "default_load_profile"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        backend = (try? c.decode(String.self, forKey: .backend)) ?? "mlx"
        quant = (try? c.decode(String.self, forKey: .quant)) ?? "bf16"
        let legacyContextLength = (try? c.decode(Int.self, forKey: .contextLength)) ?? 8192
        paramsB = (try? c.decode(Double.self, forKey: .paramsB)) ?? 0.0
        modelPath = (try? c.decode(String.self, forKey: .modelPath)) ?? ""
        roles = try? c.decodeIfPresent([String].self, forKey: .roles)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        let defaultTaskKinds = LocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend, roles: roles)
        modelFormat = (try? c.decode(String.self, forKey: .modelFormat)) ?? LocalModelCapabilityDefaults.defaultModelFormat(forBackend: backend)
        let decodedDefaultLoadProfile = (try? c.decode(LocalModelLoadProfile.self, forKey: .defaultLoadProfile))
            ?? (try? s.decode(LocalModelLoadProfile.self, forKey: .defaultLoadProfile))
        let decodedMaxContextLength = (try? c.decode(Int.self, forKey: .maxContextLength))
            ?? (try? s.decode(Int.self, forKey: .maxContextLength))
            ?? LocalModelCapabilityDefaults.defaultMaxContextLength(
                contextLength: legacyContextLength,
                defaultLoadProfile: decodedDefaultLoadProfile
            )
        defaultLoadProfile = (decodedDefaultLoadProfile ?? LocalModelCapabilityDefaults.defaultLoadProfile(contextLength: legacyContextLength))
            .normalized(maxContextLength: decodedMaxContextLength)
        contextLength = defaultLoadProfile.contextLength
        maxContextLength = max(contextLength, decodedMaxContextLength)
        taskKinds = LocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .taskKinds)) ?? defaultTaskKinds,
            fallback: defaultTaskKinds
        )
        inputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .inputModalities)) ?? LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds),
            fallback: LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds)
        )
        outputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .outputModalities)) ?? LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds),
            fallback: LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds)
        )
        offlineReady = (try? c.decode(Bool.self, forKey: .offlineReady))
            ?? LocalModelCapabilityDefaults.defaultOfflineReady(backend: backend, modelPath: modelPath)
        resourceProfile = (try? c.decode(ModelResourceProfile.self, forKey: .resourceProfile))
            ?? LocalModelCapabilityDefaults.defaultResourceProfile(backend: backend, quant: quant, paramsB: paramsB)
        trustProfile = (try? c.decode(ModelTrustProfile.self, forKey: .trustProfile))
            ?? LocalModelCapabilityDefaults.defaultTrustProfile()
        processorRequirements = (try? c.decode(ModelProcessorRequirements.self, forKey: .processorRequirements))
            ?? LocalModelCapabilityDefaults.defaultProcessorRequirements(backend: backend, modelFormat: modelFormat, taskKinds: taskKinds)
    }
}

public struct ModelCatalogSnapshot: Codable, Sendable, Equatable {
    public var models: [ModelCatalogEntry]
    public var updatedAt: Double

    public init(models: [ModelCatalogEntry], updatedAt: Double) {
        self.models = models
        self.updatedAt = updatedAt
    }

    public static func empty() -> ModelCatalogSnapshot {
        ModelCatalogSnapshot(models: [], updatedAt: Date().timeIntervalSince1970)
    }
}

public enum ModelCatalogStorage {
    public static let fileName = "models_catalog.json"

    public static func url() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> ModelCatalogSnapshot {
        let url = url()
        if let data = try? Data(contentsOf: url) {
            if let obj = try? JSONDecoder().decode(ModelCatalogSnapshot.self, from: data) {
                return obj
            }
            if let arr = try? JSONDecoder().decode([ModelCatalogEntry].self, from: data) {
                return ModelCatalogSnapshot(models: arr, updatedAt: Date().timeIntervalSince1970)
            }
        }
        return .empty()
    }

    public static func save(_ snap: ModelCatalogSnapshot) {
        var cur = snap
        cur.updatedAt = Date().timeIntervalSince1970
        let url = url()
        if let data = try? JSONEncoder().encode(cur) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

public struct ModelStateSnapshot: Codable, Sendable, Equatable {
    public var models: [HubModel]
    public var updatedAt: Double

    public init(models: [HubModel], updatedAt: Double) {
        self.models = models
        self.updatedAt = updatedAt
    }

    public static func empty() -> ModelStateSnapshot {
        ModelStateSnapshot(models: [], updatedAt: Date().timeIntervalSince1970)
    }
}

public enum ModelStateStorage {
    public static let fileName = "models_state.json"

    public static func url() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> ModelStateSnapshot {
        let url = url()
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) {
            return obj
        }
        return .empty()
    }

    public static func save(_ state: ModelStateSnapshot) {
        let url = url()
        if let data = try? JSONEncoder().encode(state) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
