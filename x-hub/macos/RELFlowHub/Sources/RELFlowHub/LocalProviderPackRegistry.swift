import Foundation
import RELFlowHubCore

struct LocalProviderPackRegistryRuntimeRequirements: Codable, Equatable {
    var executionMode: String
    var pythonModules: [String]
    var helperBinary: String
    var nativeDylib: String
    var serviceBaseUrl: String
    var notes: [String]

    init(
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
}

struct LocalProviderPackRegistryEntry: Codable, Equatable {
    var providerId: String
    var engine: String
    var version: String
    var supportedFormats: [String]
    var supportedDomains: [String]
    var runtimeRequirements: LocalProviderPackRegistryRuntimeRequirements
    var minHubVersion: String
    var installed: Bool
    var enabled: Bool
    var packState: String
    var reasonCode: String
    var note: String

    init(
        providerId: String,
        engine: String = "",
        version: String = "",
        supportedFormats: [String] = [],
        supportedDomains: [String] = [],
        runtimeRequirements: LocalProviderPackRegistryRuntimeRequirements = .init(),
        minHubVersion: String = "",
        installed: Bool = false,
        enabled: Bool = false,
        packState: String = "",
        reasonCode: String = "",
        note: String = ""
    ) {
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
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LocalProviderPackRegistrySnapshot: Codable, Equatable {
    var schemaVersion: String
    var updatedAt: Double
    var packs: [LocalProviderPackRegistryEntry]

    static func empty() -> LocalProviderPackRegistrySnapshot {
        LocalProviderPackRegistrySnapshot(
            schemaVersion: LocalProviderPackRegistry.schemaVersion,
            updatedAt: 0,
            packs: []
        )
    }
}

private final class LocalHelperBridgeDiscoveryCacheEntry: NSObject {
    let path: String
    let cachedAt: TimeInterval

    init(path: String, cachedAt: TimeInterval) {
        self.path = path
        self.cachedAt = cachedAt
    }
}

enum LocalHelperBridgeDiscovery {
    private static let defaultHelperNames = ["lms", "llmster", "lmstudio"]
    nonisolated(unsafe) private static let cache = NSCache<NSString, LocalHelperBridgeDiscoveryCacheEntry>()
    private static let cacheTTLSeconds: TimeInterval = 12.0

    static func discoverHelperBinary(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let cacheKey = "\(homeDirectory.standardizedFileURL.path)|\(environment["PATH"] ?? "")" as NSString
        let now = Date().timeIntervalSince1970
        if let cached = cache.object(forKey: cacheKey),
           now - cached.cachedAt <= cacheTTLSeconds {
            return cached.path
        }
        let candidates = candidatePaths(
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            environment: environment
        )
        let resolvedPath: String
        if let executable = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            resolvedPath = executable
        } else {
            resolvedPath = fallbackCandidatePath(candidates: candidates, fileManager: fileManager)
        }
        cache.setObject(
            LocalHelperBridgeDiscoveryCacheEntry(path: resolvedPath, cachedAt: now),
            forKey: cacheKey
        )
        return resolvedPath
    }

    static func candidatePaths(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var out: [String] = []

        let homeCandidates = [
            homeDirectory
                .appendingPathComponent(".lmstudio", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("lms")
                .path,
            homeDirectory
                .appendingPathComponent(".lmstudio", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("llmster")
                .path,
        ]
        out.append(contentsOf: homeCandidates)

        let pathValue = (environment["PATH"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !pathValue.isEmpty {
            let pathDirectories = pathValue
                .split(separator: ":")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for directory in pathDirectories {
                for helperName in defaultHelperNames {
                    out.append(URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(helperName).path)
                }
            }
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for raw in out {
            let expanded = (raw as NSString).expandingTildeInPath
            let normalized = URL(fileURLWithPath: expanded).standardizedFileURL.path
            guard seen.insert(normalized).inserted else { continue }
            deduped.append(normalized)
        }
        return deduped
    }

    private static func fallbackCandidatePath(
        candidates: [String],
        fileManager: FileManager
    ) -> String {
        let preferredLMStudioCandidates = candidates.filter(isLikelyLMStudioInstallPath)
        if let existingPreferred = preferredLMStudioCandidates.first(where: { fileManager.fileExists(atPath: $0) }) {
            return existingPreferred
        }
        if let guessedPreferred = preferredLMStudioCandidates.first {
            return guessedPreferred
        }
        if let existingCandidate = candidates.first(where: { fileManager.fileExists(atPath: $0) }) {
            return existingCandidate
        }
        return ""
    }

    private static func isLikelyLMStudioInstallPath(_ path: String) -> Bool {
        let normalized = path.lowercased()
        return normalized.contains("/.lmstudio/bin/lms")
            || normalized.contains("/.lmstudio/bin/llmster")
            || normalized.contains("/.lmstudio/bin/lmstudio")
    }
}

enum LocalProviderPackRegistry {
    static let schemaVersion = "xhub.provider_pack_registry.v1"
    static let fileName = "provider_pack_registry.json"

    private static let autoManagedNote = "auto_local_helper_bridge"
    private static let autoManagedHelperProviderIDs: Set<String> = ["llama.cpp", "mlx_vlm", "transformers"]
    private static let helperSupportedTaskKinds: Set<String> = [
        "text_generate",
        "embedding",
        "text_to_speech",
        "vision_understand",
        "ocr",
    ]
    private static let helperBlockingTaskKinds: Set<String> = [
        "speech_to_text",
    ]

    static func url(baseDir: URL = SharedPaths.ensureHubDirectory()) -> URL {
        baseDir.appendingPathComponent(fileName)
    }

    static func load(baseDir: URL = SharedPaths.ensureHubDirectory()) -> LocalProviderPackRegistrySnapshot {
        let registryURL = url(baseDir: baseDir)
        guard let data = try? Data(contentsOf: registryURL),
              let snapshot = try? JSONDecoder().decode(LocalProviderPackRegistrySnapshot.self, from: data) else {
            return .empty()
        }
        return snapshot
    }

    static func effectivePack(
        providerID: String,
        existing: LocalProviderPackRegistrySnapshot? = nil,
        catalog: ModelCatalogSnapshot = ModelCatalogStorage.load(),
        helperBinaryPath: String? = nil,
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LocalProviderPackRegistryEntry? {
        let normalizedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedProviderID.isEmpty else {
            return nil
        }
        let existingSnapshot = existing ?? load()
        let normalizedHelperBinary = normalizedHelperBinaryPath(
            helperBinaryPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? helperBinaryPath ?? ""
                : LocalHelperBridgeDiscovery.discoverHelperBinary(
                    homeDirectory: homeDirectory,
                    fileManager: fileManager,
                    environment: environment
                )
        )
        let snapshot = reconciledSnapshot(
            existing: existingSnapshot,
            catalog: catalog,
            helperBinaryPath: normalizedHelperBinary
        )
        return snapshot.packs.first { $0.providerId == normalizedProviderID }
    }

    static func save(
        _ snapshot: LocalProviderPackRegistrySnapshot,
        baseDir: URL = SharedPaths.ensureHubDirectory()
    ) {
        let registryURL = url(baseDir: baseDir)
        if snapshot.packs.isEmpty {
            try? FileManager.default.removeItem(at: registryURL)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        try? FileManager.default.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: registryURL, options: .atomic)
    }

    static func syncAutoManagedPacks(
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        catalog: ModelCatalogSnapshot = ModelCatalogStorage.load(),
        helperBinaryPath: String? = nil,
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let existing = load(baseDir: baseDir)
        let normalizedHelperBinary = normalizedHelperBinaryPath(
            helperBinaryPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? helperBinaryPath ?? ""
                : LocalHelperBridgeDiscovery.discoverHelperBinary(
                    homeDirectory: homeDirectory,
                    fileManager: fileManager,
                    environment: environment
                )
        )
        let updated = reconciledSnapshot(
            existing: existing,
            catalog: catalog,
            helperBinaryPath: normalizedHelperBinary
        )
        guard updated != existing else {
            return false
        }
        save(updated, baseDir: baseDir)
        return true
    }

    static func reconciledSnapshot(
        existing: LocalProviderPackRegistrySnapshot,
        catalog: ModelCatalogSnapshot,
        helperBinaryPath: String
    ) -> LocalProviderPackRegistrySnapshot {
        var retainedPacks: [LocalProviderPackRegistryEntry] = []
        var manualHelperOverrides = Set<String>()

        for pack in existing.packs {
            if autoManagedHelperProviderIDs.contains(pack.providerId) {
                if isAutoManagedHelperEntry(pack) {
                    continue
                }
                manualHelperOverrides.insert(pack.providerId)
            }
            retainedPacks.append(pack)
        }

        let normalizedHelperBinary = normalizedHelperBinaryPath(helperBinaryPath)
        for providerID in autoManagedHelperProviderIDs.sorted() {
            guard !manualHelperOverrides.contains(providerID) else { continue }
            guard shouldEnableAutoManagedHelperBridge(
                catalog: catalog,
                helperBinaryPath: helperBinaryPath,
                providerID: providerID
            ) else { continue }
            guard !normalizedHelperBinary.isEmpty else { continue }
            retainedPacks.append(
                autoManagedHelperEntry(
                    providerID: providerID,
                    helperBinaryPath: normalizedHelperBinary
                )
            )
        }

        retainedPacks.sort { lhs, rhs in
            if lhs.providerId == rhs.providerId {
                return lhs.note < rhs.note
            }
            return lhs.providerId < rhs.providerId
        }

        return LocalProviderPackRegistrySnapshot(
            schemaVersion: schemaVersion,
            updatedAt: retainedPacks == existing.packs ? existing.updatedAt : Date().timeIntervalSince1970,
            packs: retainedPacks
        )
    }

    static func shouldEnableTransformersHelperBridge(
        catalog: ModelCatalogSnapshot,
        helperBinaryPath: String
    ) -> Bool {
        shouldEnableAutoManagedHelperBridge(
            catalog: catalog,
            helperBinaryPath: helperBinaryPath,
            providerID: "transformers"
        )
    }

    static func shouldEnableMLXVLMHelperBridge(
        catalog: ModelCatalogSnapshot,
        helperBinaryPath: String
    ) -> Bool {
        shouldEnableAutoManagedHelperBridge(
            catalog: catalog,
            helperBinaryPath: helperBinaryPath,
            providerID: "mlx_vlm"
        )
    }

    private static func shouldEnableAutoManagedHelperBridge(
        catalog: ModelCatalogSnapshot,
        helperBinaryPath: String,
        providerID: String
    ) -> Bool {
        let normalizedHelperBinary = normalizedHelperBinaryPath(helperBinaryPath)
        guard !normalizedHelperBinary.isEmpty else {
            return false
        }
        let executableModels = catalog.models.filter {
            LocalModelExecutionProviderResolver.preferredRuntimeProviderID(
                for: $0,
                helperBinaryPath: normalizedHelperBinary
            ) == providerID
                && !$0.modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !executableModels.isEmpty else {
            return false
        }

        let hasBlockingTaskModel = executableModels.contains { model in
            let taskKinds = Set(LocalModelCapabilityDefaults.normalizedStringList(model.taskKinds, fallback: []))
            return !taskKinds.isDisjoint(with: helperBlockingTaskKinds)
        }
        guard !hasBlockingTaskModel else {
            return false
        }

        return executableModels.contains { model in
            let taskKinds = Set(LocalModelCapabilityDefaults.normalizedStringList(model.taskKinds, fallback: []))
            return !taskKinds.isDisjoint(with: helperSupportedTaskKinds)
        }
    }

    private static func normalizedHelperBinaryPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private static func isAutoManagedHelperEntry(_ pack: LocalProviderPackRegistryEntry) -> Bool {
        autoManagedHelperProviderIDs.contains(pack.providerId) && pack.note == autoManagedNote
    }

    private static func autoManagedHelperEntry(
        providerID: String,
        helperBinaryPath: String
    ) -> LocalProviderPackRegistryEntry {
        let normalizedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedHelperBinary = normalizedHelperBinaryPath(helperBinaryPath)
        let engine: String
        let version: String
        let supportedFormats: [String]
        let supportedDomains: [String]

        switch normalizedProviderID {
        case "llama.cpp":
            engine = "llama.cpp"
            version = "auto-2026-03-25"
            supportedFormats = ["gguf"]
            supportedDomains = ["text", "embedding"]
        case "mlx_vlm":
            engine = "mlx-vlm"
            version = "auto-2026-03-24"
            supportedFormats = ["mlx"]
            supportedDomains = ["vision", "ocr"]
        default:
            engine = "xhub_local_helper"
            version = "auto-2026-03-16"
            supportedFormats = ["hf_transformers"]
            supportedDomains = ["text", "embedding", "voice", "vision", "ocr"]
        }

        return LocalProviderPackRegistryEntry(
            providerId: normalizedProviderID,
            engine: engine,
            version: version,
            supportedFormats: supportedFormats,
            supportedDomains: supportedDomains,
            runtimeRequirements: LocalProviderPackRegistryRuntimeRequirements(
                executionMode: "helper_binary_bridge",
                helperBinary: normalizedHelperBinary,
                notes: ["auto_detected_local_helper_bridge"]
            ),
            minHubVersion: "2026.03",
            installed: true,
            enabled: true,
            packState: "installed",
            reasonCode: "auto_local_helper_bridge_enabled",
            note: autoManagedNote
        )
    }
}
