import Foundation

public struct XHubLocalModelManifest: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var backend: String
    public var modelFormat: String
    public var maxContextLength: Int?
    public var defaultLoadProfile: LocalModelLoadProfile?
    public var taskKinds: [String]
    public var inputModalities: [String]
    public var outputModalities: [String]
    public var offlineReady: Bool
    public var resourceProfile: ModelResourceProfile
    public var trustProfile: ModelTrustProfile
    public var processorRequirements: ModelProcessorRequirements

    public init(
        schemaVersion: String = "xhub_model_manifest.v1",
        backend: String,
        modelFormat: String,
        maxContextLength: Int? = nil,
        defaultLoadProfile: LocalModelLoadProfile? = nil,
        taskKinds: [String],
        inputModalities: [String],
        outputModalities: [String],
        offlineReady: Bool = true,
        resourceProfile: ModelResourceProfile = ModelResourceProfile(),
        trustProfile: ModelTrustProfile = ModelTrustProfile(),
        processorRequirements: ModelProcessorRequirements = ModelProcessorRequirements()
    ) {
        self.schemaVersion = schemaVersion
        self.backend = backend
        self.modelFormat = modelFormat
        self.maxContextLength = maxContextLength
        if let defaultLoadProfile {
            self.defaultLoadProfile = defaultLoadProfile.normalized(maxContextLength: maxContextLength)
        } else {
            self.defaultLoadProfile = nil
        }
        self.taskKinds = LocalModelCapabilityDefaults.normalizedStringList(
            taskKinds,
            fallback: LocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend)
        )
        self.inputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            inputModalities,
            fallback: LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: self.taskKinds)
        )
        self.outputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            outputModalities,
            fallback: LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: self.taskKinds)
        )
        self.offlineReady = offlineReady
        self.resourceProfile = resourceProfile
        self.trustProfile = trustProfile
        self.processorRequirements = processorRequirements
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case backend
        case modelFormat = "model_format"
        case maxContextLength = "max_context_length"
        case defaultLoadProfile = "default_load_profile"
        case taskKinds = "task_kinds"
        case inputModalities = "input_modalities"
        case outputModalities = "output_modalities"
        case offlineReady = "offline_ready"
        case resourceProfile = "resource_profile"
        case trustProfile = "trust_profile"
        case processorRequirements = "processor_requirements"
    }

    enum AliasCodingKeys: String, CodingKey {
        case defaultLoadConfig = "default_load_config"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let a = try decoder.container(keyedBy: AliasCodingKeys.self)
        backend = (try? c.decode(String.self, forKey: .backend)) ?? "mlx"
        let fallbackTaskKinds = LocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend)
        schemaVersion = (try? c.decode(String.self, forKey: .schemaVersion)) ?? "xhub_model_manifest.v1"
        modelFormat = (try? c.decode(String.self, forKey: .modelFormat)) ?? LocalModelCapabilityDefaults.defaultModelFormat(forBackend: backend)
        maxContextLength = try? c.decodeIfPresent(Int.self, forKey: .maxContextLength)
        defaultLoadProfile = ((try? a.decodeIfPresent(LocalModelLoadProfile.self, forKey: .defaultLoadConfig))
            ?? (try? c.decodeIfPresent(LocalModelLoadProfile.self, forKey: .defaultLoadProfile)))?
            .normalized(maxContextLength: maxContextLength)
        taskKinds = LocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .taskKinds)) ?? fallbackTaskKinds,
            fallback: fallbackTaskKinds
        )
        inputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .inputModalities)) ?? LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds),
            fallback: LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds)
        )
        outputModalities = LocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .outputModalities)) ?? LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds),
            fallback: LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds)
        )
        offlineReady = (try? c.decode(Bool.self, forKey: .offlineReady)) ?? true
        resourceProfile = (try? c.decode(ModelResourceProfile.self, forKey: .resourceProfile))
            ?? LocalModelCapabilityDefaults.defaultResourceProfile(backend: backend, quant: "", paramsB: 0.0)
        trustProfile = (try? c.decode(ModelTrustProfile.self, forKey: .trustProfile))
            ?? LocalModelCapabilityDefaults.defaultTrustProfile()
        processorRequirements = (try? c.decode(ModelProcessorRequirements.self, forKey: .processorRequirements))
            ?? LocalModelCapabilityDefaults.defaultProcessorRequirements(backend: backend, modelFormat: modelFormat, taskKinds: taskKinds)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(backend, forKey: .backend)
        try c.encode(modelFormat, forKey: .modelFormat)
        try c.encodeIfPresent(maxContextLength, forKey: .maxContextLength)
        try c.encodeIfPresent(defaultLoadProfile, forKey: .defaultLoadProfile)
        try c.encode(taskKinds, forKey: .taskKinds)
        try c.encode(inputModalities, forKey: .inputModalities)
        try c.encode(outputModalities, forKey: .outputModalities)
        try c.encode(offlineReady, forKey: .offlineReady)
        try c.encode(resourceProfile, forKey: .resourceProfile)
        try c.encode(trustProfile, forKey: .trustProfile)
        try c.encode(processorRequirements, forKey: .processorRequirements)
    }
}

public enum XHubLocalModelManifestLoader {
    public static let fileName = "xhub_model_manifest.json"

    public static func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public static func load(from directory: URL) -> XHubLocalModelManifest? {
        let url = manifestURL(in: directory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XHubLocalModelManifest.self, from: data)
    }
}
