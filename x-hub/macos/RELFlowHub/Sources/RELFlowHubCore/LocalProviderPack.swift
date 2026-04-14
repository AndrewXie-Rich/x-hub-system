import Foundation

public struct AIRuntimeProviderPackRuntimeRequirements: Codable, Sendable, Equatable {
    public var executionMode: String
    public var pythonModules: [String]
    public var helperBinary: String
    public var nativeDylib: String
    public var serviceBaseUrl: String
    public var notes: [String]

    public init(
        executionMode: String = "",
        pythonModules: [String] = [],
        helperBinary: String = "",
        nativeDylib: String = "",
        serviceBaseUrl: String = "",
        notes: [String] = []
    ) {
        self.executionMode = executionMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.pythonModules = LocalModelCapabilityDefaults.normalizedStringList(pythonModules, fallback: [])
        self.helperBinary = helperBinary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nativeDylib = nativeDylib.trimmingCharacters(in: .whitespacesAndNewlines)
        self.serviceBaseUrl = serviceBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = LocalModelCapabilityDefaults.normalizedStringList(notes, fallback: [])
    }

    enum CodingKeys: String, CodingKey {
        case executionMode
        case pythonModules
        case helperBinary
        case nativeDylib
        case serviceBaseUrl
        case notes
    }

    enum SnakeCodingKeys: String, CodingKey {
        case executionMode = "execution_mode"
        case pythonModules = "python_modules"
        case helperBinary = "helper_binary"
        case nativeDylib = "native_dylib"
        case serviceBaseUrl = "service_base_url"
        case notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            executionMode: (try? c.decode(String.self, forKey: .executionMode))
                ?? (try? s.decode(String.self, forKey: .executionMode))
                ?? "",
            pythonModules: (try? c.decode([String].self, forKey: .pythonModules))
                ?? (try? s.decode([String].self, forKey: .pythonModules))
                ?? [],
            helperBinary: (try? c.decode(String.self, forKey: .helperBinary))
                ?? (try? s.decode(String.self, forKey: .helperBinary))
                ?? "",
            nativeDylib: (try? c.decode(String.self, forKey: .nativeDylib))
                ?? (try? s.decode(String.self, forKey: .nativeDylib))
                ?? "",
            serviceBaseUrl: (try? c.decode(String.self, forKey: .serviceBaseUrl))
                ?? (try? s.decode(String.self, forKey: .serviceBaseUrl))
                ?? "",
            notes: (try? c.decode([String].self, forKey: .notes))
                ?? (try? s.decode([String].self, forKey: .notes))
                ?? []
        )
    }
}

public struct AIRuntimeProviderPackStatus: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var providerId: String
    public var engine: String
    public var version: String
    public var supportedFormats: [String]
    public var supportedDomains: [String]
    public var runtimeRequirements: AIRuntimeProviderPackRuntimeRequirements
    public var minHubVersion: String
    public var installed: Bool
    public var enabled: Bool
    public var packState: String
    public var reasonCode: String

    public init(
        schemaVersion: String = "",
        providerId: String,
        engine: String = "",
        version: String = "",
        supportedFormats: [String] = [],
        supportedDomains: [String] = [],
        runtimeRequirements: AIRuntimeProviderPackRuntimeRequirements = AIRuntimeProviderPackRuntimeRequirements(),
        minHubVersion: String = "",
        installed: Bool = false,
        enabled: Bool = false,
        packState: String = "",
        reasonCode: String = ""
    ) {
        self.schemaVersion = schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.providerId = providerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.engine = engine.trimmingCharacters(in: .whitespacesAndNewlines)
        self.version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        self.supportedFormats = LocalModelCapabilityDefaults.normalizedStringList(supportedFormats, fallback: [])
        self.supportedDomains = LocalModelCapabilityDefaults.normalizedStringList(supportedDomains, fallback: [])
        self.runtimeRequirements = runtimeRequirements
        self.minHubVersion = minHubVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.installed = installed
        self.enabled = enabled
        self.packState = packState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.reasonCode = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case providerId
        case engine
        case version
        case supportedFormats
        case supportedDomains
        case runtimeRequirements
        case minHubVersion
        case installed
        case enabled
        case packState
        case reasonCode
    }

    enum SnakeCodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case providerId = "provider_id"
        case engine
        case version
        case supportedFormats = "supported_formats"
        case supportedDomains = "supported_domains"
        case runtimeRequirements = "runtime_requirements"
        case minHubVersion = "min_hub_version"
        case installed
        case enabled
        case packState = "pack_state"
        case reasonCode = "reason_code"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            schemaVersion: (try? c.decode(String.self, forKey: .schemaVersion))
                ?? (try? s.decode(String.self, forKey: .schemaVersion))
                ?? "",
            providerId: (try? c.decode(String.self, forKey: .providerId))
                ?? (try? s.decode(String.self, forKey: .providerId))
                ?? "",
            engine: (try? c.decode(String.self, forKey: .engine))
                ?? (try? s.decode(String.self, forKey: .engine))
                ?? "",
            version: (try? c.decode(String.self, forKey: .version))
                ?? (try? s.decode(String.self, forKey: .version))
                ?? "",
            supportedFormats: (try? c.decode([String].self, forKey: .supportedFormats))
                ?? (try? s.decode([String].self, forKey: .supportedFormats))
                ?? [],
            supportedDomains: (try? c.decode([String].self, forKey: .supportedDomains))
                ?? (try? s.decode([String].self, forKey: .supportedDomains))
                ?? [],
            runtimeRequirements: (try? c.decode(AIRuntimeProviderPackRuntimeRequirements.self, forKey: .runtimeRequirements))
                ?? (try? s.decode(AIRuntimeProviderPackRuntimeRequirements.self, forKey: .runtimeRequirements))
                ?? AIRuntimeProviderPackRuntimeRequirements(),
            minHubVersion: (try? c.decode(String.self, forKey: .minHubVersion))
                ?? (try? s.decode(String.self, forKey: .minHubVersion))
                ?? "",
            installed: (try? c.decode(Bool.self, forKey: .installed))
                ?? (try? s.decode(Bool.self, forKey: .installed))
                ?? false,
            enabled: (try? c.decode(Bool.self, forKey: .enabled))
                ?? (try? s.decode(Bool.self, forKey: .enabled))
                ?? false,
            packState: (try? c.decode(String.self, forKey: .packState))
                ?? (try? s.decode(String.self, forKey: .packState))
                ?? "",
            reasonCode: (try? c.decode(String.self, forKey: .reasonCode))
                ?? (try? s.decode(String.self, forKey: .reasonCode))
                ?? ""
        )
    }

    static func synthesizedLegacy(providerId: String, providerStatus: AIRuntimeProviderStatus? = nil) -> AIRuntimeProviderPackStatus {
        let normalizedEngine = (providerStatus?.packEngine ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVersion = (providerStatus?.packVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedState = (providerStatus?.packState ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReason = (providerStatus?.packReasonCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return AIRuntimeProviderPackStatus(
            schemaVersion: "xhub.provider_pack_manifest.v1",
            providerId: providerId,
            engine: normalizedEngine.isEmpty ? providerId : normalizedEngine,
            version: normalizedVersion.isEmpty ? "legacy_unreported" : normalizedVersion,
            supportedFormats: [],
            supportedDomains: [],
            runtimeRequirements: AIRuntimeProviderPackRuntimeRequirements(
                notes: ["legacy_runtime_status_without_pack_inventory"]
            ),
            minHubVersion: "",
            installed: providerStatus?.packInstalled ?? false,
            enabled: providerStatus?.packEnabled ?? false,
            packState: normalizedState.isEmpty ? "legacy_unreported" : normalizedState,
            reasonCode: normalizedReason.isEmpty ? "runtime_status_missing_provider_pack_inventory" : normalizedReason
        )
    }
}
